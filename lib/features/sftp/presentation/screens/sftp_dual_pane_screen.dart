import 'dart:async';
import 'dart:math' as math;

import 'package:dartssh2/dartssh2.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../terminal/domain/models/terminal_tab_session.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../domain/models/sftp_file_item.dart';
import '../../domain/models/transfer_item.dart';
import '../providers/sftp_providers.dart';
import '../widgets/file_permissions_dialog.dart';
import '../widgets/remote_file_editor_dialog.dart';
import '../widgets/sftp_transfer_queue_panel.dart';
import '../widgets/sftp_transfer_queue_sheet.dart';

/// Shortest viewport the two-pane layout still fits in.
///
/// A pane owes its header, its path bar and its column header about 120px
/// before the first file row; two of those plus the docked queue and the status
/// bar need this much height to lay out without eating the list entirely.
const double _kDualPaneMinHeight = 480;

class SftpDualPaneScreen extends ConsumerStatefulWidget {
  final SftpClient? sftpClient;
  final String? hostLabel;

  /// Terminal tab whose SSH session this screen transfers files over.
  ///
  /// The screen used to follow whatever tab happened to be active, which left
  /// the user unable to tell which server they were writing to. With a target
  /// pinned, the header names the connection and it cannot drift.
  final String? sessionTabId;

  const SftpDualPaneScreen({
    super.key,
    this.sftpClient,
    this.hostLabel,
    this.sessionTabId,
  });

  @override
  ConsumerState<SftpDualPaneScreen> createState() => _SftpDualPaneScreenState();
}

