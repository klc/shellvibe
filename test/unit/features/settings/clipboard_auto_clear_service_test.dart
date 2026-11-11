import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/settings/domain/services/clipboard_auto_clear_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late ClipboardAutoClearService service;
  String? mockClipboardContent;

  setUp(() {
    mockClipboardContent = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final Map? map = methodCall.arguments as Map?;
        mockClipboardContent = map?['text'] as String?;
        return null;
      } else if (methodCall.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': mockClipboardContent};
      }
      return null;
    });

    service = ClipboardAutoClearService();
  });

  tearDown(() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('ClipboardAutoClearService Unit Tests', () {
    test('copyAndScheduleClear copies data to clipboard', () async {
      await service.copyAndScheduleClear(
        'SecretPassword123',
        duration: const Duration(seconds: 30),
      );

      final dataBefore = await Clipboard.getData(Clipboard.kTextPlain);
      expect(dataBefore?.text, equals('SecretPassword123'));
    });

    test('cancelTimer keeps the clipboard past the scheduled clear', () async {
      var wasCleared = false;
      await service.copyAndScheduleClear(
        'SecretPassword123',
        duration: const Duration(milliseconds: 50),
        onCleared: () => wasCleared = true,
      );

      service.cancelTimer();
      await Future.delayed(const Duration(milliseconds: 200));

      final currentData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(currentData?.text, equals('SecretPassword123'));
      expect(wasCleared, isFalse);
    });

    test('clears clipboard when timer expires and content matches sensitiveData', () async {
      bool wasCleared = false;
      await service.copyAndScheduleClear(
        'SecretPassword123',
        duration: const Duration(milliseconds: 50),
        onCleared: () => wasCleared = true,
      );

      await Future.delayed(const Duration(milliseconds: 200));

      final currentData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(currentData?.text, equals(''));
      expect(wasCleared, isTrue);
    });

    test('does NOT clear clipboard when timer expires if user copied different data', () async {
      bool wasCleared = false;
      await service.copyAndScheduleClear(
        'SecretPassword123',
        duration: const Duration(milliseconds: 50),
        onCleared: () => wasCleared = true,
      );

      // User copies something else
      await Clipboard.setData(const ClipboardData(text: 'OtherUserContent'));

      await Future.delayed(const Duration(milliseconds: 200));

      final currentData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(currentData?.text, equals('OtherUserContent'));
      expect(wasCleared, isFalse);
    });

    test('clearNow clears a pending secret before its timer', () async {
      await service.copyAndScheduleClear('SecretPassword123');

      await service.clearNow();

      expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, '');
    });

    test('a clipboard that throws does not escape the timer', () async {
      await service.copyAndScheduleClear(
        'SecretPassword123',
        duration: const Duration(milliseconds: 10),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async {
            throw PlatformException(code: 'busy');
          });

      // An uncaught error in the timer would fail this test.
      await Future.delayed(const Duration(milliseconds: 50));
    });

    group('leaving the app', () {
      final binding = TestWidgetsFlutterBinding.instance;
      // From no state yet, any state is a legal next one.
      tearDown(binding.resetInternalState);

      test('detached clears a pending secret at once', () async {
        await service.copyAndScheduleClear('SecretPassword123');

        binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
        await Future<void>.delayed(Duration.zero);

        expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, '');
      });

      // Switching to another app to paste the secret pauses this one.
      test('paused keeps the secret for pasting elsewhere', () async {
        await service.copyAndScheduleClear('SecretPassword123');

        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await Future<void>.delayed(Duration.zero);

        expect(
          (await Clipboard.getData(Clipboard.kTextPlain))?.text,
          'SecretPassword123',
        );
      });

      test('detached leaves what the user copied since', () async {
        await service.copyAndScheduleClear('SecretPassword123');
        await Clipboard.setData(const ClipboardData(text: 'OtherUserContent'));

        binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
        await Future<void>.delayed(Duration.zero);

        expect(
          (await Clipboard.getData(Clipboard.kTextPlain))?.text,
          'OtherUserContent',
        );
      });

      test('detached leaves a copy with auto-clear turned off', () async {
        await service.copyAndScheduleClear(
          'SecretPassword123',
          duration: Duration.zero,
        );

        binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
        await Future<void>.delayed(Duration.zero);

        expect(
          (await Clipboard.getData(Clipboard.kTextPlain))?.text,
          'SecretPassword123',
        );
      });
    });

    test('Android copies through the sensitive channel', () async {
      const channel = MethodChannel('dev.shellvibe.app/clipboard');
      final calls = <MethodCall>[];
      binaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => binaryMessenger.setMockMethodCallHandler(channel, null),
      );
      debugPlatformCapabilitiesOverride = TargetPlatform.android;
      addTearDown(() => debugPlatformCapabilitiesOverride = null);

      await service.copyAndScheduleClear('SecretPassword123');

      expect(calls.single.method, 'copySensitive');
      expect(calls.single.arguments, 'SecretPassword123');
      // The plain Flutter copy was not used.
      expect(mockClipboardContent, isNull);
    });
  });
}
