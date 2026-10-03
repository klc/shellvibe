/// Parser for dynamic variable placeholders in snippets and runbooks.
///
/// Only `${INPUT:VarName}` is a placeholder the user is prompted for. A plain
/// `${NAME}` is a shell variable (`${HOME}`, `${PWD}`, `${1:-x}` ...) and is
/// left exactly as written: treating it as a prompt turned every snippet that
/// used the shell's own expansion into a form, and substituting a blank into
/// it silently changed what the command did.
class SnippetVariableParser {
  static final _inputRegex = RegExp(r'\$\{INPUT:([a-zA-Z0-9_]+)\}');

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
