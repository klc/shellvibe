import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/utils/platform_capabilities.dart';

/// Service that automatically clears sensitive copied data from clipboard after a set duration (e.g. 30 seconds).
class ClipboardAutoClearService {
  Timer? _timer;

  /// The secret still waiting to be cleared, if any.
  String? _pending;

  /// Made with the first pending secret, so that only code which copies needs
  /// a running binding.
  AppLifecycleListener? _lifecycle;

  /// The Android and Windows runners copy with the platform's "sensitive"
  /// marks: Android 13+ keeps the clip out of the copy preview, Windows keeps
  /// it out of clipboard history and cloud sync.
  static const _sensitiveChannel = MethodChannel('dev.shellvibe.app/clipboard');

  /// Copies [sensitiveData] to the system clipboard and schedules automatic clearing after [duration].
  Future<void> copyAndScheduleClear(
    String sensitiveData, {
    Duration duration = const Duration(seconds: 30),
    void Function()? onCleared,
  }) async {
    _timer?.cancel();
    await _copySensitive(sensitiveData);
    if (duration > Duration.zero) {
      _pending = sensitiveData;
      _lifecycle ??= AppLifecycleListener(onStateChange: _onLifecycleChanged);
      _timer = Timer(duration, () async {
        if (await _clearIfStillThere(sensitiveData)) onCleared?.call();
      });
    }
  }

  Future<void> _copySensitive(String text) async {
    final platform = runtimeTargetPlatform;
    if (!kIsWeb &&
        (platform == TargetPlatform.android ||
            platform == TargetPlatform.windows)) {
      try {
        await _sensitiveChannel.invokeMethod<void>('copySensitive', text);
        return;
      } catch (e) {
        debugPrint('Sensitive clipboard copy failed, copying plainly: $e');
      }
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// The timer does not outlive the process, so a pending secret is cleared
  /// on the way out. Not on `paused`: switching to another app to paste the
  /// secret pauses this one.
  void _onLifecycleChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) unawaited(clearNow());
  }

  /// Clears a pending secret right away, as when the vault locks or the app
  /// quits: what it guards should not outlive it on the clipboard.
  Future<void> clearNow() async {
    final pending = _pending;
    cancelTimer();
    if (pending != null) await _clearIfStillThere(pending);
  }

  /// Whether [sensitiveData] was still on the clipboard and is now gone.
  /// Never throws: it runs from a timer, where an error has no caller.
  Future<bool> _clearIfStillThere(String sensitiveData) async {
    if (_pending == sensitiveData) _pending = null;
    try {
      final currentData = await Clipboard.getData(Clipboard.kTextPlain);
      if (currentData?.text != sensitiveData) return false;
      await Clipboard.setData(const ClipboardData(text: ''));
      return true;
    } catch (e) {
      debugPrint('Clipboard auto-clear failed: $e');
      return false;
    }
  }

  /// Cancels any active auto-clear timer.
  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  void dispose() {
    cancelTimer();
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}
