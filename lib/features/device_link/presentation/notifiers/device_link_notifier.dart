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
import '../../../vault/presentation/notifiers/vault_notifier.dart';

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
  int _vaultGeneration = 0;
  bool _disposed = false;
  final Map<DeviceLinkLinkedSessionController, Future<void>>
  _controllerCloseOperations = {};

  bool get _isAlive => !_disposed;

  bool get _vaultAllowsDeviceLink {
    if (_disposed) return false;
    final vault = ref.read(vaultProvider);
    return vault.hasValue &&
        !vault.isLoading &&
        !vault.hasError &&
        vault.value!.allowsDeviceLink;
  }

  @override
  DeviceLinkState build() {
    _watchConnectivity();
    ref.listen(vaultProvider, (_, next) {
      final available =
          next.hasValue &&
          !next.isLoading &&
          !next.hasError &&
          next.value!.allowsDeviceLink;
      if (available) return;
      _vaultGeneration++;
      unawaited(_closeControllersForUnavailableVault());
    });
    ref.onDispose(() {
      _disposed = true;
      _vaultGeneration++;
      unawaited(_connectivitySubscription?.cancel() ?? Future.value());
      _connectivitySubscription = null;
      final controllers = _controllers.values.toList();
      _controllers.clear();
      for (final controller in controllers) {
        unawaited(_closeControllerQuietly(controller));
      }
    });
    return const DeviceLinkState();
  }

  Future<void> _closeControllersForUnavailableVault() async {
    final controllers = _controllers.values.toList();
    _controllers.clear();
    if (_isAlive) state = state.copyWith(activeCount: 0);
    for (final controller in controllers) {
      try {
        await _closeController(controller);
      } catch (error) {
        debugPrint('[Device Link] Controller close failed: $error');
      }
      if (!_isAlive) continue;
      await ref
          .read(terminalTabsProvider.notifier)
          .closeTab(controller.terminalSession.id);
    }
  }

  Future<void> _closeController(DeviceLinkLinkedSessionController controller) {
    final existing = _controllerCloseOperations[controller];
    if (existing != null) return existing;
    final operation = controller.close();
    _controllerCloseOperations[controller] = operation;
    unawaited(
      operation.then<void>(
        (_) => _controllerCloseOperations.remove(controller),
        onError: (Object error, StackTrace stackTrace) {
          _controllerCloseOperations.remove(controller);
        },
      ),
    );
    return operation;
  }

  Future<void> _closeControllerQuietly(
    DeviceLinkLinkedSessionController controller,
  ) async {
    try {
      await _closeController(controller);
    } catch (error) {
      debugPrint('[Device Link] Controller close failed: $error');
    }
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
    if (_disposed) return;
    if (!_vaultAllowsDeviceLink) return;
    if (_reconnectInFlight) return;
    _reconnectInFlight = true;
    if (!_isAlive) return;
    state = state.copyWith(reconnecting: true, clearLastError: true);
    try {
      if (!_isAlive) return;
      final storage = DeviceLinkPairingStorage(
        ref.read(secureStorageServiceProvider),
      );
      final profiles = await storage.getAll();
      if (!_isAlive) return;
      for (final profile in profiles) {
        if (!_isAlive) break;
        if (!_vaultAllowsDeviceLink) break;
        if (_controllers.containsKey(profile.id)) continue;
        try {
          await _connectProfile(profile, storage);
        } catch (error) {
          debugPrint(
            '[Device Link] Reconnect failed for ${profile.id}: $error',
          );
          if (_isAlive) state = state.copyWith(lastError: error.toString());
        }
      }
    } finally {
      _reconnectInFlight = false;
      if (_isAlive) {
        state = state.copyWith(
          reconnecting: false,
          activeCount: _controllers.length,
        );
      }
    }
  }

  Future<void> _connectProfile(
    DeviceLinkPairingProfile profile,
    DeviceLinkPairingStorage storage,
  ) async {
    final generation = _vaultGeneration;
    final result = await DeviceLinkAutoReconnectService().connect(profile);
    if (!_vaultAllowsDeviceLink || generation != _vaultGeneration) {
      await result.connection.close();
      throw StateError('Device Link reconnect cancelled by vault state');
    }
    final controller = DeviceLinkLinkedSessionController(
      connection: result.connection,
      session: result.session,
      terminalTabId: 'device-link-${profile.id}',
    );
    var registered = false;
    try {
      ref
          .read(terminalTabsProvider.notifier)
          .registerDeviceLinkSession(
            controller.terminalSession,
            onClose: () => closeRegisteredController(profile.id, controller),
          );
      registered = true;
      _controllers[profile.id] = controller;
      controller.addListener(() => _watchController(profile.id, controller));
      await controller.connect();
      if (!_vaultAllowsDeviceLink || generation != _vaultGeneration) {
        throw StateError('Device Link reconnect cancelled by vault state');
      }
      if (result.session.id != profile.sessionId) {
        await storage.save(profile.copyWith(sessionId: result.session.id));
      }
      if (_isAlive) state = state.copyWith(activeCount: _controllers.length);
    } catch (_) {
      // The map entry has to go with the controller it points at.
      // reconnectStoredProfiles skips a profile that already has one, so a
      // controller left behind here is a pairing that never reconnects again
      // until the app restarts.
      if (identical(_controllers[profile.id], controller)) {
        _controllers.remove(profile.id);
        if (_isAlive) state = state.copyWith(activeCount: _controllers.length);
      }
      if (registered && _isAlive) {
        await ref
            .read(terminalTabsProvider.notifier)
            .closeTab(controller.terminalSession.id);
      }
      await _closeControllerQuietly(controller);
      rethrow;
    }
  }

  /// Associates a freshly paired controller with its saved profile so a
  /// connectivity callback does not open a duplicate session immediately.
  void registerActiveController(
    String profileId,
    DeviceLinkLinkedSessionController controller,
  ) {
    if (_disposed) return;
    _controllers[profileId] = controller;
    controller.addListener(() => _watchController(profileId, controller));
    if (_isAlive) state = state.copyWith(activeCount: _controllers.length);
  }

  /// Called by terminal tab ownership when a Device Link tab is closed by the
  /// shared terminal UI. It deliberately does not close the tab again.
  Future<void> closeRegisteredController(
    String profileId,
    DeviceLinkLinkedSessionController controller,
  ) async {
    if (identical(_controllers[profileId], controller)) {
      _controllers.remove(profileId);
      if (_isAlive) state = state.copyWith(activeCount: _controllers.length);
    }
    await _closeControllerQuietly(controller);
  }

  /// Ends the live session for [profileId], if there is one.
  ///
  /// Used before pairing the same phone again: the desktop hands a session to
  /// one connection at a time, so the one already running has to let go before
  /// the new one can attach.
  Future<void> releaseActiveController(String profileId) async {
    final controller = _controllers.remove(profileId);
    if (controller == null) return;
    if (_isAlive) state = state.copyWith(activeCount: _controllers.length);
    await _closeControllerQuietly(controller);
    if (!_isAlive) return;
    await ref
        .read(terminalTabsProvider.notifier)
        .closeTab(controller.terminalSession.id);
  }

  void unregisterActiveController(
    String profileId,
    DeviceLinkLinkedSessionController controller,
  ) {
    if (_disposed) return;
    if (!identical(_controllers[profileId], controller)) return;
    _controllers.remove(profileId);
    if (_isAlive) state = state.copyWith(activeCount: _controllers.length);
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
    if (!_isAlive) return;
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
