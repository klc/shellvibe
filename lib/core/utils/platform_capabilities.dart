import 'dart:io';

import 'package:flutter/foundation.dart';

import 'windows_package_identity.dart';

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

/// Overrides [isWindowsStorePackage] in tests.
@visibleForTesting
bool? debugWindowsStorePackageOverride;

/// Whether this is the Windows build installed from its MSIX package (the
/// Microsoft Store build), rather than the installer or the portable zip.
///
/// The Store updates the app itself, a login item is a manifest StartupTask
/// rather than a Run key, and the MCP bridge is reached through its execution
/// alias, because the install directory carries the package version.
bool get isWindowsStorePackage =>
    debugWindowsStorePackageOverride ??
    (!kIsWeb &&
        Platform.isWindows &&
        (_hasPackageIdentity ??= _readPackageIdentity()));

/// Fixed for the life of the process, so asked once.
bool? _hasPackageIdentity;

bool _readPackageIdentity() {
  try {
    return hasWindowsPackageIdentity();
  } catch (_) {
    // kernel32 always has the call on the Windows versions Flutter supports;
    // if it somehow does not, this is not a package.
    return false;
  }
}
