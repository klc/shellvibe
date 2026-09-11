import 'dart:async';

import '../models/ssh_config_models.dart';
import 'ssh_config_parser.dart';

/// Loads an ssh config file by path, or null when it cannot be read.
typedef SshConfigFileLoader = FutureOr<String?> Function(String path);

/// Lists the direct children of [dirPath], or null when the directory does
/// not exist. Results are sorted lexicographically by the caller.
typedef SshConfigDirLister = FutureOr<List<String>?> Function(String dirPath);

/// Resolves an ssh config file into concrete per-alias configurations,
/// implementing the `ssh_config(5)` semantics relevant for import:
///
/// * `Host` pattern matching — `*`, `?`, `!` negation, `|` alternation;
///   arguments (and therefore patterns) are case-sensitive
/// * first-obtained-wins for single-value options; accumulation for
///   `IdentityFile` and the forward directives
/// * `Match` evaluation — `all`, `host` (against the *resolved* hostname,
///   after `Hostname` substitution), `user`; unsupported criteria skip the
///   stanza with a warning
/// * `Include` flattening with `~`, token, env-var and glob expansion, and
///   cycle detection; relative paths resolve under `~/.ssh` (man page rule);
///   includes inside a `Host`/`Match` block are skipped with a warning
/// * `%` token expansion for `Hostname`, `User`, `IdentityFile`, `ProxyJump`,
///   `ProxyCommand` and `Include`; unresolvable tokens stay literal and are
///   reported
///
/// The class is pure Dart: all file access goes through [loader] and
/// [lister], which makes it unit-testable with in-memory fakes.
class SshConfigResolver {
  final SshConfigFileLoader loader;
  final SshConfigDirLister lister;
  final String homePath;
  final Map<String, String> environment;

  SshConfigResolver({
    required this.loader,
    required this.lister,
    required this.homePath,
    this.environment = const {},
  });

  /// Resolves [path] by loading it through [loader].
  Future<SshConfigResolution> resolveFile(String path) async {
    final content = await loader(path);
    if (content == null) {
      return SshConfigResolution(
        hosts: const [],
        warnings: [
          SshConfigWarning(
            source: path,
            message: 'Config file not found or unreadable: $path',
            severity: SshConfigWarningSeverity.error,
          ),
        ],
      );
    }
    return resolveContent(path, content);
  }

  /// Resolves already-read [content]; [path] is used for Include expansion
  /// bookkeeping and warning locations.
  Future<SshConfigResolution> resolveContent(
    String path,
    String content,
  ) async {
    final flat = await _flatten(path, content, <String>{});
    final hosts = <ResolvedSshConfig>[];
    for (final alias in _concreteAliases(flat.directives)) {
      hosts.add(_resolveAlias(flat.directives, alias));
    }

    final warnings = [...flat.warnings];
    for (final host in hosts) {
      warnings.addAll(host.warnings);
    }
    return SshConfigResolution(
      hosts: hosts,
      warnings: _dedupeWarnings(warnings),
    );
  }

  // ── Include flattening ──────────────────────────────────────────────────

  Future<SshConfigDocument> _flatten(
    String path,
    String content,
    Set<String> visited,
  ) async {
    final doc = const SshConfigParser().parse(content, source: path);
    final directives = <SshConfigDirective>[];
    final warnings = [...doc.warnings];
    var insideStanza = false;

    for (final d in doc.directives) {
      if (d.keyword == 'host' || d.keyword == 'match') {
        insideStanza = true;
        directives.add(d);
        continue;
      }
      if (d.keyword == 'include') {
        if (insideStanza) {
          warnings.add(
            SshConfigWarning(
              source: d.source,
              line: d.line,
              message:
                  'Include inside a Host/Match block is not supported '
                  'at import time; skipped.',
            ),
          );
          continue;
        }
        final expanded = await _expandIncludeArgs(d);
        for (final includePath in expanded) {
          if (!visited.add(includePath)) {
            warnings.add(
              SshConfigWarning(
                source: d.source,
                line: d.line,
                message: 'Include cycle detected for $includePath; skipped.',
              ),
            );
            continue;
          }
          final includedContent = await loader(includePath);
          if (includedContent == null) {
            warnings.add(
              SshConfigWarning(
                source: d.source,
                line: d.line,
                message: 'Included file not found: $includePath',
                severity: SshConfigWarningSeverity.info,
              ),
            );
            continue;
          }
          final sub = await _flatten(includePath, includedContent, visited);
          visited.remove(includePath);
          directives.addAll(sub.directives);
          warnings.addAll(sub.warnings);
        }
        continue;
      }
      directives.add(d);
    }

    return SshConfigDocument(directives: directives, warnings: warnings);
  }

