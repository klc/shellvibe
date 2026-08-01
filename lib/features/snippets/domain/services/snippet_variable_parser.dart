/// Parser for dynamic variable placeholders in snippets and runbooks.
///
/// Supports placeholders formatted as `${INPUT:VarName}` or `${VarName}`.
class SnippetVariableParser {
  static final _inputRegex = RegExp(r'\$\{INPUT:([a-zA-Z0-9_]+)\}');
  static final _generalRegex = RegExp(r'\$\{([a-zA-Z0-9_]+)\}');

  /// Extracts unique variable names from [code].
  static List<String> extractVariables(String code) {
    final vars = <String>{};
    for (final match in _inputRegex.allMatches(code)) {
      final name = match.group(1);
      if (name != null && name.isNotEmpty) {
        vars.add(name);
      }
    }
    for (final match in _generalRegex.allMatches(code)) {
      final name = match.group(1);
      if (name != null && name.isNotEmpty && !name.startsWith('INPUT:')) {
        vars.add(name);
      }
    }
    return vars.toList();
  }

  /// Substitutes variable placeholders in [code] using [values].
  static String substituteVariables(String code, Map<String, String> values) {
    var result = code;
    final sortedKeys = values.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in sortedKeys) {
      final val = values[key] ?? '';
      result = result.replaceAll('\${INPUT:$key}', val);
      result = result.replaceAll('\${$key}', val);
    }
    return result;
  }
}
