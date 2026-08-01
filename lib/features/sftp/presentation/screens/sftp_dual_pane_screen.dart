import 'dart:math' as math;

import 'package:dartssh2/dartssh2.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/models/sftp_file_item.dart';
import '../providers/sftp_providers.dart';
import '../widgets/file_permissions_dialog.dart';
import '../widgets/remote_file_editor_dialog.dart';
import '../widgets/sftp_transfer_queue_sheet.dart';

class SftpDualPaneScreen extends ConsumerStatefulWidget {
  final SftpClient? sftpClient;
  final String? hostLabel;

  const SftpDualPaneScreen({
    super.key,
    this.sftpClient,
    this.hostLabel,
  });

  @override
  ConsumerState<SftpDualPaneScreen> createState() => _SftpDualPaneScreenState();
}

class _SftpDualPaneScreenState extends ConsumerState<SftpDualPaneScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedMobileTab = 0; // 0: Local Workstation, 1: Remote SFTP

  @override
  void initState() {
    super.initState();
    if (widget.sftpClient != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(sftpNotifierProvider.notifier).setRemoteClient(widget.sftpClient);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showQueueSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SftpTransferQueueSheet(),
    );
  }

  void _handleDragAndDropUpload(List<dynamic> droppedFiles, String remoteDirectoryPath) {
    final notifier = ref.read(sftpNotifierProvider.notifier);
    for (final file in droppedFiles) {
      final item = SftpFileItem(
        name: file.name as String,
        path: file.path as String,
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
    final state = ref.watch(sftpNotifierProvider);
    final notifier = ref.read(sftpNotifierProvider.notifier);
    final colorScheme = ShadTheme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: colorScheme.card,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.folder_copy_outlined, color: Colors.cyanAccent),
            const SizedBox(width: 10),
            Text(
              widget.hostLabel != null ? 'SFTP: ${widget.hostLabel}' : 'Dual-Pane SFTP Manager',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_alt, color: Colors.cyanAccent),
            tooltip: 'Transfer Queue',
            onPressed: _showQueueSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh All',
            onPressed: () {
              notifier.loadLocalDirectory();
              notifier.loadRemoteDirectory();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Global Search & Control Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Row(
              children: [
                Expanded(
                  child: ShadInput(
                    controller: _searchController,
                    onChanged: notifier.setSearchQuery,
                    placeholder: const Text('Filter files...'),
                    leading: const Icon(Icons.search, size: 18),
                  ),
                ),
              ],
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
                      icon: Icon(Icons.laptop, size: 16),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text(
                        state.remoteClient != null ? 'Remote SFTP' : 'Remote (Disconnected)',
                        overflow: TextOverflow.ellipsis,
                      ),
                      icon: const Icon(Icons.dns, size: 16),
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
                    : _buildRemotePane(state, notifier))
                : Row(
                    children: [
                      Expanded(child: _buildLocalPane(state, notifier)),
                      VerticalDivider(width: 1, color: colorScheme.border),
                      Expanded(child: _buildRemotePane(state, notifier)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalPane(SftpState state, SftpNotifier notifier) {
    return DropTarget(
      onDragDone: (details) => _handleDragAndDropUpload(details.files, state.remotePath),
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

  Widget _buildRemotePane(SftpState state, SftpNotifier notifier) {
    return DropTarget(
      onDragDone: (details) => _handleDragAndDropUpload(details.files, state.remotePath),
      child: _buildPane(
        title: state.remoteClient != null ? 'Remote SFTP Server' : 'Remote (Disconnected)',
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
    final colorScheme = ShadTheme.of(context).colorScheme;
    final searchQuery = ref.watch(sftpNotifierProvider).searchQuery.toLowerCase();
    final filteredFiles = searchQuery.isEmpty
        ? files
        : files.where((f) => f.name.toLowerCase().contains(searchQuery)).toList();

    return Column(
      children: [
        // Pane Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: colorScheme.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isLocal ? Icons.laptop : Icons.dns,
                    size: 18,
                    color: isLocal ? Colors.greenAccent : Colors.cyanAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isLocal && onCreateFolder != null)
                    IconButton(
                      icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                      tooltip: 'New Folder',
                      onPressed: onCreateFolder,
                    ),
                  if (!isLocal && onCreateFile != null)
                    IconButton(
                      icon: const Icon(Icons.note_add_outlined, size: 18),
                      tooltip: 'New File',
                      onPressed: onCreateFile,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              // Path Breadcrumbs bar
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 16),
                    tooltip: 'Parent Directory',
                    onPressed: onNavigateUp,
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.muted,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        path,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // File Table / List
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(error, style: const TextStyle(color: Colors.redAccent)),
                      ),
                    )
                  : filteredFiles.isEmpty
                      ? Center(child: Text('Empty Directory', style: TextStyle(color: colorScheme.mutedForeground)))
                      : ListView.separated(
                          itemCount: filteredFiles.length,
                          separatorBuilder: (_, _) => Divider(height: 1, color: colorScheme.border),
                          itemBuilder: (context, index) {
                            final item = filteredFiles[index];
                            return _buildFileItemTile(
                              item: item,
                              isLocal: isLocal,
                              onTap: () => onItemTap(item),
                              onDelete: () => onDelete(item),
                              onUpload: onUpload != null ? () => onUpload(item) : null,
                              onDownload: onDownload != null ? () => onDownload(item) : null,
                              onEditPermissions: onEditPermissions != null ? () => onEditPermissions(item) : null,
                              onEditContent: onEditContent != null ? () => onEditContent(item) : null,
                              onRename: onRename != null ? () => onRename(item) : null,
                            );
                          },
                        ),
        ),
      ],
    );
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
    final colorScheme = ShadTheme.of(context).colorScheme;
    IconData iconData;
    Color iconColor;

    if (item.isDirectory) {
      iconData = Icons.folder;
      iconColor = Colors.amber;
    } else if (item.isSymlink) {
      iconData = Icons.link;
      iconColor = Colors.purpleAccent;
    } else {
      iconData = Icons.insert_drive_file;
      iconColor = Colors.blueGrey;
    }

    return ListTile(
      dense: true,
      leading: Icon(iconData, color: iconColor, size: 20),
      title: Text(
        item.name,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${item.formattedSize} • ${item.permissions}',
        style: TextStyle(fontSize: 11, color: colorScheme.mutedForeground),
      ),
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (val) {
          if (val == 'upload' && onUpload != null) onUpload();
          if (val == 'download' && onDownload != null) onDownload();
          if (val == 'edit' && onEditContent != null) onEditContent();
          if (val == 'chmod' && onEditPermissions != null) onEditPermissions();
          if (val == 'rename' && onRename != null) onRename();
          if (val == 'delete') onDelete();
        },
        itemBuilder: (context) => [
          if (isLocal && onUpload != null)
            const PopupMenuItem(value: 'upload', child: Row(children: [Icon(Icons.upload, size: 16), SizedBox(width: 8), Text('Upload to Remote')])),
          if (!isLocal && onDownload != null)
            const PopupMenuItem(value: 'download', child: Row(children: [Icon(Icons.download, size: 16), SizedBox(width: 8), Text('Download')])),
          if (!isLocal && !item.isDirectory && onEditContent != null)
            const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Edit Content')])),
          if (!isLocal && onEditPermissions != null)
            const PopupMenuItem(value: 'chmod', child: Row(children: [Icon(Icons.security, size: 16), SizedBox(width: 8), Text('Permissions (chmod)')])),
          if (!isLocal && onRename != null)
            const PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.drive_file_rename_outline, size: 16), SizedBox(width: 8), Text('Rename')])),
          const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.redAccent, size: 16), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.redAccent))])),
        ],
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
      final notifier = ref.read(sftpNotifierProvider.notifier);
      await notifier.changeRemotePermissions(item, result.mode);
      if (result.uid != null || result.gid != null) {
        await notifier.changeRemoteOwner(item, uid: result.uid, gid: result.gid);
      }
    }
  }

  void _showCreateDialog({required bool isFolder}) async {
    final controller = TextEditingController();
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = math.min(screenWidth * 0.9, 450.0);

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: Text(isFolder ? 'Create Remote Directory' : 'Create Remote File'),
        description: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ShadInput(
                controller: controller,
                autofocus: true,
                placeholder: Text(isFolder ? 'folder_name' : 'filename.txt'),
              ),
            ],
          ),
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.of(ctx).pop(text);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name != null && name.isNotEmpty) {
      final notifier = ref.read(sftpNotifierProvider.notifier);
      if (isFolder) {
        notifier.createRemoteFolder(name);
      } else {
        notifier.createRemoteFile(name);
      }
    }
  }

  void _showRenameDialog(SftpFileItem item) async {
    final controller = TextEditingController(text: item.name);
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = math.min(screenWidth * 0.9, 450.0);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: Text('Rename ${item.name}'),
        description: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ShadInput(
                controller: controller,
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty && text != item.name) {
                Navigator.of(ctx).pop(text);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName != null && newName.isNotEmpty && newName != item.name) {
      ref.read(sftpNotifierProvider.notifier).renameRemoteItem(item, newName);
    }
  }
}

