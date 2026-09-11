import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm3/xterm.dart';

import 'package:shellvibe/features/terminal/presentation/widgets/mobile_extra_keys_bar.dart';

void main() {
  group('MobileExtraKeysBar Widget & State Machine Tests', () {
    testWidgets('Renders modifier and action key buttons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MobileExtraKeysBar())),
      );

      expect(find.byKey(const Key('key_ctrl')), findsOneWidget);
      expect(find.byKey(const Key('key_alt')), findsOneWidget);
      expect(find.byKey(const Key('key_esc')), findsOneWidget);
      expect(find.byKey(const Key('key_tab')), findsOneWidget);
      expect(find.byKey(const Key('key_pipe')), findsOneWidget);
      expect(find.byKey(const Key('key_arrow_left')), findsOneWidget);
    });

    testWidgets('Tapping action key emits output string', (tester) async {
      String? emittedData;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileExtraKeysBar(onInput: (data) => emittedData = data),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('key_pipe')));
      expect(emittedData, equals('|'));

      await tester.tap(find.byKey(const Key('key_arrow_up')));
      expect(emittedData, equals('\x1b[A'));
    });

    testWidgets(
      'Sticky key state machine: Ctrl toggles and resets after action',
      (tester) async {
        String? emittedData;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MobileExtraKeysBar(onInput: (data) => emittedData = data),
            ),
          ),
        );

        // Tap Ctrl (sets sticky state)
        await tester.tap(find.byKey(const Key('key_ctrl')));
        await tester.pump();

        // Tap Esc -> should emit ctrlChar '\x1b'
        await tester.tap(find.byKey(const Key('key_esc')));
        await tester.pump();

        expect(emittedData, equals('\x1b'));

        // Next tap without Ctrl should emit normal char
        await tester.tap(find.byKey(const Key('key_slash')));
        expect(emittedData, equals('/'));
      },
    );

    testWidgets(
      'Sticky key state machine: Alt prepends ESC prefix and resets',
      (tester) async {
        String? emittedData;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MobileExtraKeysBar(onInput: (data) => emittedData = data),
            ),
          ),
        );

        // Tap Alt
        await tester.tap(find.byKey(const Key('key_alt')));
        await tester.pump();

        // Tap ~
        await tester.tap(find.byKey(const Key('key_tilde')));
        await tester.pump();

        expect(emittedData, equals('\x1b~'));

        // Next tap without Alt should emit normal char
        await tester.tap(find.byKey(const Key('key_dash')));
        expect(emittedData, equals('-'));
      },
    );

    testWidgets(
      'Combined Ctrl + Alt active emits ESC prefix and Ctrl transformed character',
      (tester) async {
        String? emittedData;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MobileExtraKeysBar(onInput: (data) => emittedData = data),
            ),
          ),
        );

        // Tap Ctrl and Alt
        await tester.tap(find.byKey(const Key('key_ctrl')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('key_alt')));
        await tester.pump();

        // Tap pipe '|' -> Ctrl+| is \x1c, with Alt prefix -> \x1b\x1c
        await tester.tap(find.byKey(const Key('key_pipe')));
        await tester.pump();

        expect(emittedData, equals('\x1b\x1c'));
      },
    );

    testWidgets('Ctrl modifier transforms symbols to ASCII control codes', (
      tester,
    ) async {
      String? emittedData;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileExtraKeysBar(onInput: (data) => emittedData = data),
          ),
        ),
      );

      // Ctrl + '|' -> \x1c
      await tester.tap(find.byKey(const Key('key_ctrl')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('key_pipe')));
      await tester.pump();
      expect(emittedData, equals('\x1c'));

      // Ctrl + '~' -> \x1e
      await tester.tap(find.byKey(const Key('key_ctrl')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('key_tilde')));
      await tester.pump();
      expect(emittedData, equals('\x1e'));
    });

    testWidgets('Sticky Ctrl transforms keyboard-typed char via onOutput', (
      tester,
    ) async {
      final terminal = Terminal();
      final received = <String>[];
      terminal.onOutput = received.add;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MobileExtraKeysBar(terminal: terminal)),
        ),
      );

      // Tap Ctrl, then type 'c' through the IME path -> Ctrl+C (0x03).
      await tester.tap(find.byKey(const Key('key_ctrl')));
      await tester.pump();
      terminal.textInput('c');
      await tester.pump();

      expect(received, equals(['\x03']));
    });

    testWidgets('Sticky Alt prepends ESC to keyboard-typed char', (
      tester,
    ) async {
      final terminal = Terminal();
      final received = <String>[];
      terminal.onOutput = received.add;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MobileExtraKeysBar(terminal: terminal)),
        ),
      );

      await tester.tap(find.byKey(const Key('key_alt')));
      await tester.pump();
      terminal.textInput('a');
      await tester.pump();

      expect(received, equals(['\x1ba']));
    });

    testWidgets('Sticky modifier resets after one masked keyboard char', (
      tester,
    ) async {
      final terminal = Terminal();
      final received = <String>[];
      terminal.onOutput = received.add;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MobileExtraKeysBar(terminal: terminal)),
        ),
      );

      await tester.tap(find.byKey(const Key('key_ctrl')));
      await tester.pump();

      terminal.textInput('a');
      terminal.textInput('a');
      await tester.pump();

      // First char masked, sticky consumed -> second char passes through.
      expect(received, equals(['\x01', 'a']));
    });

    testWidgets(
      'Multi-byte terminal output passes through unmasked and keeps sticky',
      (tester) async {
        final terminal = Terminal();
        final received = <String>[];
        terminal.onOutput = received.add;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MobileExtraKeysBar(terminal: terminal)),
          ),
        );

        await tester.tap(find.byKey(const Key('key_ctrl')));
        await tester.pump();

        // e.g. an arrow escape sequence emitted by the terminal.
        terminal.textInput('\x1b[A');
        terminal.textInput('c');
        await tester.pump();

        expect(received, equals(['\x1b[A', '\x03']));
      },
    );

    testWidgets('Bar disposes without leaking interceptor on terminal', (
      tester,
    ) async {
      final terminal = Terminal();
      void original(String data) {}
      terminal.onOutput = original;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MobileExtraKeysBar(terminal: terminal)),
        ),
      );
      expect(identical(terminal.onOutput, original), isFalse);

      await tester.pumpWidget(const SizedBox());
      expect(identical(terminal.onOutput, original), isTrue);
    });

    testWidgets('Every bar key flushes the IME before it sends', (
      tester,
    ) async {
      final events = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileExtraKeysBar(
              onInput: (data) => events.add('key:$data'),
              onFlushInput: () => events.add('flush'),
            ),
          ),
        ),
      );

      // A bar key bypasses the keyboard, so the word the IME is still holding
      // has to reach the terminal first — otherwise Tab completes a line that
      // is missing everything the user typed.
      await tester.tap(find.byKey(const Key('key_tab')));
      await tester.pump();
      expect(events, ['flush', 'key:\t']);

      await tester.tap(find.byKey(const Key('key_arrow_up')));
      await tester.pump();
      expect(events, ['flush', 'key:\t', 'flush', 'key:\x1b[A']);

      // Toggling a sticky modifier sends nothing, so it must not flush either.
      await tester.tap(find.byKey(const Key('key_ctrl')));
      await tester.pump();
      expect(events, hasLength(4));
    });

    testWidgets('Flushed IME text is not masked by the sticky modifier', (
      tester,
    ) async {
      final terminal = Terminal();
      final received = <String>[];
      terminal.onOutput = received.add;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileExtraKeysBar(
              terminal: terminal,
              // What a real flush does: hands the pending composition to the
              // terminal as ordinary input.
              onFlushInput: () => terminal.textInput('a'),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('key_ctrl')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('key_pipe')));
      await tester.pump();

      // The sticky Ctrl belongs to the key the user pressed on the bar, not to
      // the character the keyboard happened to still be holding.
      expect(received, equals(['a', '\x1c']));
    });
  });
}