class _SftpDualPaneScreenState extends ConsumerState<SftpDualPaneScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedMobileTab = 0; // 0: Local Workstation, 1: Remote SFTP
  // This subscription is explicitly cancelled in _stopWatchingSession and
  // dispose; the analyzer cannot follow that lifecycle across callbacks.
  // ignore: cancel_subscriptions
  StreamSubscription<SSHClient?>? _sessionSubscription;
  SSHSessionManager? _subscribedSession;
  String? _subscribedTabId;
  int _attachmentGeneration = 0;
  late bool _usesProvidedClient;

  @override
  void initState() {
    super.initState();
    _usesProvidedClient = widget.sftpClient != null;
    if (widget.sftpClient != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(sftpProvider.notifier).setRemoteClient(widget.sftpClient);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncActiveSshSession();
      });
    }
  }

  /// The tab this screen transfers over: the pinned [sessionTabId] when one was
  /// passed, otherwise the active terminal tab (legacy embedded usage).
  TerminalTabSession? _resolveTargetTab() {
    final tabsState = ref.read(terminalTabsProvider);
    final targetId = widget.sessionTabId;
    if (targetId == null) return tabsState.activeTab;
    return tabsState.tabs.where((tab) => tab.id == targetId).firstOrNull;
  }

  Future<void> _syncActiveSshSession() async {
    if (!mounted || _usesProvidedClient) return;

    final generation = ++_attachmentGeneration;
    final activeTab = _resolveTargetTab();
    final session = activeTab?.sshSessionManager;

    if (activeTab == null ||
        activeTab.sessionType != TerminalSessionType.ssh ||
        session == null) {
      await _stopWatchingSession();
      if (!mounted || generation != _attachmentGeneration) return;
      await ref.read(sftpProvider.notifier).setRemoteClient(null);
      return;
    }

    await _watchSession(activeTab.id, session);

    final sshClient = session.client;
    if (!session.isConnected || sshClient == null || sshClient.isClosed) {
      if (!mounted || generation != _attachmentGeneration) return;
      await ref
          .read(sftpProvider.notifier)
          .setRemoteClient(null, sessionId: activeTab.id);
      return;
    }

    late final SftpClient client;
    try {
      client = await sshClient.sftp();
      if (!_isCurrentSession(generation, activeTab.id, session, sshClient)) {
        await client.close();
        return;
      }
      await ref
          .read(sftpProvider.notifier)
          .setRemoteClient(client, sessionId: activeTab.id);
    } catch (error) {
      if (!_isCurrentSession(generation, activeTab.id, session, sshClient)) {
        return;
      }
      await ref
          .read(sftpProvider.notifier)
          .setRemoteClient(null, sessionId: activeTab.id);
    }
  }

  bool _isCurrentSession(
    int generation,
    String tabId,
    SSHSessionManager session,
    SSHClient sshClient,
  ) {
    final activeTab = _resolveTargetTab();
    return mounted &&
        generation == _attachmentGeneration &&
        activeTab?.id == tabId &&
        identical(activeTab?.sshSessionManager, session) &&
        identical(session.client, sshClient) &&
        session.isConnected &&
        !sshClient.isClosed;
  }

  Future<void> _watchSession(String tabId, SSHSessionManager session) async {
    if (identical(_subscribedSession, session) && _subscribedTabId == tabId) {
      return;
    }
    await _stopWatchingSession();
    if (!mounted) return;
    _subscribedSession = session;
    _subscribedTabId = tabId;
    _sessionSubscription = session.clientChanges.listen((_) {
      unawaited(_syncActiveSshSession());
    });
  }

  Future<void> _stopWatchingSession() async {
    final subscription = _sessionSubscription;
    _sessionSubscription = null;
    _subscribedSession = null;
    _subscribedTabId = null;
    await subscription?.cancel();
  }

  @override
  void didUpdateWidget(covariant SftpDualPaneScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sftpClient != widget.sftpClient) {
      _usesProvidedClient = widget.sftpClient != null;
      if (_usesProvidedClient) {
        unawaited(
          ref.read(sftpProvider.notifier).setRemoteClient(widget.sftpClient),
        );
      } else {
        unawaited(_syncActiveSshSession());
      }
    }
  }

  @override
  void dispose() {
    _attachmentGeneration++;
    unawaited(_stopWatchingSession());
    _searchController.dispose();
    super.dispose();
  }

  void _showQueueSheet() {
    showAdaptivePanel<void>(
      context: context,
      isScrollControlled: true,
      transparentSheetBackground: true,
      desktopWidth: 520,
      builder: (_) => const SftpTransferQueueSheet(),
    );
  }

  void _handleDragAndDropUpload(
    List<DropItem> droppedFiles,
    String remoteDirectoryPath,
  ) {
    final notifier = ref.read(sftpProvider.notifier);
    for (final file in droppedFiles) {
      final item = SftpFileItem(
        name: file.name,
        path: file.path,
        size: 0,
        permissions: '-rw-r--r--',
        isDirectory: false,
        isLocal: true,
      );
      notifier.uploadLocalItem(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, _) {
      if (!_usesProvidedClient) unawaited(_syncActiveSshSession());
    });
    final state = ref.watch(sftpProvider);
    final notifier = ref.read(sftpProvider.notifier);
    final tokens = ShellVibeTokens.resolve(context);
    final screenSize = MediaQuery.sizeOf(context);
    // Height matters as much as width here. A phone held sideways clears the
    // width tier, but two panes, a docked queue and a status bar then have to
    // share 393px of height — which is how the panes used to overflow their own
    // column. Either measure being short drops the layout to one pane.
    final isMobile =
        screenSize.width < tokens.breakpointCompact ||
        screenSize.height < _kDualPaneMinHeight;
    final targetTab = widget.sessionTabId == null
        ? null
        : ref
              .watch(terminalTabsProvider)
              .tabs
              .where((tab) => tab.id == widget.sessionTabId)
              .firstOrNull;
    final connectionLabel =
        widget.hostLabel ?? targetTab?.host?.label ?? targetTab?.title;
    final targetHost = targetTab?.host;
    final canPop = Navigator.of(context).canPop();

    final queue =
        ref.watch(transferQueueStreamProvider).value ?? const <TransferItem>[];
    final queuedCount = queue
        .where((item) => item.status != TransferStatus.completed)
        .length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _SftpToolbar(
            title: connectionLabel == null
                ? 'Files'
                : 'Files · $connectionLabel',
            // The old header never said which server was on the far side of
            // the queue; the address is the whole point of this line.
            meta: targetHost != null
                ? '${targetHost.username != null && targetHost.username!.isNotEmpty ? '${targetHost.username}@' : ''}'
                      '${targetHost.hostname}:${targetHost.port} · sftp'
                : 'local ↔ remote · sftp',
            queuedCount: queuedCount,
            onBack: canPop ? () => Navigator.of(context).maybePop() : null,
            onShowQueue: _showQueueSheet,
            onRefresh: () {
              notifier.loadLocalDirectory();
              notifier.loadRemoteDirectory();
            },
          ),
          SizedBox(height: tokens.panelGap),
          Padding(
            padding: EdgeInsets.only(bottom: tokens.panelGap),
            child: ShellVibeSearchField(
              controller: _searchController,
              hintText: 'Filter files in both panes…',
              onChanged: notifier.setSearchQuery,
            ),
          ),
          // Responsive Segmented Tab Switcher for Mobile / Narrow screens (< 600px)
          if (isMobile)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: [
                    const ButtonSegment<int>(
                      value: 0,
                      label: Text('Local Workstation'),
                      icon: Icon(LucideIcons.laptop, size: 16),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text(
                        state.remoteClient != null
                            ? 'Remote SFTP'
                            : 'Remote (Disconnected)',
                        overflow: TextOverflow.ellipsis,
                      ),
                      icon: const Icon(LucideIcons.server, size: 16),
                    ),
                  ],
                  selected: {_selectedMobileTab},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _selectedMobileTab = newSelection.first;
                    });
                  },
                ),
              ),
            ),
          // Dual Pane or Responsive Single Pane View
          Expanded(
            child: isMobile
                ? (_selectedMobileTab == 0
                      ? _buildLocalPane(state, notifier)
                      : _buildRemotePane(state, notifier, connectionLabel))
                : Row(
                    children: [
                      Expanded(child: _buildLocalPane(state, notifier)),
                      // A gap, not a rule: the two panes are separate slabs.
                      // (3A also puts a transfer-direction column here; that
                      // needs a multi-select model the app does not have yet,
                      // so per-row upload/download stays the way files move.)
                      SizedBox(width: tokens.panelGap),
                      Expanded(
                        child: _buildRemotePane(
                          state,
                          notifier,
                          connectionLabel,
                        ),
                      ),
                    ],
                  ),
          ),
          // Docked rather than a sheet: progress stays visible while browsing.
          // Narrow screens cannot spare the height and keep the sheet.
          if (!isMobile) ...[
            SizedBox(height: tokens.panelGap),
            const SftpTransferQueuePanel(),
          ],
          _buildStatusBar(context, state),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, SftpState state) {
    final connected = state.remoteClient != null;
    final queue =
        ref.watch(transferQueueStreamProvider).value ?? const <TransferItem>[];
    final active = queue
        .where((item) => item.status == TransferStatus.inProgress)
        .length;

    return ShellVibeStatusBar(
      segments: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShellVibeStatusDot(
              state: connected
                  ? ShellVibeDotState.online
                  : ShellVibeDotState.offline,
            ),
            const SizedBox(width: 7),
            Text(connected ? 'remote connected' : 'remote disconnected'),
          ],
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            state.remotePath.isEmpty ? '—' : state.remotePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text('$active transferring'),
        Text('${queue.length} in queue'),
      ],
    );
  }

  Widget _buildLocalPane(SftpState state, SftpNotifier notifier) {
    return DropTarget(
      onDragDone: (details) =>
          _handleDragAndDropUpload(details.files, state.remotePath),
      child: _buildPane(
        title: 'Local Workstation',
        path: state.localPath,
        files: state.localFiles,
        isLoading: state.isLoadingLocal,
        error: state.localError,
        isLocal: true,
        onNavigateUp: notifier.navigateLocalUp,
        onItemTap: (item) {
          if (item.isDirectory) {
            notifier.loadLocalDirectory(item.path);
          }
        },
        onDelete: notifier.deleteLocalItem,
        onUpload: (item) => notifier.uploadLocalItem(item),
      ),
    );
  }

  Widget _buildRemotePane(
    SftpState state,
    SftpNotifier notifier,
    String? connectionLabel,
  ) {
    return DropTarget(
      onDragDone: (details) =>
          _handleDragAndDropUpload(details.files, state.remotePath),
      child: _buildPane(
        title: state.remoteClient != null
            ? (connectionLabel == null
                  ? 'Remote SFTP Server'
                  : 'Remote — $connectionLabel')
            : (connectionLabel == null
                  ? 'Remote (Disconnected)'
                  : '$connectionLabel (Disconnected)'),
        path: state.remotePath,
        files: state.remoteFiles,
        isLoading: state.isLoadingRemote,
        error: state.remoteError,
        isLocal: false,
        onNavigateUp: notifier.navigateRemoteUp,
        onItemTap: (item) {
          if (item.isDirectory) {
            notifier.loadRemoteDirectory(item.path);
          } else {
            _openFileEditor(item);
          }
        },
        onDelete: notifier.deleteRemoteItem,
        onDownload: (item) => notifier.downloadItem(item),
        onEditPermissions: _openPermissionsDialog,
        onEditContent: _openFileEditor,
        onCreateFolder: () => _showCreateDialog(isFolder: true),
        onCreateFile: () => _showCreateDialog(isFolder: false),
        onRename: (item) => _showRenameDialog(item),
      ),
    );
  }

  Widget _buildPane({
    required String title,
    required String path,
    required List<SftpFileItem> files,
    required bool isLoading,
    required String? error,
    required bool isLocal,
    required VoidCallback onNavigateUp,
    required Function(SftpFileItem) onItemTap,
    required Function(SftpFileItem) onDelete,
    Function(SftpFileItem)? onUpload,
    Function(SftpFileItem)? onDownload,
    Function(SftpFileItem)? onEditPermissions,
    Function(SftpFileItem)? onEditContent,
    VoidCallback? onCreateFolder,
    VoidCallback? onCreateFile,
    Function(SftpFileItem)? onRename,
  }) {
    final tokens = ShellVibeTokens.resolve(context);
    final searchQuery = ref.watch(sftpProvider).searchQuery.toLowerCase();
    final filteredFiles = searchQuery.isEmpty
        ? files
        : files
              .where((f) => f.name.toLowerCase().contains(searchQuery))
              .toList();

    // The remote pane wears the brand hairline: of the two, it is the side
    // whose state is not obvious, so it is the one that gets marked.
    final accent = isLocal ? tokens.textMuted : tokens.brand;

    return ShellVibePanel(
      gradientExtent: 200,
      borderColor: isLocal ? null : tokens.brand.withValues(alpha: 0.22),
      child: Column(
        children: [
          // Pane Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isLocal ? LucideIcons.monitor : LucideIcons.server,
                      size: 15,
                      color: accent,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.4,
                          color: accent,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isLocal && onCreateFolder != null)
                      ShellVibeIconButton(
                        icon: LucideIcons.folderPlus,
                        tooltip: 'New Folder',
                        onPressed: onCreateFolder,
                      ),
                    if (!isLocal && onCreateFile != null)
                      ShellVibeIconButton(
                        icon: LucideIcons.filePlus,
                        tooltip: 'New File',
                        onPressed: onCreateFile,
                      ),
                  ],
                ),
                const SizedBox(height: 9),
                // Path bar. Cut into the panel rather than stacked on it, and
                // the parent-directory control lives inside it because "up" is
                // a move along this path, not a separate tool.
                InkWell(
                  onTap: onNavigateUp,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: tokens.textPrimary.withValues(alpha: 0.035),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isLocal
                            ? tokens.textPrimary.withValues(alpha: 0.05)
                            : tokens.brand.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      children: [
                        Tooltip(
                          message: 'Parent Directory',
                          child: Icon(
                            LucideIcons.chevronLeft,
                            size: 14,
                            color: tokens.textMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            path,
                            style: shellvibeMono(
                              context,
                              color: tokens.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const _FileColumnHeader(),
          // File Table / List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        error,
                        style: TextStyle(color: tokens.danger),
                      ),
                    ),
                  )
                : filteredFiles.isEmpty
                ? Center(
                    child: Text(
                      'Empty Directory',
                      style: TextStyle(color: tokens.textMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                    itemCount: filteredFiles.length,
                    itemBuilder: (context, index) {
                      final item = filteredFiles[index];
                      return _buildFileItemTile(
                        item: item,
                        isLocal: isLocal,
                        onTap: () => onItemTap(item),
                        onDelete: () => onDelete(item),
                        onUpload: onUpload != null
                            ? () => onUpload(item)
                            : null,
                        onDownload: onDownload != null
                            ? () => onDownload(item)
                            : null,
                        onEditPermissions: onEditPermissions != null
                            ? () => onEditPermissions(item)
                            : null,
                        onEditContent: onEditContent != null
                            ? () => onEditContent(item)
                            : null,
                        onRename: onRename != null
                            ? () => onRename(item)
                            : null,
                      );
                    },
                  ),
          ),
          _PaneFooter(
            summary:
                '${filteredFiles.length} items · '
                '${_formatTotalSize(filteredFiles)}'
                '${searchQuery.isEmpty ? '' : ' · filtered'}',
          ),
        ],
      ),
    );
  }

  /// A modification time in the width a column can spare: the clock for today,
  /// the date for anything older.
  static String _formatModified(DateTime? time) {
    if (time == null) return '—';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();
    final local = time.toLocal();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    if (local.year == now.year) {
      return '${local.day} ${months[local.month - 1]}';
    }
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  /// Total bytes of the files in a listing; directories report no size of
  /// their own over SFTP, so they are left out rather than counted as zero.
  static String _formatTotalSize(List<SftpFileItem> files) {
    final total = files
        .where((file) => !file.isDirectory)
        .fold<int>(0, (sum, file) => sum + file.size);
    if (total < 1024) return '$total B';
    if (total < 1024 * 1024) {
      return '${(total / 1024).toStringAsFixed(1)} KB';
    }
    if (total < 1024 * 1024 * 1024) {
      return '${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(total / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildFileItemTile({
    required SftpFileItem item,
    required bool isLocal,
    required VoidCallback onTap,
    required VoidCallback onDelete,
    VoidCallback? onUpload,
    VoidCallback? onDownload,
    VoidCallback? onEditPermissions,
    VoidCallback? onEditContent,
    VoidCallback? onRename,
  }) {
    final tokens = ShellVibeTokens.resolve(context);
    IconData iconData;
    Color iconColor;

    // Directories lead in brand and semibold; files are quieter. The type is
    // carried by weight and hue together so the eye can skim for folders.
    if (item.isDirectory) {
      iconData = LucideIcons.folder;
      iconColor = tokens.brand;
    } else if (item.isSymlink) {
      iconData = LucideIcons.link;
      iconColor = tokens.info;
    } else {
      iconData = LucideIcons.file;
      iconColor = tokens.textSubtle;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Icon(iconData, color: iconColor, size: 15),
            ),
            Expanded(
              child: Text(
                item.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: item.isDirectory
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: item.isDirectory
                      ? tokens.textPrimary
                      : tokens.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            SizedBox(
              width: 84,
              child: Text(
                item.isDirectory ? '—' : item.formattedSize,
                textAlign: TextAlign.right,
                style: shellvibeMono(context, size: 11.5),
              ),
            ),
            SizedBox(
              width: 96,
              child: Text(
                _formatModified(item.modifyTime),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: shellvibeMono(
                  context,
                  size: 11.5,
                  color: tokens.textSubtle,
                ),
              ),
            ),
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              iconSize: 16,
              tooltip: 'File actions',
              icon: Icon(
                LucideIcons.ellipsis,
                size: 16,
                color: tokens.textSubtle,
              ),
              onSelected: (val) {
                if (val == 'upload' && onUpload != null) onUpload();
                if (val == 'download' && onDownload != null) onDownload();
                if (val == 'edit' && onEditContent != null) onEditContent();
                if (val == 'chmod' && onEditPermissions != null) {
                  onEditPermissions();
                }
                if (val == 'rename' && onRename != null) onRename();
                if (val == 'delete') onDelete();
              },
              itemBuilder: (context) => [
                if (isLocal && onUpload != null)
                  const PopupMenuItem(
                    value: 'upload',
                    child: Row(
                      children: [
                        Icon(LucideIcons.upload, size: 16),
                        SizedBox(width: 8),
                        Text('Upload to Remote'),
                      ],
                    ),
                  ),
                if (!isLocal && onDownload != null)
                  const PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        Icon(LucideIcons.download, size: 16),
                        SizedBox(width: 8),
                        Text('Download'),
                      ],
                    ),
                  ),
                if (!isLocal && !item.isDirectory && onEditContent != null)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(LucideIcons.filePenLine, size: 16),
                        SizedBox(width: 8),
                        Text('Edit Content'),
                      ],
                    ),
                  ),
                if (!isLocal && onEditPermissions != null)
                  const PopupMenuItem(
                    value: 'chmod',
                    child: Row(
                      children: [
                        Icon(LucideIcons.shieldCheck, size: 16),
                        SizedBox(width: 8),
                        Text('Permissions (chmod)'),
                      ],
                    ),
                  ),
                if (!isLocal && onRename != null)
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(LucideIcons.pencil, size: 16),
                        SizedBox(width: 8),
                        Text('Rename'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(LucideIcons.trash2, size: 16),
                      SizedBox(width: 8),
                      Text('Delete'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openFileEditor(SftpFileItem item) {
    showDialog(
      context: context,
      builder: (_) => RemoteFileEditorDialog(fileItem: item),
    );
  }

  void _openPermissionsDialog(SftpFileItem item) async {
    final result = await showDialog<FilePermissionsResult>(
      context: context,
      builder: (_) => FilePermissionsDialog(item: item),
    );

    if (result != null) {
      final notifier = ref.read(sftpProvider.notifier);
      await notifier.changeRemotePermissions(item, result.mode);
      if (result.uid != null || result.gid != null) {
        await notifier.changeRemoteOwner(
          item,
          uid: result.uid,
          gid: result.gid,
        );
      }
    }
  }

  void _showCreateDialog({required bool isFolder}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _TextPromptDialog(
        title: isFolder ? 'Create Remote Directory' : 'Create Remote File',
        placeholder: isFolder ? 'folder_name' : 'filename.txt',
        confirmLabel: 'Create',
      ),
    );

    if (name != null && name.isNotEmpty) {
      final notifier = ref.read(sftpProvider.notifier);
      if (isFolder) {
        notifier.createRemoteFolder(name);
      } else {
        notifier.createRemoteFile(name);
      }
    }
  }

  void _showRenameDialog(SftpFileItem item) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _TextPromptDialog(
        title: 'Rename ${item.name}',
        initialText: item.name,
        confirmLabel: 'Rename',
        canConfirm: (text) => text.isNotEmpty && text != item.name,
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != item.name) {
      ref.read(sftpProvider.notifier).renameRemoteItem(item, newName);
    }
  }
}

