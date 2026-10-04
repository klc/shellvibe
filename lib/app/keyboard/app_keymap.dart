import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/utils/platform_capabilities.dart';

// The app's keyboard shortcuts, and the one place they are decided.
//
// The rule the map follows:
//
// * **Apple keyboards** (macOS, an iPad's hardware keyboard): ⌘ + key. ⌘ is
//   never encoded for the PTY, so the same chord works whether or not a
//   terminal has focus.
// * **Everywhere else** (Windows, Linux, an Android hardware keyboard):
//   Ctrl+Shift + key. Plain Ctrl + letter belongs to the program running in
//   the terminal — Ctrl+K is readline's kill-line, Ctrl+W its werase,
//   Ctrl+T transpose — and a terminal that claims them has broken the shell.
//   Outside a terminal, plain Ctrl is accepted too for the non-destructive
//   commands (palette, modules, new tab), as it always was; the UI only ever
//   advertises the Ctrl+Shift form, which works in both places.
// * **No Ctrl+Alt chords.** On Windows AltGr arrives as Ctrl+Alt, and the
//   Turkish and German layouts type `{ [ ] } @ \` with it.
//
// Bindings and their labels both come from `shortcutFor`, so a label cannot
// advertise a chord that is not bound.

/// Opens the command palette.
class OpenCommandPaletteIntent extends Intent {
  const OpenCommandPaletteIntent();
}

/// Switches to the module at [index] of `appNavigationItems`.
class GoToModuleIntent extends Intent {
  final int index;

  const GoToModuleIntent(this.index);
}

/// Opens a local shell in a new terminal tab.
class NewLocalTabIntent extends Intent {
  const NewLocalTabIntent();
}

/// Closes the active terminal tab, with every pane split from it.
class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

/// Opens the snippet picker for the active pane.
class OpenSnippetPickerIntent extends Intent {
  const OpenSnippetPickerIntent();
}

/// Opens the find bar of the focused terminal.
class FindInTerminalIntent extends Intent {
  const FindInTerminalIntent();
}

/// Closes the host window.
class CloseWindowIntent extends Intent {
  const CloseWindowIntent();
}

/// The commands with a fixed shortcut. Module switching is not listed: it is
/// one chord per module, see [moduleShortcut].
enum AppCommand {
  commandPalette(OpenCommandPaletteIntent()),
  newLocalTab(NewLocalTabIntent()),
  closeTab(CloseTabIntent()),
  openSnippets(OpenSnippetPickerIntent()),
  find(FindInTerminalIntent()),
  closeWindow(CloseWindowIntent());

  final Intent intent;

  const AppCommand(this.intent);
}

/// How many modules have a digit shortcut. Matches `appNavigationItems`.
const int kModuleShortcutCount = 7;

const List<LogicalKeyboardKey> _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// Whether shortcuts on [platform] are written with ⌘ rather than Ctrl+Shift.
bool usesCommandKey([TargetPlatform? platform]) =>
    switch (platform ?? runtimeTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => true,
      _ => false,
    };

/// ⌘ + [key] on Apple keyboards, Ctrl+Shift + [key] elsewhere.
SingleActivator _primary(LogicalKeyboardKey key, TargetPlatform platform) =>
    usesCommandKey(platform)
    ? SingleActivator(key, meta: true)
    : SingleActivator(key, control: true, shift: true);

/// The chord for [command] on [platform], or null where it has none.
SingleActivator? shortcutFor(AppCommand command, {TargetPlatform? platform}) {
  final target = platform ?? runtimeTargetPlatform;
  return switch (command) {
    AppCommand.commandPalette => _primary(LogicalKeyboardKey.keyK, target),
    AppCommand.newLocalTab => _primary(LogicalKeyboardKey.keyT, target),
    AppCommand.closeTab => _primary(LogicalKeyboardKey.keyW, target),
    // Shift on every platform: plain ⌘S is the save every Mac user reaches
    // for, and Ctrl+Shift is already the non-Apple base.
    AppCommand.openSnippets =>
      usesCommandKey(target)
          ? const SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: true,
              shift: true,
            )
          : const SingleActivator(
              LogicalKeyboardKey.keyS,
              control: true,
              shift: true,
            ),
    AppCommand.find => _primary(LogicalKeyboardKey.keyF, target),
    // ⌘W closes the tab, so the window moves up to ⇧⌘W the way Terminal.app
    // and iTerm do it. Ctrl+Shift+W closes the tab elsewhere, so Windows
    // keeps its own Alt+F4 — bound here because a focused terminal would
    // otherwise encode it for the PTY — and Linux takes GNOME Terminal's
    // Ctrl+Shift+Q. Phones and tablets have no window to close.
    AppCommand.closeWindow => switch (target) {
      TargetPlatform.macOS => const SingleActivator(
        LogicalKeyboardKey.keyW,
        meta: true,
        shift: true,
      ),
      TargetPlatform.windows => const SingleActivator(
        LogicalKeyboardKey.f4,
        alt: true,
      ),
      TargetPlatform.linux => const SingleActivator(
        LogicalKeyboardKey.keyQ,
        control: true,
        shift: true,
      ),
      _ => null,
    },
  };
}

