import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../data/repositories/mcp_repository_providers.dart';
import '../../domain/models/mcp_enums.dart';
import '../dialogs/mcp_command_approval_dialog.dart' show riskCategoryLabel;
import '../notifiers/mcp_activity_notifier.dart';
import '../notifiers/mcp_settings_notifier.dart';
import '../widgets/mcp_activity_panel.dart'
    show McpDecisionChip, mcpAuditRowStatusForWire;

/// Immutable filter selection for one query against [McpAuditRepository].
/// Every field left null means "no filter on this dimension", matching the
/// repository's own `query`/`exportJson`/`exportCsv` contract exactly.
@immutable
class _AuditFilters {
  final String? clientId;
  final String? hostId;
  final AuditDecision? decision;
  final RiskCategory? category;
  final DateTime? from;
  final DateTime? to;

  const _AuditFilters({
    this.clientId,
    this.hostId,
    this.decision,
    this.category,
    this.from,
    this.to,
  });

  _AuditFilters copyWith({
    String? Function()? clientId,
    String? Function()? hostId,
    AuditDecision? Function()? decision,
    RiskCategory? Function()? category,
    DateTime? Function()? from,
    DateTime? Function()? to,
  }) {
    return _AuditFilters(
      clientId: clientId != null ? clientId() : this.clientId,
      hostId: hostId != null ? hostId() : this.hostId,
      decision: decision != null ? decision() : this.decision,
      category: category != null ? category() : this.category,
      from: from != null ? from() : this.from,
      to: to != null ? to() : this.to,
    );
  }

  bool get isEmpty =>
      clientId == null &&
      hostId == null &&
      decision == null &&
      category == null &&
      from == null &&
      to == null;
}

/// The full, filterable AI audit trail.
///
/// **Why there is no delete affordance anywhere on this screen.** An audit
/// log a user (or, transitively, an agent that talked the user into it) can
/// edit is not an audit log — it is a diary the record's own subject can
/// rewrite, which defeats the one property that makes it worth keeping in the
/// first place: that "what did the agent do" has an answer nobody involved
/// can quietly change after the fact. [McpAuditRepository.purgeOlderThan] is
/// the sole sanctioned way rows disappear, and it is a retention sweep on a
/// schedule the user sets once in Settings, not a per-row action available
/// from here. This screen reflects that retention setting as read-only text
/// with a pointer to where it is actually changed, and otherwise only reads:
/// filter, page, export.
class McpAuditScreen extends ConsumerStatefulWidget {
  /// Pre-selects the client filter, e.g. when opened from one client's block
  /// in [McpActivityPanel].
  final String? initialClientId;

  const McpAuditScreen({super.key, this.initialClientId});

  @override
  ConsumerState<McpAuditScreen> createState() => _McpAuditScreenState();
}

class _McpAuditScreenState extends ConsumerState<McpAuditScreen> {
  static const int _pageSize = 50;

  late _AuditFilters _filters;
  int _page = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _exporting = false;
  Object? _loadError;
  List<McpAuditLogData> _rows = const [];

  List<McpClient> _clients = const [];
  List<HostModel> _hosts = const [];

  @override
  void initState() {
    super.initState();
    _filters = _AuditFilters(clientId: widget.initialClientId);
    unawaited(_loadFilterOptions());
    unawaited(_loadPage());
  }

  Future<void> _loadFilterOptions() async {
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final clients = await ref
        .read(mcpClientRepositoryProvider)
        .listClients(workspaceId);
    final hosts = await ref
        .read(hostsRepositoryProvider)
        .getHostsByWorkspace(workspaceId);
    if (!mounted) return;
    setState(() {
      _clients = clients;
      _hosts = hosts;
    });
  }

  Future<void> _loadPage() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rows = await ref
          .read(mcpAuditRepositoryProvider)
          .query(
            clientId: _filters.clientId,
            hostId: _filters.hostId,
            decision: _filters.decision,
            category: _filters.category,
            from: _filters.from,
            to: _filters.to,
            limit: _pageSize,
            offset: _page * _pageSize,
          );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        // A full page means there may be more; not an exact count, but the
        // repository's `query` has no separate count method and this is
        // enough to drive a Previous/Next pager honestly.
        _hasMore = rows.length == _pageSize;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _applyFilters(_AuditFilters next) {
    setState(() {
      _filters = next;
      _page = 0;
    });
    unawaited(_loadPage());
  }

