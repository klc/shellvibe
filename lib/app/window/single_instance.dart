import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Keeps one copy of the desktop app running per install and user.
///
/// With the window able to hide in the tray, launching ShellVibe again from
/// the Start menu or a launcher would otherwise start a second copy beside the
/// hidden one: two processes on one database, and the tunnels of the first
/// still running where nobody can see them. Instead the second launch asks
/// the first to show its window, and exits.
///
/// Pure Dart, so it behaves the same on Windows and Linux without touching
/// either native runner. macOS needs none of it: LaunchServices already brings
/// a running app forward instead of starting another.
///
/// The first copy holds an exclusive lock on `<name>.lock`, which the OS
/// drops when the process ends however it ends, and listens on a loopback
/// port it writes, with a random token, to `<name>.port`. A later copy that
/// cannot take the lock reads that file, sends the token, and is done. The
/// token keeps any other local process from raising the window at will.
class SingleInstance {
  SingleInstance._(this._lock, this._server, this._token);

  final RandomAccessFile _lock;
  final ServerSocket _server;
  final String _token;

  /// Claims this install for the current process.
  ///
  /// Returns the claim when this is the first copy; [onActivate] then runs
  /// each time a later launch asks to be shown. Returns null when another copy
  /// already holds the claim — it has been asked to show itself, and the
  /// caller should exit.
  ///
  /// [name] distinguishes installs sharing one [directory], e.g. a debug build
  /// beside the installed app.
  static Future<SingleInstance?> claim({
    required Directory directory,
    required String name,
    required VoidCallback onActivate,
  }) async {
    await directory.create(recursive: true);
    final lockFile = File('${directory.path}/$name.lock');
    final portFile = File('${directory.path}/$name.port');

    final lock = await lockFile.open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } on FileSystemException {
      await lock.close();
      await activateRunning(portFile);
      return null;
    }

    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final token = _newToken();
    await portFile.writeAsString(
      jsonEncode({'port': server.port, 'token': token}),
      flush: true,
    );
    final instance = SingleInstance._(lock, server, token);
    server.listen((socket) => instance._serve(socket, onActivate));
    return instance;
  }

  Future<void> _serve(Socket socket, VoidCallback onActivate) async {
    try {
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 2));
      if (line == 'show $_token') onActivate();
    } catch (_) {
      // A connection that says nothing, or the wrong thing, raises nothing.
    } finally {
      await socket.close();
    }
  }

  /// Gives the claim up; the next launch becomes the first copy.
  Future<void> release() async {
    await _server.close();
    await _lock.unlock();
    await _lock.close();
  }

  /// Asks the copy holding the claim to show its window. Best effort: if it
  /// cannot be reached this launch still exits rather than run beside it.
  ///
  /// Public for tests: two claims from one process do not contend for the
  /// lock (POSIX record locks belong to the process), so a test plays the
  /// second launch by calling this directly.
  @visibleForTesting
  static Future<void> activateRunning(File portFile) async {
    try {
      final endpoint =
          jsonDecode(await portFile.readAsString()) as Map<String, dynamic>;
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        endpoint['port'] as int,
        timeout: const Duration(seconds: 2),
      );
      socket.writeln('show ${endpoint['token']}');
      await socket.flush();
      await socket.close();
    } catch (e) {
      debugPrint('[SingleInstance] could not reach the running copy: $e');
    }
  }

  static String _newToken() {
    final random = Random.secure();
    return base64Url.encode(List.generate(18, (_) => random.nextInt(256)));
  }
}
