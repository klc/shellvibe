import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/e2ee_cloud_sync_service.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../domain/models/app_settings_model.dart';
import '../notifiers/settings_notifier.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _masterPasswordController = TextEditingController();
  final _backupPackageController = TextEditingController();

  @override
  void dispose() {
    _masterPasswordController.dispose();
    _backupPackageController.dispose();
    super.dispose();
  }

  Future<void> _handleTestBiometrics() async {
    final service = ref.read(biometricLockServiceProvider);
    final canCheck = await service.canCheckBiometrics();
    if (!canCheck) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric authentication is not available on this device.')),
        );
      }
      return;
    }

    final success = await service.authenticate(localizedReason: 'Test Terly2 Biometric Lock');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Biometric Authentication Successful!' : 'Biometric Authentication Failed/Cancelled.',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _handleExportE2EEBackup() async {
    final password = _masterPasswordController.text.trim();
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a Master Password for Zero-Knowledge encryption.')),
      );
      return;
    }

    try {
      final db = ref.read(appDatabaseProvider);
      final syncService = E2EECloudSyncService();
      final backupJson = await syncService.exportEncryptedBackup(
        db: db,
        masterPassword: password,
      );

      await Clipboard.setData(ClipboardData(text: backupJson));

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Backup Exported (Copied to Clipboard)'),
            content: SingleChildScrollView(
              child: SelectableText(backupJson),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export backup: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleImportE2EEBackup() async {
    final password = _masterPasswordController.text.trim();
    final backupJson = _backupPackageController.text.trim();

    if (password.isEmpty || backupJson.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide both Master Password and Backup Package JSON.'),
        ),
      );
      return;
    }

    try {
      final db = ref.read(appDatabaseProvider);
      final syncService = E2EECloudSyncService();
      await syncService.importEncryptedBackup(
        backupPackageJson: backupJson,
        db: db,
        masterPassword: password,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zero-Knowledge Backup Imported & Restored Successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed (wrong password or corrupted backup): $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Preferences'),
      ),
      body: settingsAsync.when(
        data: (settings) {
          final notifier = ref.read(settingsNotifierProvider.notifier);

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // --- Section 1: Appearance & Theme ---
              _buildSectionHeader('Appearance & Terminal Theme', Icons.palette),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Theme Mode'),
                        trailing: DropdownButton<ThemeMode>(
                          key: const Key('settings_theme_mode_dropdown'),
                          value: settings.themeMode,
                          onChanged: (mode) {
                            if (mode != null) notifier.setThemeMode(mode);
                          },
                          items: const [
                            DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                            DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                            DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                          ],
                        ),
                      ),
                      const Divider(),
                      ListTile(
                        title: const Text('Color Palette'),
                        subtitle: Text('Current: ${settings.palette.name.toUpperCase()}'),
                        trailing: DropdownButton<AppPalette>(
                          key: const Key('settings_palette_dropdown'),
                          value: settings.palette,
                          onChanged: (palette) {
                            if (palette != null) notifier.setPalette(palette);
                          },
                          items: const [
                            DropdownMenuItem(value: AppPalette.dark, child: Text('Dark Default')),
                            DropdownMenuItem(value: AppPalette.oled, child: Text('OLED Pure Black')),
                            DropdownMenuItem(value: AppPalette.catppuccin, child: Text('Catppuccin')),
                            DropdownMenuItem(value: AppPalette.nord, child: Text('Nord')),
                          ],
                        ),
                      ),
                      const Divider(),
                      ListTile(
                        title: const Text('Font Family'),
                        trailing: DropdownButton<String>(
                          key: const Key('settings_font_family_dropdown'),
                          value: settings.fontFamily,
                          onChanged: (font) {
                            if (font != null) notifier.setFontFamily(font);
                          },
                          items: const [
                            DropdownMenuItem(value: 'RobotoMono', child: Text('Roboto Mono')),
                            DropdownMenuItem(value: 'FiraCode', child: Text('Fira Code')),
                            DropdownMenuItem(value: 'Inter', child: Text('Inter')),
                            DropdownMenuItem(value: 'Courier', child: Text('Courier')),
                          ],
                        ),
                      ),
                      const Divider(),
                      ListTile(
                        title: const Text('Font Size'),
                        subtitle: Slider(
                          key: const Key('settings_font_size_slider'),
                          min: 10,
                          max: 24,
                          divisions: 14,
                          value: settings.fontSize,
                          label: '${settings.fontSize.toInt()} px',
                          onChanged: (val) => notifier.setFontSize(val),
                        ),
                        trailing: Text('${settings.fontSize.toInt()} px'),
                      ),
                      const Divider(),
                      ListTile(
                        title: const Text('Cursor Style'),
                        trailing: DropdownButton<AppCursorStyle>(
                          key: const Key('settings_cursor_style_dropdown'),
                          value: settings.cursorStyle,
                          onChanged: (style) {
                            if (style != null) notifier.setCursorStyle(style);
                          },
                          items: const [
                            DropdownMenuItem(value: AppCursorStyle.block, child: Text('Block')),
                            DropdownMenuItem(value: AppCursorStyle.underline, child: Text('Underline')),
                            DropdownMenuItem(value: AppCursorStyle.bar, child: Text('Bar')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // --- Section 2: Security & Biometrics ---
              _buildSectionHeader('Security & Biometric Controls', Icons.security),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Biometric Lock (FaceID / TouchID / Windows Hello)'),
                        subtitle: const Text('Verify identity on app launch or resume'),
                        trailing: ElevatedButton(
                          key: const Key('test_biometrics_button'),
                          onPressed: _handleTestBiometrics,
                          child: const Text('Test Lock'),
                        ),
                      ),
                      const Divider(),
                      ListTile(
                        title: const Text('Auto-Lock Timer'),
                        trailing: DropdownButton<int>(
                          key: const Key('settings_autolock_dropdown'),
                          value: settings.autoLockTimerSeconds,
                          onChanged: (sec) {
                            if (sec != null) notifier.setAutoLockTimer(sec);
                          },
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Disabled')),
                            DropdownMenuItem(value: 30, child: Text('30 Seconds')),
                            DropdownMenuItem(value: 60, child: Text('1 Minute')),
                            DropdownMenuItem(value: 300, child: Text('5 Minutes')),
                          ],
                        ),
                      ),
                      const Divider(),
                      ListTile(
                        title: const Text('Clipboard Auto-Clear'),
                        subtitle: const Text('Clear copied sensitive passwords/keys after timer'),
                        trailing: DropdownButton<int>(
                          key: const Key('settings_clipboard_clear_dropdown'),
                          value: settings.clipboardAutoClearSeconds,
                          onChanged: (sec) {
                            if (sec != null) notifier.setClipboardAutoClear(sec);
                          },
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Disabled')),
                            DropdownMenuItem(value: 15, child: Text('15 Seconds')),
                            DropdownMenuItem(value: 30, child: Text('30 Seconds')),
                            DropdownMenuItem(value: 60, child: Text('60 Seconds')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // --- Section 3: Zero-Knowledge E2EE Cloud Sync ---
              _buildSectionHeader('Zero-Knowledge E2EE Cloud Sync', Icons.cloud_sync),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Encrypt database records locally with AES-256-GCM using Argon2id key derivation.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('sync_master_password_field'),
                        controller: _masterPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Master Password',
                          hintText: 'Enter password to encrypt/decrypt backup',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              key: const Key('export_backup_button'),
                              onPressed: _handleExportE2EEBackup,
                              icon: const Icon(Icons.download),
                              label: const Text('Export Encrypted Backup'),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      TextField(
                        key: const Key('sync_backup_package_field'),
                        controller: _backupPackageController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Paste Encrypted Backup JSON',
                          hintText: '{"schema_version": 1, "salt": "...", "payload": "..."}',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              key: const Key('import_backup_button'),
                              onPressed: _handleImportE2EEBackup,
                              icon: const Icon(Icons.upload),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                              ),
                              label: const Text('Import Encrypted Backup'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error loading settings: $err')),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
