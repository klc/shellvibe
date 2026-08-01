import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:terly2/features/terminal/presentation/widgets/mobile_extra_keys_bar.dart';

void main() {
  group('MobileExtraKeysBar Widget & State Machine Tests', () {
    testWidgets('Renders modifier and action key buttons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MobileExtraKeysBar(),
          ),
        ),
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
            body: MobileExtraKeysBar(
              onInput: (data) => emittedData = data,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('key_pipe')));
      expect(emittedData, equals('|'));

      await tester.tap(find.byKey(const Key('key_arrow_up')));
      expect(emittedData, equals('\x1b[A'));
    });

    testWidgets('Sticky key state machine: Ctrl toggles and resets after action', (tester) async {
      String? emittedData;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileExtraKeysBar(
              onInput: (data) => emittedData = data,
            ),
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
    });

    testWidgets('Sticky key state machine: Alt prepends ESC prefix and resets', (tester) async {
      String? emittedData;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileExtraKeysBar(
              onInput: (data) => emittedData = data,
            ),
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
    });

    testWidgets('Combined Ctrl + Alt active emits ESC prefix and Ctrl transformed character', (tester) async {
      String? emittedData;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileExtraKeysBar(
              onInput: (data) => emittedData = data,
            ),
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
    });

    testWidgets('Ctrl modifier transforms symbols to ASCII control codes', (tester) async {
      String? emittedData;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileExtraKeysBar(
              onInput: (data) => emittedData = data,
            ),
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
  });
}
