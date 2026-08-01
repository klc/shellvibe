import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:terly2/features/vault/presentation/dialogs/vault_unlock_dialog.dart';
import 'package:terly2/features/vault/presentation/notifiers/vault_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  Widget createWidgetUnderTest(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: VaultUnlockDialog(),
      ),
    );
  }

  group('VaultUnlockDialog Widget Tests', () {
    testWidgets('Renders password field and unlock button', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(createWidgetUnderTest(container));
      await tester.pump();

      expect(find.text('Unlock Vault'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Unlock'), findsOneWidget);
    });

    testWidgets('Displays error feedback when wrong password is submitted', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Setup vault with password
      final notifier = container.read(vaultNotifierProvider.notifier);
      await notifier.setup('CorrectPassword123');
      notifier.lock();

      await tester.pumpWidget(createWidgetUnderTest(container));
      await tester.pump();

      // Enter wrong password
      await tester.enterText(find.byType(TextField), 'WrongPassword');
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Incorrect password'), findsOneWidget);
      expect(find.text('Failed attempts: 1'), findsOneWidget);
    });

    testWidgets('Displays lockout UI when max failed attempts reached', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(vaultNotifierProvider.notifier);
      await notifier.setup('CorrectPassword123');
      notifier.lock();

      // 5 failed unlock attempts
      for (int i = 0; i < 5; i++) {
        await notifier.unlock('WrongPassword');
      }

      await tester.pumpWidget(createWidgetUnderTest(container));
      await tester.pump();

      expect(find.text('Too Many Attempts'), findsOneWidget);
      expect(find.textContaining('Please wait'), findsOneWidget);

      // Unlock button should be disabled when locked out
      final filledButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(filledButton.onPressed, isNull);
    });
  });
}
