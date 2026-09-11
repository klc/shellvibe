import '../models/mcp_models.dart';

/// Masks secrets out of text before it reaches an AI agent.
///
/// Every byte returned by `run_command`, `sftp_read` and `read_tab_output`
/// passes through here first (see docs/mcp_plan.md, "Maskeleme motoru").
/// This engine is also the one committed to the in-app AI assistant
/// (docs/product_roadmap §3.2) — it is written once, in this file, and used
/// in two places, so a fix or a new pattern only has to happen here.
///
/// [redact] never throws on unmatched input; text with nothing to mask comes
/// back unchanged with a zero [RedactionResult.count].
class OutputRedactor {
  const OutputRedactor({this.extraPatterns = const []});

  /// Additional patterns to mask beyond the built-ins, e.g. a host-specific
  /// secret format. Each full match is replaced with `[REDACTED:custom]` —
  /// there is no way for a caller to name a type per pattern, so all of them
  /// share one label.
  final List<RegExp> extraPatterns;

  // --- Built-in patterns -----------------------------------------------
  //
  // PEM private key blocks. dotAll is required: without it `.` stops at the
  // first newline and only the `-----BEGIN ... KEY-----` header line would
  // be matched, leaving the base64 key body — the actual secret — sitting
  // in the output untouched. A partially masked key is a leaked key.
  static final RegExp _privateKeyPattern = RegExp(
    r'-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----',
    dotAll: true,
  );

  static final RegExp _awsKeyPattern = RegExp(r'AKIA[0-9A-Z]{16}');

  static final RegExp _githubTokenPattern = RegExp(
    r'gh[pousr]_[A-Za-z0-9]{36,}',
  );

  static final RegExp _apiKeyPattern = RegExp(r'sk-[A-Za-z0-9]{20,}');

  static final RegExp _jwtPattern = RegExp(
    r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]*',
  );

  // Database URLs with inline credentials. Only the `user:pass@` segment is
  // masked — the scheme and host stay visible because the agent still needs
  // to know *which* database it was talking to.
  static final RegExp _dbUrlPattern = RegExp(
    r'(?<scheme>postgres(?:ql)?|mysql|mongodb(?:\+srv)?)://(?<creds>[^@\s/]+)@',
  );

  // Generic `key: value` / `key=value` assignments. This is the broadest
  // pattern of the set (it will happily match a value that a narrower
  // pattern above already replaced with a placeholder), so it runs last —
  // see the ordering note on [redact].
  static final RegExp _assignmentPattern = RegExp(
    r'(?<key>password|passwd|secret|token|api[_-]?key)\s*[:=]\s*(?<value>\S+)',
    caseSensitive: false,
  );

  /// Runs every pattern over [input] and returns the masked text together
  /// with the total number of secrets masked.
  ///
  /// Patterns are applied most-specific first, most-generic last:
  ///
  /// 1. The private-key block pattern runs FIRST, and consumes the whole
  ///    `-----BEGIN ... -----END...-----` span in one match. If a narrower
  ///    pattern (AWS key, JWT, ...) ran first instead, it could match a
  ///    substring inside the base64 key body — base64 is dense enough that
  ///    an `AKIA`-shaped or `eyJ...`-shaped run of characters inside a key
  ///    is plausible by chance — and mask only that fragment, leaving the
  ///    rest of the key exposed while the report claims something was
  ///    handled. Redacting the whole block up front removes that risk.
  /// 2. The specific token/key formats (AWS, GitHub, API key, JWT) run next,
  ///    each replacing only its own match.
  /// 3. The database-URL pattern runs after those, masking only credentials.
  /// 4. The generic `key=value` assignment pattern runs LAST, because it is
  ///    the only pattern with no format constraint on the value — it would
  ///    otherwise be free to re-mask (and double-count) a value a more
  ///    specific pattern already replaced with a `[REDACTED:...]` marker.
  /// 5. Caller-supplied [extraPatterns] run last of all.
  ///
  /// Overlapping matches: every replacement callback below checks whether
  /// the text it is about to replace already contains a `[REDACTED:` marker
  /// and, if so, leaves it untouched and does not increment the count. This
  /// is what stops a later, broader pattern from re-redacting (and
  /// double-counting) something an earlier, narrower pattern already masked
  /// — e.g. `api_key=AKIA...` is masked once by the AWS pattern as
  /// `api_key=[REDACTED:aws_key]`; without the guard the assignment pattern
  /// would then also match `api_key=[REDACTED:aws_key]` as its own value
  /// and wrap it again, inflating the count for a single secret.
  RedactionResult redact(String input) {
    var text = input;
    var total = 0;

    for (final step in <(RegExp, String)>[
      (_privateKeyPattern, 'private_key'),
      (_awsKeyPattern, 'aws_key'),
      (_githubTokenPattern, 'github_token'),
      (_apiKeyPattern, 'api_key'),
      (_jwtPattern, 'jwt'),
    ]) {
      final result = _redactWhole(text, step.$1, step.$2);
      text = result.text;
      total += result.count;
    }

    final dbResult = _redactDbUrl(text);
    text = dbResult.text;
    total += dbResult.count;

    final assignmentResult = _redactAssignment(text);
    text = assignmentResult.text;
    total += assignmentResult.count;

    for (final pattern in extraPatterns) {
      final result = _redactWhole(text, pattern, 'custom');
      text = result.text;
      total += result.count;
    }

    return RedactionResult(text, total);
  }

  /// Replaces every full match of [pattern] with `[REDACTED:<type>]`,
  /// skipping (and not counting) a match that already contains a marker
  /// from an earlier, narrower pass.
  RedactionResult _redactWhole(String text, RegExp pattern, String type) {
    var count = 0;
    final result = text.replaceAllMapped(pattern, (match) {
      final full = match.group(0)!;
      if (full.contains('[REDACTED:')) return full;
      count++;
      return '[REDACTED:$type]';
    });
    return RedactionResult(result, count);
  }

  /// Masks only the `user:pass@` segment of a database URL, keeping the
  /// scheme and host visible.
  RedactionResult _redactDbUrl(String text) {
    var count = 0;
    final result = text.replaceAllMapped(_dbUrlPattern, (match) {
      final regExpMatch = match as RegExpMatch;
      final scheme = regExpMatch.namedGroup('scheme')!;
      final creds = regExpMatch.namedGroup('creds')!;
      if (creds.contains('[REDACTED:')) return match.group(0)!;
      count++;
      return '$scheme://[REDACTED:db_url]@';
    });
    return RedactionResult(result, count);
  }

  /// Masks only the value half of a `key: value` / `key=value` assignment,
  /// keeping the key name visible so the agent can see what kind of thing
  /// was hidden.
  RedactionResult _redactAssignment(String text) {
    var count = 0;
    final result = text.replaceAllMapped(_assignmentPattern, (match) {
      final regExpMatch = match as RegExpMatch;
      final full = regExpMatch.group(0)!;
      final value = regExpMatch.namedGroup('value')!;
      if (value.contains('[REDACTED:')) return full;
      count++;
      final prefixLength = full.length - value.length;
      return '${full.substring(0, prefixLength)}[REDACTED:assignment]';
    });
    return RedactionResult(result, count);
  }
}
