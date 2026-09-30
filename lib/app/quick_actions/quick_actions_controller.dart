import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

import 'app_shortcuts.dart';

/// The platform side of the app-icon menu.
///
/// A seam, not an abstraction for its own sake: the plugin reaches its native
/// half through a process-wide platform instance, so a test that wants to see
/// what was registered needs something of its own to hand the controller.
abstract interface class QuickActionsGateway {
  /// Starts listening. [onType] gets the type of the shortcut that opened or
  /// resumed the app, including the one that *launched* it — the plugin
  /// replays that one as soon as this is called.
  Future<void> initialize(void Function(String type) onType);

  Future<void> setShortcuts(List<AppShortcut> shortcuts);
}

/// The real thing, over the `quick_actions` plugin.
class PluginQuickActionsGateway implements QuickActionsGateway {
  const PluginQuickActionsGateway([this._plugin = const QuickActions()]);

  final QuickActions _plugin;

  @override
  Future<void> initialize(void Function(String type) onType) =>
      _plugin.initialize(onType);

  @override
  Future<void> setShortcuts(List<AppShortcut> shortcuts) =>
      _plugin.setShortcutItems([
        for (final shortcut in shortcuts)
          ShortcutItem(
            type: shortcut.type,
            localizedTitle: shortcut.title,
            localizedSubtitle: shortcut.subtitle,
          ),
      ]);
}

/// Keeps the platform's shortcut list in step with what the app wants shown.
///
/// Every change of hosts, bookmarks or workspace asks for a new list, and
/// those arrive in bursts (a sync lands a dozen rows, a workspace switch
/// reloads two providers), so a request waits [debounce] for the next before
/// it crosses the platform channel, and a list equal to the one already
/// registered never crosses it at all.
class QuickActionsController {
  QuickActionsController({
    required this.gateway,
    this.debounce = const Duration(milliseconds: 600),
  });

  final QuickActionsGateway gateway;
  final Duration debounce;

  Timer? _timer;
  List<AppShortcut>? _wanted;
  List<AppShortcut>? _applied;
  bool _disposed = false;

  Future<void> initialize(void Function(QuickAction action) onAction) {
    return gateway.initialize((type) {
      final action = parseQuickActionType(type);
      if (action != null) onAction(action);
    });
  }

  /// Asks for [shortcuts] to be the registered list.
  ///
  /// [immediate] skips the wait. It is for the list that *removes* host names:
  /// a menu that keeps showing them for another half second after the vault
  /// locked is a leak, not a delay.
  void update(List<AppShortcut> shortcuts, {bool immediate = false}) {
    if (_disposed) return;
    _wanted = shortcuts;
    _timer?.cancel();
    _timer = null;
    if (listEquals(_wanted, _applied)) return;
    if (immediate || debounce <= Duration.zero) {
      unawaited(_flush());
    } else {
      _timer = Timer(debounce, () => unawaited(_flush()));
    }
  }

  Future<void> _flush() async {
    final wanted = _wanted;
    _timer = null;
    if (wanted == null || listEquals(wanted, _applied)) return;
    try {
      await gateway.setShortcuts(wanted);
      _applied = wanted;
    } on Object catch (error) {
      // A launcher that refuses shortcuts (or a build with no plugin half) is
      // no reason to disturb the app; the next change tries again.
      debugPrint('[QuickActions] could not set shortcuts: $error');
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// Holds the one shortcut press that cannot be acted on yet.
///
/// A press can arrive before the app may act on it: on a cold start the
/// plugin replays it before the first frame, and behind the vault's lock
/// screen it must not run at all. It waits here, and only the latest press
/// is kept — the user meant that one.
class QuickActionDispatcher {
  QuickActionDispatcher({required this.canRun, required this.run});

  /// Whether a press may be acted on right now.
  final bool Function() canRun;

  final FutureOr<void> Function(QuickAction action) run;

  QuickAction? _pending;

  bool get hasPending => _pending != null;

  void submit(QuickAction action) {
    _pending = action;
    flush();
  }

  /// Runs the waiting press if it may run now. Safe to call as often as the
  /// conditions it waits on might have changed.
  void flush() {
    final action = _pending;
    if (action == null || !canRun()) return;
    _pending = null;
    unawaited(
      Future.sync(() => run(action)).catchError((Object error) {
        debugPrint('[QuickActions] could not run $action: $error');
      }),
    );
  }

  void clear() => _pending = null;
}
