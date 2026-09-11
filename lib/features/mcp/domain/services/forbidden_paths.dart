/// Blocks SFTP reads of paths that are almost never legitimate for an AI
/// agent to see, regardless of which host or how permissive its access mode
/// is (docs/mcp_plan.md, "SFTP" — yasak yol listesi, category `secret_read`).
///
/// The [builtIn] list can be extended by the user through settings (see
/// [ForbiddenPaths.new]) but the entries themselves can never be removed:
/// they cover files whose entire purpose is holding a credential (private
/// keys, `.aws/credentials`, `/etc/shadow`, ...). There is no scoped or
/// per-host reason to read one of these over SFTP — a workflow that appears
/// to need it is almost certainly a workflow that should be redesigned, not
/// a reason to open the hole. Making the built-ins removable would let a
/// single misconfigured or compromised MCP client re-open every path this
/// guard exists to close.
class ForbiddenPaths {
  const ForbiddenPaths({this.extraGlobs = const []});

  /// User-added globs, checked in addition to [builtIn]. Never used to
  /// remove a built-in entry — there is no mechanism for that.
  final List<String> extraGlobs;

  /// Built-in forbidden globs from the plan. `**` crosses path separators,
  /// `*` does not, `?` matches exactly one non-separator character.
  static const List<String> builtIn = [
    '**/.ssh/id_*',
    '**/.env*',
    '/etc/shadow',
    '/etc/gshadow',
    '**/*.pem',
    '**/*.key',
    '**/credentials*',
    '**/.aws/credentials',
    '**/.netrc',
    '**/.pgpass',
    '**/.git-credentials',
  ];

  /// [builtIn] compiled once, at first use, rather than on every
  /// [isForbidden] call.
  static final List<RegExp> _builtInPatterns = builtIn
      .map(_globToRegExp)
      .toList(growable: false);

  /// Memoizes compiled [extraGlobs] patterns across calls. [extraGlobs] is
  /// caller-supplied (not knowable at compile time), and this class has a
  /// `const` constructor so it cannot precompute them once in an
  /// initializer the way [_builtInPatterns] is — this cache gets the same
  /// "compile once, match many times" behavior without giving up `const`.
  static final Map<String, RegExp> _extraGlobCache = {};

  /// True if [path] (after normalization) matches a built-in or extra glob.
  bool isForbidden(String path) {
    final normalized = _normalize(path);

    for (final pattern in _builtInPatterns) {
      if (pattern.hasMatch(normalized)) return true;
    }

    for (final glob in extraGlobs) {
      final pattern = _extraGlobCache.putIfAbsent(
        glob,
        () => _globToRegExp(glob),
      );
      if (pattern.hasMatch(normalized)) return true;
    }

    return false;
  }

  /// Collapses repeated `/` and resolves `.` / `..` segments so that
  /// `/etc/../etc/shadow` and `/etc//shadow` both normalize to
  /// `/etc/shadow` and are caught by the same glob a plain `/etc/shadow`
  /// would be.
  static String _normalize(String path) {
    final isAbsolute = path.startsWith('/');
    final segments = <String>[];

    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue; // collapses "//" and drops "."
      }
      if (segment == '..') {
        if (segments.isNotEmpty) {
          segments.removeLast();
        }
        // ".." above the root is a no-op rather than an error here: this
        // guard only needs to compare paths, not validate them.
        continue;
      }
      segments.add(segment);
    }

    final joined = segments.join('/');
    return isAbsolute ? '/$joined' : joined;
  }

  /// Translates one glob into an anchored [RegExp]. Implemented by hand
  /// (no package dependency) per the plan: `**/` is a directory-crossing,
  /// optional-depth prefix (so `**/credentials*` matches both
  /// `/a/b/credentials` and a bare `credentials`); a bare `**` elsewhere
  /// crosses separators without being optional; `*` matches within one path
  /// segment; `?` matches exactly one non-separator character; every other
  /// character is matched literally, with regex metacharacters escaped.
  static RegExp _globToRegExp(String glob) {
    final buffer = StringBuffer('^');
    var i = 0;

    while (i < glob.length) {
      final char = glob[i];

      if (char == '*' && i + 1 < glob.length && glob[i + 1] == '*') {
        if (i + 2 < glob.length && glob[i + 2] == '/') {
          buffer.write('(?:.*/)?'); // "**/" — zero or more path segments
          i += 3;
        } else {
          buffer.write('.*'); // bare "**" — crosses separators
          i += 2;
        }
        continue;
      }

      if (char == '*') {
        buffer.write('[^/]*');
        i++;
        continue;
      }

      if (char == '?') {
        buffer.write('[^/]');
        i++;
        continue;
      }

      if (r'.^$+{}()|[]\'.contains(char)) {
        buffer
          ..write('\\')
          ..write(char);
        i++;
        continue;
      }

      buffer.write(char);
      i++;
    }

    buffer.write(r'$');
    return RegExp(buffer.toString());
  }
}
