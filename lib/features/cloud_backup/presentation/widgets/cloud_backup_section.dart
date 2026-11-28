import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/sync/backup_envelope.dart';
import '../../../../core/sync/backup_scope_store.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../settings/presentation/copy_secret_with_auto_clear.dart';
import '../../../settings/presentation/widgets/backup_scope_picker.dart';
import '../../data/cloud_backup_api.dart';
import '../../domain/backup_frequency.dart';
import '../notifiers/cloud_backup_notifier.dart';
import 'device_handoff_screen.dart';

/// Where the account's encryption is reset. Behind the panel's own
/// re-confirmation -- password or a linked Google or GitHub sign-in -- which
/// the app cannot ask for itself on an account that has no password.
const String kResetEncryptionUrl =
    'https://shellvibe.dev/panel/danger#reset-encryption';

/// Cloud backup surface in Settings → Sync.
///
/// Sits above the existing local file export/import, which keeps working with
/// no account: the encrypted file on disk is the fallback for everyone who does
/// not pay, and for anyone who would rather hold their own copy.
final class CloudBackupSection extends ConsumerStatefulWidget {
  const CloudBackupSection({super.key});

  @override
  ConsumerState<CloudBackupSection> createState() => _CloudBackupSectionState();
}

class _CloudBackupSectionState extends ConsumerState<CloudBackupSection> {
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();
  final _recoveryConfirmController = TextEditingController();
  final _unlockSecretController = TextEditingController();
  final _unlockRecoveryController = TextEditingController();
  final _adoptRecoveryController = TextEditingController();

  /// Which secret the unlock form is asking for.
  BackupUnlockMethod _unlockMethod = BackupUnlockMethod.passphrase;

  /// A recovery code made for an account that has none, until it is saved.
  String? _newRecoveryCode;

  /// Set once the reset page has been opened, so there is a way back to
  /// asking the server what the account holds now.
  bool _sentToReset = false;

  /// The code generated for this setup, held only until the user confirms it.
  String? _pendingRecoveryCode;

  String? _setupError;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    _recoveryConfirmController.dispose();
    _unlockSecretController.dispose();
    _unlockRecoveryController.dispose();
    _adoptRecoveryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final backup = ref.watch(cloudBackupProvider);

    return backup.when(
      loading: () => const ShadCard(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
      ),
      error: (error, _) => ShadCard(child: _Error('$error')),
      data: (state) => ShadCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Encrypted on this device before it leaves it. The server stores '
              'ciphertext and cannot read your hosts, keys or passwords.',
              style: TextStyle(fontSize: 13, color: tokens.textMuted),
            ),
            const SizedBox(height: 12),
            switch (state.blocker) {
              CloudBackupBlocker.signedOut => _blocked(
                tokens,
                'Sign in under Account to use cloud backup. Local file backup '
                'below needs no account.',
              ),
              CloudBackupBlocker.needsExistingPassphrase => _buildUnlock(
                tokens,
                state,
              ),
              CloudBackupBlocker.notConfigured => _buildSetup(tokens, state),
              null => _buildReady(tokens, state),
            },
            if (state.message != null) ...[
              const SizedBox(height: 12),
              _Message(
                text: state.message!,
                isError: state.messageIsError,
                onDismiss: ref.read(cloudBackupProvider.notifier).clearMessage,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _blocked(ShellVibeTokens tokens, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(LucideIcons.lock, size: 16, color: tokens.textMuted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(fontSize: 13, color: tokens.textMuted),
        ),
      ),
    ],
  );

  // --- Unlock an existing backup -------------------------------------------

