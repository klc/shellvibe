import 'app_alert.dart';

/// What the window looks like to the user right now.
class WindowPresence {
  const WindowPresence({
    required this.visible,
    required this.focused,
    required this.minimized,
  });

  final bool visible;
  final bool focused;
  final bool minimized;

  /// Whether the user can be taken to be looking at the window: on screen, not
  /// minimised, and the one being typed into. A visible window behind another
  /// one is not.
  bool get isInFront => visible && focused && !minimized;
}

/// Where the user is, as far as an alert is concerned.
class NotificationContext {
  const NotificationContext({
    required this.window,
    required this.terminalInView,
    required this.activeTabId,
    required this.vaultLocked,
  });

  final WindowPresence window;

  /// Whether the terminal screen is the one on show. A focused window on the
  /// Settings page is not a window looking at its tabs.
  final bool terminalInView;

  /// Root id of the tab the tab strip has selected.
  final String? activeTabId;

  /// Whether the vault is locked, or not known to be open. Fails closed: the
  /// text then names nothing.
  final bool vaultLocked;
}

/// A notification ready to hand to the OS.
class NotificationRequest {
  const NotificationRequest({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  /// Stable per source, so a second alert from the same place replaces the
  /// first in the notification centre instead of stacking beside it.
  final int id;
  final String title;
  final String body;

  /// Opaque to the OS; read back by [NotificationTarget.parse] on a click.
  final String payload;
}

/// Where a click on a notification goes.
sealed class NotificationTarget {
  const NotificationTarget();

  static const _tabPrefix = 'tab:';
  static const _tunnels = 'tunnels';

  static NotificationTarget? parse(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    if (payload == _tunnels) return const NotificationTunnels();
    if (payload.startsWith(_tabPrefix)) {
      final id = payload.substring(_tabPrefix.length);
      return id.isEmpty ? null : NotificationTab(id);
    }
    return null;
  }

  String get payload;
}

class NotificationTab extends NotificationTarget {
  const NotificationTab(this.tabId);

  final String tabId;

  @override
  String get payload => '${NotificationTarget._tabPrefix}$tabId';
}

class NotificationTunnels extends NotificationTarget {
  const NotificationTunnels();

  @override
  String get payload => NotificationTarget._tunnels;
}

/// Decides whether an [AppAlert] becomes a notification, and what it says.
///
/// Three things keep it from being noise:
///
/// * **Only what would be missed.** Nothing is sent while the window is in
///   front, and for an alert that belongs to a tab, nothing while that tab is
///   the one on show. A dropped session in the tab being typed into is already
///   in the user's face.
/// * **Throttling.** Every source gets one notification per [throttle]: a
///   program ringing the bell in a loop is one notification, not hundreds.
///   Bell and OSC alerts from a tab share a budget, and a drop or an exit has
///   its own, so a bell a moment earlier cannot swallow the news that the
///   session is gone.
/// * **Nothing private while locked.** The notification centre outlives the
///   window and shows on a locked screen, so while the vault is locked the text
///   carries no host, tab title or command output.
///
/// Stateful only in its throttle; the clock is injected so it is testable.
class NotificationPolicy {
  NotificationPolicy({
    this.throttle = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration throttle;
  final DateTime Function() _now;
  final Map<String, DateTime> _lastSent = {};

  /// Longest title and body that reach the OS. Program-supplied text is
  /// unbounded and some notification servers render all of it.
  static const maxTitleLength = 80;
  static const maxBodyLength = 200;

  /// The notification for [alert], or null when the user would not miss it or
  /// one from the same source went out too recently.
  NotificationRequest? evaluate(AppAlert alert, NotificationContext context) {
    if (_isSeen(alert, context)) return null;

    final key = _throttleKey(alert);
    final now = _now();
    final last = _lastSent[key];
    if (last != null && now.difference(last) < throttle) return null;
    _lastSent[key] = now;
    _prune(now);

    final (title, body) = context.vaultLocked
        ? _genericText(alert.kind)
        : _text(alert);
    return NotificationRequest(
      id: _stableId(key),
      title: _clean(title, maxTitleLength),
      body: _clean(body, maxBodyLength),
      payload: _target(alert)?.payload ?? '',
    );
  }

  bool _isSeen(AppAlert alert, NotificationContext context) {
    if (!context.window.isInFront) return false;
    final tabId = alert.tabId;
    // A forward belongs to no tab: a window in front has it in view.
    if (tabId == null) return true;
    return context.terminalInView && tabId == context.activeTabId;
  }

  String _throttleKey(AppAlert alert) {
    final source = alert.tabId ?? alert.ruleId ?? '';
    final group = switch (alert.kind) {
      AppAlertKind.terminalBell ||
      AppAlertKind.terminalNotification => 'terminal',
      AppAlertKind.sessionDropped || AppAlertKind.sessionEnded => 'session',
      AppAlertKind.tunnelFailed => 'tunnel',
    };
    return '$group:$source';
  }

  /// Keeps the throttle map from growing with every tab ever opened.
  void _prune(DateTime now) {
    if (_lastSent.length < 64) return;
    _lastSent.removeWhere((_, sent) => now.difference(sent) >= throttle);
  }

  NotificationTarget? _target(AppAlert alert) {
    final tabId = alert.tabId;
    if (tabId != null) return NotificationTab(tabId);
    if (alert.kind == AppAlertKind.tunnelFailed) {
      return const NotificationTunnels();
    }
    return null;
  }

  (String, String) _genericText(AppAlertKind kind) => switch (kind) {
    AppAlertKind.sessionDropped => ('ShellVibe', 'A session disconnected'),
    AppAlertKind.sessionEnded => ('ShellVibe', 'A session ended'),
    AppAlertKind.tunnelFailed => ('ShellVibe', 'A tunnel stopped'),
    AppAlertKind.terminalBell ||
    AppAlertKind.terminalNotification => ('ShellVibe', 'A terminal needs you'),
  };

  (String, String) _text(AppAlert alert) {
    final tab = _clean(alert.tabTitle ?? '', maxTitleLength);
    final named = tab.isEmpty ? 'A session' : tab;
    switch (alert.kind) {
      case AppAlertKind.sessionDropped:
        return ('Session disconnected', '$named lost its connection.');
      case AppAlertKind.sessionEnded:
        return ('Session ended', '$named exited.');
      case AppAlertKind.tunnelFailed:
        final subject = _clean(alert.subject ?? '', maxTitleLength);
        final error = _clean(alert.body ?? '', maxBodyLength);
        final label = subject.isEmpty ? 'A tunnel' : subject;
        return ('Tunnel stopped', error.isEmpty ? label : '$label: $error');
      case AppAlertKind.terminalBell:
        return (tab.isEmpty ? 'Terminal' : tab, 'The terminal rang the bell.');
      case AppAlertKind.terminalNotification:
        final title = _clean(alert.title ?? '', maxTitleLength);
        final body = _clean(alert.body ?? '', maxBodyLength);
        // OSC 9 has no title, so the tab stands in for it.
        return (
          title.isNotEmpty ? title : (tab.isEmpty ? 'Terminal' : tab),
          body.isNotEmpty ? body : 'Needs your attention.',
        );
    }
  }

  /// Collapses control characters and runs of whitespace, then cuts to
  /// [limit]. A program can put anything in an OSC payload, newlines and
  /// escape bytes included.
  static String _clean(String value, int limit) {
    final flat = value
        .replaceAll(RegExp(r'[\u0000-\u001f\u007f-\u009f]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return flat.length <= limit ? flat : '${flat.substring(0, limit - 1)}…';
  }

  /// FNV-1a: the same in every process, unlike [String.hashCode], and kept
  /// positive because some platforms take the id as a signed 32-bit integer.
  static int _stableId(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
