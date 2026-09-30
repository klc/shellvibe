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

/// The platform the app runs on, honouring the same test override as
/// [isMobilePlatform] so the two can never disagree about it.
TargetPlatform get runtimeTargetPlatform =>
    debugPlatformCapabilitiesOverride ?? defaultTargetPlatform;