  /// Expands one `Include` directive into concrete file paths: `~`, env vars,
  /// `%` tokens, relative-path defaulting to `~/.ssh` (man page rule), and
  /// glob expansion (`*`, `?`, `[...]`) with lexical ordering.
  Future<List<String>> _expandIncludeArgs(SshConfigDirective d) async {
    final result = <String>[];
    for (final raw in d.args) {
      var expanded = _expandPathTokens(raw, d);
      if (expanded == null) continue;
      // "Files without absolute paths are assumed to be in ~/.ssh if
      // included in a user configuration file."
      if (!expanded.startsWith('/')) {
        expanded = '$homePath/.ssh/$expanded';
      }
      if (_hasGlobChars(expanded)) {
        final dir = _dirname(expanded);
        final entries = await lister(dir);
        if (entries == null) continue;
        final pattern = _basename(expanded);
        final matches =
            entries.where((e) => _globMatch(pattern, e, classes: true)).toList()
              ..sort();
        result.addAll(matches.map((e) => _join(dir, e)));
      } else {
        result.add(expanded);
      }
    }
    return result;
  }

  // ── Alias discovery ─────────────────────────────────────────────────────

  /// Aliases that are concrete enough to import: `Host` patterns with no
  /// wildcard and no negation, after `|` alternation splitting.
  List<String> _concreteAliases(List<SshConfigDirective> directives) {
    final aliases = <String>[];
    final seen = <String>{};
    for (final d in directives) {
      if (d.keyword != 'host') continue;
      for (final pattern in d.args) {
        for (final alt in pattern.split('|')) {
          var p = alt;
          if (p.startsWith('!')) p = p.substring(1);
          if (p.isEmpty) continue;
          if (p.contains('*') || p.contains('?')) continue;
          if (seen.add(p)) aliases.add(p);
        }
      }
    }
    return aliases;
  }

  // ── Per-alias resolution ────────────────────────────────────────────────

