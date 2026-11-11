import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/sftp/domain/models/transfer_item.dart';
import 'package:shellvibe/features/sftp/presentation/providers/sftp_providers.dart';
import 'package:shellvibe/features/sftp/presentation/widgets/transfer_row_actions.dart';

class _FakeSftp implements SftpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ConnectedTo extends SftpNotifier {
  _ConnectedTo(this.sessionId);

  final String sessionId;

  @override
  SftpState build() =>
      SftpState(remoteClient: _FakeSftp(), remoteSessionId: sessionId);
}

const _failed = TransferItem(
  id: 't-1',
  fileName: 'app.conf',
  sourcePath: '/local/app.conf',
  destinationPath: '/etc/app.conf',
  totalBytes: 10,
  type: TransferType.upload,
  status: TransferStatus.failed,
  sessionId: 'tab-a',
);

void main() {
  Future<void> pump(WidgetTester tester, String connectedTab) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            sftpProvider.overrideWith(() => _ConnectedTo(connectedTab)),
          ],
          child: const ShadApp(
            home: Scaffold(body: TransferRowActions(item: _failed)),
          ),
        ),
      );

  testWidgets('retry runs over the connection the transfer started on', (
    tester,
  ) async {
    await pump(tester, 'tab-a');
    expect(find.byTooltip('Retry transfer'), findsOneWidget);
  });

  testWidgets('another host being open offers no retry', (tester) async {
    // Retrying here would write the file to the other host's same path.
    await pump(tester, 'tab-b');
    expect(find.byTooltip('Retry transfer'), findsNothing);
  });
}
