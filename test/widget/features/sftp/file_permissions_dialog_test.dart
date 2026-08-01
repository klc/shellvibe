import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:terly2/features/sftp/domain/models/sftp_file_item.dart';
import 'package:terly2/features/sftp/presentation/widgets/file_permissions_dialog.dart';

void main() {
  group('FilePermissionsDialog Widget Tests', () {
    testWidgets('renders checkboxes for user, group, others and displays octal mode', (WidgetTester tester) async {
      const item = SftpFileItem(
        name: 'script.sh',
        path: '/script.sh',
        size: 120,
        permissions: '-rwxr-xr-x',
        isDirectory: false,
        ownerId: 1000,
        groupId: 1000,
      );

      await tester.pumpWidget(
        ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: const MaterialApp(
            home: Scaffold(
              body: FilePermissionsDialog(item: item),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Permissions: script.sh'), findsOneWidget);
      expect(find.text('Octal Permissions: 0755'), findsOneWidget);
      expect(find.text('Apply Changes'), findsOneWidget);
    });

    testWidgets('correctly parses permissions with s and t setuid/setgid/sticky bits', (WidgetTester tester) async {
      const item = SftpFileItem(
        name: 'suid_script.sh',
        path: '/suid_script.sh',
        size: 256,
        permissions: '-rwsr-sr-t',
        isDirectory: false,
        ownerId: 0,
        groupId: 0,
      );

      await tester.pumpWidget(
        ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: const MaterialApp(
            home: Scaffold(
              body: FilePermissionsDialog(item: item),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Permissions: suid_script.sh'), findsOneWidget);
      expect(find.text('Octal Permissions: 0755'), findsOneWidget);
    });
  });
}

