import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'notification_policy.dart';
import 'notification_presenter.dart';

/// Reads what the window looks like to the user.
///
/// A seam so tests stage a hidden, unfocused or minimised window without a
/// `window_manager` behind the channel.
abstract interface class WindowPresenceReader {
  Future<WindowPresence> read();
}

/// Asks the native window. Each call is a round trip to the platform, which is
/// why it is read when an alert is due and not tracked on every window event:
/// `window_manager` reports focus and minimise, but not hide and show.
class WindowManagerPresenceReader implements WindowPresenceReader {
  const WindowManagerPresenceReader();

  @override
  Future<WindowPresence> read() async {
    try {
      final visible = await windowManager.isVisible();
      final minimized = await windowManager.isMinimized();
      final focused = await windowManager.isFocused();
      return WindowPresence(
        visible: visible,
        focused: focused,
        minimized: minimized,
      );
    } catch (e) {
      debugPrint('[Notifications] window state unreadable: $e');
      // Unreadable means unknown, and an unknown window is one the user may
      // not be looking at.
      return const WindowPresence(
        visible: false,
        focused: false,
        minimized: false,
      );
    }
  }
}

final windowPresenceReaderProvider = Provider<WindowPresenceReader>(
  (ref) => const WindowManagerPresenceReader(),
);

final notificationPresenterProvider = Provider<NotificationPresenter>((ref) {
  final presenter = LocalNotificationsPresenter();
  ref.onDispose(presenter.dispose);
  return presenter;
});

/// Whether something went wrong while the window was out of the user's sight
/// and nobody has looked since. The tray draws its error icon from it, and
/// showing the window clears it.
final trayAttentionProvider = NotifierProvider<TrayAttention, bool>(
  TrayAttention.new,
);

class TrayAttention extends Notifier<bool> {
  @override
  bool build() => false;

  void raise() => state = true;

  void clear() => state = false;
}
