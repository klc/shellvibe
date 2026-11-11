import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service that automatically clears sensitive copied data from clipboard after a set duration (e.g. 30 seconds).
class ClipboardAutoClearService {
  Timer? _timer;

  /// The secret still waiting to be cleared, if any.
  String? _pending;

  /// Copies [sensitiveData] to the system clipboard and schedules automatic clearing after [duration].
  Future<void> copyAndScheduleClear(
    String sensitiveData, {
    Duration duration = const Duration(seconds: 30),
    void Function()? onCleared,
  }) async {
    _timer?.cancel();
    await Clipboard.setData(ClipboardData(text: sensitiveData));
    if (duration > Duration.zero) {
      _pending = sensitiveData;
      _timer = Timer(duration, () async {
        if (await _clearIfStillThere(sensitiveData)) onCleared?.call();
      });
    }
  }

  /// Clears a pending secret right away, as when the vault locks: what it
  /// guards should not outlive it on the clipboard.
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
}
