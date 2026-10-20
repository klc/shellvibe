import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/sftp/domain/models/sftp_file_item.dart';
import 'package:shellvibe/features/sftp/presentation/providers/sftp_providers.dart';
import 'package:shellvibe/features/sftp/presentation/widgets/remote_file_editor_dialog.dart';

class _FailingSaveNotifier extends SftpNotifier {
  @override
  SftpState build() => const SftpState();

  @override
  Future<String> readRemoteFileContent(String path) async => 'remote';

  @override
  Future<void> saveRemoteFileContent(String path, String content) async =>
      throw Exception('disk full');
}

void main() {
  testWidgets('a failed save keeps the editor and what was typed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sftpProvider.overrideWith(_FailingSaveNotifier.new)],
        child: ShadApp(
          home: const Scaffold(
            body: RemoteFileEditorDialog(
              fileItem: SftpFileItem(
                name: 'a.txt',
                path: '/a.txt',
                size: 6,
                permissions: '-rw-r--r--',
                isDirectory: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'typed edits');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Could not save file'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'typed edits');
  });
}