  ResolvedSshConfig _resolveAlias(
    List<SshConfigDirective> directives,
    String alias,
  ) {
    String? hostname;
    String? username;
    int? port;
    final identityFiles = <String>[];
    final forwards = <SshForwardDraft>[];
    final warnings = <SshConfigWarning>[];
    SshJumpHostDraft? jumpHost;
    var jumpViaProxyCommand = false;
    var jumpSet = false;
    var proxyCommandSet = false;

    var stanzaActive = true;

    String effectiveHostname() => hostname ?? alias;
    String effectiveUsername() => username ?? '';
    int effectivePort() => port ?? 22;

    void warn(
      SshConfigDirective d,
      String message, [
      SshConfigWarningSeverity severity = SshConfigWarningSeverity.warning,
    ]) {
      warnings.add(
        SshConfigWarning(
          source: d.source,
          line: d.line,
          message: message,
          severity: severity,
        ),
      );
    }

    for (final d in directives) {
      switch (d.keyword) {
        case 'host':
          if (d.args.isEmpty) {
            stanzaActive = false;
            warn(
              d,
              'Host keyword requires at least one pattern; stanza '
              'ignored.',
            );
          } else {
            stanzaActive = _hostPatternsMatch(d.args, alias);
          }
          break;

        case 'match':
          final evaluation = _evaluateMatch(
            d,
            alias,
            effectiveHostname(),
            effectiveUsername(),
          );
          if (evaluation.warning != null) {
            warnings.add(evaluation.warning!);
            stanzaActive = false;
          } else {
            stanzaActive = evaluation.active;
          }
          break;

        default:
          if (!stanzaActive) break;

          switch (d.keyword) {
            case 'hostname':
              if (hostname != null) break; // first-wins
              if (d.args.length != 1) {
                warn(d, 'Hostname expects exactly one argument; ignored.');
                break;
              }
              hostname = _expandHostnameToken(d.args.first, alias, d, warn);
              break;

            case 'user':
              if (username != null) break;
              if (d.args.length != 1) {
                warn(d, 'User expects exactly one argument; ignored.');
                break;
              }
              username = _expandUserToken(
                d.args.first,
                alias,
                effectivePort(),
                d,
                warn,
              );
              break;

            case 'port':
              if (port != null) break;
              final parsed = int.tryParse(d.args.first);
              if (parsed == null || parsed < 1 || parsed > 65535) {
                warn(d, 'Invalid Port value "${d.args.first}"; ignored.');
                break;
              }
              port = parsed;
              break;

            case 'identityfile':
              for (final raw in d.args) {
                if (raw == 'none') {
                  identityFiles.clear();
                  continue;
                }
                final expanded = _expandPathTokens(
                  raw,
                  d,
                  alias: alias,
                  port: effectivePort(),
                  username: username,
                  onWarning: (msg) => warn(d, msg),
                );
                if (expanded == null) continue;
                identityFiles.add(expanded);
              }
              break;

            case 'proxyjump':
              if (jumpSet) break; // first-wins, `none` included
              jumpSet = true;
              final spec = d.args.join(' ');
              if (spec == 'none') {
                jumpHost = null;
              } else {
                jumpHost = _parseJumpSpec(spec);
                if (jumpHost == null) {
                  warn(d, 'Unparsable ProxyJump value "$spec"; ignored.');
                }
              }
              break;

            case 'proxycommand':
              if (proxyCommandSet) break;
              proxyCommandSet = true;
              final tokens = d.args;
              if (tokens.isNotEmpty &&
                  tokens.first == 'ssh' &&
                  tokens.contains('-W')) {
                final jump = _jumpFromProxyCommand(tokens);
                if (jump != null) {
                  jumpHost = jump;
                  jumpViaProxyCommand = true;
                  warn(
                    d,
                    'ProxyCommand approximated as ProxyJump to '
                    '${jump.host}; ShellVibe routes through the jump host at '
                    'connect time.',
                    SshConfigWarningSeverity.info,
                  );
                } else {
                  warn(
                    d,
                    'ProxyCommand with -W but no usable jump host; '
                    'ignored.',
                  );
                }
              } else {
                warn(d, 'ProxyCommand is not supported by ShellVibe; ignored.');
              }
              break;

            case 'localforward':
            case 'remoteforward':
            case 'dynamicforward':
              final parsed = _parseForward(d);
              final forward = parsed.draft;
              if (forward == null) {
                warn(d, 'Unsupported forward: ${parsed.reason}.');
                break;
              }
              final bind = forward.bindAddress;
              if (bind != null &&
                  bind.isNotEmpty &&
                  bind != 'localhost' &&
                  bind != '127.0.0.1' &&
                  bind != '::1') {
                warn(
                  d,
                  'Forward bind address "$bind" is not preserved by ShellVibe; '
                  'the tunnel listens on localhost only.',
                  SshConfigWarningSeverity.info,
                );
              }
              forwards.add(forward);
              break;

            case 'canonicalizehostname':
            case 'hostkeyalias':
            case 'certificatefile':
            case 'controlmaster':
            case 'controlpath':
            case 'forwardagent':
              warn(
                d,
                'Option ${_canonicalKeyword(d.keyword)} is not mapped by '
                'import; ignored.',
                SshConfigWarningSeverity.info,
              );
              break;

            default:
              // Every other option (ServerAliveInterval, TCPKeepAlive,
              // Compression, …) has no ShellVibe equivalent and is silently
              // dropped.
              break;
          }
      }
    }

    return ResolvedSshConfig(
      alias: alias,
      hostname: hostname ?? alias,
      username: username,
      port: port ?? 22,
      identityFiles: identityFiles,
      jumpHost: jumpHost,
      jumpViaProxyCommand: jumpViaProxyCommand,
      forwards: forwards,
      warnings: warnings,
    );
  }

  // ── Host pattern matching ───────────────────────────────────────────────

