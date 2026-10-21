import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/restored_data.dart';
import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/sync/backup_scope.dart';
import '../../../../core/sync/backup_scope_store.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../domain/services/backup_file_service.dart';
import '../notifiers/settings_notifier.dart';
import 'backup_scope_picker.dart';

/// Exports the database to an encrypted file, and imports one back.
class FileBackupSection extends ConsumerStatefulWidget {
  const FileBackupSection({super.key});

  @override
  ConsumerState<FileBackupSection> createState() => _FileBackupSectionState();
}

class _FileBackupSectionState extends ConsumerState<FileBackupSection> {
  final _masterPasswordController = TextEditingController();

  @override
  void dispose() {
    _masterPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Encrypt database records locally with AES-256-GCM using Argon2id key derivation.',
            style: TextStyle(
              fontSize: 13,
              color: ShellVibeTokens.resolve(context).textMuted,
            ),
          ),
          const SizedBox(height: 12),
          ShadInput(
            key: const Key('sync_master_password_field'),
            controller: _masterPasswordController,
            obscureText: true,
            placeholder: const Text('Enter password to encrypt/decrypt backup'),
          ),
          const Divider(height: 24),
          const BackupScopePicker(target: BackupTarget.file),
          const SizedBox(height: 12),
          ShellVibeButton(
            key: const Key('export_backup_button'),
            label: 'Export Encrypted Backup to File',
            icon: LucideIcons.download,
            onPressed: _handleExportE2EEBackup,
          ),
          const SizedBox(height: 8),
          Text(
            isMobilePlatform
                ? 'Export writes a .$kBackupFileExtension file into the app documents folder; import reads one back.'
                : 'Export writes a .$kBackupFileExtension file you choose; import reads one back.',
            style: TextStyle(
              fontSize: 12,
              color: ShellVibeTokens.resolve(context).textMuted,
            ),
          ),
          const Divider(height: 24),
          ShellVibeButton.secondary(
            key: const Key('import_backup_button'),
            label: 'Import Encrypted Backup from File',
            icon: LucideIcons.upload,
            onPressed: _handleImportE2EEBackup,
          ),
        ],
      ),
    );
  }

  Future<void> _handleExportE2EEBackup() async {
    final password = _masterPasswordController.text.trim();
    if (password.isEmpty) {
      ShadToaster.of(context).show(
        const ShadToast(
          description: Text(
            'Please enter a Master Password for Zero-Knowledge encryption.',
          ),
        ),
      );
      return;
    }

    try {
      final db = ref.read(appDatabaseProvider);
      final syncService = ref.read(e2eeCloudSyncServiceProvider);

      // This picker's own scope. A file saved to disk and a backup uploaded
      // to the vault are different acts with different risks, so narrowing
      // one says nothing about the other.
      final scope = await BackupScopeStore(
        storage: ref.read(secureStorageServiceProvider),
      ).read(BackupTarget.file);

      final backupJson = await syncService.exportEncryptedBackup(
        db: db,
        masterPassword: password,
        scope: scope,
        settings: scope.contains(BackupCategory.settings)
            ? (await ref.read(settingsRepositoryProvider).loadSettings())
                  .toJson()
            : null,
      );

      final path = await ref
          .read(backupFileServiceProvider)
          .saveBackup(backupJson);
      // Null means the native save dialog was cancelled: nothing to report.
      if (path == null) return;

      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            title: const Text('Backup Exported'),
            description: Text('Saved to $path'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Failed to export backup: $e'),
          ),
        );
      }
    }
  }

  Future<void> _handleImportE2EEBackup() async {
    final password = _masterPasswordController.text.trim();

    if (password.isEmpty) {
      ShadToaster.of(context).show(
        const ShadToast(
          description: Text(
            'Please enter the Master Password the backup was encrypted with.',
          ),
        ),
      );
      return;
    }

    final PickedBackup? picked;
    try {
      picked = await ref.read(backupFileServiceProvider).pickBackup();
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Could not read the backup file: $e'),
          ),
        );
      }
      return;
    }
    // Null means the file picker was cancelled.
    if (picked == null) return;
    final backupJson = picked.contents.trim();

    try {
      final db = ref.read(appDatabaseProvider);
      final syncService = ref.read(e2eeCloudSyncServiceProvider);
      final result = await syncService.importEncryptedBackup(
        backupPackageJson: backupJson,
        db: db,
        masterPassword: password,
      );

      // Settings live in secure storage, so the sync service hands them back
      // rather than applying them itself.
      final restoredSettings = result.settings;
      final settingsNotes = restoredSettings == null
          ? const <String>[]
          : await ref
                .read(settingsProvider.notifier)
                .applyRestoredSettings(restoredSettings);
      final notes = [
        result.warning,
        ...result.repairs.messages,
        ...settingsNotes,
      ].nonNulls.toList();

      // The import wrote straight to the database; the list notifiers are
      // still holding what they read at startup and would keep showing the old
      // hosts and identities until the app was restarted.
      invalidateRestoredData(ref.invalidate);

      if (mounted) {
        ShadToaster.of(context).show(
          result.secretsRecovered
              ? (result.warning == null
                    ? ShadToast.new
                    : ShadToast.destructive)(
                  description: Text(
                    [
                      'Zero-Knowledge Backup Imported & Restored Successfully!',
                      ...notes,
                    ].join(' '),
                  ),
                )
              : ShadToast.destructive(
                  description: Text(
                    [
                      if (result.warning == null)
                        'Backup restored, but stored secrets could not be recovered.',
                      ...notes,
                    ].join(' '),
                  ),
                ),
        );
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text(
              'Import failed (wrong password or corrupted backup): $e',
            ),
          ),
        );
      }
    }
  }
}
