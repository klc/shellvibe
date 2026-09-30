import 'dart:async';

import 'package:flutter/foundation.dart';

import 'foreground_service_gateway.dart';
import 'foreground_service_state.dart';

/// Keeps the foreground service in step with the counts it is told about.
///
/// Counts arrive in bursts (a reconnect drops a tab and brings it back within
/// a second, closing a window of tabs is a dozen changes), so nothing but the
/// first start waits: starting is immediate, because the app may be about to
/// leave the screen and Android only lets a service start from the foreground,
/// while an update or a stop waits [debounce] for the next count. A drop to
/// zero that recovers inside the window never reaches the platform at all.
class ForegroundServiceController {
  ForegroundServiceController({
    required this.gateway,
    this.debounce = const Duration(milliseconds: 500),
  });

  final ForegroundServiceGateway gateway;
  final Duration debounce;

  Timer? _timer;
  ServiceCounts _wanted = ServiceCounts.idle;

  /// What the service is showing, or null when it is not running. Only ever
  /// set once the platform has said yes.
  ServiceCounts? _shown;

  bool _reconciling = false;
  bool _askedForNotificationPermission = false;
  bool _disposed = false;

  Future<void> initialize({required void Function() onDisconnectAll}) =>
      gateway.initialize(onDisconnectAll: onDisconnectAll);

  /// Asks for the service to show [counts], or to be gone when they are idle.
  void update(ServiceCounts counts) {
    if (_disposed || counts == _wanted) return;
    _wanted = counts;
    _timer?.cancel();
    _timer = null;

    switch (planServiceCommand(shown: _shown, wanted: counts)) {
      case null:
        return;
      case StartService():
        unawaited(_reconcile());
      case UpdateService() || StopService():
        _timer = Timer(debounce, () => unawaited(_reconcile()));
    }
  }

  /// Runs commands until the service shows what is wanted. One at a time: the
  /// platform calls are slow enough for the wanted counts to change under a
  /// call in flight, and a second loop would issue its commands over the first.
  Future<void> _reconcile() async {
    if (_reconciling || _disposed) return;
    _reconciling = true;
    try {
      while (!_disposed) {
        final command = planServiceCommand(shown: _shown, wanted: _wanted);
        if (command == null) return;
        if (!await _run(command)) return;
      }
    } finally {
      _reconciling = false;
    }
  }

  /// Whether [command] went through. A refusal leaves the loop: retrying the
  /// same command at once would only be refused again, and the next change in
  /// the counts is a fine moment to try again.
  Future<bool> _run(ServiceCommand command) async {
    try {
      switch (command) {
        case StartService():
          await _askForNotificationPermissionOnce();
          // The counts may have moved on while the dialog was up.
          final counts = _wanted;
          if (counts.isIdle || _disposed) return true;
          await gateway.start(_contentFor(counts));
          _shown = counts;
          // Disposed while the platform was starting it: nothing else is left
          // to stop this one.
          if (_disposed) await gateway.stop();
        case UpdateService(:final counts):
          await gateway.update(_contentFor(counts));
          _shown = counts;
        case StopService():
          await gateway.stop();
          _shown = null;
      }
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('[ForegroundService] could not run $command: $error');
      debugPrintStack(stackTrace: stackTrace);
      // Unknown now: a failed update usually means the system ended the
      // service, and the next attempt should start it afresh.
      _shown = null;
      return false;
    }
  }

  /// Asks the first time the service would start, and not again this run. A
  /// refusal is not an error: the service runs without the permission, it
  /// only has no notification in the shade.
  Future<void> _askForNotificationPermissionOnce() async {
    if (_askedForNotificationPermission) return;
    _askedForNotificationPermission = true;
    try {
      await gateway.requestNotificationPermission();
    } on Object catch (error) {
      debugPrint('[ForegroundService] notification permission: $error');
    }
  }

  ServiceNotificationContent _contentFor(ServiceCounts counts) => (
    title: kServiceNotificationTitle,
    text: buildServiceNotificationText(counts),
  );

  /// Stops the service for good, for the app going away.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    try {
      await gateway.stop();
    } on Object catch (error) {
      debugPrint('[ForegroundService] could not stop on dispose: $error');
    } finally {
      gateway.dispose();
    }
  }
}
