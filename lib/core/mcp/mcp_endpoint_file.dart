import 'dart:convert';
import 'dart:io';

/// Reads, writes, and deletes `~/.shellvibe/mcp-endpoint.json` — the
/// handshake file the standalone `shellvibe-mcp` stdio bridge reads on
/// startup to find the running app's MCP HTTP server.
///
/// **Why the raw token lives here, and only a hash lives in the database.**
/// `McpClients.tokenHash` (see `docs/mcp_plan.md` §Faz 3 and
/// `McpToken.hash`) stores a SHA-256 hash, never the raw token — but the
/// bridge binary has no access to the vault or the database at all (it is
/// pure Dart with no Flutter/Drift dependency) and
/// the only thing it can do with a hash is fail to reconnect with it. It
/// needs the *raw* token, because that is what it puts in the
/// `Authorization: Bearer <token>` header on every request it forwards.
///
/// This is also why the raw token is allowed to sit here in the clear where
/// it would never be allowed to sit in `McpClients`: this file does not
/// travel. The database is included in local backups and (per
/// `core/sync/e2ee_cloud_sync_service.dart`) in cross-device sync, so a
/// secret placed there is replicated wherever the user's data goes. This
/// file is deliberately kept out of that path — it is regenerated fresh
/// every time the app starts the MCP server and deleted when the app
/// closes — so its only protection needs to be (and is) OS file
/// permissions on the single machine it was written on.
class McpEndpointFile {
  const McpEndpointFile._();

  static const String _dirName = '.shellvibe';
  static const String _fileName = 'mcp-endpoint.json';
  static const int _version = 1;

  /// Resolves `~/.shellvibe/mcp-endpoint.json` for the current user.
  ///
  /// Home directory resolution is POSIX `HOME`, Windows `USERPROFILE` — the
  /// two variables `dart:io` cannot resolve for us without `path_provider`,
  /// which this file must not depend on (it is compiled into the
  /// Flutter-free `shellvibe-mcp` bridge binary; see `docs/mcp_plan.md`
  /// §"stdio köprüsü"). If neither is set we throw rather than silently
  /// falling back to, say, the current working directory — writing a file
  /// containing a live bearer token to an unexpected location is worse than
  /// failing loudly.
  static String defaultPath() {
    final home = _homeDirectory();
    return '$home${Platform.pathSeparator}$_dirName${Platform.pathSeparator}'
        '$_fileName';
  }

