import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// What the service notification says.
typedef ServiceNotificationContent = ({String title, String text});

/// The platform half of the foreground service, overridable so a test can see
/// what the service is asked to do without a native plugin behind it.
///
/// Every method throws when the platform refuses, so the caller has one way to
/// find out; none of them is expected to be called off Android.
abstract interface class ForegroundServiceGateway {
  /// Prepares the service and starts listening for the notification's
  /// "Disconnect all" button. Safe to call once, before anything else.
  Future<void> initialize({required void Function() onDisconnectAll});

  /// Asks for the Android 13+ notification permission when it is still
  /// askable. Returns normally whatever the answer: a foreground service runs
  /// without the permission, it just has no notification in the shade.
  Future<void> requestNotificationPermission();

  /// Starts the service showing [content]. Updates it instead when one is
  /// already running (a process restarted by the system can find one), so a
  /// start never fails for being a second.
  Future<void> start(ServiceNotificationContent content);

  Future<void> update(ServiceNotificationContent content);

  Future<void> stop();

  /// Drops what [initialize] registered. The service is not stopped.
  void dispose();
}

/// Id of the "Disconnect all" notification button. Also what the task isolate
/// sends back to the app, so the two sides agree on one word.
const String kDisconnectAllButtonId = 'disconnect_all';

/// Notification id of the service. Arbitrary, but fixed, so an update lands on
/// the same notification the start created.
const int _kServiceId = 4117;

/// Channel of the service notification. A channel's importance is fixed once
/// the user's device has seen it, so changing how loud this is means a new id.
const String _kChannelId = 'shellvibe_open_connections';

/// Meta-data in AndroidManifest.xml naming the status-bar glyph
/// (`drawable/ic_stat_shellvibe`).
const String _kNotificationIconMetaData =
    'dev.shellvibe.app.service.NOTIFICATION_ICON';

/// The real thing, over `flutter_foreground_task`.
///
/// The plugin is built to run work in a second isolate. None is wanted here:
/// SSH, Mosh and the tunnels stay on the main isolate, and the service exists
/// only so the process holding them counts as foreground and is left running.
/// That is why the options below turn the task's repeat event off and the task
/// handler does nothing but forward the notification button. A service with no
/// callback at all would leave even that button with nowhere to be handled,
/// because the plugin delivers button presses to the task isolate only.
class PluginForegroundServiceGateway implements ForegroundServiceGateway {
  PluginForegroundServiceGateway();

  void Function()? _onDisconnectAll;

  @override
  Future<void> initialize({required void Function() onDisconnectAll}) async {
    _onDisconnectAll = onDisconnectAll;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _kChannelId,
        channelName: 'Open connections',
        channelDescription:
            'Shown while a terminal session or a tunnel is open, so it is '
            'not cut off when the app is in the background.',
        // Low: present, but no sound, no vibration and no heads-up.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        // Private: the lock screen shows the app name and nothing else, and
        // hides the button with the rest of the content. The text is counts
        // only, but what is open on a phone is still nobody else's business.
        visibility: NotificationVisibility.VISIBILITY_PRIVATE,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        // The CPU must stay awake for SSH keep-alives and relayed tunnel
        // traffic once the screen is off; without it a sleeping phone runs no
        // Dart timers at all. Costs battery only while a session is open.
        allowWakeLock: true,
        allowWifiLock: false,
        // A system-killed process comes back with no sessions in it. A
        // service restarted into that would show counts that are not true.
        allowAutoRestart: false,
        // stopWithTask is deliberately left unset. The manifest's
        // android:stopWithTask="true" is the swipe-away behaviour wanted; the
        // plugin's Dart-side flag of the same name instead stops the service
        // whenever the app leaves the screen, which is the opposite of this.
      ),
    );
  }

  void _onTaskData(Object data) {
    if (data == kDisconnectAllButtonId) _onDisconnectAll?.call();
  }

  @override
  Future<void> requestNotificationPermission() async {
    final status = await FlutterForegroundTask.checkNotificationPermission();
    // Only `denied` is worth a dialog: Android stops showing it after the
    // second refusal, which the plugin reports as permanently denied.
    if (status == NotificationPermission.denied) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  @override
  Future<void> start(ServiceNotificationContent content) async {
    if (await FlutterForegroundTask.isRunningService) return update(content);
    final result = await FlutterForegroundTask.startService(
      serviceId: _kServiceId,
      // Must match android:foregroundServiceType in the manifest.
      serviceTypes: const [ForegroundServiceTypes.specialUse],
      notificationTitle: content.title,
      notificationText: content.text,
      notificationIcon: const NotificationIcon(
        metaDataName: _kNotificationIconMetaData,
      ),
      notificationButtons: const [
        NotificationButton(id: kDisconnectAllButtonId, text: 'Disconnect all'),
      ],
      callback: foregroundServiceTaskEntryPoint,
    );
    _throwIfFailed(result);
  }

  @override
  Future<void> update(ServiceNotificationContent content) async {
    final result = await FlutterForegroundTask.updateService(
      notificationTitle: content.title,
      notificationText: content.text,
    );
    _throwIfFailed(result);
  }

  @override
  Future<void> stop() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    _throwIfFailed(await FlutterForegroundTask.stopService());
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _onDisconnectAll = null;
  }

  void _throwIfFailed(ServiceRequestResult result) {
    if (result case ServiceRequestFailure(:final error)) {
      throw StateError('Foreground service request failed: $error');
    }
  }
}

/// Entry point of the service's task isolate. Top level, and kept by the
/// compiler, because the plugin looks it up by handle.
@pragma('vm:entry-point')
void foregroundServiceTaskEntryPoint() {
  FlutterForegroundTask.setTaskHandler(_ButtonRelayHandler());
}

/// The whole of the task isolate's job: pass a button press to the main
/// isolate, where the sessions and tunnels are.
class _ButtonRelayHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == kDisconnectAllButtonId) {
      FlutterForegroundTask.sendDataToMain(kDisconnectAllButtonId);
    } else {
      debugPrint('[ForegroundService] unknown notification button: $id');
    }
  }
}
