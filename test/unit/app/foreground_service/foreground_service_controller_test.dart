import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/foreground_service/foreground_service_controller.dart';
import 'package:shellvibe/app/foreground_service/foreground_service_gateway.dart';
import 'package:shellvibe/app/foreground_service/foreground_service_state.dart';

/// Records what the service is asked to do. [calls] is the whole story: the
/// controller is correct when it says the right things in the right order and
/// nothing else.
class FakeForegroundServiceGateway implements ForegroundServiceGateway {
  final List<String> calls = [];
  void Function()? onDisconnectAll;
  bool running = false;
  Error? failStartWith;
  Error? failUpdateWith;
  Error? failPermissionWith;

  /// Held open to stage a call still in flight.
  Completer<void>? permissionDialog;

  @override
  Future<void> initialize({required void Function() onDisconnectAll}) async {
    this.onDisconnectAll = onDisconnectAll;
    calls.add('initialize');
  }

  @override
  Future<void> requestNotificationPermission() async {
    calls.add('permission');
    final dialog = permissionDialog;
    if (dialog != null) await dialog.future;
    if (failPermissionWith != null) throw failPermissionWith!;
  }

  @override
  Future<void> start(ServiceNotificationContent content) async {
    if (failStartWith != null) throw failStartWith!;
    running = true;
    calls.add('start:${content.title}|${content.text}');
  }

  @override
  Future<void> update(ServiceNotificationContent content) async {
    if (failUpdateWith != null) throw failUpdateWith!;
    calls.add('update:${content.text}');
  }

  @override
  Future<void> stop() async {
    if (!running) return;
    running = false;
    calls.add('stop');
  }

  @override
  void dispose() => calls.add('dispose');
}

const _one = ServiceCounts(sessions: 1);
const _two = ServiceCounts(sessions: 2);
const _twoAndTunnel = ServiceCounts(sessions: 2, tunnels: 1);

/// Lets queued microtasks (the awaited fake calls) run.
void _settle(FakeAsync async) => async.flushMicrotasks();