  void _goToPage(int page) {
    setState(() => _page = page);
    unawaited(_loadPage());
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = (isFrom ? _filters.from : _filters.to)?.toLocal() ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked == null) return;
    // A "from" filter means the start of that local day; a "to" filter means
    // the end of it, so picking the same day for both covers that whole day
    // rather than an instant inside it.
    final boundary = isFrom
        ? DateTime(picked.year, picked.month, picked.day).toUtc()
        : DateTime(
            picked.year,
            picked.month,
            picked.day,
            23,
            59,
            59,
            999,
          ).toUtc();
    _applyFilters(
      isFrom
          ? _filters.copyWith(from: () => boundary)
          : _filters.copyWith(to: () => boundary),
    );
  }

  Future<void> _export({required bool asCsv}) async {
    setState(() => _exporting = true);
    try {
      final repo = ref.read(mcpAuditRepositoryProvider);
      final content = asCsv
          ? await repo.exportCsv(
              clientId: _filters.clientId,
              hostId: _filters.hostId,
              decision: _filters.decision,
              category: _filters.category,
              from: _filters.from,
              to: _filters.to,
            )
          : await repo.exportJson(
              clientId: _filters.clientId,
              hostId: _filters.hostId,
              decision: _filters.decision,
              category: _filters.category,
              from: _filters.from,
              to: _filters.to,
            );

      final stamp = DateTime.now().toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      final name =
          'shellvibe-mcp-audit-${stamp.year}${two(stamp.month)}${two(stamp.day)}-'
          '${two(stamp.hour)}${two(stamp.minute)}${two(stamp.second)}'
          '.${asCsv ? 'csv' : 'json'}';

      final path = await _saveExportFile(
        content: content,
        suggestedName: name,
        mimeType: asCsv ? 'text/csv' : 'application/json',
        extensions: [asCsv ? 'csv' : 'json'],
        label: asCsv ? 'CSV audit export' : 'JSON audit export',
      );
      if (!mounted) return;
      if (path == null) {
        ShadToaster.of(
          context,
        ).show(const ShadToast(description: Text('Export cancelled.')));
      } else {
        ShadToaster.of(
          context,
        ).show(ShadToast(description: Text('Exported to $path')));
      }
    } catch (error) {
      if (!mounted) return;
      ShadToaster.of(
        context,
      ).show(ShadToast.destructive(description: Text('Export failed: $error')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Writes [content] to a user-chosen location on desktop, or the app
  /// documents directory on mobile — the exact mechanism
  /// `BackupFileService.saveBackup` uses for backup exports
  /// (`features/settings/domain/services/backup_file_service.dart`), applied
  /// here with an audit-export type group instead of that service's
  /// backup-specific one, since a `.shellvibebak.json` file type filter would
  /// be misleading for a plain audit export.
  Future<String?> _saveExportFile({
    required String content,
    required String suggestedName,
    required String mimeType,
    required List<String> extensions,
    required String label,
  }) async {
    final bytes = utf8.encode(content);

    if (isMobilePlatform) {
      final dir = await getApplicationDocumentsDirectory();
      final path = p.join(dir.path, suggestedName);
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    }

    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: extensions, mimeTypes: [mimeType]),
      ],
    );
    if (location == null) return null;

    final file = XFile.fromData(bytes, name: suggestedName, mimeType: mimeType);
    await file.saveTo(location.path);
    return location.path;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final settingsAsync = ref.watch(mcpSettingsProvider);
    final retentionDays = settingsAsync.value?.auditRetentionDays;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShellVibeWorkToolbar(
            title: 'Audit Log',
            meta: '${_rows.length} shown on this page · page ${_page + 1}',
            leading: [
              ShellVibeIconButton(
                key: const Key('mcp_audit_back_button'),
                icon: LucideIcons.arrowLeft,
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
            actions: [
              ShellVibeButton.secondary(
                buttonKey: const Key('mcp_audit_export_json_button'),
                icon: LucideIcons.fileJson,
                label: 'Export JSON',
                onPressed: _exporting ? null : () => _export(asCsv: false),
              ),
              ShellVibeButton.secondary(
                buttonKey: const Key('mcp_audit_export_csv_button'),
                icon: LucideIcons.fileSpreadsheet,
                label: 'Export CSV',
                onPressed: _exporting ? null : () => _export(asCsv: true),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.pagePadding),
            child: ShellVibeInfoNote(
              icon: LucideIcons.shieldCheck,
              message: retentionDays != null
                  ? 'Retention: $retentionDays days. Records are never '
                        'edited or deleted from here — change the window in '
                        'Settings → AI Access → Audit log retention.'
                  : 'Records are never edited or deleted from here — the '
                        'retention window is set in Settings → AI Access → '
                        'Audit log retention.',
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.pagePadding,
              12,
              tokens.pagePadding,
              0,
            ),
            child: _FiltersBar(
              filters: _filters,
              clients: _clients,
              hosts: _hosts,
              onChanged: _applyFilters,
              onPickDate: _pickDate,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody(context, tokens)),
          _PagerBar(
            page: _page,
            hasMore: _hasMore,
            onPrevious: _page == 0 ? null : () => _goToPage(_page - 1),
            onNext: _hasMore ? () => _goToPage(_page + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ShellVibeTokens tokens) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return ShellVibeEmptyState(
        icon: LucideIcons.triangleAlert,
        title: 'Could not load the audit log',
        description: '$_loadError',
        actions: [
          ShellVibeButton.secondary(
            label: 'Retry',
            onPressed: () => unawaited(_loadPage()),
          ),
        ],
      );
    }
    if (_rows.isEmpty) {
      return ShellVibeEmptyState(
        icon: LucideIcons.scrollText,
        title: _filters.isEmpty ? 'No activity yet' : 'No matching records',
        description: _filters.isEmpty
            ? 'Every tool call an AI client makes through this app is '
                  'recorded here, whether it ran, was denied, or errored.'
            : 'No audit rows match the current filters on this page.',
      );
    }
    return ListView.separated(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.pagePadding,
        vertical: 8,
      ),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
      itemBuilder: (context, index) => _AuditRowTile(entry: _rows[index]),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  final _AuditFilters filters;
  final List<McpClient> clients;
  final List<HostModel> hosts;
  final ValueChanged<_AuditFilters> onChanged;
  final Future<void> Function({required bool isFrom}) onPickDate;

  const _FiltersBar({
    required this.filters,
    required this.clients,
    required this.hosts,
    required this.onChanged,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 170,
          child: ShadSelect<String?>(
            // Keyed on the current value (not just a fixed id) so an
            // external reset — "Clear filters", or `initialClientId` from
            // the activity panel — actually remounts the select instead of
            // it silently keeping whatever the user last picked in its own
            // internal state.
            key: Key('mcp_audit_client_filter_${filters.clientId ?? 'all'}'),
            placeholder: const Text('All clients'),
            initialValue: filters.clientId,
            selectedOptionBuilder: (context, value) => Text(
              value == null
                  ? 'All clients'
                  : clients
                            .where((c) => c.id == value)
                            .map((c) => c.name)
                            .firstOrNull ??
                        value,
              overflow: TextOverflow.ellipsis,
            ),
            options: [
              const ShadOption<String?>(
                value: null,
                child: Text('All clients'),
              ),
              for (final client in clients)
                ShadOption<String?>(value: client.id, child: Text(client.name)),
            ],
            onChanged: (value) =>
                onChanged(filters.copyWith(clientId: () => value)),
          ),
        ),
        SizedBox(
          width: 170,
          child: ShadSelect<String?>(
            key: Key('mcp_audit_host_filter_${filters.hostId ?? 'all'}'),
            placeholder: const Text('All hosts'),
            initialValue: filters.hostId,
            selectedOptionBuilder: (context, value) => Text(
              value == null
                  ? 'All hosts'
                  : hosts
                            .where((h) => h.id == value)
                            .map((h) => h.label)
                            .firstOrNull ??
                        value,
              overflow: TextOverflow.ellipsis,
            ),
            options: [
              const ShadOption<String?>(value: null, child: Text('All hosts')),
              for (final host in hosts)
                ShadOption<String?>(value: host.id, child: Text(host.label)),
            ],
            onChanged: (value) =>
                onChanged(filters.copyWith(hostId: () => value)),
          ),
        ),
        SizedBox(
          width: 160,
          child: ShadSelect<AuditDecision?>(
            key: Key(
              'mcp_audit_decision_filter_${filters.decision?.wireName ?? 'all'}',
            ),
            placeholder: const Text('All decisions'),
            initialValue: filters.decision,
            selectedOptionBuilder: (context, value) =>
                Text(value == null ? 'All decisions' : _decisionLabel(value)),
            options: [
              const ShadOption<AuditDecision?>(
                value: null,
                child: Text('All decisions'),
              ),
              for (final decision in AuditDecision.values)
                ShadOption<AuditDecision?>(
                  value: decision,
                  child: Text(_decisionLabel(decision)),
                ),
            ],
            onChanged: (value) =>
                onChanged(filters.copyWith(decision: () => value)),
          ),
        ),
        SizedBox(
          width: 200,
          child: ShadSelect<RiskCategory?>(
            key: Key(
              'mcp_audit_category_filter_${filters.category?.wireName ?? 'all'}',
            ),
            placeholder: const Text('All categories'),
            initialValue: filters.category,
            selectedOptionBuilder: (context, value) => Text(
              value == null ? 'All categories' : riskCategoryLabel(value),
              overflow: TextOverflow.ellipsis,
            ),
            options: [
              const ShadOption<RiskCategory?>(
                value: null,
                child: Text('All categories'),
              ),
              for (final category in RiskCategory.values)
                ShadOption<RiskCategory?>(
                  value: category,
                  child: Text(riskCategoryLabel(category)),
                ),
            ],
            onChanged: (value) =>
                onChanged(filters.copyWith(category: () => value)),
          ),
        ),
        ShellVibeButton.secondary(
          buttonKey: const Key('mcp_audit_from_date_button'),
          icon: LucideIcons.calendar,
          label: filters.from == null ? 'From' : _formatDate(filters.from!),
          onPressed: () => onPickDate(isFrom: true),
        ),
        ShellVibeButton.secondary(
          buttonKey: const Key('mcp_audit_to_date_button'),
          icon: LucideIcons.calendar,
          label: filters.to == null ? 'To' : _formatDate(filters.to!),
          onPressed: () => onPickDate(isFrom: false),
        ),
        if (!filters.isEmpty)
          ShellVibeButton.secondary(
            buttonKey: const Key('mcp_audit_clear_filters_button'),
            icon: LucideIcons.x,
            label: 'Clear filters',
            onPressed: () => onChanged(const _AuditFilters()),
          ),
      ],
    );
  }

  String _decisionLabel(AuditDecision decision) => switch (decision) {
    AuditDecision.allowed => 'Allowed',
    AuditDecision.confirmed => 'Confirmed',
    AuditDecision.denied => 'Denied',
    AuditDecision.autoDenied => 'Auto-denied',
    AuditDecision.error => 'Error',
  };

  String _formatDate(DateTime at) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

class _AuditRowTile extends StatelessWidget {
  final McpAuditLogData entry;

  const _AuditRowTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 138,
            child: Text(
              _formatTimestamp(entry.at),
              style: shellvibeMono(context, size: 11, color: tokens.textSubtle),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              entry.clientName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              entry.hostLabel ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: shellvibeMono(
                context,
                size: 11,
                color: tokens.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              entry.tool,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: shellvibeMono(
                context,
                size: 11,
                color: tokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              summarizeMcpAuditArgs(entry.argsJson),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: shellvibeMono(context, size: 11, color: tokens.textMuted),
            ),
          ),
          const SizedBox(width: 8),
          McpDecisionChip(status: mcpAuditRowStatusForWire(entry.decision)),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime at) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _PagerBar extends StatelessWidget {
  final int page;
  final bool hasMore;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _PagerBar({
    required this.page,
    required this.hasMore,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.pagePadding,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'Page ${page + 1}',
            style: shellvibeMono(context, size: 11, color: tokens.textSubtle),
          ),
          const SizedBox(width: 12),
          ShellVibeButton.secondary(
            buttonKey: const Key('mcp_audit_prev_page_button'),
            icon: LucideIcons.chevronLeft,
            label: 'Previous',
            onPressed: onPrevious,
          ),
          const SizedBox(width: 8),
          ShellVibeButton.secondary(
            buttonKey: const Key('mcp_audit_next_page_button'),
            icon: LucideIcons.chevronRight,
            label: 'Next',
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
