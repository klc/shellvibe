import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/settings/domain/models/app_settings_model.dart';
import '../../features/settings/presentation/notifiers/settings_notifier.dart';
import '../../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../features/tunnels/presentation/providers/tunnels_providers.dart';
import 'window_chrome.dart';

/// Puts ShellVibe in the system tray (the menu bar on macOS) and, where the
/// platform would otherwise quit, turns closing the window into hiding it.
///
/// A tunnel or a session outlives the window it was opened from only if the
/// process does. On Windows and Linux the last window closing ends the
/// process, so with [AppSettingsModel.keepRunningInTray] on the close is
/// intercepted and the window hidden instead, and Quit moves to the tray menu.
/// macOS already keeps the app alive with no window (see `AppDelegate`), so
/// there the icon is only a status line and a way back to the window.
///
/// The menu reads the live tunnel and tab counts, so what is still running
/// behind a hidden window can be seen without opening it.
class DesktopTrayHost extends ConsumerStatefulWidget {
  const DesktopTrayHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DesktopTrayHost> createState() => _DesktopTrayHostState();
}

class _DesktopTrayHostState extends ConsumerState<DesktopTrayHost>
    with TrayListener, WindowListener {
  static const _showKey = 'show';
  static const _quitKey = 'quit';

  /// Whether the icon is currently up. Tracked here rather than asked of the
  /// plugin, which has no way to say.
  bool _trayShown = false;

  /// Serialises tray updates: a settings change and a count change arriving
  /// together must not interleave `setIcon` with `destroy`.
  Future<void> _pending = Future.value();

  bool get _interceptsClose => Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  bool get _enabled =>
      (ref.read(settingsProvider).value ?? const AppSettingsModel())
          .keepRunningInTray;

  void _sync() {
    _pending = _pending.then((_) => _apply()).catchError((Object e) {
      // A desktop without a tray host (a bare Linux window manager) still
      // runs the app; it just has no icon to hide behind.
      debugPrint('[DesktopTray] $e');
    });
  }

  Future<void> _apply() async {
    if (!mounted) return;
    final enabled = _enabled;
    if (_interceptsClose) await windowManager.setPreventClose(enabled);

    if (!enabled) {
      if (_trayShown) {
        await trayManager.destroy();
        _trayShown = false;
      }
      return;
    }

    if (!_trayShown) {
      if (Platform.isMacOS) {
        await trayManager.setIcon(
          'assets/brand/tray_macos.png',
          isTemplate: true,
        );
      } else {
        await trayManager.setIcon(
          Platform.isWindows
              ? 'assets/brand/tray.ico'
              : 'assets/brand/tray.png',
        );
      }
      if (!Platform.isLinux) await trayManager.setToolTip('ShellVibe');
      _trayShown = true;
    }
    await trayManager.setContextMenu(_buildMenu());
  }

  Menu _buildMenu() {
    final tunnels = ref.read(activeTunnelsStreamProvider).value?.length ?? 0;
    final tabs = ref
        .read(terminalTabsProvider)
        .tabs
        .where((tab) => tab.splitParentId == null)
        .length;
    return Menu(
      items: [
        MenuItem(key: _showKey, label: 'Show ShellVibe'),
        MenuItem.separator(),
        MenuItem(
          label: tunnels == 1 ? '1 active tunnel' : '$tunnels active tunnels',
          disabled: true,
        ),
        MenuItem(
          label: tabs == 1 ? '1 open tab' : '$tabs open tabs',
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(key: _quitKey, label: 'Quit ShellVibe'),
      ],
    );
  }

  Future<void> _quit() async {
    try {
      await trayManager.destroy();
      _trayShown = false;
      if (_interceptsClose) {
        await windowManager.setPreventClose(false);
        // The runner ends the process with its last window.
        await windowManager.destroy();
      } else {
        // macOS keeps running with no window; this is the app-level quit.
        await SystemNavigator.pop();
      }
    } catch (e) {
      debugPrint('[DesktopTray] quit failed, exiting: $e');
      exit(0);
    }
  }

  @override
  void onWindowClose() {
    // Only reached while the close is intercepted, which is only while the
    // tray is on — but the setting may have just been turned off.
    if (_enabled) {
      unawaited(windowManager.hide());
    } else {
      unawaited(_quit());
    }
  }

  @override
  void onTrayIconMouseDown() {
    // A click on a Windows tray icon means "open"; a macOS menu bar item
    // opens its menu. Linux trays show the menu themselves.
    if (Platform.isWindows) {
      unawaited(showHostWindow());
    } else {
      unawaited(trayManager.popUpContextMenu());
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _showKey:
        unawaited(showHostWindow());
      case _quitKey:
        unawaited(_quit());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      settingsProvider.select((s) => s.value?.keepRunningInTray),
      (_, _) => _sync(),
    );
    ref.listen(activeTunnelsStreamProvider, (_, _) => _sync());
    ref.listen(
      terminalTabsProvider.select(
        (s) => s.tabs.where((tab) => tab.splitParentId == null).length,
      ),
      (_, _) => _sync(),
    );
    return widget.child;
  }
}
