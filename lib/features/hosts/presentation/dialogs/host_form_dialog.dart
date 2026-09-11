import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/theme/shellvibe_tokens.dart';
import 'package:shellvibe/app/widgets/shellvibe_ui.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/identities_notifier.dart';

import '../../../../shared/providers/workspace_provider.dart';
import '../../domain/models/host_model.dart';
import '../notifiers/host_groups_notifier.dart';
import '../notifiers/hosts_notifier.dart';

class HostFormDialog extends ConsumerStatefulWidget {
  final HostModel? initialHost;
  final String? workspaceId;

  const HostFormDialog({super.key, this.initialHost, this.workspaceId});

  @override
  ConsumerState<HostFormDialog> createState() => _HostFormDialogState();
}

class _HostFormDialogState extends ConsumerState<HostFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _labelController;
  late TextEditingController _hostnameController;
  late TextEditingController _usernameController;
  late TextEditingController _portController;
  late TextEditingController _colorTagController;
  late TextEditingController _moshServerPathController;
  late TextEditingController _moshPortRangeController;
  late FocusNode _hostnameFocusNode;

  late String _protocol;
  String? _selectedGroupId;
  String? _selectedIdentityId;
  String? _selectedJumpHostId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initialHost;
    _labelController = TextEditingController(text: init?.label ?? '');
    _hostnameController = TextEditingController(text: init?.hostname ?? '');
    _usernameController = TextEditingController(text: init?.username ?? '');
    _portController = TextEditingController(
      text: (init?.port ?? 22).toString(),
    );
    _colorTagController = TextEditingController(text: init?.colorTag ?? '');
    _moshServerPathController = TextEditingController(
      text: init?.moshServerPath ?? '',
    );
    _moshPortRangeController = TextEditingController(
      text: init?.moshPortRange ?? '',
    );
    _hostnameFocusNode = FocusNode();

    _hostnameFocusNode.addListener(() {
      if (!_hostnameFocusNode.hasFocus) {
        _parseHostnameInput();
      }
    });

    final proto = init?.protocol;
    _protocol = (proto == 'local' || proto == 'mosh') ? proto! : 'ssh';
    _selectedGroupId = init?.groupId;
    _selectedIdentityId = init?.identityId;
    _selectedJumpHostId = init?.jumpHostId;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _hostnameController.dispose();
    _usernameController.dispose();
    _portController.dispose();
    _colorTagController.dispose();
    _moshServerPathController.dispose();
    _moshPortRangeController.dispose();
    _hostnameFocusNode.dispose();
    super.dispose();
  }

  /// Accepts an empty value (the mosh default 60000:61000 is used) or a
  /// `start:end` pair inside the UDP port space. A bad range would otherwise
  /// only surface as a `mosh-server` failure at connect time.
  String? _validateMoshPortRange(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;

    final parts = text.split(':');
    if (parts.length != 2) return 'Use start:end, e.g. 60000:61000';

    final start = int.tryParse(parts[0].trim());
    final end = int.tryParse(parts[1].trim());
    if (start == null || end == null) return 'Ports must be numbers';
    if (start < 1 || start > 65535 || end < 1 || end > 65535) {
      return 'Ports must be between 1 and 65535';
    }
    if (end < start) return 'End must not be below start';
    return null;
  }

  void _parseHostnameInput() {
    final text = _hostnameController.text.trim();
    if (text.contains('@')) {
      final atIndex = text.indexOf('@');
      final user = text.substring(0, atIndex).trim();
      final host = text.substring(atIndex + 1).trim();
      if (user.isNotEmpty) {
        _usernameController.text = user;
      }
      _hostnameController.text = host;
    }
  }

  Future<void> _save() async {
    _parseHostnameInput();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final notifier = ref.read(hostsProvider.notifier);
      final isEditing = widget.initialHost != null;
      final portVal = int.tryParse(_portController.text.trim()) ?? 22;
      final usernameVal = _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim();
      // Only persisted for a Mosh host: leaving them behind on a host switched
      // back to SSH would silently resurface if it were ever switched again.
      final isMosh = _protocol == 'mosh';
      final moshServerPathVal = !isMosh
          ? null
          : (_moshServerPathController.text.trim().isEmpty
                ? null
                : _moshServerPathController.text.trim());
      final moshPortRangeVal = !isMosh
          ? null
          : (_moshPortRangeController.text.trim().isEmpty
                ? null
                : _moshPortRangeController.text.trim());

      if (isEditing) {
        await notifier.updateHost(
          id: widget.initialHost!.id,
          workspaceId: widget.initialHost!.workspaceId,
          groupId: _selectedGroupId,
          identityId: _selectedIdentityId,
          label: _labelController.text.trim(),
          hostname: _hostnameController.text.trim(),
          username: usernameVal,
          port: portVal,
          protocol: _protocol,
          moshServerPath: moshServerPathVal,
          moshPortRange: moshPortRangeVal,
          colorTag: _colorTagController.text.trim().isEmpty
              ? null
              : _colorTagController.text.trim(),
          jumpHostId: _selectedJumpHostId,
        );
      } else {
        await notifier.addHost(
          workspaceId:
              widget.workspaceId ?? ref.read(activeWorkspaceIdProvider),
          groupId: _selectedGroupId,
          identityId: _selectedIdentityId,
          label: _labelController.text.trim(),
          hostname: _hostnameController.text.trim(),
          username: usernameVal,
          port: portVal,
          protocol: _protocol,
          moshServerPath: moshServerPathVal,
          moshPortRange: moshPortRangeVal,
          colorTag: _colorTagController.text.trim().isEmpty
              ? null
              : _colorTagController.text.trim(),
          jumpHostId: _selectedJumpHostId,
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Save Host Error'),
            description: Text('$e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// The address this form resolves to, including the bastion it rides
  /// through. Rendered under the routing section so the route is stated rather
  /// than inferred from three separate fields.
  String _routeSummary(List<HostModel> hosts) {
    final user = _usernameController.text.trim();
    final host = _hostnameController.text.trim();
    final port = _portController.text.trim();
    final target = host.isEmpty
        ? 'no hostname yet'
        : '${user.isEmpty ? '' : '$user@'}$host${port.isEmpty ? '' : ':$port'}';
    final jump = hosts
        .where((candidate) => candidate.id == _selectedJumpHostId)
        .firstOrNull;
    return jump == null ? target : '$target via ${jump.label}';
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialHost != null;
    final groupsAsync = ref.watch(hostGroupsProvider);
    final identitiesAsync = ref.watch(identitiesProvider);
    final hostsAsync = ref.watch(hostsProvider);

    final tokens = ShellVibeTokens.resolve(context);

    return ShadDialog(
      // The form is two fields wide, so it asks for more room than shadcn's
      // 512px default. Expressed as a constraint rather than a fixed width on
      // the child: a phone shrinks it, a desktop gets the designed size.
      constraints: const BoxConstraints(maxWidth: 640),
      // A brand-tinted glyph tile instead of a bare icon: the dialog is an
      // overlay slab, and the tile is what gives its header the same weight as
      // a panel's.
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.brand.withValues(alpha: 0.26)),
            ),
            child: Icon(LucideIcons.server, size: 19, color: tokens.brand),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              isEditing ? 'Edit host' : 'New host',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      description: Padding(
        padding: const EdgeInsets.only(left: 54),
        child: Text(
          'workspace: ${widget.workspaceId ?? 'default'}',
          style: shellvibeMono(context, size: 11, color: tokens.textSubtle),
        ),
      ),
      // Nothing flexible may go in here: below shadcn's `sm` breakpoint the
      // actions become a shrink-wrapped Column, and an `Expanded` in one throws
      // on every phone. The TOFU note therefore lives at the foot of the form,
      // where it is also nearer the fields it is about.
      actions: [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        if (_isLoading)
          const SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          ShellVibeButton(
            buttonKey: const Key('host_save_button'),
            label: isEditing ? 'Update host' : 'Save and connect',
            onPressed: _save,
          ),
      ],
      child: SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const ShellVibeFormSectionHeader(
                  icon: LucideIcons.server,
                  title: 'Connection',
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: ShadInputFormField(
                        key: const Key('host_label_input'),
                        controller: _labelController,
                        label: const Text('Label / Name'),
                        placeholder: const Text('e.g. AWS Production Web'),
                        leading: const Icon(LucideIcons.tag, size: 16),
                        validator: (v) =>
                            v.trim().isEmpty ? 'Label is required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: ShadInputFormField(
                        key: const Key('host_colortag_input'),
                        controller: _colorTagController,
                        label: const Text('Color Tag'),
                        placeholder: const Text('#4CAF50 or green'),
                        leading: const Icon(LucideIcons.palette, size: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: ShadInputFormField(
                        key: const Key('host_hostname_input'),
                        focusNode: _hostnameFocusNode,
                        controller: _hostnameController,
                        label: const Text('Hostname / IP Address'),
                        placeholder: const Text(
                          'e.g. 192.168.1.10 or root@192.168.1.10',
                        ),
                        leading: const Icon(LucideIcons.globe, size: 16),
                        validator: (v) =>
                            v.trim().isEmpty ? 'Hostname is required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: ShadInputFormField(
                        key: const Key('host_username_input'),
                        controller: _usernameController,
                        label: const Text('Username'),
                        placeholder: const Text('e.g. root'),
                        leading: const Icon(LucideIcons.user, size: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: ShadSelectFormField<String>(
                        key: const Key('host_protocol_dropdown'),
                        initialValue: _protocol,
                        label: const Text('Protocol'),
                        selectedOptionBuilder: (context, value) =>
                            Text(value.toUpperCase()),
                        options: [
                          const ShadOption(value: 'ssh', child: Text('SSH')),
                          const ShadOption(value: 'mosh', child: Text('Mosh')),
                          if (supportsLocalShell)
                            const ShadOption(
                              value: 'local',
                              child: Text('Local Shell'),
                            ),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() {
                            _protocol = val;
                            // Mosh carries its session over UDP, which cannot
                            // be tunneled through an SSH channel. The jump host
                            // is dropped here rather than at connect time so
                            // the form never holds a combination that cannot
                            // work; the note below the field says why.
                            if (val == 'mosh') _selectedJumpHostId = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: ShadInputFormField(
                        key: const Key('host_port_input'),
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        label: const Text('Port'),
                        leading: const Icon(LucideIcons.hash, size: 16),
                        validator: (v) {
                          if (v.trim().isEmpty) return 'Required';
                          final port = int.tryParse(v.trim());
                          if (port == null || port < 1 || port > 65535) {
                            return 'Must be between 1 and 65535';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                if (_protocol == 'mosh') ...[
                  const SizedBox(height: 20),
                  const ShellVibeFormSectionHeader(
                    icon: LucideIcons.radio,
                    title: 'Mosh',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: ShadInputFormField(
                          key: const Key('host_mosh_server_path_input'),
                          controller: _moshServerPathController,
                          label: const Text('Server binary'),
                          placeholder: const Text('mosh-server'),
                          leading: const Icon(LucideIcons.terminal, size: 16),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: ShadInputFormField(
                          key: const Key('host_mosh_port_range_input'),
                          controller: _moshPortRangeController,
                          label: const Text('UDP ports'),
                          placeholder: const Text('60000:61000'),
                          leading: const Icon(LucideIcons.hash, size: 16),
                          validator: _validateMoshPortRange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const _FieldNote(
                    'The SSH connection stays open alongside the Mosh session, '
                    'so SFTP and tunnels keep working.',
                  ),
                ],
                const SizedBox(height: 20),
                const ShellVibeFormSectionHeader(
                  icon: LucideIcons.lockKeyhole,
                  title: 'Authentication',
                ),
                const SizedBox(height: 12),
                // Identity Selection
                identitiesAsync.when(
                  data: (identities) => ShadSelectFormField<String?>(
                    key: const Key('host_identity_dropdown'),
                    initialValue: _selectedIdentityId,
                    label: const Text('Identity / Credentials'),
                    selectedOptionBuilder: (context, value) {
                      if (value == null) {
                        return const Text('(None - Prompt on Connect)');
                      }
                      final i = identities
                          .where((item) => item.id == value)
                          .firstOrNull;
                      return Text(
                        i != null
                            ? '${i.title}${i.username.isNotEmpty ? ' (${i.username})' : ''}'
                            : value,
                      );
                    },
                    options: [
                      const ShadOption<String?>(
                        value: null,
                        child: Text('(None - Prompt on Connect)'),
                      ),
                      ...identities.map(
                        (i) => ShadOption<String?>(
                          value: i.id,
                          child: Text(
                            '${i.title}${i.username.isNotEmpty ? ' (${i.username})' : ''}',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) =>
                        setState(() => _selectedIdentityId = val),
                  ),
                  loading: () => const _SelectStatus(
                    icon: LucideIcons.loaderCircle,
                    text: 'Loading identities…',
                  ),
                  error: (e, s) => const _SelectStatus(
                    icon: LucideIcons.triangleAlert,
                    text: 'Failed to load identities',
                  ),
                ),
                const SizedBox(height: 20),
                const ShellVibeFormSectionHeader(
                  icon: LucideIcons.network,
                  title: 'Routing & Organization',
                ),
                const SizedBox(height: 12),
                // Group Selection
                groupsAsync.when(
                  data: (groups) => ShadSelectFormField<String?>(
                    key: const Key('host_group_dropdown'),
                    initialValue: _selectedGroupId,
                    label: const Text('Group / Folder'),
                    selectedOptionBuilder: (context, value) {
                      if (value == null) {
                        return const Text('(None - Ungrouped)');
                      }
                      final g = groups
                          .where((item) => item.id == value)
                          .firstOrNull;
                      return Text(g?.name ?? value);
                    },
                    options: [
                      const ShadOption<String?>(
                        value: null,
                        child: Text('(None - Ungrouped)'),
                      ),
                      ...groups.map(
                        (g) => ShadOption<String?>(
                          value: g.id,
                          child: Text(g.name),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => _selectedGroupId = val),
                  ),
                  loading: () => const _SelectStatus(
                    icon: LucideIcons.loaderCircle,
                    text: 'Loading groups…',
                  ),
                  error: (e, s) => const _SelectStatus(
                    icon: LucideIcons.triangleAlert,
                    text: 'Failed to load groups',
                  ),
                ),
                const SizedBox(height: 12),
                // Jump Host Selection. Not offered on Mosh: UDP does not travel
                // through an SSH channel, so the two cannot be combined.
                if (_protocol == 'mosh')
                  const _FieldNote(
                    'Jump host is unavailable on Mosh — UDP cannot be tunneled '
                    'through an SSH connection.',
                    icon: LucideIcons.info,
                  )
                else
                  hostsAsync.when(
                    data: (hosts) {
                      final excludedJumpHostIds = <String>{};
                      if (isEditing) {
                        final editedId = widget.initialHost!.id;
                        excludedJumpHostIds.add(editedId);
                        final jumpTargets = {
                          for (final h in hosts) h.id: h.jumpHostId,
                        };
                        for (final h in hosts) {
                          final visited = <String>{};
                          var current = h.jumpHostId;
                          while (current != null && visited.add(current)) {
                            if (current == editedId) {
                              excludedJumpHostIds.add(h.id);
                              break;
                            }
                            current = jumpTargets[current];
                          }
                        }
                      }
                      final candidateJumpHosts = hosts
                          .where((h) => !excludedJumpHostIds.contains(h.id))
                          .toList();

                      return ShadSelectFormField<String?>(
                        key: const Key('host_jumphost_dropdown'),
                        initialValue: _selectedJumpHostId,
                        label: const Text('Jump Host (Bastion)'),
                        selectedOptionBuilder: (context, value) {
                          if (value == null) {
                            return const Text('(Direct Connection)');
                          }
                          final h = candidateJumpHosts
                              .where((item) => item.id == value)
                              .firstOrNull;
                          return Text(
                            h != null ? '${h.label} (${h.hostname})' : value,
                          );
                        },
                        options: [
                          const ShadOption<String?>(
                            value: null,
                            child: Text('(Direct Connection)'),
                          ),
                          ...candidateJumpHosts.map(
                            (h) => ShadOption<String?>(
                              value: h.id,
                              child: Text('${h.label} (${h.hostname})'),
                            ),
                          ),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedJumpHostId = val),
                      );
                    },
                    loading: () => const _SelectStatus(
                      icon: LucideIcons.loaderCircle,
                      text: 'Loading jump hosts…',
                    ),
                    error: (e, s) => const _SelectStatus(
                      icon: LucideIcons.triangleAlert,
                      text: 'Failed to load jump hosts',
                    ),
                  ),
                const SizedBox(height: 16),
                // The address the form actually resolves to, spelled out. Two
                // fields and a jump-host select do not add up to a route in
                // anyone's head.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.brand.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(tokens.radiusMedium),
                    border: Border.all(
                      color: tokens.brand.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.route, size: 15, color: tokens.brand),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          _routeSummary(hostsAsync.value ?? const []),
                          style: shellvibeMono(
                            context,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // The one thing a first connection will surprise you with,
                // said before you press the button rather than in a dialog
                // after it.
                const SizedBox(height: 14),
                Text(
                  'host key is verified on first connect (TOFU)',
                  style: shellvibeMono(
                    context,
                    size: 11,
                    color: tokens.textSubtle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Slight placeholder shown while an async select is loading or failed.
/// A quiet explanatory line under a field, for the cases where a setting is
/// missing or constrained and the reason is not obvious from the form.
class _FieldNote extends StatelessWidget {
  final String text;
  final IconData icon;

  const _FieldNote(this.text, {this.icon = LucideIcons.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectStatus extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SelectStatus({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
