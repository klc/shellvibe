import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:terly2/features/vault/presentation/notifiers/identities_notifier.dart';
import '../notifiers/host_groups_notifier.dart';
import '../notifiers/hosts_notifier.dart';
import '../../domain/models/host_model.dart';

class HostFormDialog extends ConsumerStatefulWidget {
  final HostModel? initialHost;
  final String workspaceId;

  const HostFormDialog({
    super.key,
    this.initialHost,
    this.workspaceId = 'default',
  });

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
    _portController = TextEditingController(text: (init?.port ?? 22).toString());
    _colorTagController = TextEditingController(text: init?.colorTag ?? '');
    _hostnameFocusNode = FocusNode();

    _hostnameFocusNode.addListener(() {
      if (!_hostnameFocusNode.hasFocus) {
        _parseHostnameInput();
      }
    });

    _protocol = init?.protocol ?? 'ssh';
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
    _hostnameFocusNode.dispose();
    super.dispose();
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
      final notifier = ref.read(hostsNotifierProvider.notifier);
      final isEditing = widget.initialHost != null;
      final portVal = int.tryParse(_portController.text.trim()) ?? 22;
      final usernameVal = _usernameController.text.trim().isEmpty ? null : _usernameController.text.trim();

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
          colorTag: _colorTagController.text.trim().isEmpty ? null : _colorTagController.text.trim(),
          jumpHostId: _selectedJumpHostId,
        );
      } else {
        await notifier.addHost(
          workspaceId: widget.workspaceId,
          groupId: _selectedGroupId,
          identityId: _selectedIdentityId,
          label: _labelController.text.trim(),
          hostname: _hostnameController.text.trim(),
          username: usernameVal,
          port: portVal,
          protocol: _protocol,
          colorTag: _colorTagController.text.trim().isEmpty ? null : _colorTagController.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialHost != null;
    final groupsAsync = ref.watch(hostGroupsNotifierProvider);
    final identitiesAsync = ref.watch(identitiesNotifierProvider);
    final hostsAsync = ref.watch(hostsNotifierProvider);

    return ShadDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.server, size: 20),
          const SizedBox(width: 8),
          Text(isEditing ? 'Edit Server Host' : 'Add Server Host'),
        ],
      ),
      description: const Text('Configure remote connection details for this workstation.'),
      actions: [
        ShadButton.outline(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          key: const Key('host_save_button'),
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Update' : 'Save'),
        ),
      ],
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('host_label_input'),
                  controller: _labelController,
                  decoration: const InputDecoration(
                    labelText: 'Label / Name',
                    hintText: 'e.g. AWS Production Web',
                    prefixIcon: Icon(LucideIcons.tag, size: 16),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Label is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('host_hostname_input'),
                  focusNode: _hostnameFocusNode,
                  controller: _hostnameController,
                  decoration: const InputDecoration(
                    labelText: 'Hostname / IP Address',
                    hintText: 'e.g. 192.168.1.10 or root@192.168.1.10',
                    prefixIcon: Icon(LucideIcons.globe, size: 16),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Hostname is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('host_username_input'),
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'e.g. root or admin',
                    prefixIcon: Icon(LucideIcons.user, size: 16),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        key: const Key('host_protocol_dropdown'),
                        initialValue: _protocol,
                        decoration: const InputDecoration(
                          labelText: 'Protocol',
                          prefixIcon: Icon(LucideIcons.terminal, size: 16),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'ssh', child: Text('SSH')),
                          DropdownMenuItem(value: 'mosh', child: Text('Mosh')),
                          DropdownMenuItem(value: 'local', child: Text('Local Shell')),
                          DropdownMenuItem(value: 'serial', child: Text('Serial')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _protocol = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        key: const Key('host_port_input'),
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (int.tryParse(v) == null) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Group Selection
                groupsAsync.when(
                  data: (groups) => DropdownButtonFormField<String?>(
                    key: const Key('host_group_dropdown'),
                    initialValue: _selectedGroupId,
                    decoration: const InputDecoration(
                      labelText: 'Group / Folder',
                      prefixIcon: Icon(LucideIcons.folder, size: 16),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('(None - Ungrouped)'),
                      ),
                      ...groups.map(
                        (g) => DropdownMenuItem<String?>(
                          value: g.id,
                          child: Text(g.name),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => _selectedGroupId = val),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, s) => Text('Error loading groups: $e'),
                ),
                const SizedBox(height: 12),
                // Identity Selection
                identitiesAsync.when(
                  data: (identities) => DropdownButtonFormField<String?>(
                    key: const Key('host_identity_dropdown'),
                    initialValue: _selectedIdentityId,
                    decoration: const InputDecoration(
                      labelText: 'Identity / Credentials',
                      prefixIcon: Icon(LucideIcons.keyRound, size: 16),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('(None - Prompt on Connect)'),
                      ),
                      ...identities.map(
                        (i) => DropdownMenuItem<String?>(
                          value: i.id,
                          child: Text('${i.title} (${i.username})'),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => _selectedIdentityId = val),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, s) => Text('Error loading identities: $e'),
                ),
                const SizedBox(height: 12),
                // Jump Host Selection
                hostsAsync.when(
                  data: (hosts) {
                    final candidateJumpHosts = hosts
                        .where((h) => isEditing ? h.id != widget.initialHost!.id : true)
                        .toList();

                    return DropdownButtonFormField<String?>(
                      key: const Key('host_jumphost_dropdown'),
                      initialValue: _selectedJumpHostId,
                      decoration: const InputDecoration(
                        labelText: 'Jump Host (Bastion)',
                        prefixIcon: Icon(LucideIcons.route, size: 16),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('(Direct Connection)'),
                        ),
                        ...candidateJumpHosts.map(
                          (h) => DropdownMenuItem<String?>(
                            value: h.id,
                            child: Text('${h.label} (${h.hostname})'),
                          ),
                        ),
                      ],
                      onChanged: (val) => setState(() => _selectedJumpHostId = val),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, s) => Text('Error loading hosts: $e'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('host_colortag_input'),
                  controller: _colorTagController,
                  decoration: const InputDecoration(
                    labelText: 'Color Tag (HEX / Name)',
                    hintText: 'e.g. #4CAF50 or green',
                    prefixIcon: Icon(LucideIcons.palette, size: 16),
                    border: OutlineInputBorder(),
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

