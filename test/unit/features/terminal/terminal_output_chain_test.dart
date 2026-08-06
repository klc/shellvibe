import 'package:flutter_test/flutter_test.dart';
import 'package:xterm3/xterm.dart';

import 'package:terly2/features/terminal/domain/services/terminal_output_chain.dart';

void main() {
  late Terminal terminal;
  late List<String> session;
  late TerminalOutputChain chain;

  /// Stands in for a bridge connecting: bridges own the slot and assign it
  /// directly, which the chain has to pick up.
  void connectBridge() {
    terminal.onOutput = (data) => session.add(data);
  }

  setUp(() {
    terminal = Terminal(maxLines: 100);
    session = [];
    chain = TerminalOutputChain(terminal);
  });

  group('TerminalOutputChain', () {
    test('passes input to the session when no interceptor is registered', () {
      connectBridge();
      terminal.onOutput!('ls');
      expect(session, ['ls']);
    });

    test('stays dormant while there is no session handler', () {
      chain.add('x', (data, next) => next('!$data'));
      expect(terminal.onOutput, isNull); // null still means "cannot deliver"
      expect(chain.base, isNull);

      // ...and wakes up as soon as the bridge connects.
      connectBridge();
      chain.add('y', (data, next) => next(data));
      terminal.onOutput!('ls');
      expect(session, ['!ls']);
    });

    test('runs interceptors last-added-first, then the session', () {
      connectBridge();
      final order = <String>[];
      chain.add('inner', (data, next) {
        order.add('inner');
        next(data);
      });
      chain.add('outer', (data, next) {
        order.add('outer');
        next(data);
      });

      terminal.onOutput!('x');

      expect(order, ['outer', 'inner']);
      expect(session, ['x']);
    });

    test('an innermost link sees the data last, whatever the install order',
        () {
      connectBridge();
      final innerSaw = <String>[];
      // Registered first, but pinned innermost...
      chain.add('inner', (data, next) {
        innerSaw.add(data);
        next(data);
      }, innermost: true);
      // ...so this later link still runs before it.
      chain.add('folder', (data, next) => next(data.toUpperCase()));

      terminal.onOutput!('ls');

      expect(innerSaw, ['LS']);
      expect(session, ['LS']);
    });

    test('a link can be removed whatever joined the chain after it', () {
      connectBridge();
      chain.add('first', (data, next) => next('[$data]'));
      chain.add('second', (data, next) => next('<$data>'));

      chain.remove('first');
      terminal.onOutput!('x');
      expect(session, ['<x>']); // only the later link is left

      chain.remove('second');
      terminal.onOutput!('y');
      expect(session, ['<x>', 'y']);
      expect(chain.has('second'), isFalse);
    });

    test('without() disables one link for the duration of a call', () {
      connectBridge();
      final seen = <String>[];
      chain.add('mine', (data, next) {
        seen.add(data);
        next(data);
      });
      chain.add('other', (data, next) => next('*$data'));

      chain.without('mine', () => terminal.onOutput!('paste'));

      expect(seen, isEmpty); // our own link never fired...
      expect(session, ['*paste']); // ...but the rest of the chain did

      terminal.onOutput!('typed');
      expect(seen, ['*typed']); // and it is back afterwards
    });

    test('adopts the bridge handler installed by a reconnect', () {
      connectBridge();
      chain.add('mine', (data, next) => next('$data!'));

      // Bridge tears down and a reconnect installs a brand new handler.
      terminal.onOutput = null;
      final reconnected = <String>[];
      terminal.onOutput = (data) => reconnected.add(data);

      // Any chain operation repairs the wiring over the new handler.
      chain.add('mine', (data, next) => next('$data!'));
      terminal.onOutput!('x');

      expect(reconnected, ['x!']);
      expect(session, isEmpty); // nothing went to the dead handler
    });

    test('base bypasses every interceptor', () {
      connectBridge();
      chain.add('mine', (data, next) => next('never'));
      chain.base!('direct');
      expect(session, ['direct']);
    });

    test('dispose puts the bare session handler back', () {
      connectBridge();
      chain.add('mine', (data, next) => next('$data!'));
      chain.dispose();

      terminal.onOutput!('x');
      expect(session, ['x']);
    });
  });
}