  /// Shown on a device joining an account that already has a backup.
  ///
  /// The passphrase is not invented here. It already exists, it lives only in
  /// the user's head and on the device that set it, and asking this device to
  /// make up a new one is what produced a backup the first device could not
  /// open.
  Widget _buildUnlock(ShellVibeTokens tokens, CloudBackupState state) {
    final head = state.head;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.cloudDownload, size: 16, color: tokens.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.accountHasKey
                    ? 'This account is already set up on another device. Add '
                          'this one from it with a code, or enter your sync '
                          'passphrase or recovery code.'
                    : head == null
                    ? 'This account already has a backup.'
                    : 'This account already has a backup '
                          '(revision ${head.currentRevision}). Enter the sync '
                          'passphrase you set on your other device to unlock '
                          'it here.',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        if (state.accountHasKey) ...[
          const SizedBox(height: 12),
          ShellVibeButton(
            buttonKey: const Key('cloud_backup_handoff_receive_button'),
            label: isMobilePlatform
                ? 'Scan a Code From Another Device'
                : 'Show a Code for Another Device',
            icon: isMobilePlatform ? LucideIcons.scanLine : LucideIcons.qrCode,
            onPressed: () => _openHandoff(context, gives: false),
          ),
        ],
        const SizedBox(height: 12),
        ShadInput(
          key: const Key('cloud_backup_unlock_secret_field'),
          controller: _unlockSecretController,
          obscureText: _unlockMethod == BackupUnlockMethod.passphrase,
          placeholder: Text(
            _unlockMethod == BackupUnlockMethod.passphrase
                ? 'Sync passphrase'
                : 'Recovery code',
          ),
        ),
        // An account with a key carries its recovery slot in the key record,
        // so there is nothing for this device to be told.
        if (_unlockMethod == BackupUnlockMethod.passphrase &&
            !state.accountHasKey) ...[
          const SizedBox(height: 8),
          ShadInput(
            key: const Key('cloud_backup_unlock_recovery_field'),
            controller: _unlockRecoveryController,
            placeholder: const Text('Recovery code (optional)'),
          ),
          const SizedBox(height: 4),
          Text(
            'Without it, backups written from this device cannot be opened '
            'with your recovery code. You can add it later.',
            style: TextStyle(fontSize: 11, color: tokens.textSubtle),
          ),
        ],
        if (_setupError != null) ...[
          const SizedBox(height: 8),
          _Error(_setupError!),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ShellVibeButton(
              buttonKey: const Key('cloud_backup_unlock_button'),
              label: 'Unlock',
              icon: LucideIcons.lockKeyholeOpen,
              busy: state.busy,
              onPressed: state.busy ? null : _unlockExisting,
            ),
            const SizedBox(width: 8),
            ShellVibeButton.quiet(
              buttonKey: const Key('cloud_backup_unlock_toggle_button'),
              label: _unlockMethod == BackupUnlockMethod.passphrase
                  ? 'Use the recovery code'
                  : 'Use the passphrase',
              onPressed: () => setState(() {
                _unlockMethod = _unlockMethod == BackupUnlockMethod.passphrase
                    ? BackupUnlockMethod.recoveryCode
                    : BackupUnlockMethod.passphrase;
                _unlockSecretController.clear();
                _setupError = null;
              }),
            ),
          ],
        ),
        const Divider(height: 24),
        Text(
          'Lost the passphrase, the recovery code and every device that was '
          'set up? Reset the account\'s encryption in the web panel and start '
          'again. The cloud copies go; what is on your devices stays.',
          style: TextStyle(fontSize: 11, color: tokens.textSubtle),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ShellVibeButton.quiet(
              buttonKey: const Key('cloud_backup_reset_link'),
              label: 'Reset in the Web Panel',
              icon: LucideIcons.externalLink,
              onPressed: _openResetPage,
            ),
            if (_sentToReset)
              ShellVibeButton.secondary(
                buttonKey: const Key('cloud_backup_check_after_reset_button'),
                label: 'I Reset It, Check Again',
                icon: LucideIcons.refreshCw,
                onPressed: () async {
                  setState(() => _sentToReset = false);
                  await ref
                      .read(cloudBackupProvider.notifier)
                      .checkAfterReset();
                },
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _openResetPage() async {
    final opened = await launchUrl(
      Uri.parse(kResetEncryptionUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;

    setState(() {
      _sentToReset = true;
      if (!opened) _setupError = 'Open $kResetEncryptionUrl in a browser.';
    });
  }

  Future<void> _unlockExisting() async {
    final secret = _unlockSecretController.text;

    if (secret.isEmpty) {
      setState(() => _setupError = 'Enter your passphrase.');

      return;
    }

    setState(() => _setupError = null);

    final recovery = _unlockRecoveryController.text.trim();

    await ref
        .read(cloudBackupProvider.notifier)
        .unlockExisting(
          secret: secret,
          method: _unlockMethod,
          recoveryCode: recovery.isEmpty ? null : recovery,
        );

    if (!mounted) return;

    _unlockSecretController.clear();
    _unlockRecoveryController.clear();
  }

  // --- Setup --------------------------------------------------------------

  Widget _buildSetup(ShellVibeTokens tokens, CloudBackupState state) {
    final code = _pendingRecoveryCode;

    if (code == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose a sync passphrase. It is not your account password and not '
            'your vault master password: the server never sees it, so nobody '
            'can reset it for you.',
            style: TextStyle(fontSize: 12, color: tokens.textMuted),
          ),
          const SizedBox(height: 12),
          ShadInput(
            key: const Key('cloud_backup_passphrase_field'),
            controller: _passphraseController,
            obscureText: true,
            placeholder: const Text('Sync passphrase'),
          ),
          const SizedBox(height: 8),
          ShadInput(
            key: const Key('cloud_backup_confirm_field'),
            controller: _confirmController,
            obscureText: true,
            placeholder: const Text('Repeat the passphrase'),
          ),
          if (_setupError != null) ...[
            const SizedBox(height: 8),
            _Error(_setupError!),
          ],
          const SizedBox(height: 12),
          ShellVibeButton(
            buttonKey: const Key('cloud_backup_continue_button'),
            label: 'Continue',
            icon: LucideIcons.arrowRight,
            onPressed: _generateRecoveryCode,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.keyRound, size: 16, color: tokens.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Write this recovery code down now. It opens your backup if '
                'you forget the passphrase, it is shown once, and it is stored '
                'nowhere. Lose both and the backup cannot be opened by anyone, '
                'including us.',
                style: TextStyle(fontSize: 12, color: tokens.warning),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.surfaceLow,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
          ),
          child: SelectableText(
            code,
            key: const Key('cloud_backup_recovery_code'),
            style: const TextStyle(
              fontFamily: 'JetBrainsMono Nerd Font Mono',
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ShellVibeButton.quiet(
          buttonKey: const Key('cloud_backup_copy_code_button'),
          label: 'Copy Code',
          icon: LucideIcons.copy,
          onPressed: () => copySecretWithAutoClear(
            ref,
            context,
            code,
            toast: 'Recovery code copied',
          ),
        ),
        const SizedBox(height: 12),
        ShadInput(
          key: const Key('cloud_backup_recovery_confirm_field'),
          controller: _recoveryConfirmController,
          placeholder: const Text('Type the recovery code back'),
        ),
        if (_setupError != null) ...[
          const SizedBox(height: 8),
          _Error(_setupError!),
        ],
        const SizedBox(height: 12),
        ShellVibeButton(
          buttonKey: const Key('cloud_backup_finish_setup_button'),
          label: 'Turn On Cloud Backup',
          icon: LucideIcons.cloudUpload,
          busy: state.busy,
          onPressed: state.busy ? null : _finishSetup,
        ),
      ],
    );
  }

  void _generateRecoveryCode() {
    final passphrase = _passphraseController.text;

    // Only at setup. The passphrase is all that stands between the server's
    // copy and an offline guess, so it is held to more than a login password
    // -- but one already in use keeps working.
    if (passphrase.length < 12) {
      setState(() => _setupError = 'Use at least 12 characters.');

      return;
    }

    if (passphrase != _confirmController.text) {
      setState(() => _setupError = 'The two passphrases do not match.');

      return;
    }

    setState(() {
      _setupError = null;
      _pendingRecoveryCode = BackupEnvelope().generateRecoveryCode();
    });
  }

  Future<void> _finishSetup() async {
    final code = _pendingRecoveryCode;
    if (code == null) return;

    // Typing it back is the only evidence the code left the screen. Grouping
    // and case are normalised, so a paste without dashes still matches.
    if (BackupEnvelope.normalizeRecoveryCode(_recoveryConfirmController.text) !=
        BackupEnvelope.normalizeRecoveryCode(code)) {
      setState(
        () => _setupError = 'That is not the code above. Check it and retype.',
      );

      return;
    }

    setState(() => _setupError = null);

    await ref
        .read(cloudBackupProvider.notifier)
        .configure(passphrase: _passphraseController.text, recoveryCode: code);

    if (!mounted) return;

    setState(() {
      _pendingRecoveryCode = null;
      _passphraseController.clear();
      _confirmController.clear();
      _recoveryConfirmController.clear();
    });
  }

  // --- Ready --------------------------------------------------------------

  Widget _buildReady(ShellVibeTokens tokens, CloudBackupState state) {
    final head = state.head;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.cloudCheck, size: 16, color: tokens.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(switch (head) {
                null => 'Cloud backup is on.',
                final h when h.isEmpty => 'No backup stored yet.',
                final h => 'Server holds revision ${h.currentRevision}.',
              }, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        if (state.lastKnownRevision != null) ...[
          const SizedBox(height: 4),
          Text(
            'This device last wrote revision ${state.lastKnownRevision}.',
            style: TextStyle(fontSize: 11, color: tokens.textSubtle),
          ),
        ],
        if (state.recoveryCodeMissing && state.usesAccountKey)
          ..._buildCreateRecoveryCode(tokens, state)
        else if (state.recoveryCodeMissing) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.keyRound, size: 16, color: tokens.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This device does not know your recovery code, so backups '
                  'written here can only be opened with the passphrase. Add '
                  'it to close that gap.',
                  style: TextStyle(fontSize: 12, color: tokens.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ShadInput(
            key: const Key('cloud_backup_adopt_recovery_field'),
            controller: _adoptRecoveryController,
            placeholder: const Text('Recovery code'),
          ),
          const SizedBox(height: 8),
          ShellVibeButton.secondary(
            buttonKey: const Key('cloud_backup_adopt_recovery_button'),
            label: 'Save Recovery Code',
            icon: LucideIcons.keyRound,
            busy: state.busy,
            onPressed: state.busy
                ? null
                : () async {
                    final code = _adoptRecoveryController.text.trim();
                    if (code.isEmpty) return;

                    await ref
                        .read(cloudBackupProvider.notifier)
                        .adoptRecoveryCode(code);

                    if (mounted) _adoptRecoveryController.clear();
                  },
          ),
        ],
        if (state.conflictingServerRevision != null) ...[
          const SizedBox(height: 12),
          Text(
            'Revision ${state.conflictingServerRevision} on the server is '
            'newer than what this device based its backup on.',
            style: TextStyle(fontSize: 12, color: tokens.warning),
          ),
          const SizedBox(height: 8),
          ShellVibeButton.danger(
            buttonKey: const Key('cloud_backup_overwrite_button'),
            label: 'Overwrite Newer Backup',
            icon: LucideIcons.triangleAlert,
            busy: state.busy,
            onPressed: state.busy
                ? null
                : () => ref
                      .read(cloudBackupProvider.notifier)
                      .backUpNow(force: true),
          ),
        ],
        const Divider(height: 24),
        BackupScopePicker(
          target: BackupTarget.cloud,
          title: 'What a manual backup uploads',
          lastFullBackupAt: state.lastFullBackupAt,
        ),
        const Divider(height: 24),
        const SizedBox(height: 12),
        // A Wrap rather than a stack: these buttons size to their labels, and
        // a column of them left-aligned reads as ragged rather than as a set
        // of actions. Side by side their edges line up, and on a narrow phone
        // they wrap instead of being squeezed.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ShellVibeButton(
              buttonKey: const Key('cloud_backup_now_button'),
              label: 'Back Up Now',
              icon: LucideIcons.cloudUpload,
              busy: state.busy,
              onPressed: state.busy
                  ? null
                  : () => ref.read(cloudBackupProvider.notifier).backUpNow(),
            ),
            ShellVibeButton.secondary(
              buttonKey: const Key('cloud_backup_restore_button'),
              label: 'Restore From Cloud',
              icon: LucideIcons.cloudDownload,
              onPressed: state.busy ? null : () => _openRestoreSheet(context),
            ),
            if (state.usesAccountKey)
              ShellVibeButton.secondary(
                buttonKey: const Key('cloud_backup_handoff_give_button'),
                label: 'Add Another Device',
                icon: LucideIcons.qrCode,
                onPressed: () => _openHandoff(context, gives: true),
              ),
          ],
        ),
        const Divider(height: 24),
        _FrequencyPicker(state: state),
        const Divider(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ShellVibeButton.quiet(
              buttonKey: const Key('cloud_backup_forget_button'),
              label: state.usesAccountKey
                  ? 'Remove From This Device'
                  : 'Forget Passphrase',
              icon: LucideIcons.eraser,
              onPressed: () =>
                  ref.read(cloudBackupProvider.notifier).forgetOnThisDevice(),
            ),
            ShellVibeButton.danger(
              buttonKey: const Key('cloud_backup_delete_button'),
              label: 'Delete Cloud Backup',
              icon: LucideIcons.trash2,
              busy: state.busy,
              onPressed: state.busy ? null : () => _confirmDelete(context),
            ),
          ],
        ),
      ],
    );
  }

  /// A device that holds the account key gives the account a recovery code
  /// by making one: shown once, typed back, and from then on a second way to
  /// reach the key.
  List<Widget> _buildCreateRecoveryCode(
    ShellVibeTokens tokens,
    CloudBackupState state,
  ) {
    final code = _newRecoveryCode;

    return [
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.keyRound, size: 16, color: tokens.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              code == null
                  ? 'This account has no recovery code. Without one, a '
                        'forgotten passphrase and no device left means the '
                        'backup cannot be opened by anyone.'
                  : 'Write this recovery code down now. It is shown once and '
                        'stored nowhere.',
              style: TextStyle(fontSize: 12, color: tokens.warning),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (code == null)
        ShellVibeButton.secondary(
          buttonKey: const Key('cloud_backup_new_recovery_button'),
          label: 'Create Recovery Code',
          icon: LucideIcons.keyRound,
          onPressed: () => setState(
            () => _newRecoveryCode = BackupEnvelope().generateRecoveryCode(),
          ),
        )
      else ...[
        SelectableText(
          code,
          key: const Key('cloud_backup_new_recovery_code'),
          style: const TextStyle(
            fontFamily: 'JetBrainsMono Nerd Font Mono',
            fontSize: 13,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        ShadInput(
          key: const Key('cloud_backup_new_recovery_confirm_field'),
          controller: _adoptRecoveryController,
          placeholder: const Text('Type the recovery code back'),
        ),
        const SizedBox(height: 8),
        ShellVibeButton.secondary(
          buttonKey: const Key('cloud_backup_save_new_recovery_button'),
          label: 'Save Recovery Code',
          icon: LucideIcons.keyRound,
          busy: state.busy,
          onPressed: state.busy
              ? null
              : () async {
                  // Typing it back is the only evidence the code left the
                  // screen.
                  if (BackupEnvelope.normalizeRecoveryCode(
                        _adoptRecoveryController.text,
                      ) !=
                      BackupEnvelope.normalizeRecoveryCode(code)) {
                    return;
                  }

                  final saved = await ref
                      .read(cloudBackupProvider.notifier)
                      .createRecoveryCode(code);
                  if (!mounted || !saved) return;

                  setState(() => _newRecoveryCode = null);
                  _adoptRecoveryController.clear();
                },
        ),
      ],
    ];
  }

  Future<void> _openHandoff(BuildContext context, {required bool gives}) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => DeviceHandoffScreen(gives: gives),
        ),
      );

  Future<void> _confirmDelete(BuildContext context) async {
    // Resolved before the sheet opens, for the same reason the restore sheet
    // captures its data: this widget can be gone by the time the sheet
    // closes, and `ref` is unsafe once it is.
    final notifier = ref.read(cloudBackupProvider.notifier);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Delete every revision on the server?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'This cannot be undone. Local data on this device is not '
                'touched, and the local file backup below is unaffected.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              ShellVibeButton.danger(
                buttonKey: const Key('cloud_backup_delete_confirm_button'),
                label: 'Delete Everything',
                icon: LucideIcons.trash2,
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
              const SizedBox(height: 8),
              ShellVibeButton.quiet(
                label: 'Keep It',
                onPressed: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed ?? false) {
      await notifier.deleteVault();
    }
  }

  Future<void> _openRestoreSheet(BuildContext context) async {
    // Everything the sheet needs is read here and captured, so its builder
    // closes over plain values. A `ref` read inside that builder runs again
    // on every rebuild of the sheet -- including the rebuilds the restore
    // itself causes -- by which point this section can already be
    // deactivated. Riverpod then throws "using ref when a widget is about to
    // or has been unmounted", on a phone, in the middle of a restore.
    final notifier = ref.read(cloudBackupProvider.notifier);
    await notifier.loadRevisions();

    if (!context.mounted) return;

    final revisions =
        ref.read(cloudBackupProvider).value?.revisions ??
        const <BackupRevision>[];
    final usesAccountKey =
        ref.read(cloudBackupProvider).value?.usesAccountKey ?? false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _RestoreSheet(
        revisions: revisions,
        usesAccountKey: usesAccountKey,
        onRestore: (revision, secret, method) async {
          await notifier.restore(
            revision: revision,
            secret: secret,
            unlockWith: method,
          );
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        },
      ),
    );
  }
}

