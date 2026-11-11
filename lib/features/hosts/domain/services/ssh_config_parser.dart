import '../models/ssh_config_models.dart';

/// Tokenizer for the OpenSSH `ssh_config(5)` file format.
///
/// Implements the syntax rules from the man page:
/// * `#` starts a comment outside quotes (both full-line and trailing)
/// * the keyword is separated from its values by whitespace or a single `=`
/// * double or single quotes group arguments containing spaces
/// * `\` escapes only what OpenSSH's argument splitter escapes: `\\`, `\"`,
///   `\'` and, outside quotes, `\ `. Any other backslash is literal, so a
///   Windows path such as `C:\Users\me\.ssh\id_ed25519` survives intact.
///
/// There is no line continuation: a trailing `\` is part of the value.
///
/// Keywords are lowercased; arguments keep their case.
class SshConfigParser {
  const SshConfigParser();

  SshConfigDocument parse(String content, {String? source}) {
    final directives = <SshConfigDirective>[];
    final warnings = <SshConfigWarning>[];
    final lines = content.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final directive = _parseLine(lines[i], source, i + 1, warnings);
      if (directive != null) directives.add(directive);
    }

    return SshConfigDocument(directives: directives, warnings: warnings);
  }

  /// True when `line[i]` is a backslash that escapes the character after it.
  static bool _isEscape(String line, int i, {required bool inQuote}) {
    if (line[i] != '\\' || i + 1 >= line.length) return false;
    final next = line[i + 1];
    return next == '\\' ||
        next == '"' ||
        next == "'" ||
        (!inQuote && next == ' ');
  }

  /// Cuts `#` comments (outside quotes) and returns the trimmed remainder.
  String _stripComment(String raw) {
    String? quote;
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (_isEscape(raw, i, inQuote: quote != null)) {
        i++; // escaped char: skip both
        continue;
      }
      if (quote == null && (c == '"' || c == "'")) {
        quote = c;
        continue;
      }
      if (c == quote) {
        quote = null;
        continue;
      }
      if (c == '#' && quote == null) {
        return raw.substring(0, i).trim();
      }
    }
    return raw.trim();
  }

  SshConfigDirective? _parseLine(
    String raw,
    String? source,
    int line,
    List<SshConfigWarning> warnings,
  ) {
    final cleaned = _stripComment(raw);
    if (cleaned.isEmpty) return null;

    final tokens = _tokenize(cleaned, source, line, warnings);
    if (tokens == null || tokens.isEmpty) return null;

    // Phase B: `=` keyword separation. `HostName=foo` and `Host = foo` both
    // mean keyword `hostname` with value `foo`; `=` inside value tokens
    // (e.g. `SendEnv LC_ALL=C`) is preserved.
    String keyword;
    List<String> args;
    final first = tokens.first;
    if (first == '=') {
      if (tokens.length < 2) return null;
      keyword = tokens[1];
      args = tokens.sublist(2);
    } else {
      final eq = first.indexOf('=');
      if (eq > 0) {
        keyword = first.substring(0, eq);
        final rest = first.substring(eq + 1);
        args = rest.isEmpty ? tokens.sublist(1) : [rest, ...tokens.sublist(1)];
      } else {
        keyword = first;
        args = tokens.sublist(1);
      }
    }

    if (keyword.isEmpty) return null;
    // `Host = foo` tokenizes as [Host, =, foo]; the lone `=` is the separator.
    if (args.isNotEmpty && args.first == '=') {
      args = args.sublist(1);
    }
    if (args.isEmpty) {
      warnings.add(
        SshConfigWarning(
          source: source,
          line: line,
          message: 'Keyword "$keyword" has no arguments; line ignored.',
        ),
      );
      return null;
    }

    return SshConfigDirective(
      keyword: keyword.toLowerCase(),
      args: args,
      source: source,
      line: line,
    );
  }

  /// Splits a comment-free line into tokens, resolving quotes and `\` escapes.
  ///
  /// Returns null when the line holds nothing but an unterminated quote.
  List<String>? _tokenize(
    String line,
    String? source,
    int lineNo,
    List<SshConfigWarning> warnings,
  ) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    String? quote;
    var hasContent = false;

    void flush() {
      if (buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
      }
    }

    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (_isEscape(line, i, inQuote: quote != null)) {
        buffer.write(line[i + 1]);
        hasContent = true;
        i++;
        continue;
      }
      if (quote == null && (c == '"' || c == "'")) {
        quote = c;
        hasContent = true;
        continue;
      }
      if (c == quote) {
        quote = null;
        hasContent = true;
        continue;
      }
      if (c == ' ' || c == '\t') {
        if (quote != null) {
          buffer.write(c);
        } else {
          flush();
        }
        continue;
      }
      buffer.write(c);
      hasContent = true;
    }

    if (quote != null) {
      warnings.add(
        SshConfigWarning(
          source: source,
          line: lineNo,
          message: 'Unterminated quote; treated as end of line.',
          severity: SshConfigWarningSeverity.info,
        ),
      );
    }
    flush();
    if (!hasContent) return null;
    return tokens;
  }
}
