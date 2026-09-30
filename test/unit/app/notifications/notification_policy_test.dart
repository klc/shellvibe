import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/notifications/app_alert.dart';
import 'package:shellvibe/app/notifications/notification_policy.dart';

void main() {
  const hidden = WindowPresence(
    visible: false,
    focused: false,
    minimized: false,
  );
  const minimized = WindowPresence(
    visible: true,
    focused: false,
    minimized: true,
  );
  const behind = WindowPresence(
    visible: true,
    focused: false,
    minimized: false,
  );
  const inFront = WindowPresence(
    visible: true,
    focused: true,
    minimized: false,
  );

  NotificationContext context({
    WindowPresence window = hidden,
    bool terminalInView = true,
    String? activeTabId = 'a',
    bool vaultLocked = false,
  }) => NotificationContext(
    window: window,
    terminalInView: terminalInView,
    activeTabId: activeTabId,
    vaultLocked: vaultLocked,
  );

  const drop = AppAlert(
    kind: AppAlertKind.sessionDropped,
    tabId: 'b',
    tabTitle: 'prod-db',
  );

  late DateTime now;
  late NotificationPolicy policy;

  setUp(() {
    now = DateTime(2026, 9, 30, 12);
    policy = NotificationPolicy(now: () => now);
  });

  group('who would miss it', () {
    test('a hidden, minimised or unfocused window is notified', () {
      for (final window in [hidden, minimized, behind]) {
        final fresh = NotificationPolicy(now: () => now);
        expect(
          fresh.evaluate(drop, context(window: window)),
          isNotNull,
          reason: '$window',
        );
      }
    });

    test('nothing for the tab being looked at in a focused window', () {
      expect(
        policy.evaluate(drop, context(window: inFront, activeTabId: 'b')),
        isNull,
      );
    });

    test('a tab that is not the active one is notified even when focused', () {
      expect(
        policy.evaluate(drop, context(window: inFront, activeTabId: 'a')),
        isNotNull,
      );
    });

    test('a focused window on another screen is not looking at its tabs', () {
      expect(
        policy.evaluate(
          drop,
          context(window: inFront, activeTabId: 'b', terminalInView: false),
        ),
        isNotNull,
      );
    });

    test('a tunnel, which has no tab, is seen by any window in front', () {
      const failed = AppAlert(
        kind: AppAlertKind.tunnelFailed,
        ruleId: 'r1',
        subject: 'prod · L 8080',
        body: 'Address already in use',
      );
      expect(
        policy.evaluate(
          failed,
          context(window: inFront, terminalInView: false),
        ),
        isNull,
      );
      expect(policy.evaluate(failed, context(window: behind)), isNotNull);
    });
  });

  group('text', () {
    test('names the tab while the vault is open', () {
      final request = policy.evaluate(drop, context())!;
      expect(request.title, 'Session disconnected');
      expect(request.body, 'prod-db lost its connection.');
      expect(request.payload, 'tab:b');
    });

    test('names nothing while the vault is locked', () {
      for (final alert in [
        drop,
        const AppAlert(
          kind: AppAlertKind.sessionEnded,
          tabId: 'b',
          tabTitle: 'prod-db',
        ),
        const AppAlert(
          kind: AppAlertKind.tunnelFailed,
          ruleId: 'r',
          subject: 'prod-db · L 8080',
          body: 'refused by prod-db',
        ),
        const AppAlert(
          kind: AppAlertKind.terminalBell,
          tabId: 'b',
          tabTitle: 'prod-db',
        ),
        const AppAlert(
          kind: AppAlertKind.terminalNotification,
          tabId: 'b',
          tabTitle: 'prod-db',
          title: 'deploy prod-db',
          body: 'rm -rf /srv/prod-db done',
        ),
      ]) {
        final request = NotificationPolicy(
          now: () => now,
        ).evaluate(alert, context(vaultLocked: true))!;
        expect(request.title, 'ShellVibe', reason: '${alert.kind}');
        expect(
          '${request.title} ${request.body}',
          isNot(contains('prod-db')),
          reason: '${alert.kind}',
        );
        expect(request.body, isNot(contains('rm -rf')));
      }
    });

    test('the locked text still says what kind of thing happened', () {
      expect(
        policy.evaluate(drop, context(vaultLocked: true))!.body,
        'A session disconnected',
      );
    });

    test('an OSC 9 message has no title, so the tab stands in', () {
      final request = policy.evaluate(
        const AppAlert(
          kind: AppAlertKind.terminalNotification,
          tabId: 'b',
          tabTitle: 'build box',
          title: '',
          body: 'make finished',
        ),
        context(),
      )!;
      expect(request.title, 'build box');
      expect(request.body, 'make finished');
    });

    test('an OSC 777 title and body are used as sent', () {
      final request = policy.evaluate(
        const AppAlert(
          kind: AppAlertKind.terminalNotification,
          tabId: 'b',
          tabTitle: 'build box',
          title: 'CI',
          body: 'green',
        ),
        context(),
      )!;
      expect(request.title, 'CI');
      expect(request.body, 'green');
    });

    test('program-supplied text is flattened and bounded', () {
      final request = policy.evaluate(
        AppAlert(
          kind: AppAlertKind.terminalNotification,
          tabId: 'b',
          tabTitle: 'x',
          title: 'a\u001b[31m\nb',
          body: 'y' * 500,
        ),
        context(),
      )!;
      expect(request.title, isNot(contains('\n')));
      expect(request.title, isNot(contains('\u001b')));
      expect(
        request.body.length,
        lessThanOrEqualTo(NotificationPolicy.maxBodyLength),
      );
    });

    test('a tunnel notification points at the Tunnels screen', () {
      final request = policy.evaluate(
        const AppAlert(
          kind: AppAlertKind.tunnelFailed,
          ruleId: 'r1',
          subject: 'prod · L 8080',
          body: 'Address already in use',
        ),
        context(),
      )!;
      expect(request.body, 'prod · L 8080: Address already in use');
      expect(
        NotificationTarget.parse(request.payload),
        isA<NotificationTunnels>(),
      );
    });
  });

  group('throttle', () {
    const bell = AppAlert(
      kind: AppAlertKind.terminalBell,
      tabId: 'b',
      tabTitle: 'prod-db',
    );

    test('a burst from one tab is one notification', () {
      expect(policy.evaluate(bell, context()), isNotNull);
      for (var i = 0; i < 20; i++) {
        now = now.add(const Duration(milliseconds: 100));
        expect(policy.evaluate(bell, context()), isNull);
      }
    });

    test('the next one goes out once the window has passed', () {
      expect(policy.evaluate(bell, context()), isNotNull);
      now = now.add(const Duration(seconds: 6));
      expect(policy.evaluate(bell, context()), isNotNull);
    });

    test('tabs do not share a budget', () {
      expect(policy.evaluate(bell, context()), isNotNull);
      expect(
        policy.evaluate(
          const AppAlert(kind: AppAlertKind.terminalBell, tabId: 'c'),
          context(),
        ),
        isNotNull,
      );
    });

    test('a bell does not swallow the news that the session dropped', () {
      expect(policy.evaluate(bell, context()), isNotNull);
      expect(policy.evaluate(drop, context()), isNotNull);
    });

    test('a bell and an OSC notification from one tab share a budget', () {
      expect(policy.evaluate(bell, context()), isNotNull);
      expect(
        policy.evaluate(
          const AppAlert(
            kind: AppAlertKind.terminalNotification,
            tabId: 'b',
            body: 'done',
          ),
          context(),
        ),
        isNull,
      );
    });

    test('an alert that was not shown does not use up the budget', () {
      expect(
        policy.evaluate(bell, context(window: inFront, activeTabId: 'b')),
        isNull,
      );
      expect(policy.evaluate(bell, context()), isNotNull);
    });

    test(
      'the same source keeps the same id, so it replaces its notification',
      () {
        final first = policy.evaluate(bell, context())!;
        now = now.add(const Duration(seconds: 10));
        final second = policy.evaluate(bell, context())!;
        expect(second.id, first.id);
        expect(first.id, isNonNegative);
      },
    );
  });

  group('NotificationTarget', () {
    test('round-trips a tab and the tunnels screen', () {
      final tab = NotificationTarget.parse(const NotificationTab('t1').payload);
      expect(tab, isA<NotificationTab>());
      expect((tab as NotificationTab).tabId, 't1');
      expect(
        NotificationTarget.parse(const NotificationTunnels().payload),
        isA<NotificationTunnels>(),
      );
    });

    test('anything else is no target', () {
      expect(NotificationTarget.parse(null), isNull);
      expect(NotificationTarget.parse(''), isNull);
      expect(NotificationTarget.parse('tab:'), isNull);
      expect(NotificationTarget.parse('nonsense'), isNull);
    });
  });
}
