import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/sync/backup_envelope.dart';
import '../../../../core/sync/backup_scope_store.dart';
import '../../../settings/presentation/notifiers/backup_scope_notifier.dart';
import '../../../settings/presentation/widgets/backup_scope_picker.dart';
import '../../data/cloud_backup_api.dart';
import '../notifiers/cloud_backup_notifier.dart';
import '../notifiers/sync_notifier.dart';

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
              CloudBackupBlocker.notEntitled => _blocked(
                tokens,
                'Cloud backup is not included in your plan. Local file backup '
                'below is always available.',
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
            Icon(LucideIcons.cloudDownload, size: 16, color: tokens.brand),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                head == null
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
        if (_unlockMethod == BackupUnlockMethod.passphrase) ...[
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
        Row(
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
      ],
    );
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
          onPressed: () => Clipboard.setData(ClipboardData(text: code)),
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

    if (passphrase.length < 8) {
      setState(() => _setupError = 'Use at least 8 characters.');

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
        if (state.recoveryCodeMissing) ...[
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
        const _AutoSyncControls(),
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
          ],
        ),
        const Divider(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ShellVibeButton.quiet(
              buttonKey: const Key('cloud_backup_forget_button'),
              label: 'Forget Passphrase',
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _RestoreSheet(
        revisions: revisions,
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

/// Picks a revision, then asks for the passphrase or the recovery code.
final class _RestoreSheet extends StatefulWidget {
  const _RestoreSheet({required this.revisions, required this.onRestore});

  final List<BackupRevision> revisions;
  final Future<void> Function(
    int revision,
    String secret,
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
                          _secretController.text,
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

/// Automatic sync: whether it runs, and what it carries.
///
/// Deliberately its own switch rather than an implication of the manual
/// backup's scope. A manual backup is something the user asks for at a moment
/// they chose; automatic sync writes to the account on its own schedule, in
/// both directions. Turning the last category off would be a strange way to
/// say "stop doing that", and leaving it on by default would be a stranger way
/// to start.
final class _AutoSyncControls extends ConsumerWidget {
  const _AutoSyncControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final enabled = ref.watch(autoSyncEnabledProvider).value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile.adaptive(
            key: const Key('auto_sync_enabled_switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Automatic sync'),
            subtitle: Text(
              'Sends changes as you make them and applies what other devices '
              'send. Separate from the manual backup above, which stays a '
              'snapshot you take yourself.',
              style: TextStyle(fontSize: 11, color: tokens.textSubtle),
            ),
            value: enabled,
            onChanged: (value) =>
                ref.read(autoSyncEnabledProvider.notifier).set(value),
          ),
        ),
        if (enabled) ...[
          const SizedBox(height: 4),
          _SyncStatus(state: ref.watch(syncProvider)),
        ],
        const SizedBox(height: 8),
        BackupScopePicker(
          target: BackupTarget.autoSync,
          title: 'What syncs automatically',
          subtitle:
              'Per device, and in both directions: a category that is off is '
              'neither sent from here nor applied here. Manual backups are '
              'not affected.',
          enabled: enabled,
        ),
      ],
    );
  }
}

/// What automatic sync is doing right now, in one line.
///
/// A switch that is on but does nothing is worse than one that is off, so
/// every state that stops sync says which one it is and what would clear it.
final class _SyncStatus extends ConsumerWidget {
  const _SyncStatus({required this.state});

  final AsyncValue<SyncState> state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);

    final (icon, colour, text) = switch (state) {
      AsyncLoading() => (LucideIcons.refreshCw, tokens.textSubtle, 'Starting…'),
      AsyncError(:final error) => (
        LucideIcons.circleAlert,
        Theme.of(context).colorScheme.error,
        'Sync could not start: $error',
      ),
      AsyncData(:final value) => _describe(context, tokens, value),
    };

    if (text.isEmpty) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: colour),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 11, color: colour)),
        ),
        if (value(state)?.isActive ?? false)
          ShellVibeIconButton(
            icon: LucideIcons.refreshCw,
            tooltip: 'Sync now',
            onPressed: () => ref.read(syncProvider.notifier).syncNow(),
          ),
      ],
    );
  }

  static SyncState? value(AsyncValue<SyncState> state) => state.value;

  (IconData, Color, String) _describe(
    BuildContext context,
    ShellVibeTokens tokens,
    SyncState value,
  ) {
    if (value.error != null) {
      return (
        LucideIcons.circleAlert,
        value.needsSnapshotRestore
            ? tokens.warning
            : Theme.of(context).colorScheme.error,
        value.error!,
      );
    }

    return switch (value.blocker) {
      SyncBlocker.disabled => (LucideIcons.info, tokens.textSubtle, ''),
      SyncBlocker.notEntitled => (
        LucideIcons.circleAlert,
        tokens.warning,
        'Sign in with a plan that includes cloud backup to sync.',
      ),
      SyncBlocker.notConfigured => (
        LucideIcons.circleAlert,
        tokens.warning,
        'Set a sync passphrase first.',
      ),
      // Every snapshot this account holds carries less than sync does.
      // Starting from one would leave a category missing that nothing later
      // fills in, so the user is asked rather than quietly given part of it.
      SyncBlocker.noCompleteGround => (
        LucideIcons.cloudUpload,
        tokens.warning,
        'No complete snapshot to start from. Take a full backup on a device '
            'that already has your data, then try again.',
      ),
      SyncBlocker.wrongPassphrase => (
        LucideIcons.circleAlert,
        tokens.warning,
        'The passphrase on this device does not open this account\'s sync '
            'snapshot. Use the one from a device that is already syncing.',
      ),
      null when value.running => (
        LucideIcons.refreshCw,
        tokens.textSubtle,
        'Syncing…',
      ),
      null => (
        LucideIcons.circleCheck,
        tokens.success,
        value.lastSyncAt == null
            ? 'Watching for changes.'
            : 'Up to date · sent ${value.lastPushed}, received '
                  '${value.lastPulled}.',
      ),
    };
  }
}