  /// `Host` patterns match the alias given on the command line; a negated
  /// match vetoes the stanza no matter what the positive patterns say.
  bool _hostPatternsMatch(List<String> patterns, String host) {
    var anyPositive = false;
    var positiveMatch = false;
    for (final raw in patterns) {
      final negated = raw.startsWith('!');
      final body = negated ? raw.substring(1) : raw;
      if (!negated) anyPositive = true;
      final matched = _patternListMatches(body, host);
      if (matched && negated) return false;
      if (matched && !negated) positiveMatch = true;
    }
    return !anyPositive || positiveMatch;
  }

  /// `|` alternation + case-sensitive `*`/`?` glob against [host].
  bool _patternListMatches(String patternList, String host) {
    for (final alt in patternList.split('|')) {
      if (_globMatch(alt, host, classes: false)) return true;
    }
    return false;
  }

  // ── Match evaluation ────────────────────────────────────────────────────

  static const _criterionKeywords = {
    'all',
    'canonical',
    'final',
    'exec',
    'localnetwork',
    'host',
    'originalhost',
    'tagged',
    'command',
    'user',
    'localuser',
    'version',
    'sessiontype',
  };

  ({bool active, SshConfigWarning? warning}) _evaluateMatch(
    SshConfigDirective d,
    String alias,
    String hostname,
    String username,
  ) {
    var active = true;
    final args = d.args;
    var i = 0;

    while (i < args.length) {
      var token = args[i];
      final negated = token.startsWith('!');
      if (negated) token = token.substring(1);

      if (token == 'all') {
        if (negated) active = false;
        i++;
        continue;
      }

      if (token == 'host' ||
          token == 'originalhost' ||
          token == 'user' ||
          token == 'localuser') {
        final list = <String>[];
        i++;
        while (i < args.length &&
            !_criterionKeywords.contains(_stripNegation(args[i]))) {
          list.add(args[i]);
          i++;
        }
        final patterns = list
            .expand((e) => e.split(','))
            .where((e) => e.isNotEmpty)
            .toList();

        if (token == 'localuser') {
          return (
            active: false,
            warning: SshConfigWarning(
              source: d.source,
              line: d.line,
              message:
                  'Match localuser is not supported at import time; '
                  'stanza skipped.',
            ),
          );
        }

        final target = token == 'host'
            ? hostname
            : token == 'originalhost'
            ? alias
            : username;
        var matched = _patternListWithNegation(patterns, target);
        if (negated) matched = !matched;
        if (!matched) active = false;
        continue;
      }

      // canonical, final, exec, localnetwork, tagged, command, version,
      // sessiontype — runtime-only criteria.
      return (
        active: false,
        warning: SshConfigWarning(
          source: d.source,
          line: d.line,
          message:
              'Match $token cannot be evaluated at import time; '
              'stanza skipped.',
        ),
      );
    }

    return (active: active, warning: null);
  }

  String _stripNegation(String token) =>
      token.startsWith('!') ? token.substring(1) : token;

  /// Pattern list where negated entries veto the whole match.
  bool _patternListWithNegation(List<String> patterns, String target) {
    var anyPositive = false;
    var positiveMatch = false;
    for (final raw in patterns) {
      final negated = raw.startsWith('!');
      final body = negated ? raw.substring(1) : raw;
      if (!negated) anyPositive = true;
      final matched = _patternListMatches(body, target);
      if (matched && negated) return false;
      if (matched && !negated) positiveMatch = true;
    }
    return !anyPositive || positiveMatch;
  }

  // ── Token expansion ─────────────────────────────────────────────────────

  String _expandHostnameToken(
    String value,
    String alias,
    SshConfigDirective d,
    void Function(SshConfigDirective, String) warn,
  ) {
    // Hostname accepts only %% and %h.
    return _expandTokens(
      value,
      alias: alias,
      hostname: alias,
      username: null,
      port: null,
      allowed: const {'%', 'h'},
      warn: (msg) => warn(d, msg),
    );
  }

  String _expandUserToken(
    String value,
    String alias,
    int port,
    SshConfigDirective d,
    void Function(SshConfigDirective, String) warn,
  ) {
    // User accepts all tokens except %r (self-reference).
    return _expandTokens(
      value,
      alias: alias,
      hostname: alias,
      username: null,
      port: port,
      allowed: const {'%', 'h', 'p', 'u', 'd', 'n', 'l', 'L', 'i', 'j', 'k'},
      warn: (msg) => warn(d, msg),
    );
  }

