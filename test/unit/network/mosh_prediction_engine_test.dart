import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/network/mosh_prediction_engine.dart';

void main() {
  group('MoshPredictionEngine', () {
    late DateTime now;
    late MoshPredictionEngine engine;

    DateTime clock() => now;

    MoshPredictionEngine build({
      MoshPredictionMode mode = MoshPredictionMode.adaptive,
      Duration adaptiveRttThreshold = const Duration(milliseconds: 60),
      Duration minTimeout = const Duration(milliseconds: 500),
    }) => MoshPredictionEngine(
      mode: mode,
      adaptiveRttThreshold: adaptiveRttThreshold,
      minTimeout: minTimeout,
      clock: clock,
    );

    setUp(() {
      now = DateTime(2026, 1, 1);
      // always mode sidesteps the adaptive RTT gate so most tests can focus
      // on the confirmation/epoch logic rather than mode plumbing; the mode
      // group below covers adaptive/never on their own.
      engine = build(mode: MoshPredictionMode.always);
    });

    // -----------------------------------------------------------------
    // R3 is the reason this class exists: an unconfirmed prediction must
    // never reach the screen, because at a password prompt the server never
    // echoes and a leaked prediction would be the user's password. Nobody
    // should ever "simplify" this group away.
    // -----------------------------------------------------------------
    group('R3 security — nothing is shown before confirmation', () {
      test('a printable character is recorded but not shown', () {
        engine.recordInput('a', 1);

        expect(engine.pendingCount, 1);
        expect(engine.isEpochConfirmed, isFalse);
        expect(engine.visibleText, '');
      });

      test('predictions stay hidden across several unconfirmed keystrokes', () {
        engine.recordInput('p', 1);
        engine.recordInput('a', 2);
        engine.recordInput('s', 3);
        engine.recordInput('s', 4);

        expect(engine.pendingCount, 4);
        expect(engine.visibleText, '');
      });

      test('an echo ack alone does not confirm or reveal anything', () {
        engine.recordInput('a', 1);
        engine.onEchoAck(1);

        expect(engine.isEpochConfirmed, isFalse);
        expect(engine.visibleText, '');
      });

      test('only a byte-for-byte server match confirms and reveals', () {
        // The confirmed glyph itself is retired (the real echo already put
        // it on screen); what R3 unlocks is the *still-unconfirmed*
        // prediction typed after it, which was hidden until this moment.
        engine.recordInput('a', 1);
        engine.recordInput('b', 2);
        engine.onServerOutput(utf8.encode('a'));

        expect(engine.isEpochConfirmed, isTrue);
        expect(engine.visibleText, 'b');
      });
    });

    group('recordInput classification (R1)', () {
      test('printable character is appended as a prediction', () {
        engine.recordInput('x', 1);
        expect(engine.pendingCount, 1);
      });

      test('backspace removes the most recent prediction', () {
        engine.recordInput('a', 1);
        engine.recordInput('b', 2);
        engine.recordInput('\x08', 3);

        expect(engine.pendingCount, 1);
        // The epoch survives a backspace with something to retract.
        engine.onServerOutput(utf8.encode('a'));
        expect(engine.isEpochConfirmed, isTrue);
      });

      test('DEL (0x7F) also acts as backspace', () {
        engine.recordInput('a', 1);
        engine.recordInput('\x7F', 2);

        expect(engine.pendingCount, 0);
      });

      test('backspace with nothing pending kills the epoch', () {
        engine.recordInput('a', 1);
        engine.onServerOutput(utf8.encode('a'));
        expect(engine.isEpochConfirmed, isTrue);

        engine.recordInput('\x08', 2);

        expect(engine.pendingCount, 0);
        expect(engine.isEpochConfirmed, isFalse);
      });

      test('Enter kills the epoch', () {
        engine.recordInput('a', 1);
        engine.recordInput('\r', 2);

        expect(engine.pendingCount, 0);
      });

      test('Tab kills the epoch', () {
        engine.recordInput('a', 1);
        engine.recordInput('\t', 2);

        expect(engine.pendingCount, 0);
      });

      test('an escape sequence kills the epoch', () {
        engine.recordInput('a', 1);
        engine.recordInput('\x1b[A', 2);

        expect(engine.pendingCount, 0);
      });

      test('a multi-character paste kills the epoch', () {
        engine.recordInput('a', 1);
        engine.recordInput('pasted text', 2);

        expect(engine.pendingCount, 0);
      });

      test('empty input kills the epoch', () {
        engine.recordInput('a', 1);
        engine.recordInput('', 2);

        expect(engine.pendingCount, 0);
      });

      test('a live epoch is killed by a control character too', () {
        engine.recordInput('a', 1);
        engine.onServerOutput(utf8.encode('a'));
        expect(engine.isEpochConfirmed, isTrue);

        engine.recordInput('\r', 2);

        expect(engine.isEpochConfirmed, isFalse);
        expect(engine.pendingCount, 0);
      });
    });

    group('onEchoAck (R2)', () {
      /// Brings the engine to a confirmed epoch, since acks are deliberately
      /// inert before that point, and leaves nothing pending behind.
      void confirmEpoch() {
        engine.recordInput('~', 900);
        engine.onServerOutput(utf8.encode('~'));
        expect(engine.isEpochConfirmed, isTrue);
        expect(engine.pendingCount, 0);
      }

      test('retires predictions up to and including the ack number', () {
        confirmEpoch();
        engine.recordInput('a', 1);
        engine.recordInput('b', 2);
        engine.recordInput('c', 3);

        engine.onEchoAck(2);

        expect(engine.pendingCount, 1);
      });

      test('an out-of-order ack does not misbehave', () {
        confirmEpoch();
        engine.recordInput('a', 1);
        engine.recordInput('b', 2);

        engine.onEchoAck(5);

        expect(engine.pendingCount, 0);
      });

      test('a duplicate ack is a harmless no-op', () {
        confirmEpoch();
        engine.recordInput('a', 1);
        engine.onEchoAck(1);
        engine.onEchoAck(1);

        expect(engine.pendingCount, 0);
      });

      test('a negative ack number does not throw and retires nothing extra', () {
        confirmEpoch();
        engine.recordInput('a', 1);

        expect(() => engine.onEchoAck(-1), returnsNormally);
        expect(engine.pendingCount, 1);
      });

      test('an ack is inert while the epoch is unconfirmed', () {
        // A mosh host message carries the echoed bytes and the ack together.
        // If an ack could retire an unconfirmed prediction, it would consume
        // the very prediction the bytes were about to confirm — and since only
        // a byte match can ever confirm an epoch, nothing would be shown again
        // for the rest of the session.
        engine.recordInput('a', 1);
        engine.onEchoAck(1);

        expect(engine.pendingCount, 1);
        expect(engine.isEpochConfirmed, isFalse);
      });

      test('confirmation still works when the ack is applied first', () {
        engine.recordInput('a', 1);
        engine.recordInput('b', 2);

        engine.onEchoAck(2);
        engine.onServerOutput(utf8.encode('a'));

        expect(engine.isEpochConfirmed, isTrue);
        expect(engine.visibleText, 'b');
      });
    });

    group('onServerOutput / epoch confirmation (R4)', () {
      test('a matching printable character confirms and consumes it', () {
        engine.recordInput('a', 1);
        engine.onServerOutput(utf8.encode('a'));

        expect(engine.isEpochConfirmed, isTrue);
        expect(engine.pendingCount, 0);
      });

      test('a mismatching printable character kills the epoch', () {
        engine.recordInput('a', 1);
        engine.onServerOutput(utf8.encode('b'));

        expect(engine.isEpochConfirmed, isFalse);
        expect(engine.pendingCount, 0);
      });

      test('a control character in the output kills the epoch', () {
        engine.recordInput('a', 1);
        engine.onServerOutput(utf8.encode('a'));
        expect(engine.isEpochConfirmed, isTrue);

        engine.recordInput('b', 2);
        // A bell (0x07) mixed in with otherwise-matching text still kills it:
        // something structural happened and position can't be trusted.
        engine.onServerOutput([0x07, ...utf8.encode('b')]);

        expect(engine.isEpochConfirmed, isFalse);
        expect(engine.pendingCount, 0);
      });

      test('an ESC byte in the output kills the epoch', () {
        engine.recordInput('a', 1);
        engine.onServerOutput([0x1b, 0x5b, 0x41]);

        expect(engine.isEpochConfirmed, isFalse);
        expect(engine.pendingCount, 0);
      });

      test('server output with nothing pending is harmless', () {
        expect(() => engine.onServerOutput(utf8.encode('hello')), returnsNormally);

        expect(engine.isEpochConfirmed, isFalse);
        expect(engine.pendingCount, 0);
      });

      test('confirms multiple predictions in one output batch, in order', () {
        engine.recordInput('a', 1);
        engine.recordInput('b', 2);
        engine.recordInput('c', 3);

        engine.onServerOutput(utf8.encode('abc'));

        expect(engine.isEpochConfirmed, isTrue);
        expect(engine.pendingCount, 0);
      });

      test('malformed UTF-8 bytes do not throw', () {
        expect(
          () => engine.onServerOutput([0xC3, 0x28, 0xFF]),
          returnsNormally,
        );
      });
    });

    group('timeout / staleness (R5)', () {
      test('a stale prediction is dropped and kills the epoch', () {
        engine.updateRtt(const Duration(milliseconds: 10));
        engine.recordInput('a', 1);

        // minTimeout is 500ms and 2*srtt is only 20ms, so the floor applies.
        now = now.add(const Duration(milliseconds: 600));

        expect(engine.pendingCount, 0);
        expect(engine.isEpochConfirmed, isFalse);
      });

      test('a prediction just under the threshold survives', () {
        engine.updateRtt(const Duration(milliseconds: 10));
        engine.recordInput('a', 1);

        now = now.add(const Duration(milliseconds: 400));

        expect(engine.pendingCount, 1);
      });

      test('a larger srtt raises the timeout via 2 * srtt', () {
        engine.updateRtt(const Duration(milliseconds: 400));
        engine.recordInput('a', 1);

        // 2 * srtt = 800ms > minTimeout(500ms), so this should still be
        // pending at 600ms.
        now = now.add(const Duration(milliseconds: 600));
        expect(engine.pendingCount, 1);

        now = now.add(const Duration(milliseconds: 300));
        expect(engine.pendingCount, 0);
      });

      test('staleness kills a confirmed epoch too', () {
        engine.recordInput('a', 1);
        engine.onServerOutput(utf8.encode('a'));
        expect(engine.isEpochConfirmed, isTrue);

        engine.recordInput('b', 2);
        now = now.add(const Duration(milliseconds: 600));

        expect(engine.isEpochConfirmed, isFalse);
        expect(engine.pendingCount, 0);
      });
    });

    group('modes (R6)', () {
      test('never mode records nothing', () {
        final never = build(mode: MoshPredictionMode.never);

        never.recordInput('a', 1);

        expect(never.pendingCount, 0);
        expect(never.visibleText, '');
      });

      test('switching to never clears everything already pending', () {
        final adaptive = build();
        adaptive.recordInput('a', 1);
        expect(adaptive.pendingCount, 1);

        adaptive.mode = MoshPredictionMode.never;

        expect(adaptive.pendingCount, 0);
        adaptive.recordInput('b', 2);
        expect(adaptive.pendingCount, 0);
      });

      test('adaptive mode hides confirmed predictions below the RTT threshold', () {
        final adaptive = build(adaptiveRttThreshold: const Duration(milliseconds: 60));
        adaptive.updateRtt(const Duration(milliseconds: 30));
        adaptive.recordInput('a', 1);
        adaptive.recordInput('b', 2);
        adaptive.onServerOutput(utf8.encode('a'));

        expect(adaptive.isEpochConfirmed, isTrue);
        expect(adaptive.visibleText, '');
      });

      test('adaptive mode shows confirmed predictions above the RTT threshold', () {
        final adaptive = build(adaptiveRttThreshold: const Duration(milliseconds: 60));
        adaptive.updateRtt(const Duration(milliseconds: 90));
        adaptive.recordInput('a', 1);
        adaptive.recordInput('b', 2);
        adaptive.onServerOutput(utf8.encode('a'));

        expect(adaptive.visibleText, 'b');
      });

      test('adaptive mode hides when RTT is unknown', () {
        final adaptive = build();
        adaptive.recordInput('a', 1);
        adaptive.onServerOutput(utf8.encode('a'));

        expect(adaptive.isEpochConfirmed, isTrue);
        expect(adaptive.visibleText, '');
      });

      test(
        'adaptive mode keeps recording while hidden, so a later RTT rise '
        'shows it without a fresh keystroke',
        () {
          final adaptive = build(adaptiveRttThreshold: const Duration(milliseconds: 60));
          adaptive.recordInput('a', 1);
          adaptive.recordInput('b', 2);
          adaptive.onServerOutput(utf8.encode('a'));
          expect(adaptive.visibleText, '');

          adaptive.updateRtt(const Duration(milliseconds: 90));

          expect(adaptive.visibleText, 'b');
        },
      );

      test('always mode still hides until confirmed', () {
        final always = build(mode: MoshPredictionMode.always);
        always.updateRtt(Duration.zero);
        always.recordInput('a', 1);
        always.recordInput('b', 2);

        expect(always.visibleText, '');

        always.onServerOutput(utf8.encode('a'));
        expect(always.visibleText, 'b');
      });
    });

    group('visibleText content (R7)', () {
      test('joins pending glyphs in typed order', () {
        engine.recordInput('a', 1);
        engine.recordInput('b', 2);
        engine.recordInput('c', 3);
        // Confirming 'a' retires it (the real echo already drew it); 'b' and
        // 'c' are still unconfirmed individually but become visible because
        // the epoch as a whole is now trusted.
        engine.onServerOutput(utf8.encode('a'));

        expect(engine.visibleText, 'bc');
      });
    });

    group('reset', () {
      test('clears pending predictions, confirmation, and RTT-driven state', () {
        engine.updateRtt(const Duration(milliseconds: 90));
        engine.recordInput('a', 1);
        engine.onServerOutput(utf8.encode('a'));
        expect(engine.isEpochConfirmed, isTrue);

        engine.reset();

        expect(engine.pendingCount, 0);
        expect(engine.isEpochConfirmed, isFalse);
        expect(engine.visibleText, '');
      });
    });

    group('robustness (R8)', () {
      test('no public method throws on adversarial input', () {
        expect(() => engine.recordInput('a', -5), returnsNormally);
        expect(() => engine.onEchoAck(-100), returnsNormally);
        expect(() => engine.onServerOutput(const [0xFF, 0xFE, 0x00, -1, 300]), returnsNormally);
        expect(() => engine.updateRtt(null), returnsNormally);
        expect(() => engine.reset(), returnsNormally);
      });
    });
  });
}
