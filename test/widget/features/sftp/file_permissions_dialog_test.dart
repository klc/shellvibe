import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
        const MaterialApp(
          home: Scaffold(
            body: FilePermissionsDialog(item: item),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Permissions: script.sh'), findsOneWidget);
      expect(find.text('Octal Permissions: 0755'), findsOneWidget);
      expect(find.text('Apply Changes'), findsOneWidget);
    });
  });
}