  /// Expands `~`, env vars and `%` tokens in an `IdentityFile`/`Include` path.
  ///
  /// Returns null when the path is unusable. [onWarning] receives expansion
  /// problems so the caller can attach them to the directive's location.
  String? _expandPathTokens(
    String raw,
    SshConfigDirective d, {
    String? alias,
    int? port,
    String? username,
    void Function(String message)? onWarning,
  }) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    if (s == '~') {
      return homePath;
    }
    if (s.startsWith('~/')) {
      s = '$homePath/${s.substring(2)}';
    } else if (s.startsWith('~')) {
      // ~user/… — not resolvable without a user database.
      onWarning?.call('~user path "$raw" is not supported; ignored.');
      return null;
    }

    // Env vars: $VAR and ${VAR} (Include only per man page, but harmless).
    s = s.replaceAllMapped(RegExp(r'\$\{(\w+)\}|\$(\w+)'), (m) {
      final name = m.group(1) ?? m.group(2)!;
      final value = environment[name];
      if (value == null) {
        onWarning?.call('Environment variable \$$name not found; left as-is.');
      }
      return value ?? m[0]!;
    });

    // % tokens: IdentityFile/Include accept the full token set; unresolvable
    // tokens stay literal.
    s = _expandTokens(
      s,
      alias: alias,
      hostname: alias,
      username: username,
      port: port,
      warn: onWarning,
    );

