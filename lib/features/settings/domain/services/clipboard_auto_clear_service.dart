import 'dart:async';
import 'package:flutter/services.dart';

/// Service that automatically clears sensitive copied data from clipboard after a set duration (e.g. 30 seconds).
class ClipboardAutoClearService {
  Timer? _timer;

  /// Copies [sensitiveData] to the system clipboard and schedules automatic clearing after [duration].
  Future<void> copyAndScheduleClear(
    String sensitiveData, {
    Duration duration = const Duration(seconds: 30),
    void Function()? onCleared,
  }) async {
    _timer?.cancel();
    await Clipboard.setData(ClipboardData(text: sensitiveData));
    if (duration.inSeconds > 0) {
      _timer = Timer(duration, () async {
        await Clipboard.setData(const ClipboardData(text: ''));
        if (onCleared != null) onCleared();
      });
    }
  }

  /// Cancels any active auto-clear timer.
  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }
}
