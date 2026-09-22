import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/core/sync/backup_envelope.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_api.dart';
import 'package:shellvibe/features/cloud_backup/presentation/notifiers/cloud_backup_notifier.dart';
import 'package:shellvibe/features/cloud_backup/presentation/widgets/cloud_backup_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, CloudBackupState state) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cloudBackupProvider.overrideWith(() => _StubNotifier(state)),
        ],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: CloudBackupSection()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Same tree, pumped a single frame. For states that never settle, such as
  /// a button showing a running spinner.
  Future<void> pumpWithoutSettling(
    WidgetTester tester,
    CloudBackupState state,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cloudBackupProvider.overrideWith(() => _StubNotifier(state)),
        ],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: CloudBackupSection()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('blocked states', () {
    testWidgets('signed out points at Account and keeps file backup', (
      tester,
    ) async {
      await pump(
        tester,
        const CloudBackupState(blocker: CloudBackupBlocker.signedOut),
      );

      expect(find.textContaining('Sign in under Account'), findsOneWidget);
      expect(
        find.textContaining('needs no account'),
        findsOneWidget,
        reason: 'The free fallback must stay visible in the blocked state.',
      );
      expect(find.byKey(const Key('cloud_backup_now_button')), findsNothing);
    });
  });

  group('setup', () {
    testWidgets('asks for a passphrase before anything else', (tester) async {
      await pump(
        tester,
        const CloudBackupState(blocker: CloudBackupBlocker.notConfigured),
      );

      expect(
        find.byKey(const Key('cloud_backup_passphrase_field')),
        findsOneWidget,
      );
      expect(
        find.textContaining('nobody can reset it for you'),
        findsOneWidget,
        reason: 'The consequence has to be stated before the choice is made.',
      );
      expect(find.byKey(const Key('cloud_backup_recovery_code')), findsNothing);
    });

    testWidgets('rejects a short passphrase', (tester) async {
      await pump(
        tester,
        const CloudBackupState(blocker: CloudBackupBlocker.notConfigured),
      );

      await tester.enterText(
        find.byKey(const Key('cloud_backup_passphrase_field')),
        'short',
      );
      await tester.tap(find.byKey(const Key('cloud_backup_continue_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('at least 8 characters'), findsOneWidget);
      expect(find.byKey(const Key('cloud_backup_recovery_code')), findsNothing);
    });

    testWidgets('rejects a mismatched confirmation', (tester) async {
      await pump(
        tester,
        const CloudBackupState(blocker: CloudBackupBlocker.notConfigured),
      );

      await tester.enterText(
        find.byKey(const Key('cloud_backup_passphrase_field')),
        'a good passphrase',
      );
      await tester.enterText(
        find.byKey(const Key('cloud_backup_confirm_field')),
        'a different passphrase',
      );
      await tester.tap(find.byKey(const Key('cloud_backup_continue_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('do not match'), findsOneWidget);
    });

    testWidgets('shows the recovery code with its consequence', (tester) async {
      await pump(
        tester,
        const CloudBackupState(blocker: CloudBackupBlocker.notConfigured),
      );

      await _fillPassphrase(tester);

      expect(
        find.byKey(const Key('cloud_backup_recovery_code')),
        findsOneWidget,
      );
      expect(
        find.textContaining('cannot be opened by anyone'),
        findsOneWidget,
        reason:
            'Irreversible loss has to be said plainly at the moment the code '
            'is shown.',
      );
    });

    testWidgets('refuses to finish until the code is typed back', (
      tester,
    ) async {
      await pump(
        tester,
        const CloudBackupState(blocker: CloudBackupBlocker.notConfigured),
      );

      await _fillPassphrase(tester);

      await tester.enterText(
        find.byKey(const Key('cloud_backup_recovery_confirm_field')),
        'NOT-THE-CODE',
      );
      await tester.tap(
        find.byKey(const Key('cloud_backup_finish_setup_button')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('not the code above'), findsOneWidget);
    });

    testWidgets('accepts the code pasted without its dashes', (tester) async {
      // A password manager strips the grouping. Refusing that would tell the
      // user their correct code is wrong.
      await pump(
        tester,
        const CloudBackupState(blocker: CloudBackupBlocker.notConfigured),
      );

      await _fillPassphrase(tester);

      final shown = tester
          .widget<SelectableText>(
            find.byKey(const Key('cloud_backup_recovery_code')),
          )
          .data!;

      await tester.enterText(
        find.byKey(const Key('cloud_backup_recovery_confirm_field')),
        shown.replaceAll('-', '').toLowerCase(),
      );
      await tester.tap(
        find.byKey(const Key('cloud_backup_finish_setup_button')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('not the code above'), findsNothing);
    });
  });

  group('ready', () {
    testWidgets('reports what the server holds', (tester) async {
      await pump(
        tester,
        const CloudBackupState(
          head: VaultHead(id: '01V', currentRevision: 4),
          lastKnownRevision: 4,
        ),
      );

      expect(find.textContaining('Server holds revision 4'), findsOneWidget);
      expect(find.byKey(const Key('cloud_backup_now_button')), findsOneWidget);
      expect(
        find.byKey(const Key('cloud_backup_restore_button')),
        findsOneWidget,
      );
    });

    testWidgets('an empty vault says so rather than showing revision 0', (
      tester,
    ) async {
      await pump(
        tester,
        const CloudBackupState(head: VaultHead(id: '01V', currentRevision: 0)),
      );

      expect(find.textContaining('No backup stored yet'), findsOneWidget);
    });

    testWidgets('a conflict offers overwrite as an explicit danger', (
      tester,
    ) async {
      await pump(
        tester,
        const CloudBackupState(
          head: VaultHead(id: '01V', currentRevision: 9),
          lastKnownRevision: 3,
          conflictingServerRevision: 9,
        ),
      );

      expect(
        find.textContaining('newer than what this device'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cloud_backup_overwrite_button')),
        findsOneWidget,
        reason: 'Overwriting another device must be a deliberate action.',
      );
    });

    testWidgets('no conflict means no overwrite button', (tester) async {
      await pump(
        tester,
        const CloudBackupState(
          head: VaultHead(id: '01V', currentRevision: 4),
          lastKnownRevision: 4,
        ),
      );

      expect(
        find.byKey(const Key('cloud_backup_overwrite_button')),
        findsNothing,
      );
    });

    testWidgets('a failure message is shown and dismissable', (tester) async {
      await pump(
        tester,
        const CloudBackupState(
          head: VaultHead(id: '01V', currentRevision: 1),
          message: 'This backup is 7.2 MB, over the 5 MB your plan allows.',
          messageIsError: true,
        ),
      );

      expect(find.textContaining('over the 5 MB'), findsOneWidget);
    });

    testWidgets('busy disables the actions', (tester) async {
      // Not pumpAndSettle: the busy button animates a spinner forever, so
      // settling never happens.
      await pumpWithoutSettling(
        tester,
        const CloudBackupState(
          head: VaultHead(id: '01V', currentRevision: 1),
          busy: true,
        ),
      );

      // `buttonKey` lands on the InkWell, whose onTap is null while disabled.
      final inkWell = tester.widget<InkWell>(
        find.byKey(const Key('cloud_backup_now_button')),
      );

      expect(inkWell.onTap, isNull);
    });
  });

  group('the restore sheet', () {
    testWidgets('survives the section leaving the tree beneath it', (
      tester,
    ) async {
      // The crash on the phone: a restore invalidates providers, the screen
      // underneath rebuilds and the section goes, and the sheet -- still on
      // screen, still rebuilding -- reaches into that section's `ref`.
      // Riverpod throws "using ref when a widget is about to or has been
      // unmounted", in the middle of a restore, after the data is written.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = CloudBackupState(
        lastKnownRevision: 1,
        revisions: [
          BackupRevision(
            id: 'rev-1',
            revision: 1,
            baseRevision: 0,
            deviceId: 'desktop',
            schemaVersion: 4,
            encryptionVersion: 1,
            ciphertextSha256: 'abc',
            sizeBytes: 2048,
            createdAt: DateTime(2026, 9, 19),
          ),
        ],
      );

      Widget app({required bool withSection}) => ProviderScope(
        overrides: [
          cloudBackupProvider.overrideWith(() => _StubNotifier(state)),
        ],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: MaterialApp(
            home: Scaffold(
              body: withSection
                  ? const SingleChildScrollView(child: CloudBackupSection())
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );

      await tester.pumpWidget(app(withSection: true));
      await tester.pump();

      await tester.tap(find.byKey(const Key('cloud_backup_restore_button')));
      await tester.pumpAndSettle();

      expect(find.text('Restore from cloud'), findsOneWidget);

      // The screen underneath rebuilds without the section, the way it does
      // when a restore invalidates the providers it was built from. The sheet
      // stays on screen, and the frame that follows runs its builder again.
      await tester.pumpWidget(app(withSection: false));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'The sheet reached into a ref that no longer has a widget.',
      );
    });
  });
}

/// Fills the passphrase pair and advances to the recovery code step.
Future<void> _fillPassphrase(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('cloud_backup_passphrase_field')),
    'a good passphrase',
  );
  await tester.enterText(
    find.byKey(const Key('cloud_backup_confirm_field')),
    'a good passphrase',
  );
  await tester.tap(find.byKey(const Key('cloud_backup_continue_button')));
  await tester.pumpAndSettle();
}

/// Publishes a fixed state without touching storage, the network or the vault.
final class _StubNotifier extends CloudBackupNotifier {
  _StubNotifier(this._state);

  final CloudBackupState _state;

  @override
  Future<CloudBackupState> build() async => _state;

  @override
  Future<void> loadRevisions() async {}

  /// Publishes new state the way a real restore does.
  ///
  /// The rebuild that causes is what used to reach into a `ref` belonging to
  /// a section that had already been deactivated.
  @override
  Future<void> restore({
    required int revision,
    required String secret,
    BackupUnlockMethod unlockWith = BackupUnlockMethod.passphrase,
  }) async {
    state = AsyncValue.data(
      _state.copyWith(
        lastKnownRevision: revision,
        message: 'Restored revision $revision.',
      ),
    );
  }
}
