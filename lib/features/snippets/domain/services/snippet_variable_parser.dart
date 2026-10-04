/// Parser for dynamic variable placeholders in snippets and runbooks.
///
/// Only `${INPUT:VarName}` is a placeholder the user is prompted for. A plain
/// `${NAME}` is a shell variable (`${HOME}`, `${PWD}`, `${1:-x}` ...) and is
/// left exactly as written: treating it as a prompt turned every snippet that
/// used the shell's own expansion into a form, and substituting a blank into
/// it silently changed what the command did.
///
/// `${SV:NAME}` is the other kind: a value taken from the machine the command
/// runs on (see [builtinNames]), filled in per host and never prompted for.
/// The `SV:` prefix cannot collide with a shell variable, which cannot contain
/// a colon in its name.
class SnippetVariableParser {
  static final _inputRegex = RegExp(r'\$\{INPUT:([a-zA-Z0-9_]+)\}');
  static final _builtinRegex = RegExp(r'\$\{SV:([A-Z_]+)\}');

  /// The per-host values `${SV:...}` can stand for.
  static const List<String> builtinNames = [
    'HOST',
    'HOST_LABEL',
    'USER',
    'PORT',
  ];

  /// Extracts the unique `${SV:…}` names in [code], known or not.
  static List<String> extractBuiltins(String code) => {
    for (final match in _builtinRegex.allMatches(code)) match.group(1)!,
  }.toList();

  /// Substitutes `${SV:…}` placeholders in [code] from [values]. A name with no
  /// entry is left as written, so a typo shows instead of vanishing.
  static String substituteBuiltins(String code, Map<String, String> values) {
    return code.replaceAllMapped(_builtinRegex, (match) {
      return values[match.group(1)] ?? match.group(0)!;
    });
  }

  /// Extracts unique `${INPUT:…}` variable names from [code].
  static List<String> extractVariables(String code) {
    final vars = <String>{};
    for (final match in _inputRegex.allMatches(code)) {
      final name = match.group(1);
      if (name != null && name.isNotEmpty) {
        vars.add(name);
      }
    }
    return vars.toList();
  }

  /// Substitutes `${INPUT:…}` placeholders in [code] using [values].
  ///
  /// A placeholder with no entry in [values] is left in place rather than
  /// blanked, so a missing value is visible instead of becoming an empty
  /// argument.
  static String substituteVariables(String code, Map<String, String> values) {
    return code.replaceAllMapped(_inputRegex, (match) {
      return values[match.group(1)] ?? match.group(0)!;
    });
  }
}
