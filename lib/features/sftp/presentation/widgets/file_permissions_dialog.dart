import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../domain/models/sftp_file_item.dart';

class FilePermissionsResult {
  final int mode;
  final int? uid;
  final int? gid;

  const FilePermissionsResult({
    required this.mode,
    this.uid,
    this.gid,
  });
}

class FilePermissionsDialog extends StatefulWidget {
  final SftpFileItem item;

  const FilePermissionsDialog({
    super.key,
    required this.item,
  });

  @override
  State<FilePermissionsDialog> createState() => _FilePermissionsDialogState();
}

class _FilePermissionsDialogState extends State<FilePermissionsDialog> {
  late bool uR, uW, uX;
  late bool gR, gW, gX;
  late bool oR, oW, oX;
  late TextEditingController _uidController;
  late TextEditingController _gidController;

  @override
  void initState() {
    super.initState();
    final p = widget.item.permissions;
    // Permissions string format: d rwx rwx rwx
    final str = p.length >= 10 ? p.substring(1) : (p.length == 9 ? p : 'rwxr-xr-x');

    uR = str.isNotEmpty && str[0] == 'r';
    uW = str.length > 1 && str[1] == 'w';
    uX = str.length > 2 && (str[2] == 'x' || str[2] == 's' || str[2] == 't');

    gR = str.length > 3 && str[3] == 'r';
    gW = str.length > 4 && str[4] == 'w';
    gX = str.length > 5 && (str[5] == 'x' || str[5] == 's' || str[5] == 't');

    oR = str.length > 6 && str[6] == 'r';
    oW = str.length > 7 && str[7] == 'w';
    oX = str.length > 8 && (str[8] == 'x' || str[8] == 's' || str[8] == 't');

    _uidController = TextEditingController(text: widget.item.ownerId?.toString() ?? '');
    _gidController = TextEditingController(text: widget.item.groupId?.toString() ?? '');
  }

  @override
  void dispose() {
    _uidController.dispose();
    _gidController.dispose();
    super.dispose();
  }

  int get _calculatedMode {
    int user = (uR ? 4 : 0) + (uW ? 2 : 0) + (uX ? 1 : 0);
    int group = (gR ? 4 : 0) + (gW ? 2 : 0) + (gX ? 1 : 0);
    int others = (oR ? 4 : 0) + (oW ? 2 : 0) + (oX ? 1 : 0);

    // Convert octal (e.g. 0755) to integer
    return (user << 6) | (group << 3) | others;
  }

  String get _octalString {
    int user = (uR ? 4 : 0) + (uW ? 2 : 0) + (uX ? 1 : 0);
    int group = (gR ? 4 : 0) + (gW ? 2 : 0) + (gX ? 1 : 0);
    int others = (oR ? 4 : 0) + (oW ? 2 : 0) + (oX ? 1 : 0);
    return '$user$group$others';
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: Row(
        children: [
          const Icon(Icons.security, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Permissions: ${widget.item.name}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: () {
            final uid = int.tryParse(_uidController.text.trim());
            final gid = int.tryParse(_gidController.text.trim());
            Navigator.of(context).pop(
              FilePermissionsResult(
                mode: _calculatedMode,
                uid: uid,
                gid: gid,
              ),
            );
          },
          leading: const Icon(Icons.check, size: 16),
          child: const Text('Apply Changes'),
        ),
      ],
      child: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Octal Permissions: 0$_octalString',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent),
              ),
              const SizedBox(height: 12),
              const Text('Mode (chmod):', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Table(
                border: TableBorder.all(color: Colors.white24),
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Colors.black26),
                    children: [
                      Padding(padding: EdgeInsets.all(8), child: Text('Class', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('Read (4)')),
                      Padding(padding: EdgeInsets.all(8), child: Text('Write (2)')),
                      Padding(padding: EdgeInsets.all(8), child: Text('Execute (1)')),
                    ],
                  ),
                  TableRow(
                    children: [
                      const Padding(padding: EdgeInsets.all(8), child: Text('User')),
                      Center(child: ShadCheckbox(value: uR, onChanged: (v) => setState(() => uR = v))),
                      Center(child: ShadCheckbox(value: uW, onChanged: (v) => setState(() => uW = v))),
                      Center(child: ShadCheckbox(value: uX, onChanged: (v) => setState(() => uX = v))),
                    ],
                  ),
                  TableRow(
                    children: [
                      const Padding(padding: EdgeInsets.all(8), child: Text('Group')),
                      Center(child: ShadCheckbox(value: gR, onChanged: (v) => setState(() => gR = v))),
                      Center(child: ShadCheckbox(value: gW, onChanged: (v) => setState(() => gW = v))),
                      Center(child: ShadCheckbox(value: gX, onChanged: (v) => setState(() => gX = v))),
                    ],
                  ),
                  TableRow(
                    children: [
                      const Padding(padding: EdgeInsets.all(8), child: Text('Others')),
                      Center(child: ShadCheckbox(value: oR, onChanged: (v) => setState(() => oR = v))),
                      Center(child: ShadCheckbox(value: oW, onChanged: (v) => setState(() => oW = v))),
                      Center(child: ShadCheckbox(value: oX, onChanged: (v) => setState(() => oX = v))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Owner & Group (chown):', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: _uidController,
                      keyboardType: TextInputType.number,
                      placeholder: const Text('User ID (UID)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShadInput(
                      controller: _gidController,
                      keyboardType: TextInputType.number,
                      placeholder: const Text('Group ID (GID)'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

