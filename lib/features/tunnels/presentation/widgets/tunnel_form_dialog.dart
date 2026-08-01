import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../domain/models/tunnel_rule_model.dart';

class TunnelFormDialog extends ConsumerStatefulWidget {
  final TunnelRuleModel? rule;
  final String? defaultHostId;

  const TunnelFormDialog({
    super.key,
    this.rule,
    this.defaultHostId,
  });

  @override
  ConsumerState<TunnelFormDialog> createState() => _TunnelFormDialogState();
}

class _TunnelFormDialogState extends ConsumerState<TunnelFormDialog> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedHostId;
  String _ruleType = 'local'; // 'local', 'remote', 'dynamic'
  late TextEditingController _localPortController;
  late TextEditingController _remoteHostController;
  late TextEditingController _remotePortController;
  bool _autoStart = false;

  List<Host> _hosts = [];
  bool _isLoadingHosts = true;

  @override
  void initState() {
    super.initState();
    _selectedHostId = widget.rule?.hostId ?? widget.defaultHostId;
    _ruleType = widget.rule?.type ?? 'local';
    _localPortController = TextEditingController(
      text: widget.rule?.localPort.toString() ?? '8080',
    );
    _remoteHostController = TextEditingController(
      text: widget.rule?.remoteHost ?? '127.0.0.1',
    );
    _remotePortController = TextEditingController(
      text: widget.rule?.remotePort?.toString() ?? '80',
    );
    _autoStart = widget.rule?.autoStart ?? false;

    _loadHosts();
  }

  @override
  void dispose() {
    _localPortController.dispose();
    _remoteHostController.dispose();
    _remotePortController.dispose();
    super.dispose();
  }

  Future<void> _loadHosts() async {
    try {
      final hostsDao = ref.read(hostsDaoProvider);
      final hosts = await hostsDao.getAllHosts();
      if (mounted) {
        setState(() {
          _hosts = hosts;
          if (_selectedHostId == null && hosts.isNotEmpty) {
            _selectedHostId = hosts.first.id;
          }
          _isLoadingHosts = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingHosts = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.rule != null;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.hub_outlined, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Text(isEditing ? 'Edit Port Forwarding Rule' : 'New Port Forwarding Rule'),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Host Selector
                if (_isLoadingHosts)
                  const LinearProgressIndicator()
                else
                  DropdownButtonFormField<String>(
                    initialValue: _selectedHostId,
                    decoration: const InputDecoration(
                      labelText: 'SSH Target Host',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.dns),
                    ),
                    items: _hosts.map((host) {
                      return DropdownMenuItem<String>(
                        value: host.id,
                        child: Text('${host.label} (${host.hostname})'),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedHostId = val),
                    validator: (val) => val == null ? 'Please select a host' : null,
                  ),
                const SizedBox(height: 16),
                // Rule Type Selector
                const Text('Tunnel Type:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'local',
                      label: Text('Local (-L)'),
                      icon: Icon(Icons.arrow_forward),
                    ),
                    ButtonSegment(
                      value: 'remote',
                      label: Text('Remote (-R)'),
                      icon: Icon(Icons.arrow_back),
                    ),
                    ButtonSegment(
                      value: 'dynamic',
                      label: Text('Dynamic (-D)'),
                      icon: Icon(Icons.sync_alt),
                    ),
                  ],
                  selected: {_ruleType},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _ruleType = newSelection.first;
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Local Port
                TextFormField(
                  controller: _localPortController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _ruleType == 'remote' ? 'Local Destination Port' : 'Local Listen Port',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.power_input),
                    helperText: 'Port on localhost (e.g. 8080, 1080)',
                  ),
                  validator: (val) {
                    final p = int.tryParse(val ?? '');
                    if (p == null || p < 1 || p > 65535) {
                      return 'Enter valid port (1-65535)';
                    }
                    return null;
                  },
                ),
                if (_ruleType != 'dynamic') ...[
                  const SizedBox(height: 16),
                  // Remote Host
                  TextFormField(
                    controller: _remoteHostController,
                    decoration: InputDecoration(
                      labelText: _ruleType == 'local' ? 'Remote Target Host' : 'Local Target IP/Host',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.computer),
                      helperText: 'e.g. 127.0.0.1 or internal.db.net',
                    ),
                    validator: (val) {
                      if (_ruleType != 'dynamic' && (val == null || val.trim().isEmpty)) {
                        return 'Host address is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Remote Port
                  TextFormField(
                    controller: _remotePortController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _ruleType == 'local' ? 'Remote Target Port' : 'Remote Listen Port',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.settings_input_component),
                      helperText: 'e.g. 80, 5432, 3306',
                    ),
                    validator: (val) {
                      if (_ruleType != 'dynamic') {
                        final p = int.tryParse(val ?? '');
                        if (p == null || p < 1 || p > 65535) {
                          return 'Enter valid port (1-65535)';
                        }
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 16),
                // Auto-start switch
                SwitchListTile(
                  title: const Text('Auto-start with SSH Connection'),
                  subtitle: const Text('Automatically open tunnel when host connects'),
                  value: _autoStart,
                  onChanged: (val) => setState(() => _autoStart = val),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check),
          label: Text(isEditing ? 'Save Changes' : 'Create Rule'),
          onPressed: _saveForm,
        ),
      ],
    );
  }

  void _saveForm() {
    if (!_formKey.currentState!.validate() || _selectedHostId == null) return;

    final localPort = int.parse(_localPortController.text.trim());
    final remoteHost = _ruleType != 'dynamic' ? _remoteHostController.text.trim() : null;
    final remotePort = _ruleType != 'dynamic' ? int.tryParse(_remotePortController.text.trim()) : null;

    final rule = TunnelRuleModel(
      id: widget.rule?.id ?? const Uuid().v4(),
      hostId: _selectedHostId!,
      type: _ruleType,
      localPort: localPort,
      remoteHost: remoteHost,
      remotePort: remotePort,
      autoStart: _autoStart,
    );

    Navigator.of(context).pop(rule);
  }
}