void main() {
  late FakeForegroundServiceGateway gateway;
  late ForegroundServiceController controller;

  void withController(void Function(FakeAsync async) body) {
    fakeAsync((async) {
      gateway = FakeForegroundServiceGateway();
      controller = ForegroundServiceController(gateway: gateway);
      body(async);
    });
  }

  group('ForegroundServiceController', () {
    test('starts at once when the first session connects', () {
      withController((async) {
        controller.update(_one);
        _settle(async);
        // No debounce: the app may be about to leave the screen.
        expect(gateway.calls, ['permission', 'start:ShellVibe|1 session']);
      });
    });

    test(
      'asks for the notification permission once, before the first start',
      () {
        withController((async) {
          controller.update(_one);
          _settle(async);
          controller.update(ServiceCounts.idle);
          async.elapse(const Duration(seconds: 1));
          controller.update(_one);
          _settle(async);

          expect(gateway.calls.where((c) => c == 'permission'), hasLength(1));
          expect(gateway.calls, [
            'permission',
            'start:ShellVibe|1 session',
            'stop',
            'start:ShellVibe|1 session',
          ]);
        });
      },
    );

    test('still starts when the permission prompt throws', () {
      withController((async) {
        gateway.failPermissionWith = StateError('no activity');
        controller.update(_one);
        _settle(async);
        expect(gateway.calls.last, 'start:ShellVibe|1 session');
      });
    });

    test('starts with the counts of after the dialog, not before', () {
      withController((async) {
        gateway.permissionDialog = Completer<void>();
        controller.update(_one);
        _settle(async);
        controller.update(_twoAndTunnel);
        gateway.permissionDialog!.complete();
        _settle(async);

        expect(gateway.calls, [
          'permission',
          'start:ShellVibe|2 sessions · 1 tunnel',
        ]);
      });
    });

    test('does not start when everything closed under the dialog', () {
      withController((async) {
        gateway.permissionDialog = Completer<void>();
        controller.update(_one);
        _settle(async);
        controller.update(ServiceCounts.idle);
        gateway.permissionDialog!.complete();
        async.elapse(const Duration(seconds: 1));

        expect(gateway.calls, ['permission']);
      });
    });

    test('debounces updates into one with the last counts', () {
      withController((async) {
        controller.update(_one);
        _settle(async);
        gateway.calls.clear();

        controller.update(_two);
        async.elapse(const Duration(milliseconds: 200));
        controller.update(_twoAndTunnel);
        async.elapse(const Duration(milliseconds: 200));
        expect(gateway.calls, isEmpty);

        async.elapse(const Duration(seconds: 1));
        expect(gateway.calls, ['update:2 sessions · 1 tunnel']);
      });
    });

    test('equal counts cause no call at all', () {
      withController((async) {
        controller.update(_twoAndTunnel);
        _settle(async);
        gateway.calls.clear();

        for (var i = 0; i < 20; i++) {
          // What a tunnel's speed tick amounts to once it is derived.
          controller.update(const ServiceCounts(sessions: 2, tunnels: 1));
          async.elapse(const Duration(milliseconds: 100));
        }
        async.elapse(const Duration(seconds: 2));
        expect(gateway.calls, isEmpty);
      });
    });

    test('an update that lands back on what is shown is not sent', () {
      withController((async) {
        controller.update(_one);
        _settle(async);
        gateway.calls.clear();

        controller.update(_two);
        async.elapse(const Duration(milliseconds: 100));
        controller.update(_one);
        async.elapse(const Duration(seconds: 2));
        expect(gateway.calls, isEmpty);
      });
    });

    test('stops once nothing is left, after the debounce', () {
      withController((async) {
        controller.update(_one);
        _settle(async);
        gateway.calls.clear();

        controller.update(ServiceCounts.idle);
        async.elapse(const Duration(milliseconds: 200));
        expect(gateway.calls, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(gateway.calls, ['stop']);
        expect(gateway.running, isFalse);
      });
    });

    test('a reconnect that drops to zero and back never stops it', () {
      withController((async) {
        controller.update(_one);
        _settle(async);
        gateway.calls.clear();

        controller.update(ServiceCounts.idle);
        async.elapse(const Duration(milliseconds: 150));
        controller.update(_one);
        async.elapse(const Duration(seconds: 2));

        expect(gateway.calls, isEmpty);
        expect(gateway.running, isTrue);
      });
    });

    test('never stops something that was never started', () {
      withController((async) {
        controller.update(ServiceCounts.idle);
        async.elapse(const Duration(seconds: 2));
        expect(gateway.calls, isEmpty);
      });
    });

    test('a refused start is retried on the next change, not in a loop', () {
      withController((async) {
        gateway.failStartWith = StateError('not allowed from background');
        controller.update(_one);
        async.elapse(const Duration(seconds: 5));
        expect(gateway.calls, ['permission']);

        gateway.failStartWith = null;
        controller.update(_two);
        _settle(async);
        expect(gateway.calls, ['permission', 'start:ShellVibe|2 sessions']);
      });
    });

    test('a failed update falls back to starting afresh', () {
      withController((async) {
        controller.update(_one);
        _settle(async);
        gateway.calls.clear();

        gateway.failUpdateWith = StateError('service is gone');
        controller.update(_two);
        async.elapse(const Duration(seconds: 1));
        expect(gateway.calls, isEmpty);

        gateway.failUpdateWith = null;
        controller.update(_twoAndTunnel);
        _settle(async);
        expect(gateway.calls, ['start:ShellVibe|2 sessions · 1 tunnel']);
      });
    });

    test('dispose stops the service and releases the gateway', () {
      withController((async) {
        controller.update(_one);
        _settle(async);
        gateway.calls.clear();

        unawaited(controller.dispose());
        _settle(async);
        expect(gateway.calls, ['stop', 'dispose']);
        expect(gateway.running, isFalse);
      });
    });

    test('dispose cancels a pending update and ignores later ones', () {
      withController((async) {
        controller.update(_one);
        _settle(async);
        controller.update(_two);
        unawaited(controller.dispose());
        _settle(async);
        gateway.calls.clear();

        async.elapse(const Duration(seconds: 2));
        controller.update(_twoAndTunnel);
        async.elapse(const Duration(seconds: 2));
        expect(gateway.calls, isEmpty);
      });
    });

    test('initialize hands the gateway the disconnect callback', () {
      withController((async) {
        var pressed = 0;
        unawaited(controller.initialize(onDisconnectAll: () => pressed++));
        _settle(async);
        gateway.onDisconnectAll!();
        expect(pressed, 1);
      });
    });
  });
}