/// Picks a revision, then asks for the passphrase or the recovery code --
/// unless this device holds the account key and the revision was sealed with
/// it, in which case there is nothing to ask.
final class _RestoreSheet extends StatefulWidget {
  const _RestoreSheet({
    required this.revisions,
    required this.onRestore,
    this.usesAccountKey = false,
  });

  final List<BackupRevision> revisions;
  final bool usesAccountKey;
  final Future<void> Function(
    int revision,
    String? secret,
    BackupUnlockMethod method,
  )
  onRestore;

  @override
  State<_RestoreSheet> createState() => _RestoreSheetState();
}

class _RestoreSheetState extends State<_RestoreSheet> {
  final _secretController = TextEditingController();

  int? _selected;
  BackupUnlockMethod _method = BackupUnlockMethod.passphrase;
  bool _busy = false;

  @override
  void dispose() {
    _secretController.dispose();
    super.dispose();
  }

  /// Whether the selected revision needs a secret typed. One sealed before
  /// the account key existed always does.
  bool get _asksForSecret {
    if (!widget.usesAccountKey) return true;

    final selected = widget.revisions
        .where((r) => r.revision == _selected)
        .firstOrNull;

    return selected != null &&
        !BackupEnvelope.opensWithAccountKey(selected.schemaVersion);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Restore from cloud',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Restoring merges the backup over what is on this device.',
              style: TextStyle(fontSize: 12, color: tokens.textMuted),
            ),
            const SizedBox(height: 12),
            if (widget.revisions.isEmpty)
              Text(
                'The server holds no revisions yet.',
                style: TextStyle(color: tokens.textMuted),
              )
            else ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: RadioGroup<int>(
                    groupValue: _selected,
                    onChanged: (value) => setState(() => _selected = value),
                    child: Column(
                      children: [
                        for (final revision in widget.revisions)
                          Material(
                            type: MaterialType.transparency,
                            child: RadioListTile<int>(
                              key: Key('restore_revision_${revision.revision}'),
                              contentPadding: EdgeInsets.zero,
                              value: revision.revision,
                              title: Text('Revision ${revision.revision}'),
                              subtitle: Text(
                                '${_size(revision.sizeBytes)} · envelope v'
                                '${revision.schemaVersion}'
                                '${revision.createdAt == null ? '' : ' · ${_date(revision.createdAt!)}'}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: tokens.textSubtle,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_asksForSecret) ...[
                ShadInput(
                  key: const Key('restore_secret_field'),
                  controller: _secretController,
                  obscureText: _method == BackupUnlockMethod.passphrase,
                  placeholder: Text(
                    _method == BackupUnlockMethod.passphrase
                        ? 'Sync passphrase'
                        : 'Recovery code',
                  ),
                ),
                const SizedBox(height: 8),
                ShellVibeButton.quiet(
                  buttonKey: const Key('restore_toggle_method_button'),
                  label: _method == BackupUnlockMethod.passphrase
                      ? 'Use the recovery code instead'
                      : 'Use the passphrase instead',
                  onPressed: () => setState(() {
                    _method = _method == BackupUnlockMethod.passphrase
                        ? BackupUnlockMethod.recoveryCode
                        : BackupUnlockMethod.passphrase;
                    _secretController.clear();
                  }),
                ),
                const SizedBox(height: 12),
              ],
              ShellVibeButton(
                buttonKey: const Key('restore_confirm_button'),
                label: 'Restore',
                icon: LucideIcons.cloudDownload,
                busy: _busy,
                onPressed: (_selected == null || _busy)
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        await widget.onRestore(
                          _selected!,
                          _asksForSecret ? _secretController.text : null,
                          _method,
                        );
                        if (mounted) setState(() => _busy = false);
                      },
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _date(DateTime value) {
    final local = value.toLocal();

    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

final class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.isError,
    required this.onDismiss,
  });

  final String text;
  final bool isError;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final color = isError
        ? Theme.of(context).colorScheme.error
        : tokens.success;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isError ? LucideIcons.circleAlert : LucideIcons.circleCheck,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: color)),
        ),
        ShellVibeIconButton(
          icon: LucideIcons.x,
          tooltip: 'Dismiss',
          onPressed: onDismiss,
        ),
      ],
    );
  }
}

