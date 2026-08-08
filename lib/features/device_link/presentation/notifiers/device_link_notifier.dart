import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../data/repositories/device_link_pairing_storage.dart';
import '../../data/services/device_link_auto_reconnect_service.dart';
import '../../domain/models/device_link_pairing_profile.dart';
import '../controllers/linked_session_controller.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';

part 'device_link_notifier.g.dart';

final class DeviceLinkState {
  final bool reconnecting;
  final int activeCount;
  final String? lastError;

  const DeviceLinkState({
    this.reconnecting = false,
    this.activeCount = 0,
    this.lastError,
  });

  DeviceLinkState copyWith({
    bool? reconnecting,
    int? activeCount,
    String? lastError,
    bool clearLastError = false,
  }) {
    return DeviceLinkState(
      reconnecting: reconnecting ?? this.reconnecting,
      activeCount: activeCount ?? this.activeCount,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Owns saved-pairing reconnects and their mobile terminal controllers.
@Riverpod(keepAlive: true)
class DeviceLinkNotifier extends _$DeviceLinkNotifier {
  final Map<String, DeviceLinkLinkedSessionController> _controllers = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _reconnectInFlight = false;

  @override
  DeviceLinkState build() {
    _watchConnectivity();
    ref.onDispose(() {
      unawaited(_connectivitySubscription?.cancel() ?? Future.value());
      _connectivitySubscription = null;
      for (final controller in _controllers.values) {
        unawaited(controller.close());
      }
      _controllers.clear();
    });
    return const DeviceLinkState();
  }

  void _watchConnectivity() {
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
        (_) => unawaited(reconnectStoredProfiles()),
        onError: (_) {},
      );
    } catch (_) {
      _connectivitySubscription = null;
    }
  }

  /// Reconnects every saved pairing sequentially after resume or a network
  /// transition. One unreachable desktop does not block other pairings.
  Future<void> reconnectStoredProfiles() async {
    if (_reconnectInFlight) return;
    _reconnectInFlight = true;
    state = state.copyWith(reconnecting: true, clearLastError: true);
    try {
      final storage = DeviceLinkPairingStorage(
        ref.read(secureStorageServiceProvider),
      );
      final profiles = await storage.getAll();
      for (final profile in profiles) {
        if (_controllers.containsKey(profile.id)) continue;
        try {
          await _connectProfile(profile, storage);
        } catch (error) {
          debugPrint(
            '[Device Link] Reconnect failed for ${profile.id}: $error',
          );
          state = state.copyWith(lastError: error.toString());
        }
      }
    } finally {
      _reconnectInFlight = false;
      state = state.copyWith(
        reconnecting: false,
        activeCount: _controllers.length,
      );
    }
  }

  Future<void> _connectProfile(
    DeviceLinkPairingProfile profile,
    DeviceLinkPairingStorage storage,
  ) async {
    final result = await DeviceLinkAutoReconnectService().connect(profile);
    final controller = DeviceLinkLinkedSessionController(
      connection: result.connection,
      session: result.session,
      terminalTabId: 'device-link-${profile.id}',
    );
    var registered = false;
    try {
      ref
          .read(terminalTabsProvider.notifier)
          .registerDeviceLinkSession(controller.terminalSession);
      registered = true;
      _controllers[profile.id] = controller;
      controller.addListener(() => _watchController(profile.id, controller));
      await controller.connect();
      if (result.session.id != profile.sessionId) {
        await storage.save(profile.copyWith(sessionId: result.session.id));
      }
      state = state.copyWith(activeCount: _controllers.length);
    } catch (_) {
      if (registered) {
        await ref
            .read(terminalTabsProvider.notifier)
            .closeTab(controller.terminalSession.id);
      }
      await controller.close();
      rethrow;
    }
  }

  /// Associates a freshly paired controller with its saved profile so a
  /// connectivity callback does not open a duplicate session immediately.
  void registerActiveController(
    String profileId,
    DeviceLinkLinkedSessionController controller,
  ) {
    _controllers[profileId] = controller;
    controller.addListener(() => _watchController(profileId, controller));
    state = state.copyWith(activeCount: _controllers.length);
  }

  void unregisterActiveController(
    String profileId,
    DeviceLinkLinkedSessionController controller,
  ) {
    if (!identical(_controllers[profileId], controller)) return;
    _controllers.remove(profileId);
    state = state.copyWith(activeCount: _controllers.length);
  }

  void _watchController(
    String profileId,
    DeviceLinkLinkedSessionController controller,
  ) {
    final terminalEnded =
        controller.status == DeviceLinkLinkedSessionStatus.error ||
        controller.status == DeviceLinkLinkedSessionStatus.disconnected ||
        controller.status == DeviceLinkLinkedSessionStatus.detached;
    if (!terminalEnded || !identical(_controllers[profileId], controller)) {
      return;
    }
    _controllers.remove(profileId);
    state = state.copyWith(activeCount: _controllers.length);
    if (controller.status == DeviceLinkLinkedSessionStatus.detached) return;
    unawaited(controller.close());
    unawaited(
      ref
          .read(terminalTabsProvider.notifier)
          .closeTab(controller.terminalSession.id),
    );
  }
}