/// The chord that opens the module at [index] (0-based).
SingleActivator moduleShortcut(int index, {TargetPlatform? platform}) =>
    _primary(_digitKeys[index], platform ?? runtimeTargetPlatform);

/// Every app shortcut on [platform], for a `Shortcuts` widget or a terminal's
/// shortcut map.
///
/// [terminalFocused] drops the plain-Ctrl aliases, which belong to the PTY.
Map<ShortcutActivator, Intent> appKeymap({
  TargetPlatform? platform,
  required bool terminalFocused,
}) {
  final target = platform ?? runtimeTargetPlatform;
  final aliases = !terminalFocused && !usesCommandKey(target);
  return {
    for (final command in AppCommand.values)
      ?shortcutFor(command, platform: target): command.intent,
    for (var index = 0; index < kModuleShortcutCount; index++) ...{
      moduleShortcut(index, platform: target): GoToModuleIntent(index),
      if (aliases)
        SingleActivator(_digitKeys[index], control: true): GoToModuleIntent(
          index,
        ),
    },
    if (aliases) ...{
      const SingleActivator(LogicalKeyboardKey.keyK, control: true):
          const OpenCommandPaletteIntent(),
      const SingleActivator(LogicalKeyboardKey.keyT, control: true):
          const NewLocalTabIntent(),
    },
  };
}

/// [activator] as this platform writes it: `⇧⌘S` on Apple keyboards,
/// `Ctrl+Shift+S` elsewhere.
String describeShortcut(SingleActivator activator, {TargetPlatform? platform}) {
  final target = platform ?? runtimeTargetPlatform;
  final key = activator.trigger.keyLabel;
  if (usesCommandKey(target)) {
    // Apple's fixed modifier order: Control, Option, Shift, Command.
    return [
      if (activator.control) '⌃',
      if (activator.alt) '⌥',
      if (activator.shift) '⇧',
      if (activator.meta) '⌘',
      key,
    ].join();
  }
  return [
    if (activator.control) 'Ctrl',
    if (activator.alt) 'Alt',
    if (activator.shift) 'Shift',
    if (activator.meta) target == TargetPlatform.windows ? 'Win' : 'Super',
    key,
  ].join('+');
}

/// The label for [command] on [platform], or null where it has no shortcut.
String? shortcutLabel(AppCommand command, {TargetPlatform? platform}) {
  final activator = shortcutFor(command, platform: platform);
  return activator == null
      ? null
      : describeShortcut(activator, platform: platform);
}

/// The label for the module at [index].
String moduleShortcutLabel(int index, {TargetPlatform? platform}) =>
    describeShortcut(
      moduleShortcut(index, platform: platform),
      platform: platform,
    );

/// The module chords as one range: `⌘1…7` or `Ctrl+Shift+1…7`.
String moduleRangeShortcutLabel({TargetPlatform? platform}) =>
    '${moduleShortcutLabel(0, platform: platform)}…$kModuleShortcutCount';

/// Binds [appKeymap] for everything under [child] that is not a terminal.
///
/// A focused terminal handles its keys before they could bubble up here, so
/// it is handed the same map through `TerminalView.shortcuts` instead.
class AppKeymapShortcuts extends StatelessWidget {
  final Widget child;

  const AppKeymapShortcuts({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      Shortcuts(shortcuts: appKeymap(terminalFocused: false), child: child);
}

/// Whether two activators fire on the same chord.
///
/// `SingleActivator` has no value equality, so a map can hold the same chord
/// twice; tests use this to prove it does not.
@visibleForTesting
bool sameChord(SingleActivator a, SingleActivator b) =>
    a.trigger == b.trigger &&
    a.control == b.control &&
    a.shift == b.shift &&
    a.alt == b.alt &&
    a.meta == b.meta;
