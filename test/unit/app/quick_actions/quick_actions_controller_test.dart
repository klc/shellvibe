import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/quick_actions/app_shortcuts.dart';
import 'package:shellvibe/app/quick_actions/quick_actions_controller.dart';

class _FakeGateway implements QuickActionsGateway {
  void Function(String type)? onType;
  final List<List<AppShortcut>> sets = [];
  Exception? failWith;

  @override
  Future<void> initialize(void Function(String type) onType) async {
    this.onType = onType;
  }

  @override
  Future<void> setShortcuts(List<AppShortcut> shortcuts) async {
    if (failWith != null) throw failWith!;
    sets.add(shortcuts);
  }
}

const _a = AppShortcut(type: 'host:a', title: 'A');
const _b = AppShortcut(type: 'host:b', title: 'B');
const _quick = AppShortcut(type: kQuickConnectShortcutType, title: 'Quick');

void main() {
  group('QuickActionsController', () {
    test('debounces a burst into one call with the last list', () {
      fakeAsync((async) {
        final gateway = _FakeGateway();
        final controller = QuickActionsController(gateway: gateway);

        controller.update([_a, _quick]);
        async.elapse(const Duration(milliseconds: 200));
        controller.update([_b, _quick]);
        async.elapse(const Duration(milliseconds: 200));
        controller.update([_a, _b, _quick]);
        expect(gateway.sets, isEmpty);

        async.elapse(const Duration(seconds: 1));
        expect(gateway.sets, [
          [_a, _b, _quick],
        ]);
        controller.dispose();
      });
    });

    test('does not resend a list that is already registered', () {
      fakeAsync((async) {
        final gateway = _FakeGateway();
        final controller = QuickActionsController(gateway: gateway);

        controller.update([_a, _quick]);
        async.elapse(const Duration(seconds: 1));
        controller.update([_a, _quick]);
        async.elapse(const Duration(seconds: 1));

        expect(gateway.sets, hasLength(1));
        controller.dispose();
      });
    });

    test('a change that settles back on the registered list sends nothing', () {
      fakeAsync((async) {
        final gateway = _FakeGateway();
        final controller = QuickActionsController(gateway: gateway);

        controller.update([_a, _quick]);
        async.elapse(const Duration(seconds: 1));
        controller.update([_b, _quick]);
        controller.update([_a, _quick]);
        async.elapse(const Duration(seconds: 1));

        expect(gateway.sets, hasLength(1));
        controller.dispose();
      });
    });

    test('an immediate update skips the debounce', () {
      fakeAsync((async) {
        final gateway = _FakeGateway();
        final controller = QuickActionsController(gateway: gateway);

        controller.update([_a, _quick]);
        controller.update([_quick], immediate: true);
        async.flushMicrotasks();

        expect(gateway.sets, [
          [_quick],
        ]);
        // The superseded debounced update never fires.
        async.elapse(const Duration(seconds: 2));
        expect(gateway.sets, hasLength(1));
        controller.dispose();
      });
    });

    test('a failing platform call is swallowed and retried next time', () {
      fakeAsync((async) {
        final gateway = _FakeGateway()..failWith = Exception('no launcher');
        final controller = QuickActionsController(gateway: gateway);

        controller.update([_quick]);
        async.elapse(const Duration(seconds: 1));
        expect(gateway.sets, isEmpty);

        gateway.failWith = null;
        controller.update([_quick]);
        async.elapse(const Duration(seconds: 1));
        expect(gateway.sets, [
          [_quick],
        ]);
        controller.dispose();
      });
    });

    test('nothing is sent after dispose', () {
      fakeAsync((async) {
        final gateway = _FakeGateway();
        final controller = QuickActionsController(gateway: gateway);

        controller.update([_quick]);
        controller.dispose();
        async.elapse(const Duration(seconds: 2));
        controller.update([_a], immediate: true);
        async.flushMicrotasks();

        expect(gateway.sets, isEmpty);
      });
    });

    test(
      'routes platform presses through the parser, dropping unknowns',
      () async {
        final gateway = _FakeGateway();
        final controller = QuickActionsController(gateway: gateway);
        final received = <QuickAction>[];
        await controller.initialize(received.add);

        gateway.onType!('host:abc');
        gateway.onType!('bogus');
        gateway.onType!('quick_connect');

        expect(received, [
          const ConnectHostAction('abc'),
          isA<QuickConnectAction>(),
        ]);
        controller.dispose();
      },
    );
  });

  group('QuickActionDispatcher', () {
    test('runs a press straight away when it may', () {
      final ran = <QuickAction>[];
      final dispatcher = QuickActionDispatcher(
        canRun: () => true,
        run: ran.add,
      );

      dispatcher.submit(const QuickConnectAction());

      expect(ran, [isA<QuickConnectAction>()]);
      expect(dispatcher.hasPending, isFalse);
    });

    test('holds a press while the vault is locked and runs it after', () {
      var locked = true;
      final ran = <QuickAction>[];
      final dispatcher = QuickActionDispatcher(
        canRun: () => !locked,
        run: ran.add,
      );

      dispatcher.submit(const ConnectHostAction('a'));
      dispatcher.flush();
      expect(ran, isEmpty);
      expect(dispatcher.hasPending, isTrue);

      locked = false;
      dispatcher.flush();
      expect(ran, [const ConnectHostAction('a')]);
      expect(dispatcher.hasPending, isFalse);

      dispatcher.flush();
      expect(ran, hasLength(1), reason: 'a press runs once');
    });

    test('keeps only the latest waiting press', () {
      var locked = true;
      final ran = <QuickAction>[];
      final dispatcher = QuickActionDispatcher(
        canRun: () => !locked,
        run: ran.add,
      );

      dispatcher.submit(const ConnectHostAction('a'));
      dispatcher.submit(const ConnectHostAction('b'));
      locked = false;
      dispatcher.flush();

      expect(ran, [const ConnectHostAction('b')]);
    });

    test('a run that throws does not escape', () async {
      final dispatcher = QuickActionDispatcher(
        canRun: () => true,
        run: (_) => throw StateError('boom'),
      );

      expect(
        () => dispatcher.submit(const QuickConnectAction()),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);
    });
  });
}
