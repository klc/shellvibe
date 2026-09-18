import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/sync/backup_envelope.dart';
import '../../data/cloud_backup_api.dart';
import '../notifiers/cloud_backup_notifier.dart';

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

  /// The code generated for this setup, held only until the user confirms it.
  String? _pendingRecoveryCode;

  String? _setupError;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    _recoveryConfirmController.dispose();
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
            expand: true,
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
          label: 'Copy code',
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
          expand: true,
          busy: state.busy,
          onPressed: state.busy ? null : _finishSetup,
        ),
      ],
    );
  }

  void _generateRecoveryCode() {
    final passphrase = _passphraseController.text;

    if (passphrase.length < 8) {
      setState(
        () => _setupError = 'Use at least 8 characters.',
      );

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
        .configure(
          passphrase: _passphraseController.text,
          recoveryCode: code,
        );

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
              child: Text(
                switch (head) {
                  null => 'Cloud backup is on.',
                  final h when h.isEmpty => 'No backup stored yet.',
                  final h => 'Server holds revision ${h.currentRevision}.',
                },
                style: const TextStyle(fontSize: 13),
              ),
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
            label: 'Overwrite the newer backup',
            icon: LucideIcons.triangleAlert,
            expand: true,
            busy: state.busy,
            onPressed: state.busy
                ? null
                : () => ref
                      .read(cloudBackupProvider.notifier)
                      .backUpNow(force: true),
          ),
        ],
        const SizedBox(height: 12),
        ShellVibeButton(
          buttonKey: const Key('cloud_backup_now_button'),
          label: 'Back Up Now',
          icon: LucideIcons.cloudUpload,
          expand: true,
          busy: state.busy,
          onPressed: state.busy
              ? null
              : () => ref.read(cloudBackupProvider.notifier).backUpNow(),
        ),
        const SizedBox(height: 8),
        ShellVibeButton.secondary(
          buttonKey: const Key('cloud_backup_restore_button'),
          label: 'Restore From Cloud',
          icon: LucideIcons.cloudDownload,
          expand: true,
          onPressed: state.busy ? null : () => _openRestoreSheet(context),
        ),
        const Divider(height: 24),
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile.adaptive(
            key: const Key('cloud_backup_on_exit_switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Back up when the app closes'),
            subtitle: Text(
              'One upload per close, not one per change: a full snapshot on '
              'every edit would exhaust the revisions your plan keeps.',
              style: TextStyle(fontSize: 11, color: tokens.textSubtle),
            ),
            value: state.backupOnExit,
            onChanged: (value) =>
                ref.read(cloudBackupProvider.notifier).setBackupOnExit(value),
          ),
        ),
        const SizedBox(height: 8),
        ShellVibeButton.quiet(
          buttonKey: const Key('cloud_backup_forget_button'),
          label: 'Forget the passphrase on this device',
          icon: LucideIcons.eraser,
          expand: true,
          onPressed: () =>
              ref.read(cloudBackupProvider.notifier).forgetOnThisDevice(),
        ),
        const SizedBox(height: 8),
        ShellVibeButton.danger(
          buttonKey: const Key('cloud_backup_delete_button'),
          label: 'Delete the cloud backup',
          icon: LucideIcons.trash2,
          expand: true,
          busy: state.busy,
          onPressed: state.busy ? null : () => _confirmDelete(context),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
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
                expand: true,
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
              const SizedBox(height: 8),
              ShellVibeButton.quiet(
                label: 'Keep it',
                expand: true,
                onPressed: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed ?? false) {
      await ref.read(cloudBackupProvider.notifier).deleteVault();
    }
  }

  Future<void> _openRestoreSheet(BuildContext context) async {
    final notifier = ref.read(cloudBackupProvider.notifier);
    await notifier.loadRevisions();

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _RestoreSheet(
        revisions: ref.read(cloudBackupProvider).value?.revisions ?? const [],
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
                expand: true,
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
    style: TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.error,
    ),
  );
}
