import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:terly2/app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Setup global Flutter framework error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exception}\n${details.stack}');
  };

  // Setup global uncaught platform/async error handling
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[PlatformDispatcher Error] $error\n$stack');
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

