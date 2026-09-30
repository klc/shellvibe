import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_policy.dart';

/// Shows a [NotificationRequest] through the OS and reports clicks on it.
///
/// A seam so the host is tested against a fake, not the plugin's channels.
abstract interface class NotificationPresenter {
  /// Payloads of notifications the user clicked, as handed to
  /// [NotificationRequest.payload].
  Stream<String?> get clicks;

  /// Asks the OS for the right to show notifications where it asks at all.
  /// Returns whether notifications may be shown.
  Future<bool> ensurePermission();

  Future<void> show(NotificationRequest request);

  Future<void> dispose();
}

/// [NotificationPresenter] over `flutter_local_notifications`, which covers
/// macOS (UserNotifications), Windows (toasts) and Linux (the freedesktop
/// notification service) with one API.
///
/// The plugin is brought up, and on macOS the permission asked for, the first
/// time a notification is actually due, not at app start: a prompt for a
/// permission nothing has used yet is a prompt the user denies.
class LocalNotificationsPresenter implements NotificationPresenter {
  LocalNotificationsPresenter({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _clicks = StreamController<String?>.broadcast();

  Future<void>? _initialized;
  bool _granted = false;

  @override
  Stream<String?> get clicks => _clicks.stream;

  /// Identifies the toast sender to Windows. Fixed, because a new value would
  /// make Windows treat every build as another app with its own settings.
  static const _windowsAppUserModelId = 'dev.shellvibe.app';
  static const _windowsActivationGuid = '35407ec1-dece-4566-8532-af5c80998b47';

  Future<void> _ensureInitialized() => _initialized ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          // All three requests are off: the permission is asked for by
          // [ensurePermission], when a notification is first due.
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          // Names the action a click on the notification body runs; without it
          // a click calls nothing back.
          linux: LinuxInitializationSettings(
            defaultActionName: 'Show ShellVibe',
          ),
          windows: WindowsInitializationSettings(
            appName: 'ShellVibe',
            appUserModelId: _windowsAppUserModelId,
            guid: _windowsActivationGuid,
          ),
        ),
        onDidReceiveNotificationResponse: (response) =>
            _clicks.add(response.payload),
      )
      .then((_) {});

  @override
  Future<bool> ensurePermission() async {
    await _ensureInitialized();
    // Windows and Linux have no permission to ask for.
    if (!Platform.isMacOS) return true;
    if (_granted) return true;
    // Asked again until granted: once answered the system returns the answer
    // without showing anything, so a denial costs nothing to re-read and a
    // grant made later in System Settings is picked up.
    _granted =
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true) ??
        false;
    return _granted;
  }

  @override
  Future<void> show(NotificationRequest request) async {
    if (!await ensurePermission()) return;
    await _plugin.show(
      id: request.id,
      title: request.title,
      body: request.body,
      payload: request.payload,
      notificationDetails: const NotificationDetails(
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
        windows: WindowsNotificationDetails(),
      ),
    );
  }

  @override
  Future<void> dispose() => _clicks.close();
}