  static String _homeDirectory() {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError(
        'Cannot resolve the home directory: neither HOME nor USERPROFILE '
        'is set in the environment. Refusing to guess a location for '
        'mcp-endpoint.json.',
      );
    }
    return home;
  }

  /// Writes the handshake file the bridge reads to reach the running app at
  /// [path] (defaulting to [defaultPath]).
  ///
  /// The containing directory (`~/.shellvibe/`) is created with mode
  /// `0700` and the file itself with mode `0600`. `dart:io` has no direct
  /// chmod API, so permissions are applied by shelling out to the `chmod`
  /// binary on POSIX; this is skipped entirely on Windows, where ACLs work
  /// differently and the concept doesn't map onto a POSIX mode bit.
  ///
  /// These permissions are not a nice-to-have here: `README.md`
  /// ("macOS App Sandbox is disabled") documents that this app deliberately
  /// runs unsandboxed on macOS (release and debug) so the Local Shell
  /// feature can exec the user's real login shell — the same is true on
  /// the other desktop platforms this file targets. With no sandbox
  /// container isolating the app's files from the rest of the user's
  /// account, the 0700/0600 modes set here are the *only* thing standing
  /// between this file's raw bearer token and any other process running as
  /// the same OS user.
  static Future<void> write({
    required int port,
    required String token,
    required int pid,
    String? path,
  }) async {
    final file = File(path ?? defaultPath());
    final dir = Directory(file.parent.path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await _chmod('0700', dir.path);

    // The token must never touch a file that is still at the default umask
    // mode. Creating (or truncating) the file empty first means the only
    // window in which it is world-readable is a window in which it holds
    // nothing; by the time the payload below goes in, the mode is already
    // 0600. Writing first and tightening afterwards would publish a live
    // bearer token to every other process on the machine for the duration
    // of two syscalls.
    await file.writeAsString('', flush: true);
    try {
      await _chmod('0600', file.path);
    } on Object {
      // A file we could not lock down is worse than no file at all: the
      // bridge treats a missing file as "app not running" and retries,
      // which is a recoverable state, while a readable one leaks the token
      // for as long as the app runs.
      try {
        await file.delete();
      } catch (_) {}
      rethrow;
    }

    final payload = <String, Object?>{
      'port': port,
      'token': token,
      'pid': pid,
      'version': _version,
    };
    await file.writeAsString(json.encode(payload), flush: true);
  }

  /// Applies [mode] to [path], throwing if `chmod` did not actually apply it.
  ///
  /// An unchecked `Process.run` is indistinguishable from success here: if
  /// `chmod` fails — missing binary, a path on a filesystem that ignores mode
  /// bits, a sandbox denying it — the file simply stays at whatever the umask
  /// gave it, permanently, with nothing in the logs to say so.
  static Future<void> _chmod(String mode, String path) async {
    // Windows has no POSIX mode bits to set here; NTFS ACLs are a different
    // model entirely and are intentionally left at their inherited default
    // rather than approximated.
    if (Platform.isWindows) return;

    final result = await Process.run('chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Failed to restrict permissions to $mode (chmod exited with '
        '${result.exitCode}: ${result.stderr}). Refusing to leave a file '
        'holding a live MCP bearer token at its default permissions.',
        path,
      );
    }
  }

  /// Reads and parses the handshake file at [path] (defaulting to
  /// [defaultPath]).
  ///
  /// Returns `null` — rather than throwing — both when the file does not
  /// exist and when it exists but fails to parse as the expected shape. The
  /// bridge calls this on every reconnect attempt; a stale file left behind
  /// by a previous crash, a half-written file caught mid-[write], or a file
  /// from a future/older incompatible version must not crash the bridge —
  /// it should simply report "not available yet" and let the caller retry
  /// or surface a human-readable "app not running" error (see
  /// `docs/mcp_plan.md` §"stdio köprüsü").
  static Future<McpEndpointData?> read([String? path]) async {
    final file = File(path ?? defaultPath());
    if (!await file.exists()) return null;

    try {
      final raw = await file.readAsString();
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final port = decoded['port'];
      final token = decoded['token'];
      final pid = decoded['pid'];
      final version = decoded['version'];
      if (port is! int ||
          token is! String ||
          token.isEmpty ||
          pid is! int ||
          version is! int) {
        return null;
      }

      return McpEndpointData(
        port: port,
        token: token,
        pid: pid,
        version: version,
      );
    } on FormatException {
      return null;
    } on IOException {
      return null;
    }
  }

  /// Deletes the handshake file at [path] (defaulting to [defaultPath]), if
  /// present. Called when the app shuts down or turns the MCP server off, so
  /// a stale file never points the bridge at a server that is no longer
  /// listening.
  static Future<void> delete([String? path]) async {
    final file = File(path ?? defaultPath());
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// The parsed contents of `~/.shellvibe/mcp-endpoint.json`.
class McpEndpointData {
  /// Port the app's local MCP HTTP server is listening on.
  final int port;

  /// Raw bearer token the bridge sends as `Authorization: Bearer <token>`.
  final String token;

  /// Process id of the app instance that wrote this file, so the bridge (or
  /// a future health check) can tell a genuinely stopped app apart from one
  /// that simply hasn't cleaned up its endpoint file yet.
  final int pid;

  /// Schema version of this file's JSON shape.
  final int version;

  const McpEndpointData({
    required this.port,
    required this.token,
    required this.pid,
    required this.version,
  });

  @override
  String toString() =>
      'McpEndpointData(port: $port, pid: $pid, version: $version)';
}