/// Single-field text-entry dialog used for create-folder, create-file, and
/// rename prompts.
///
/// Owns its [TextEditingController] itself (created in [initState], disposed
/// in [dispose]) instead of the caller disposing one after `showDialog`
/// returns — the caller's `await` completes as soon as the route is popped,
/// but the dialog widget (and the [ShadInput] holding the controller) stays
/// mounted through its exit transition, so a caller-side dispose can race a
/// still-mounted input and throw.
class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String? placeholder;
  final String? initialText;
  final String confirmLabel;

  /// Whether [text] may be submitted. Defaults to "non-empty" when omitted.
  final bool Function(String text)? canConfirm;

  const _TextPromptDialog({
    required this.title,
    this.placeholder,
    this.initialText,
    required this.confirmLabel,
    this.canConfirm,
  });

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    final canConfirm = widget.canConfirm?.call(text) ?? text.isNotEmpty;
    if (canConfirm) {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = math.min(screenWidth * 0.9, 450.0);

    return ShadDialog(
      title: Text(widget.title),
      description: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ShadInput(
              controller: _controller,
              autofocus: true,
              placeholder: widget.placeholder == null
                  ? null
                  : Text(widget.placeholder!),
            ),
          ],
        ),
      ),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        ShellVibeButton(label: widget.confirmLabel, onPressed: _submit),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
    );
  }
}

