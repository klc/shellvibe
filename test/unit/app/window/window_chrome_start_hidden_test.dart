import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/window/window_chrome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> calls;

  setUp(() {
    calls = [];
    debugWindowChromeOverride = TargetPlatform.windows;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          calls.add(call.method);
          if (call.method == 'isMinimized') return false;
          return null;
        });
  });

  tearDown(() {
    debugWindowChromeOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  test(
    'a hidden start hides, and hides again once the runner has shown it',
    () async {
      await hideHostWindowAtLaunch();
      expect(calls, ['hide']);

      // The Windows and Linux runners show the window when the first frame lands.
      await keepHostWindowHiddenAtLaunch();
      expect(calls, ['hide', 'hide']);

      // Shown by the user: the hold is over, and the maximise a normal launch
      // does before showing is done now.
      await showHostWindow();
      expect(calls.skip(2).where((c) => c != 'isMinimized'), [
        'maximize',
        'show',
        'focus',
      ]);

      calls.clear();
      await keepHostWindowHiddenAtLaunch();
      expect(calls, isEmpty, reason: 'a shown window is not hidden again');

      // Only the first show owes the maximise.
      await showHostWindow();
      expect(calls, isNot(contains('maximize')));
    },
  );

  test('a normal launch is never held hidden', () async {
    await keepHostWindowHiddenAtLaunch();
    expect(calls, isEmpty);
  });
}
