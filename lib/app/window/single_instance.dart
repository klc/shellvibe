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

  /// Holds the claim for as long as the process lives. Nothing reads it but
  /// [release], which no code path calls, so an AOT build's tree shaker drops
  /// the field; the handle is then collected, its finalizer closes the file,
  /// and the lock goes with it within seconds. Every later launch found the
  /// file unlocked and started a second copy. The pragma keeps the field.
  @pragma('vm:entry-point')
  final RandomAccessFile _lock;
  final ServerSocket _server;
  final String _token;

  /// Claims this install for the current process.
  ///
  /// Returns the claim when this is the first copy; [onActivate] then runs
  /// each time a later launch asks to be shown. Returns null when another copy
  /// already holds the claim — it has been asked to show itself, and the
  /// caller should exit. Throws when the lock cannot be taken and no copy
  /// answers: a filesystem without locks, or a copy that hung. Starting then
  /// beats exiting with no window and no word.
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
      // The holder writes its port just after taking the lock, so a launch
      // right behind it (a double-click) can find the file missing or stale.
      for (var attempt = 0; attempt < 3; attempt++) {
        if (await activateRunning(portFile)) return null;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      throw StateError('the lock is held, but no running copy answered');
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

  /// Asks the copy holding the claim to show its window. Returns whether it
  /// was reached.
  ///
  /// Public for tests: two claims from one process do not contend for the
  /// lock (POSIX record locks belong to the process), so a test plays the
  /// second launch by calling this directly.
  @visibleForTesting
  static Future<bool> activateRunning(File portFile) async {
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
      return true;
    } catch (e) {
      debugPrint('[SingleInstance] could not reach the running copy: $e');
      return false;
    }
  }

  static String _newToken() {
    final random = Random.secure();
    return base64Url.encode(List.generate(18, (_) => random.nextInt(256)));
  }
}
