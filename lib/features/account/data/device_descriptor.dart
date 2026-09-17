import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';

/// How this install introduces itself to `POST /auth/register` and
/// `POST /auth/login`.
@immutable
final class DeviceDescriptor {
  /// Human-readable device name shown in the account's device list.
  final String name;

  /// One of the platforms the contract accepts: `ios`, `android`, `macos`,
  /// `windows`, `linux`, `web`.
  final String platform;

  /// This build's version, from [AppConstants.appVersion].
  final String appVersion;

  const DeviceDescriptor({
    required this.name,
    required this.platform,
    required this.appVersion,
  });

  /// Describes the running device.
  factory DeviceDescriptor.current() => DeviceDescriptor(
    name: _currentName(),
    platform: currentPlatform(),
    appVersion: AppConstants.appVersion,
  );

  /// The platform string the server validates against.
  ///
  /// `AuthController` rejects anything outside its `in:` list with a 422, so an
  /// unexpected host platform falls back to `linux` rather than failing the
  /// whole sign-in: being labelled inaccurately is recoverable, being unable
  /// to authenticate is not.
  static String currentPlatform() {
    if (kIsWeb) return 'web';

    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'linux',
    };
  }

  static String _currentName() {
    if (kIsWeb) return 'Web browser';

    try {
      final hostname = Platform.localHostname.trim();
      if (hostname.isNotEmpty) {
        // macOS reports "name.local"; the suffix is noise in a device list.
        return hostname.endsWith('.local')
            ? hostname.substring(0, hostname.length - '.local'.length)
            : hostname;
      }
    } on Object {
      // Platform.localHostname throws on sandboxed or restricted platforms.
    }

    return switch (currentPlatform()) {
      'ios' => 'iPhone',
      'android' => 'Android device',
      'macos' => 'Mac',
      'windows' => 'Windows PC',
      _ => 'ShellVibe device',
    };
  }
}
