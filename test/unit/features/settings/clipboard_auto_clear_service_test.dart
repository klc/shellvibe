import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/settings/domain/services/clipboard_auto_clear_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    service.cancelTimer();
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

    test('cancelTimer cancels active clear timer', () async {
      await service.copyAndScheduleClear(
        'SecretPassword123',
        duration: const Duration(seconds: 30),
      );

      service.cancelTimer();
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
  });
}
