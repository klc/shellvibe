import 'package:flutter_test/flutter_test.dart';
import 'package:xterm3/xterm.dart';

import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/features/terminal/domain/services/broadcast_input_router.dart';

void main() {
  late BroadcastInputRouter router;

  /// Builds a session whose terminal logs everything pushed through its
  /// (fake bridge) `onOutput` handler.
  TerminalTabSession session(
    String id, {
    bool connected = true,
    required List<String> captured,
  }) {
    final terminal = Terminal(maxLines: 100);
    if (connected) {
      terminal.onOutput = (data) => captured.add(data); // fake bridge handler
    }
    return TerminalTabSession(
      id: id,
      title: id,
      sessionType: TerminalSessionType.local,
      terminal: terminal,
      isConnected: connected,
    );
  }

  void wireForward(BroadcastInputRouter r, Set<String> liveSelected,
      List<TerminalTabSession> liveTabs) {
    // Mirrors TerminalTabsNotifier.build(): tee wrappers reach the router via
    // a callback that reads the LIVE selection at emit time — never a
    // snapshot captured at install time.
    r.forwardCallback = (originId, data) => r.forwardToOthers(
        originId: originId,
        selectedIds: liveSelected,
        tabs: liveTabs,
        data: data);
  }

  setUp(() {
    router = BroadcastInputRouter();
  });

  group('BroadcastInputRouter', () {
    test('installing a tee forwards input to every other selected pane', () {
      final a = <String>[];
      final b = <String>[];
      final tabA = session('a', captured: a);
      final tabB = session('b', captured: b);
      final tabs = [tabA, tabB];
      final selected = {'a', 'b'};
      wireForward(router, selected, tabs);

      router.sync(selectedIds: selected, tabs: tabs);

      tabA.terminal.onOutput!('echo hi');

      expect(a, ['echo hi']); // origin still writes to its own session
      expect(b, ['echo hi']); // ...and gets forwarded to the other pane
    });

    test('deselecting restores normal single-pane behaviour', () {
      final a = <String>[];
      final b = <String>[];
      final tabA = session('a', captured: a);
      final tabB = session('b', captured: b);
      final tabs = [tabA, tabB];
      final live = <String>{'a', 'b'};
      wireForward(router, live, tabs);

      router.sync(selectedIds: live, tabs: tabs);
      live.remove('b');
      router.sync(selectedIds: live, tabs: tabs); // selection is now {a}

      // After deselecting b, typing into b reaches only b's own session.
      tabB.terminal.onOutput!('x');
      expect(b, ['x']);
      expect(a, isEmpty); // no cross-pane forwarding

      // a is still the sole selected pane: no other pane to fan out to.
      tabA.terminal.onOutput!('y');
      expect(a, ['y']);
      expect(b, ['x']); // b was not touched by a's input
    });

    test('sendTextToPanes delivers to every selected pane exactly once with '
        'newline conversion', () {
      final a = <String>[];
      final b = <String>[];
      final c = <String>[];
      final tabs = [
        session('a', captured: a),
        session('b', captured: b),
        session('c', captured: c),
      ];
      final selected = {'a', 'b', 'c'};

      final sent = router.sendTextToPanes(
        selectedIds: selected,
        tabs: tabs,
        text: 'cd /home/xyz\npwd',
      );

      expect(sent, 3);
      expect(a, ['cd /home/xyz\rpwd']);
      expect(b, ['cd /home/xyz\rpwd']);
      expect(c, ['cd /home/xyz\rpwd']);
    });

    test('unconnected pane (no onOutput handler) is skipped', () {
      final a = <String>[];
      final tabA = session('a', captured: a);
      final tabB = session('b', connected: false, captured: <String>[]);
      final tabs = [tabA, tabB];
      final selected = {'a', 'b'};

      final sent = router.sendTextToPanes(
        selectedIds: selected,
        tabs: tabs,
        text: 'ls',
      );

      expect(sent, 1);
      expect(a, ['ls']);
    });

    test('sendTextToPanes with tees installed delivers exactly once '
        '(paste never re-broadcasts)', () {
      final a = <String>[];
      final b = <String>[];
      final tabA = session('a', captured: a);
      final tabB = session('b', captured: b);
      final tabs = [tabA, tabB];
      final live = {'a', 'b'};
      wireForward(router, live, tabs);

      router.sync(selectedIds: live, tabs: tabs); // tees installed

      final sent = router.sendTextToPanes(
        selectedIds: live,
        tabs: tabs,
        text: 'ls',
      );

      expect(sent, 2);
      expect(a, ['ls']); // paste landed once, no fan-out from the tee
      expect(b, ['ls']);

      // Tees are still in place: the next keystroke still broadcasts.
      tabA.terminal.onOutput!('pwd');
      expect(a, ['ls', 'pwd']);
      expect(b, ['ls', 'pwd']);
    });

    test('a foreign interceptor installed on top does not duplicate a '
        'broadcast snippet', () {
      // The mobile extra-keys bar registers its own interceptor in the same
      // chain, possibly after broadcast is already live. Wrapping the raw
      // `onOutput` slot used to make the router lose track of its own tee,
      // which sent the snippet once directly and once more through the tee.
      final a = <String>[];
      final b = <String>[];
      final tabA = session('a', captured: a);
      final tabB = session('b', captured: b);
      final tabs = [tabA, tabB];
      final live = {'a', 'b'};
      wireForward(router, live, tabs);

      router.sync(selectedIds: live, tabs: tabs);
      for (final tab in tabs) {
        tab.outputChain.add('extra_keys', (data, next) => next(data));
      }

      final sent =
          router.sendTextToPanes(selectedIds: live, tabs: tabs, text: 'ls');

      expect(sent, 2);
      expect(a, ['ls']);
      expect(b, ['ls']);

      // Typing still broadcasts exactly once per pane through both links.
      tabA.terminal.onOutput!('pwd');
      expect(a, ['ls', 'pwd']);
      expect(b, ['ls', 'pwd']);
    });

    test('a foreign interceptor can be removed while broadcast stays live',
        () {
      final a = <String>[];
      final b = <String>[];
      final tabA = session('a', captured: a);
      final tabB = session('b', captured: b);
      final tabs = [tabA, tabB];
      final live = {'a', 'b'};
      wireForward(router, live, tabs);

      // Foreign link first, broadcast on top: the reverse install order.
      tabA.outputChain.add('extra_keys', (data, next) => next('$data!'));
      router.sync(selectedIds: live, tabs: tabs);

      tabA.terminal.onOutput!('x');
      expect(a, ['x!']);
      expect(b, ['x!']); // forwarded after the foreign link had its say

      tabA.outputChain.remove('extra_keys');
      tabA.terminal.onOutput!('y');
      expect(a, ['x!', 'y']);
      expect(b, ['x!', 'y']);
    });

    test('reconnect re-installs the tee and forwards to the NEW handler', () {
      final a = <String>[];
      final bOld = <String>[];
      final tabA = session('a', captured: a);
      final tabB = session('b', captured: bOld);
      final tabs = [tabA, tabB];
      final live = {'a', 'b'};
      wireForward(router, live, tabs);

      router.sync(selectedIds: live, tabs: tabs);

      // b's bridge tears down (onOutput = null), wiping the tee, then a
      // reconnect installs a brand new handler writing somewhere else.
      tabB.terminal.onOutput = null;
      final bNew = <String>[];
      tabB.terminal.onOutput = (data) => bNew.add(data);

      // The notifier re-syncs once the bridge is wired again.
      router.sync(selectedIds: live, tabs: tabs);

      tabA.terminal.onOutput!('echo hi');

      expect(a, ['echo hi']);
      expect(bNew, ['echo hi']); // reaches the live handler...
      expect(bOld, isEmpty); // ...never the dead pre-disconnect closure
    });

    test('deselect after a reconnect leaves the live handler intact', () {
      final a = <String>[];
      final tabA = session('a', captured: a);
      final tabB = session('b', captured: <String>[]);
      final tabs = [tabA, tabB];
      final live = <String>{'a', 'b'};
      wireForward(router, live, tabs);

      router.sync(selectedIds: live, tabs: tabs);

      // b reconnects with a fresh handler while still selected.
      final bNew = <String>[];
      tabB.terminal.onOutput = (data) => bNew.add(data);

      // Deselect b without an intervening sync: the router must not restore
      // the handler it stashed before the reconnect.
      live.remove('b');
      router.sync(selectedIds: live, tabs: tabs);

      tabB.terminal.onOutput!('x');
      expect(bNew, ['x']); // typing still reaches b's session
      expect(a, isEmpty); // and no longer fans out
    });

    test('sendTextToPanes skips panes removed from the tab list (closed)', () {
      final a = <String>[];
      final tabA = session('a', captured: a);
      final tabB = session('b', captured: <String>[]);
      final live = {'a', 'b'};
      wireForward(router, live, [tabA, tabB]);

      router.sync(selectedIds: live, tabs: [tabA, tabB]);

      // 'b' is closed: gone from both the tab list and the selection.
      live.remove('b');
      router.sync(selectedIds: live, tabs: [tabA]);

      final sent = router.sendTextToPanes(
        selectedIds: live,
        tabs: [tabA],
        text: 'ls',
      );

      expect(sent, 1);
      expect(a, ['ls']);
    });
  });
}