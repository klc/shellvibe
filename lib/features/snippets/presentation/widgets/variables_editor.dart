import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../domain/models/variable_declaration.dart';

/// The "Variables" section of the snippet and runbook editors.
///
/// It lists the `${INPUT:name}` placeholders found in the code, one row each,
/// and lets each be given a type, a default, choices and a description. The
/// parent owns the list: it passes the names it found, receives every change,
/// and on save keeps only declarations for names still in use (see
/// [declarationsToSave]).
class VariablesEditor extends StatelessWidget {
  /// The placeholders currently in the code, in order.
  final List<String> names;

  /// What has been declared so far; may name placeholders that are gone.
  final List<VariableDeclaration> declarations;

  /// One declaration changed. A single value rather than the whole list, so
  /// the parent merges it into its *current* list: two edits landing before a
  /// rebuild must not undo each other.
  final ValueChanged<VariableDeclaration> onChanged;

  const VariablesEditor({
    super.key,
    required this.names,
    required this.declarations,
    required this.onChanged,
  });

  /// The declarations worth storing: those for [names] still in use that say
  /// something beyond "required text". A name no longer used is dropped.
  static List<VariableDeclaration> declarationsToSave(
    List<String> names,
    List<VariableDeclaration> declarations,
  ) => [
    for (final d in declarations)
      if (names.contains(d.name) && !d.isPlain) d,
  ];

  /// [declarations] with [next] in place of the one of the same name.
  static List<VariableDeclaration> merge(
    List<VariableDeclaration> declarations,
    VariableDeclaration next,
  ) => [
    for (final d in declarations)
      if (d.name != next.name) d,
    next,
  ];

  VariableDeclaration _of(String name) =>
      declarations.where((d) => d.name == name).firstOrNull ??
      VariableDeclaration(name: name);

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    if (names.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'No variables yet. Write \${INPUT:name} in the code and it appears '
          'here.',
          key: const Key('variables_empty'),
          style: TextStyle(color: tokens.textMuted, fontSize: 12),
        ),
      );
    }
    // Chips and checkboxes below are Material widgets, and this is also shown
    // inside a ShadDialog, which paints no Material of its own.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final name in names)
            _VariableRow(
              key: Key('variable_row_$name'),
              declaration: _of(name),
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

class _VariableRow extends StatefulWidget {
  final VariableDeclaration declaration;
  final ValueChanged<VariableDeclaration> onChanged;

  const _VariableRow({
    super.key,
    required this.declaration,
    required this.onChanged,
  });

  @override
  State<_VariableRow> createState() => _VariableRowState();
}

class _VariableRowState extends State<_VariableRow> {
  late final _default = TextEditingController(
    text: widget.declaration.defaultValue ?? '',
  );
  late final _options = TextEditingController(
    text: widget.declaration.options.join(', '),
  );
  late final _description = TextEditingController(
    text: widget.declaration.description ?? '',
  );

  @override
  void dispose() {
    _default.dispose();
    _options.dispose();
    _description.dispose();
    super.dispose();
  }

  VariableDeclaration get _d => widget.declaration;

  List<String> get _optionList => [
    for (final o in _options.text.split(','))
      if (o.trim().isNotEmpty) o.trim(),
  ];

  /// Rebuilt from the fields as they are: the declaration is a value, so each
  /// edit hands the parent a whole new one.
  void _emit({VariableType? type, bool? required}) {
    final nextType = type ?? _d.type;
    widget.onChanged(
      VariableDeclaration(
        name: _d.name,
        type: nextType,
        label: _d.label,
        description: _description.text.isEmpty ? null : _description.text,
        // Never kept for a secret.
        defaultValue: nextType == VariableType.secret || _default.text.isEmpty
            ? null
            : _default.text,
        options: nextType == VariableType.enumeration ? _optionList : const [],
        required: required ?? _d.required,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final name = _d.name;
    Widget typeChip(VariableType type, String label, String keyName) {
      final selected = _d.type == type;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          key: Key('variable_type_${name}_$keyName'),
          onTap: () => _emit(type: type),
          borderRadius: BorderRadius.circular(tokens.radiusPill),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? tokens.brand.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(tokens.radiusPill),
              border: Border.all(
                color: selected
                    ? tokens.brand.withValues(alpha: 0.34)
                    : tokens.border,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? tokens.brand : tokens.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\${INPUT:$name}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              typeChip(VariableType.text, 'Text', 'text'),
              typeChip(VariableType.enumeration, 'Choice', 'enum'),
              typeChip(VariableType.secret, 'Secret', 'secret'),
              const Spacer(),
              Checkbox(
                key: Key('variable_required_$name'),
                value: _d.required,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => _emit(required: v ?? true),
              ),
              const Text('Required', style: TextStyle(fontSize: 11)),
            ],
          ),
          if (_d.type == VariableType.enumeration) ...[
            const SizedBox(height: 6),
            ShadInput(
              key: Key('variable_options_$name'),
              controller: _options,
              placeholder: const Text('Choices, comma separated'),
              onChanged: (_) => _emit(),
            ),
          ],
          if (_d.type != VariableType.secret) ...[
            const SizedBox(height: 6),
            ShadInput(
              key: Key('variable_default_$name'),
              controller: _default,
              placeholder: const Text('Default value (optional)'),
              onChanged: (_) => _emit(),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Hidden as typed. Never given a default, never remembered, '
                'never saved in history.',
                style: TextStyle(color: tokens.textMuted, fontSize: 11),
              ),
            ),
          const SizedBox(height: 6),
          ShadInput(
            key: Key('variable_description_$name'),
            controller: _description,
            placeholder: const Text('Description shown when asked (optional)'),
            onChanged: (_) => _emit(),
          ),
        ],
      ),
    );
  }
}

/// The helper text under a code field: what each kind of placeholder does.
class PlaceholderHelp extends StatelessWidget {
  const PlaceholderHelp({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '\${INPUT:name} is asked for when this runs. '
        '\${SV:HOST}, \${SV:HOST_LABEL}, \${SV:USER} and \${SV:PORT} are '
        "filled in from each target host and never asked. Plain \${NAME} is "
        "the shell's own.",
        key: const Key('placeholder_help'),
        style: TextStyle(color: tokens.textMuted, fontSize: 11),
      ),
    );
  }
}