final class _Error extends StatelessWidget {
  const _Error(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
  );
}

/// How often a backup runs without being asked.
///
/// The promise under each option is not decoration. There is no background
/// task on any platform here, so "daily" means "once a day, the first time you
/// open the app" -- and a schedule that quietly does not happen on a device
/// nobody opened is worse than one that says so.
final class _FrequencyPicker extends ConsumerWidget {
  const _FrequencyPicker({required this.state});

  final CloudBackupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Automatic backup',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: tokens.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          state.frequency.promise,
          style: TextStyle(fontSize: 11, color: tokens.textSubtle),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final frequency in BackupFrequency.values)
              if (frequency == state.frequency)
                ShellVibeButton(
                  buttonKey: Key('backup_frequency_${frequency.wireName}'),
                  label: frequency.label,
                  icon: LucideIcons.check,
                  onPressed: null,
                )
              else
                ShellVibeButton.quiet(
                  buttonKey: Key('backup_frequency_${frequency.wireName}'),
                  label: frequency.label,
                  onPressed: state.busy
                      ? null
                      : () => ref
                            .read(cloudBackupProvider.notifier)
                            .setFrequency(frequency),
                ),
          ],
        ),
        if (state.lastAutoBackupAt != null) ...[
          const SizedBox(height: 8),
          Text(
            'Last automatic backup ${_ago(state.lastAutoBackupAt!)}.',
            style: TextStyle(fontSize: 11, color: tokens.textSubtle),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'A scheduled backup is skipped when nothing has changed, and never '
          'overwrites a newer backup from another device.',
          style: TextStyle(fontSize: 11, color: tokens.textSubtle),
        ),
      ],
    );
  }

  static String _ago(DateTime at) {
    final elapsed = DateTime.now().difference(at);

    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
    if (elapsed.inDays < 1) return '${elapsed.inHours} h ago';

    return '${elapsed.inDays} d ago';
  }
}
