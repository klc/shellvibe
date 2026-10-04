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

    test('a terminal keeps every plain Ctrl chord that is a control code', () {
      for (final platform in TargetPlatform.values) {
        for (final chord in chords(
          appKeymap(platform: platform, terminalFocused: true),
        )) {
          if (chord.control && !chord.shift) {
            expect(
              _hasControlCode(chord.trigger),
              isFalse,
              reason: '$platform: $chord',
            );
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

    test('Apple keyboards bind ⌘, and Ctrl only for ⌃Tab', () {
      for (final platform in apple) {
        for (final chord in chords(
          appKeymap(platform: platform, terminalFocused: false),
        )) {
          if (chord.control) {
            expect(
              chord.trigger,
              LogicalKeyboardKey.tab,
              reason: '$platform: $chord',
            );
          }
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

  group('phase 3 commands', () {
    test('tab cycling and settings use the forms every app uses', () {
      expect(
        shortcutLabel(AppCommand.nextTab, platform: TargetPlatform.windows),
        'Ctrl+Tab',
      );
      expect(
        shortcutLabel(AppCommand.previousTab, platform: TargetPlatform.linux),
        'Ctrl+Shift+Tab',
      );
      expect(
        shortcutLabel(AppCommand.previousTab, platform: TargetPlatform.macOS),
        '⌃⇧Tab',
      );
      expect(
        shortcutLabel(AppCommand.openSettings, platform: TargetPlatform.macOS),
        '⌘,',
      );
      expect(
        shortcutLabel(
          AppCommand.openSettings,
          platform: TargetPlatform.windows,
        ),
        'Ctrl+,',
      );
    });

    test('zoom has a keypad way in off Apple', () {
      bool binds(AppCommand command, SingleActivator wanted) => shortcutsFor(
        command,
        platform: TargetPlatform.windows,
      ).any((chord) => sameChord(chord, wanted));

      expect(
        shortcutLabel(AppCommand.zoomIn, platform: TargetPlatform.windows),
        'Ctrl+Shift+=',
      );
      expect(
        binds(
          AppCommand.zoomIn,
          const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true),
        ),
        isTrue,
      );
      expect(
        binds(
          AppCommand.zoomOut,
          const SingleActivator(
            LogicalKeyboardKey.numpadSubtract,
            control: true,
          ),
        ),
        isTrue,
      );
      expect(
        shortcutLabel(AppCommand.zoomReset, platform: TargetPlatform.macOS),
        '⌘0',
      );
    });

    test('the shortcut list names every command bound on the platform', () {
      for (final platform in TargetPlatform.values) {
        final listed = {
          for (final (_, rows) in shortcutReference(platform: platform))
            for (final row in rows) row.label,
        };
        for (final command in AppCommand.values) {
          if (shortcutFor(command, platform: platform) == null) continue;
          expect(listed, contains(command.label), reason: '$platform');
        }
      }
      final windows = shortcutReference(platform: TargetPlatform.windows);
      final terminalRows = windows.firstWhere((g) => g.$1 == 'Terminal').$2;
      expect(
        terminalRows.map((row) => (row.label, row.keys)),
        contains(('Copy', 'Ctrl+Shift+C')),
      );
    });

    test('a device with no local shell is not told about local tabs', () {
      final rows = [
        for (final (_, rows) in shortcutReference(
          platform: TargetPlatform.iOS,
          includeLocalTab: false,
        ))
          ...rows,
      ];
      expect(rows.map((row) => row.label), isNot(contains('New local tab')));
    });
  });
}

/// Whether Ctrl + [key] is one of the C0 control codes a shell reads:
/// letters, digits (Ctrl+2…8 in xterm's table), and `@ [ \ ] ^ _ - / space`.
bool _hasControlCode(LogicalKeyboardKey key) {
  final label = key.keyLabel;
  if (label.length != 1) return key == LogicalKeyboardKey.space;
  return RegExp(r'[A-Za-z0-9@\[\\\]^_\-/ ]').hasMatch(label);
}
