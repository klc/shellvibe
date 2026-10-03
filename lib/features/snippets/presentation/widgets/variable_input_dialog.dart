import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/variable_declaration.dart';
import '../notifiers/remembered_variables.dart';

/// Dialog to prompt the user for variable inputs in placeholders.
///
/// Each variable is asked for as it was declared: free text, a choice from a
/// list, or a secret (hidden as typed, never prefilled, never remembered).
/// Defaults are prefilled, required ones must be filled in, and the last
/// non-secret value typed for the same [memoryKey] comes back next time, for
/// this session only.
class VariableInputDialog extends ConsumerStatefulWidget {
  final List<String> variables;
  final String title;

  /// How each name is asked for. A name with no entry is required free text.
  final List<VariableDeclaration> declarations;

  /// What the remembered values are filed under, e.g. `runbook:<id>`. Null
  /// remembers nothing.
  final String? memoryKey;

  const VariableInputDialog({
    super.key,
    required this.variables,
    this.title = 'Variable Inputs Required',
    this.declarations = const [],
    this.memoryKey,
  });

  static Future<Map<String, String>?> show(
    BuildContext context, {
    required List<String> variables,
    String title = 'Variable Inputs Required',
    List<VariableDeclaration> declarations = const [],
    String? memoryKey,
  }) {
    if (variables.isEmpty) return Future.value({});
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => VariableInputDialog(
        variables: variables,
        title: title,
        declarations: declarations,
        memoryKey: memoryKey,
      ),
    );
  }

  @override
  ConsumerState<VariableInputDialog> createState() =>
      _VariableInputDialogState();
}

class _VariableInputDialogState extends ConsumerState<VariableInputDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _choices = {};
  final Set<String> _missing = {};

  VariableDeclaration _declarationOf(String name) =>
      widget.declarations.where((d) => d.name == name).firstOrNull ??
      VariableDeclaration(name: name);

  @override
  void initState() {
    super.initState();
    final remembered = widget.memoryKey == null
        ? const <String, String>{}
        : ref.read(rememberedVariablesProvider)[widget.memoryKey] ??
              const <String, String>{};
    for (final name in widget.variables) {
      final d = _declarationOf(name);
      // A secret starts empty, always: no default and no memory.
      final start = d.type == VariableType.secret
          ? ''
          : remembered[name] ?? d.defaultValue ?? '';
      switch (d.type) {
        case VariableType.enumeration:
          _choices[name] = d.options.contains(start) ? start : null;
        case VariableType.text:
        case VariableType.secret:
          _controllers[name] = TextEditingController(text: start);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _valueOf(String name) => _choices.containsKey(name)
      ? (_choices[name] ?? '')
      : _controllers[name]!.text;

  void _submit() {
    final missing = {
      for (final name in widget.variables)
        if (_declarationOf(name).required && _valueOf(name).isEmpty) name,
    };
    if (missing.isNotEmpty) {
      setState(() {
        _missing
          ..clear()
          ..addAll(missing);
      });
      return;
    }
    final result = {for (final name in widget.variables) name: _valueOf(name)};
    final key = widget.memoryKey;
    if (key != null) {
      ref.read(rememberedVariablesProvider.notifier).remember(key, {
        for (final entry in result.entries)
          if (_declarationOf(entry.key).type != VariableType.secret &&
              entry.value.isNotEmpty)
            entry.key: entry.value,
      });
    }
    Navigator.of(context).pop(result);
  }

  Widget _field(String name, ShellVibeTokens tokens) {
    final d = _declarationOf(name);
    final error = _missing.contains(name) && _valueOf(name).isEmpty;
    final Widget input = switch (d.type) {
      VariableType.enumeration => DropdownButtonFormField<String>(
        key: Key('variable_input_$name'),
        initialValue: _choices[name],
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        hint: const Text('Choose…'),
        items: [
          for (final option in d.options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (value) => setState(() => _choices[name] = value),
      ),
      VariableType.secret => ShadInput(
        key: Key('variable_input_$name'),
        controller: _controllers[name],
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        placeholder: const Text('Hidden as you type'),
      ),
      VariableType.text => ShadInput(
        key: Key('variable_input_$name'),
        controller: _controllers[name],
        placeholder: Text('Enter value for \${INPUT:$name}'),
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.displayLabel + (d.required ? '' : ' (optional)'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (d.description != null && d.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                d.description!,
                style: TextStyle(color: tokens.textMuted, fontSize: 11),
              ),
            ),
          const SizedBox(height: 4),
          input,
          if (error)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Required',
                key: Key('variable_error_$name'),
                style: TextStyle(color: tokens.danger, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return ShadDialog(
      title: Text(widget.title),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(null),
        ),
        ShellVibeButton(
          key: const Key('variable_input_confirm_button'),
          label: 'Submit',
          onPressed: _submit,
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
      // A choice is a Material dropdown, which wants a Material above it that
      // a ShadDialog does not paint.
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                for (final name in widget.variables) _field(name, tokens),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
