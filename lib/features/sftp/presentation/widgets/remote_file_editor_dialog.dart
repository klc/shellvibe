import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../domain/models/sftp_file_item.dart';
import '../providers/sftp_providers.dart';

class RemoteFileEditorDialog extends ConsumerStatefulWidget {
  final SftpFileItem fileItem;

  const RemoteFileEditorDialog({
    super.key,
    required this.fileItem,
  });

  @override
  ConsumerState<RemoteFileEditorDialog> createState() => _RemoteFileEditorDialogState();
}

class _RemoteFileEditorDialogState extends ConsumerState<RemoteFileEditorDialog> {
  late TextEditingController _textController;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  bool _isModified = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _loadFileContent();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadFileContent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Check size to prevent memory lock (> 5MB)
    const maxSizeBytes = 5 * 1024 * 1024;
    if (widget.fileItem.size > maxSizeBytes) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'File is too large to edit directly (${widget.fileItem.formattedSize}). Maximum supported size is 5 MB.';
        });
      }
      return;
    }

    try {
      final content = await ref.read(sftpNotifierProvider.notifier).readRemoteFileContent(widget.fileItem.path);
      if (mounted) {
        _textController.text = content;
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load file: $e';
        });
      }
    }
  }

  Future<void> _saveFileContent() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(sftpNotifierProvider.notifier)
          .saveRemoteFileContent(widget.fileItem.path, _textController.text);
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isModified = false;
        });
        ShadToaster.of(context).show(
          const ShadToast(
            title: Text('File saved successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to save file: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: Row(
        children: [
          const Icon(Icons.edit_note, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.fileItem.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (_isModified)
                      const Text(' *', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                  ],
                ),
                Text(
                  widget.fileItem.path,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (_isSaving)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          ShadButton(
            onPressed: _isModified && !_isLoading ? _saveFileContent : null,
            leading: const Icon(Icons.save, size: 18),
            child: const Text('Save'),
          ),
        ShadIconButton.ghost(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: SizedBox(
        width: 850,
        height: 550,
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Body
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Reading remote file over SFTP...'),
                    ],
                  ),
                ),
              )
            else if (_errorMessage != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
                      const SizedBox(height: 16),
                      ShadButton(
                        onPressed: _loadFileContent,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    controller: _textController,
                    maxLines: null,
                    expands: true,
                    onChanged: (_) {
                      if (!_isModified) {
                        setState(() => _isModified = true);
                      }
                    },
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFFD4D4D4),
                    ),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.all(12),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