/// The Files module's top strip: what is connected, and the queue.
class _SftpToolbar extends StatelessWidget {
  final String title;
  final String meta;
  final int queuedCount;
  final VoidCallback? onBack;
  final VoidCallback onShowQueue;
  final VoidCallback onRefresh;

  const _SftpToolbar({
    required this.title,
    required this.meta,
    required this.queuedCount,
    required this.onBack,
    required this.onShowQueue,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      // A floor, not a fixed height: the title and its mono meta line stack,
      // and at a large system text scale the pair is taller than 52px.
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tokens.railBg, tokens.surfaceLow],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            ShellVibeIconButton(
              buttonKey: const Key('sftp_back_button'),
              icon: LucideIcons.arrowLeft,
              tooltip: 'Back',
              onPressed: onBack!,
            ),
            const SizedBox(width: 6),
          ],
          Icon(LucideIcons.folderSync, size: 18, color: tokens.brand),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: tokens.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: shellvibeMono(
                    context,
                    size: 10.5,
                    color: tokens.textSubtle,
                  ),
                ),
              ],
            ),
          ),
          ShellVibeIconButton(
            icon: LucideIcons.refreshCw,
            tooltip: 'Refresh All',
            onPressed: onRefresh,
          ),
          const SizedBox(width: 10),
          // The queue is the one thing on this screen with a running count, so
          // it is the one control that carries a badge instead of an icon.
          Tooltip(
            message: 'Transfer Queue',
            child: InkWell(
              onTap: onShowQueue,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: tokens.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: tokens.brand.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.arrowUpDown,
                      size: 15,
                      color: tokens.brandSoft,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Queue',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: tokens.brandSoft,
                      ),
                    ),
                    if (queuedCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.brand.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '$queuedCount',
                          style: shellvibeMono(
                            context,
                            size: 11,
                            color: tokens.brandSoft,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The mono column ruler above a file list.
class _FileColumnHeader extends StatelessWidget {
  const _FileColumnHeader();

  @override
  Widget build(BuildContext context) {
    final style = shellvibeMono(
      context,
      size: 10,
      letterSpacing: 1.2,
      color: ShellVibeTokens.resolve(context).textSubtle,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Row(
        children: [
          const SizedBox(width: 26),
          Expanded(child: Text('NAME', style: style)),
          SizedBox(
            width: 84,
            child: Text('SIZE', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 96,
            child: Text('MODIFIED', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

/// The summary strip along the bottom edge of a file pane.
class _PaneFooter extends StatelessWidget {
  final String summary;

  const _PaneFooter({required this.summary});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.textPrimary.withValues(alpha: 0.02),
        border: Border(
          top: BorderSide(color: tokens.textPrimary.withValues(alpha: 0.05)),
        ),
      ),
      child: Text(
        summary,
        style: shellvibeMono(context, size: 11, color: tokens.textSubtle),
      ),
    );
  }
}
