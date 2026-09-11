import 'dart:io';

import 'package:flutter/foundation.dart';

/// Overrides the runtime platform in tests without changing Flutter globals.
@visibleForTesting
TargetPlatform? debugPlatformCapabilitiesOverride;

/// Whether the current platform uses the mobile ShellVibe feature surface.
bool get isMobilePlatform {
  if (kIsWeb) return false;
  final override = debugPlatformCapabilitiesOverride;
  if (override != null) {
    return override == TargetPlatform.android || override == TargetPlatform.iOS;
  }
  return Platform.isAndroid || Platform.isIOS;
}

/// Local PTY sessions are intentionally exposed only on desktop platforms.
bool get supportsLocalShell => !isMobilePlatform;
