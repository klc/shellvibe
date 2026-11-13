import 'package:dartssh2/dartssh2.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/widgets/window_chrome_frame.dart';
import 'package:shellvibe/app/window/window_chrome.dart';
import 'package:shellvibe/core/network/ssh_session_manager.dart';
import 'package:shellvibe/features/sftp/domain/models/sftp_file_item.dart';
import 'package:shellvibe/features/sftp/presentation/providers/sftp_providers.dart';
import 'package:shellvibe/features/sftp/presentation/screens/sftp_dual_pane_screen.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xterm3/xterm.dart';

/// Serves one local row and records what is deleted.
class _FakeSftpNotifier extends SftpNotifier {
  final deleted = <String>[];

  @override
  SftpState build() => const SftpState(
    localPath: '/tmp',
    localFiles: [
      SftpFileItem(
        name: 'notes.txt',
        path: '/tmp/notes.txt',
        size: 1,
        permissions: '-rw-r--r--',
        isDirectory: false,
      ),
    ],
  );

  @override
  Future<void> deleteLocalItem(SftpFileItem item) async =>
      deleted.add(item.path);
}

const _notes = SftpFileItem(
  name: 'notes.txt',
  path: '/tmp/notes.txt',
  size: 1,
  permissions: '-rw-r--r--',
  isDirectory: false,
);

const _photos = SftpFileItem(
  name: 'photos',
  path: '/tmp/photos',
  size: 0,
  permissions: 'drwxr-xr-x',
  isDirectory: true,
);

/// Local rows to act on; records uploads, and fails deletes on demand.
class _OpsNotifier extends SftpNotifier {
  bool remoteExists = false;
  final uploaded = <String>[];

  @override
  SftpState build() =>
      const SftpState(localPath: '/tmp', localFiles: [_photos, _notes]);

  @override
  Future<bool> uploadWouldOverwrite(String localPath) async => remoteExists;

  @override
  void uploadLocalItem(String localPath) => uploaded.add(localPath);

  @override
  Future<void> deleteLocalItem(SftpFileItem item) async =>
      throw Exception('Permission denied');
}

class _FakeSftp implements SftpClient {
  bool closed = false;

  @override
  Stream<List<SftpName>> readdir(String path) => const Stream.empty();

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An SSH connection that hands out a new SFTP channel per request.
class _FakeSsh implements SSHClient {
  final channels = <_FakeSftp>[];

  @override
  bool get isClosed => false;