    return s;
  }

  /// Expands `%%`, `%h`, `%n`, `%p`, `%r`, `%d`; everything else stays
  /// literal. [allowed] restricts the token set when a directive accepts only
  /// a subset (Hostname, User); null means the full set.
  String _expandTokens(
    String value, {
    required String? alias,
    required String? hostname,
    required String? username,
    required int? port,
    Set<String>? allowed,
    void Function(String)? warn,
  }) {
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final c = value[i];
      if (c != '%' || i + 1 >= value.length) {
        buffer.write(c);
        continue;
      }
      final token = value[i + 1];
      i++;
      final tokenKey = token == '%' ? '%' : token;
      if (allowed != null && !allowed.contains(tokenKey)) {
        warn?.call('Token %$token is not allowed here; left as-is.');
        buffer.write('%$token');
        continue;
      }
      switch (token) {
        case '%':
          buffer.write('%');
        case 'h':
          buffer.write(hostname ?? '%h');
        case 'n':
          buffer.write(alias ?? '%n');
        case 'p':
          buffer.write(port?.toString() ?? '%p');
        case 'r':
          buffer.write(username ?? '%r');
        case 'd':
          buffer.write(homePath);
        default:
          warn?.call(
            'Token %$token cannot be expanded at import time; '
            'left as-is.',
          );
          buffer.write('%$token');
      }
    }
    return buffer.toString();
  }

  /// `[user@]host[:port]`, with bracket-wrapped IPv6 addresses. Multi-hop
  /// chains (`host1,host2`) are cut to the first hop — ShellVibe models a single
  /// jump host per connection.
  SshJumpHostDraft? _parseJumpSpec(String spec) {
    var s = spec.trim().split(',')[0].trim();
    if (s.isEmpty) return null;

    String? user;
    final at = s.lastIndexOf('@');
    if (at != -1) {
      user = s.substring(0, at).trim();
      s = s.substring(at + 1).trim();
      if (user.isEmpty) user = null;
    }

    int? port;
    if (s.startsWith('[')) {
      final close = s.indexOf(']');
      if (close == -1) return null;
      final host = s.substring(1, close);
      final rest = s.substring(close + 1);
      if (rest.startsWith(':')) {
        port = int.tryParse(rest.substring(1));
        if (port == null) return null;
      } else if (rest.isNotEmpty) {
        return null;
      }
      return SshJumpHostDraft(username: user, host: host, port: port);
    }

    final colon = s.lastIndexOf(':');
    if (colon != -1 && s.indexOf(':') == colon) {
      final p = int.tryParse(s.substring(colon + 1));
      if (p != null) {
        port = p;
        s = s.substring(0, colon);
      }
    }
    if (s.isEmpty) return null;
    return SshJumpHostDraft(username: user, host: s, port: port);
  }

  /// Extracts the jump host from `ssh -W %h:%p [user@]host` style commands.
  SshJumpHostDraft? _jumpFromProxyCommand(List<String> tokens) {
    String? jumpSpec;
    for (final t in tokens) {
      if (t == 'ssh' || t.startsWith('-')) continue;
      if (t.contains('%h') || t.contains('%p') || t.contains('%n')) continue;
      jumpSpec = t;
    }
    if (jumpSpec == null) return null;
    return _parseJumpSpec(jumpSpec);
  }

  // ── Forward parsing ─────────────────────────────────────────────────────

  /// Parses one forward directive. Returns null when the syntax is
  /// unsupported; [reason] then describes the problem for the warning.
  ({SshForwardDraft? draft, String? reason}) _parseForward(
    SshConfigDirective d,
  ) {
    final type = d.keyword == 'localforward'
        ? 'local'
        : d.keyword == 'remoteforward'
        ? 'remote'
        : 'dynamic';
    final args = d.args;
    final option = _canonicalKeyword(d.keyword);
    final raw = '${d.keyword} ${args.join(' ')}';

    if (type == 'dynamic') {
      if (args.length != 1) {
        return (
          draft: null,
          reason: 'DynamicForward expects [bind:]port: $raw',
        );
      }
      final listen = _parseListenSpec(args.first);
      if (listen == null) {
        return (
          draft: null,
          reason:
              'Unparsable or unsupported listen spec '
              '(${args.first}); Unix sockets and port 0 are not supported',
        );
      }
      return (
        draft: SshForwardDraft(
          type: type,
          localPort: listen.port,
          bindAddress: listen.bind,
          line: d.line,
        ),
        reason: null,
      );
    }

    final listen = _parseListenSpec(args.first);
    if (listen == null) {
      return (
        draft: null,
        reason:
            'Unparsable or unsupported listen spec '
            '(${args.first}); Unix sockets and port 0 are not supported',
      );
    }
    if (type == 'remote' && args.length == 1) {
      // Destination-less RemoteForward = remote SOCKS proxy; unsupported.
      return (
        draft: null,
        reason:
            'RemoteForward without a destination (remote SOCKS proxy) '
            'is not supported: $raw',
      );
    }
    if (args.length < 2) {
      return (
        draft: null,
        reason: '$option requires a host:hostport destination: $raw',
      );
    }
    final dest = _parseDestSpec(args[1]);
    if (dest == null) {
      return (
        draft: null,
        reason:
            'Unparsable destination (${args[1]}); Unix sockets and '
            'port 0 are not supported',
      );
    }
    return (
      draft: SshForwardDraft(
        type: type,
        localPort: listen.port,
        bindAddress: listen.bind,
        remoteHost: dest.host,
        remotePort: dest.port,
        line: d.line,
      ),
      reason: null,
    );
  }

  ({int port, String? bind})? _parseListenSpec(String spec) {
    if (spec.contains('/')) return null; // Unix socket
    if (spec.startsWith('[')) {
      final close = spec.indexOf(']');
      if (close == -1) return null;
      final bind = spec.substring(1, close);
      final rest = spec.substring(close + 1);
      if (!rest.startsWith(':')) return null;
      final port = int.tryParse(rest.substring(1));
      if (port == null || port == 0) return null;
      return (port: port, bind: bind);
    }
    final port = int.tryParse(spec);
    if (port != null) {
      if (port == 0) return null;
      return (port: port, bind: null);
    }
    final colon = spec.lastIndexOf(':');
    if (colon <= 0 || colon == spec.length - 1) return null;
    final bind = spec.substring(0, colon);
    final parsedPort = int.tryParse(spec.substring(colon + 1));
    if (parsedPort == null || parsedPort == 0) return null;
    return (port: parsedPort, bind: bind);
  }

  ({String host, int port})? _parseDestSpec(String spec) {
    if (spec.contains('/')) return null; // Unix socket
    String host;
    String portPart;
    if (spec.startsWith('[')) {
      final close = spec.indexOf(']');
      if (close == -1) return null;
      host = spec.substring(1, close);
      final rest = spec.substring(close + 1);
      if (!rest.startsWith(':')) return null;
      portPart = rest.substring(1);
    } else {
      final colon = spec.lastIndexOf(':');
      if (colon <= 0 || colon == spec.length - 1) return null;
      host = spec.substring(0, colon);
      portPart = spec.substring(colon + 1);
    }
    final port = int.tryParse(portPart);
    if (port == null || port == 0) return null;
    return (host: host, port: port);
  }

  // ── Small helpers ───────────────────────────────────────────────────────

  String _canonicalKeyword(String keyword) {
    switch (keyword) {
      case 'localforward':
        return 'LocalForward';
      case 'remoteforward':
        return 'RemoteForward';
      case 'dynamicforward':
        return 'DynamicForward';
      case 'canonicalizehostname':
        return 'CanonicalizeHostname';
      case 'hostkeyalias':
        return 'HostKeyAlias';
      case 'certificatefile':
        return 'CertificateFile';
      case 'controlmaster':
        return 'ControlMaster';
      case 'controlpath':
        return 'ControlPath';
      case 'forwardagent':
        return 'ForwardAgent';
      default:
        return keyword;
    }
  }

  static bool _hasGlobChars(String s) =>
      s.contains('*') || s.contains('?') || s.contains('[');

  String _dirname(String path) {
    final slash = path.lastIndexOf('/');
    if (slash <= 0) return '.';
    return path.substring(0, slash);
  }

  String _basename(String path) {
    final slash = path.lastIndexOf('/');
    return slash == -1 ? path : path.substring(slash + 1);
  }

  String _join(String dir, String name) => dir == '.' ? name : '$dir/$name';

  /// Case-sensitive `*`/`?` glob; [classes] additionally enables `[...]`
  /// character classes (glob(7) for Include paths).
  bool _globMatch(String pattern, String value, {required bool classes}) {
    // Character-class expansion: rewrite `[abc]`/`[!abc]`/`[a-z]` into a
    // predicate-free matcher by expanding to a set of alternatives is not
    // practical for a full glob; instead run a recursive matcher.
    return _globMatchRec(pattern, value, classes: classes);
  }

  bool _globMatchRec(String pattern, String value, {required bool classes}) {
    var p = 0;
    var v = 0;
    var starP = -1;
    var starV = 0;

    while (v < value.length) {
      if (p < pattern.length) {
        final pc = pattern[p];
        if (pc == '*') {
          starP = p;
          starV = v;
          p++;
          continue;
        }
        if (pc == '?' || pc == value[v]) {
          p++;
          v++;
          continue;
        }
        if (classes && pc == '[') {
          final end = pattern.indexOf(']', p + 1);
          if (end != -1) {
            var negate = false;
            var idx = p + 1;
            if (idx < end && (pattern[idx] == '!' || pattern[idx] == '^')) {
              negate = true;
              idx++;
            }
            var matched = false;
            while (idx < end) {
              if (idx + 2 < end && pattern[idx + 1] == '-') {
                final lo = pattern.codeUnitAt(idx);
                final hi = pattern.codeUnitAt(idx + 2);
                if (value.codeUnitAt(v) >= lo && value.codeUnitAt(v) <= hi) {
                  matched = true;
                }
                idx += 3;
              } else {
                if (pattern[idx] == value[v]) matched = true;
                idx++;
              }
            }
            if (matched != negate) {
              p = end + 1;
              v++;
              continue;
            }
          }
        }
      }
      if (starP != -1) {
        p = starP + 1;
        v = ++starV;
        continue;
      }
      return false;
    }
    while (p < pattern.length && pattern[p] == '*') {
      p++;
    }
    return p == pattern.length;
  }

  List<SshConfigWarning> _dedupeWarnings(List<SshConfigWarning> warnings) {
    final seen = <String>{};
    final result = <SshConfigWarning>[];
    for (final w in warnings) {
      // Per-alias resolution re-reports the same directive for every alias
      // that matches it; the summary needs one entry per problem, not per
      // alias. Keying on source+line as well as the message means two
      // distinct directives that happen to produce the same message text
      // (different line, or the same line pulled in via different Includes)
      // still surface as separate entries — the same directive always has
      // the same source+line, so its re-reports still collapse to one.
      final key = '${w.source}|${w.line}|${w.message}';
      if (seen.add(key)) result.add(w);
    }
    return result;
  }
}
