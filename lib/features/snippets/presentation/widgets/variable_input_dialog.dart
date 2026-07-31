import 'package:flutter/material.dart';

/// Dialog to prompt the user for variable inputs in placeholders.
class VariableInputDialog extends StatefulWidget {
  final List<String> variables;
  final String title;

  const VariableInputDialog({
    super.key,
    required this.variables,
    this.title = 'Variable Inputs Required',
  });

  static Future<Map<String, String>?> show(
    BuildContext context, {
    required List<String> variables,
    String title = 'Variable Inputs Required',
  }) {
    if (variables.isEmpty) return Future.value({});
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => VariableInputDialog(
        variables: variables,
        title: title,
      ),
    );
  }

  @override
  State<VariableInputDialog> createState() => _VariableInputDialogState();
}

class _VariableInputDialogState extends State<VariableInputDialog> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final v in widget.variables) {
      _controllers[v] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widget.variables.map((v) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: TextField(
                key: Key('variable_input_$v'),
                controller: _controllers[v],
                decoration: InputDecoration(
                  labelText: v,
                  hintText: 'Enter value for \${INPUT:$v}',
                  border: const OutlineInputBorder(),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('variable_input_confirm_button'),
          onPressed: () {
            final result = <String, String>{};
            _controllers.forEach((key, controller) {
              result[key] = controller.text;
            });
            Navigator.of(context).pop(result);
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