  @override
  Future<SftpClient> sftp() async {
    final channel = _FakeSftp();
    channels.add(channel);
    return channel;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSession implements SSHSessionManager {
  _FakeSession(this.client);

  @override
  final SSHClient client;

  @override
  bool get isConnected => true;

  @override
  Stream<SSHClient?> get clientChanges => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTabs extends TerminalTabsNotifier {
  _FakeTabs(this.tab);

  final TerminalTabSession tab;

  @override
  TerminalTabsState build() => TerminalTabsState(tabs: [tab]);
}

Widget _app(Widget home) => ShadApp(home: home);

void main() {
  group('SftpDualPaneScreen file operations', () {
    Future<_OpsNotifier> pumpOps(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      final fake = _OpsNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sftpProvider.overrideWith(() => fake)],
          child: _app(const SftpDualPaneScreen(hostLabel: 'Test Server')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      return fake;
    }

    Future<void> openMenu(WidgetTester tester, int row) async {
      await tester.tap(find.byTooltip('File actions').at(row));
      await tester.pumpAndSettle();
    }

    testWidgets('uploading over an existing remote file asks first', (
      tester,
    ) async {
      final fake = await pumpOps(tester);
      fake.remoteExists = true;

      await openMenu(tester, 1);
      await tester.tap(find.text('Upload to Remote'));
      await tester.pumpAndSettle();
      expect(find.text('Replace notes.txt?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fake.uploaded, isEmpty);

      await openMenu(tester, 1);
      await tester.tap(find.text('Upload to Remote'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sftp_overwrite_confirm')));
      await tester.pumpAndSettle();
      expect(fake.uploaded, ['/tmp/notes.txt']);
    });

    testWidgets('a new remote file uploads without asking', (tester) async {
      final fake = await pumpOps(tester);

      await openMenu(tester, 1);
      await tester.tap(find.text('Upload to Remote'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Replace'), findsNothing);
      expect(fake.uploaded, ['/tmp/notes.txt']);
    });

    testWidgets('a folder is not offered an upload', (tester) async {
      await pumpOps(tester);

      await openMenu(tester, 0);
      expect(find.text('Upload to Remote'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('a failed delete is a toast; the listing stays', (
      tester,
    ) async {
      await pumpOps(tester);

      await openMenu(tester, 1);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sftp_delete_confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Failed to delete'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('photos'), findsOneWidget);
      // Let the toast time out so no timer outlives the test.
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('only the remote pane takes dropped files', (tester) async {
      await pumpOps(tester);
      expect(find.byType(DropTarget), findsOneWidget);
    });
  });

  testWidgets('coming back to the screen keeps the open SFTP channel', (
    tester,
  ) async {
    // The "already attached" check lived in the screen's State, so a new
    // visit opened a second channel and closed the first under its transfers.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    final ssh = _FakeSsh();
    final tab = TerminalTabSession(
      id: 'tab-1',
      title: 'prod',
      sessionType: TerminalSessionType.ssh,
      terminal: Terminal(),
      isConnected: true,
    )..sshSessionManager = _FakeSession(ssh);
    final container = ProviderContainer(
      overrides: [terminalTabsProvider.overrideWith(() => _FakeTabs(tab))],
    );
    addTearDown(container.dispose);

    Future<void> show(Widget home) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _app(home)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    await show(const SftpDualPaneScreen(sessionTabId: 'tab-1'));
    expect(ssh.channels, hasLength(1));
    expect(container.read(sftpProvider).remoteClient, same(ssh.channels[0]));

    await show(const SizedBox());
    await show(const SftpDualPaneScreen(sessionTabId: 'tab-1'));

    expect(ssh.channels, hasLength(1));
    expect(ssh.channels[0].closed, isFalse);
    expect(container.read(sftpProvider).remoteHostLabel, 'prod');
  });

  group('SftpDualPaneScreen Widget Tests', () {
    testWidgets('the remote pane names its server even while disconnected', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: SftpDualPaneScreen(hostLabel: 'Test Server'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Files · Test Server'), findsOneWidget);
      expect(find.text('Local Workstation'), findsOneWidget);
      // The remote pane names the connection so the target server is never
      // ambiguous, even while it is disconnected.
      expect(find.text('Test Server (Disconnected)'), findsOneWidget);
    });

    testWidgets('renders segmented tab control on narrow screens (< 600px)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: SftpDualPaneScreen(hostLabel: 'Test Server'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(SegmentedButton<int>), findsOneWidget);
    });

    testWidgets('window chrome frame keeps the toolbar clear of the traffic '
        'lights on macOS', (WidgetTester tester) async {
      // The screen is pushed over the navigation shell, so it does not inherit
      // the shell's strip: without its own frame the toolbar's back button and
      // title start at y=0, right underneath the window controls.
      debugWindowChromeOverride = TargetPlatform.macOS;
      addTearDown(() => debugWindowChromeOverride = null);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: WindowChromeFrame(
                child: SftpDualPaneScreen(hostLabel: 'Test Server'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final strip = find.byType(DragToMoveArea);
      expect(strip, findsOneWidget);
      expect(tester.getSize(strip).height, kTrafficLightStripHeight);
      expect(tester.getTopLeft(strip).dy, 0);
      expect(
        tester.getTopLeft(find.text('Files · Test Server')).dy,
        greaterThanOrEqualTo(kTrafficLightStripHeight),
      );
    });

    testWidgets('window chrome frame carries the caption buttons on Windows', (
      WidgetTester tester,
    ) async {
      // The route is pushed over the shell, so without the frame's own strip
      // a window with its native caption hidden would have no close button.
      debugWindowChromeOverride = TargetPlatform.windows;
      addTearDown(() => debugWindowChromeOverride = null);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: WindowChromeFrame(
                child: SftpDualPaneScreen(hostLabel: 'Test Server'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final strip = find.byType(DragToMoveArea);
      expect(strip, findsOneWidget);
      expect(tester.getSize(strip).height, kCaptionStripHeight);
      expect(find.byKey(const Key('window_caption_close')), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Files · Test Server')).dy,
        greaterThanOrEqualTo(kCaptionStripHeight),
      );
    });

    testWidgets('window chrome frame leaves the phone layout alone', (
      WidgetTester tester,
    ) async {
      // A phone has no window controls to keep clear of, and the frame's panel
      // gap would inset a layout that is meant to reach the screen edge.
      debugWindowChromeOverride = TargetPlatform.macOS;
      addTearDown(() => debugWindowChromeOverride = null);
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: WindowChromeFrame(
                child: SftpDualPaneScreen(hostLabel: 'Test Server'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(DragToMoveArea), findsNothing);
      expect(find.byType(SegmentedButton<int>), findsOneWidget);
    });

    testWidgets('transfer queue sheet header fits a phone width', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(411, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: SftpDualPaneScreen(hostLabel: 'Test Server'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'screen layout');

      await tester.tap(find.byTooltip('Transfer Queue'));
      // Not pumpAndSettle: the queue's loading indicator animates forever
      // while no worker stream is attached.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('SFTP Transfer Queue'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'queue sheet header');
    });

    testWidgets('Delete asks first and only deletes once confirmed', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      final fake = _FakeSftpNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sftpProvider.overrideWith(() => fake)],
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: SftpDualPaneScreen(hostLabel: 'Test Server'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      Future<void> openConfirm() async {
        await tester.tap(find.byTooltip('File actions').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(find.text('Delete notes.txt?'), findsOneWidget);
      }

      await openConfirm();
      expect(fake.deleted, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fake.deleted, isEmpty);

      await openConfirm();
      await tester.tap(find.byKey(const Key('sftp_delete_confirm')));
      await tester.pumpAndSettle();
      expect(fake.deleted, ['/tmp/notes.txt']);
    });
  });
}
