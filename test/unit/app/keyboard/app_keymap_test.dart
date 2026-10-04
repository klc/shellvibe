import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/keyboard/app_keymap.dart';
import 'package:xterm3/xterm.dart';

void main() {
  const apple = [TargetPlatform.macOS, TargetPlatform.iOS];
  const ctrl = [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.android,
  ];

  List<SingleActivator> chords(Map<ShortcutActivator, Intent> map) =>
      map.keys.cast<SingleActivator>().toList();

  group('labels', () {
    test('Command on Apple keyboards, in Apple\'s modifier order', () {
      for (final platform in apple) {
        String? label(AppCommand c) => shortcutLabel(c, platform: platform);
        expect(label(AppCommand.commandPalette), '⌘K', reason: '$platform');
        expect(label(AppCommand.openSnippets), '⇧⌘S', reason: '$platform');
        expect(label(AppCommand.find), '⌘F', reason: '$platform');
        expect(
          moduleRangeShortcutLabel(platform: platform),
          '⌘1…7',
          reason: '$platform',
        );
      }
      expect(
        shortcutLabel(AppCommand.closeWindow, platform: TargetPlatform.macOS),
        '⇧⌘W',
      );
    });

    test('Ctrl+Shift everywhere else', () {
      for (final platform in ctrl) {
        String? label(AppCommand c) => shortcutLabel(c, platform: platform);
        expect(label(AppCommand.commandPalette), 'Ctrl+Shift+K');
        expect(label(AppCommand.newLocalTab), 'Ctrl+Shift+T');
        expect(label(AppCommand.closeTab), 'Ctrl+Shift+W');
        expect(label(AppCommand.openSnippets), 'Ctrl+Shift+S');
        expect(label(AppCommand.find), 'Ctrl+Shift+F');
        expect(moduleShortcutLabel(1, platform: platform), 'Ctrl+Shift+2');
        expect(moduleRangeShortcutLabel(platform: platform), 'Ctrl+Shift+1…7');
      }
    });

    test('the window closes the way each desktop closes windows', () {
      String? label(TargetPlatform p) =>
          shortcutLabel(AppCommand.closeWindow, platform: p);
      expect(label(TargetPlatform.windows), 'Alt+F4');
      expect(label(TargetPlatform.linux), 'Ctrl+Shift+Q');
      expect(label(TargetPlatform.android), isNull);
      expect(label(TargetPlatform.iOS), isNull);
    });
  });

  group('keymap', () {
    test('no chord is bound twice', () {
      for (final platform in TargetPlatform.values) {
        for (final terminalFocused in [true, false]) {
          final list = chords(
            appKeymap(platform: platform, terminalFocused: terminalFocused),
          );
          for (var i = 0; i < list.length; i++) {
            for (var j = i + 1; j < list.length; j++) {
              expect(
                sameChord(list[i], list[j]),
                isFalse,
                reason: '$platform: ${list[i]} and ${list[j]}',
              );
            }
          }
        }
      }
    });

    test('a terminal keeps every plain Ctrl chord for the PTY', () {
      for (final platform in TargetPlatform.values) {
        for (final chord in chords(
          appKeymap(platform: platform, terminalFocused: true),
        )) {
          if (chord.control) {
            expect(chord.shift, isTrue, reason: '$platform: $chord');
          }
        }
      }
    });

    test('nothing is bound to Ctrl+Alt, which is AltGr on Windows', () {
      for (final platform in TargetPlatform.values) {
        for (final terminalFocused in [true, false]) {
          for (final chord in chords(
            appKeymap(platform: platform, terminalFocused: terminalFocused),
          )) {
            expect(chord.control && chord.alt, isFalse, reason: '$chord');
          }
        }
      }
    });

    test('Apple keyboards bind ⌘ only, so Ctrl stays the shell\'s', () {
      for (final platform in apple) {
        for (final chord in chords(
          appKeymap(platform: platform, terminalFocused: false),
        )) {
          expect(chord.control, isFalse, reason: '$platform: $chord');
        }
      }
    });

    test('plain Ctrl aliases outside a terminal, for what closes nothing', () {
      final map = appKeymap(
        platform: TargetPlatform.windows,
        terminalFocused: false,
      );
      Intent? intentFor(SingleActivator wanted) => map.entries
          .where((e) => sameChord(e.key as SingleActivator, wanted))
          .map((e) => e.value)
          .firstOrNull;

      expect(
        intentFor(
          const SingleActivator(LogicalKeyboardKey.keyK, control: true),
        ),
        isA<OpenCommandPaletteIntent>(),
      );
      expect(
        intentFor(
          const SingleActivator(LogicalKeyboardKey.digit3, control: true),
        ),
        isA<GoToModuleIntent>().having((i) => i.index, 'index', 2),
      );
      expect(
        intentFor(
          const SingleActivator(LogicalKeyboardKey.keyW, control: true),
        ),
        isNull,
        reason: 'closing a tab needs the Shift form everywhere',
      );
    });

    test('no app chord shadows one of xterm\'s own', () {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final xterm = chords(defaultTerminalShortcuts);
          for (final chord in chords(
            appKeymap(platform: platform, terminalFocused: true),
          )) {
            expect(
              xterm.any((other) => sameChord(chord, other)),
              isFalse,
              reason: '$platform: $chord',
            );
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
    });
  });
}
