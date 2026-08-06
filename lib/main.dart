import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:terly2/app/app.dart';

/// Appends one crash record to `crash.log` in the app support directory.
///
/// `debugPrint` alone is a no-op in release builds (stdout isn't attached),
/// so without this a release crash leaves zero trace. This is deliberately
/// just a local file, not a telemetry SDK — good enough to ask a user for
/// the file after a report, not for aggregate crash visibility.
Future<void> _logCrashToFile(String tag, Object error, StackTrace? stack) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/crash.log');
    final entry = StringBuffer()
      ..writeln('--- ${DateTime.now().toIso8601String()} [$tag] ---')
      ..writeln(error.toString())
      ..writeln(stack?.toString() ?? '');
    await file.writeAsString(entry.toString(), mode: FileMode.append, flush: true);
  } catch (_) {
    // Logging must never throw back into the error handler.
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Setup global Flutter framework error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exception}\n${details.stack}');
    unawaited(_logCrashToFile('FlutterError', details.exception, details.stack));
  };

  // Setup global uncaught platform/async error handling
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[PlatformDispatcher Error] $error\n$stack');
    unawaited(_logCrashToFile('PlatformDispatcher', error, stack));
    return true; // prevent unhandled crash propagation
  };

  // Desktop window manager initialization
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await windowManager.ensureInitialized();
    } catch (e) {
      debugPrint('[WindowManager Init Warning] $e');
    }
  }

  runApp(
    const ProviderScope(
      child: TerlyApp(),
    ),
  );
}

