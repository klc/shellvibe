import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
        ShadToaster.of(context).show(
          const ShadToast(
            description: Text('Biometric authentication is not available on this device.'),
          ),
        );
      }
      return;
    }

    final success = await service.authenticate(localizedReason: 'Test Terly2 Biometric Lock');
    if (mounted) {
      if (success) {
        ShadToaster.of(context).show(
          const ShadToast(
            description: Text('Biometric Authentication Successful!'),
          ),
        );
      } else {
        ShadToaster.of(context).show(
          const ShadToast.destructive(
            description: Text('Biometric Authentication Failed/Cancelled.'),
          ),
        );
      }
    }
  }

  Future<void> _handleExportE2EEBackup() async {
    final password = _masterPasswordController.text.trim();
    if (password.isEmpty) {
      ShadToaster.of(context).show(
        const ShadToast(
          description: Text('Please enter a Master Password for Zero-Knowledge encryption.'),
        ),
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
          builder: (context) => ShadDialog(
            title: const Text('Backup Exported (Copied to Clipboard)'),
            description: SingleChildScrollView(
              child: SelectableText(backupJson),
            ),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
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
    final backupJson = _backupPackageController.text.trim();

    if (password.isEmpty || backupJson.isEmpty) {
      ShadToaster.of(context).show(
        const ShadToast(
          description: Text('Please provide both Master Password and Backup Package JSON.'),
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
        ShadToaster.of(context).show(
          const ShadToast(
            description: Text('Zero-Knowledge Backup Imported & Restored Successfully!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Import failed (wrong password or corrupted backup): $e'),
          ),
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
              ShadCard(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Theme Mode'),
                      trailing: ShadSelect<ThemeMode>(
                        key: const Key('settings_theme_mode_dropdown'),
                        initialValue: settings.themeMode,
                        selectedOptionBuilder: (context, value) {
                          switch (value) {
                            case ThemeMode.dark:
                              return const Text('Dark');
                            case ThemeMode.light:
                              return const Text('Light');
                            case ThemeMode.system:
                              return const Text('System');
                          }
                        },
                        options: const [
                          ShadOption(value: ThemeMode.dark, child: Text('Dark')),
                          ShadOption(value: ThemeMode.light, child: Text('Light')),
                          ShadOption(value: ThemeMode.system, child: Text('System')),
                        ],
                        onChanged: (mode) {
                          if (mode != null) notifier.setThemeMode(mode);
                        },
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('Color Palette'),
                      subtitle: Text('Current: ${settings.palette.name.toUpperCase()}'),
                      trailing: ShadSelect<AppPalette>(
                        key: const Key('settings_palette_dropdown'),
                        initialValue: settings.palette,
                        selectedOptionBuilder: (context, value) {
                          switch (value) {
                            case AppPalette.dark:
                              return const Text('Dark Default');
                            case AppPalette.oled:
                              return const Text('OLED Pure Black');
                            case AppPalette.catppuccin:
                              return const Text('Catppuccin');
                            case AppPalette.nord:
                              return const Text('Nord');
                          }
                        },
                        options: const [
                          ShadOption(value: AppPalette.dark, child: Text('Dark Default')),
                          ShadOption(value: AppPalette.oled, child: Text('OLED Pure Black')),
                          ShadOption(value: AppPalette.catppuccin, child: Text('Catppuccin')),
                          ShadOption(value: AppPalette.nord, child: Text('Nord')),
                        ],
                        onChanged: (palette) {
                          if (palette != null) notifier.setPalette(palette);
                        },
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('Font Family'),
                      trailing: ShadSelect<String>(
                        key: const Key('settings_font_family_dropdown'),
                        initialValue: settings.fontFamily,
                        selectedOptionBuilder: (context, value) {
                          switch (value) {
                            case 'FiraCode':
                              return const Text('Fira Code');
                            case 'Inter':
                              return const Text('Inter');
                            case 'Courier':
                              return const Text('Courier');
                            case 'RobotoMono':
                            default:
                              return const Text('Roboto Mono');
                          }
                        },
                        options: const [
                          ShadOption(value: 'RobotoMono', child: Text('Roboto Mono')),
                          ShadOption(value: 'FiraCode', child: Text('Fira Code')),
                          ShadOption(value: 'Inter', child: Text('Inter')),
                          ShadOption(value: 'Courier', child: Text('Courier')),
                        ],
                        onChanged: (font) {
                          if (font != null) notifier.setFontFamily(font);
                        },
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
                      trailing: ShadSelect<AppCursorStyle>(
                        key: const Key('settings_cursor_style_dropdown'),
                        initialValue: settings.cursorStyle,
                        selectedOptionBuilder: (context, value) {
                          switch (value) {
                            case AppCursorStyle.underline:
                              return const Text('Underline');
                            case AppCursorStyle.bar:
                              return const Text('Bar');
                            case AppCursorStyle.block:
                              return const Text('Block');
                          }
                        },
                        options: const [
                          ShadOption(value: AppCursorStyle.block, child: Text('Block')),
                          ShadOption(value: AppCursorStyle.underline, child: Text('Underline')),
                          ShadOption(value: AppCursorStyle.bar, child: Text('Bar')),
                        ],
                        onChanged: (style) {
                          if (style != null) notifier.setCursorStyle(style);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // --- Section 2: Security & Biometrics ---
              _buildSectionHeader('Security & Biometric Controls', Icons.security),
              ShadCard(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Biometric Lock (FaceID / TouchID / Windows Hello)'),
                      subtitle: const Text('Verify identity on app launch or resume'),
                      trailing: ShadButton(
                        key: const Key('test_biometrics_button'),
                        onPressed: _handleTestBiometrics,
                        child: const Text('Test Lock'),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('Auto-Lock Timer'),
                      trailing: ShadSelect<int>(
                        key: const Key('settings_autolock_dropdown'),
                        initialValue: settings.autoLockTimerSeconds,
                        selectedOptionBuilder: (context, value) {
                          switch (value) {
                            case 30:
                              return const Text('30 Seconds');
                            case 60:
                              return const Text('1 Minute');
                            case 300:
                              return const Text('5 Minutes');
                            case 0:
                            default:
                              return const Text('Disabled');
                          }
                        },
                        options: const [
                          ShadOption(value: 0, child: Text('Disabled')),
                          ShadOption(value: 30, child: Text('30 Seconds')),
                          ShadOption(value: 60, child: Text('1 Minute')),
                          ShadOption(value: 300, child: Text('5 Minutes')),
                        ],
                        onChanged: (sec) {
                          if (sec != null) notifier.setAutoLockTimer(sec);
                        },
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('Clipboard Auto-Clear'),
                      subtitle: const Text('Clear copied sensitive passwords/keys after timer'),
                      trailing: ShadSelect<int>(
                        key: const Key('settings_clipboard_clear_dropdown'),
                        initialValue: settings.clipboardAutoClearSeconds,
                        selectedOptionBuilder: (context, value) {
                          switch (value) {
                            case 15:
                              return const Text('15 Seconds');
                            case 30:
                              return const Text('30 Seconds');
                            case 60:
                              return const Text('60 Seconds');
                            case 0:
                            default:
                              return const Text('Disabled');
                          }
                        },
                        options: const [
                          ShadOption(value: 0, child: Text('Disabled')),
                          ShadOption(value: 15, child: Text('15 Seconds')),
                          ShadOption(value: 30, child: Text('30 Seconds')),
                          ShadOption(value: 60, child: Text('60 Seconds')),
                        ],
                        onChanged: (sec) {
                          if (sec != null) notifier.setClipboardAutoClear(sec);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // --- Section 3: Zero-Knowledge E2EE Cloud Sync ---
              _buildSectionHeader('Zero-Knowledge E2EE Cloud Sync', Icons.cloud_sync),
              ShadCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Encrypt database records locally with AES-256-GCM using Argon2id key derivation.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    ShadInput(
                      key: const Key('sync_master_password_field'),
                      controller: _masterPasswordController,
                      obscureText: true,
                      placeholder: const Text('Enter password to encrypt/decrypt backup'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ShadButton(
                            key: const Key('export_backup_button'),
                            onPressed: _handleExportE2EEBackup,
                            leading: const Icon(Icons.download, size: 16),
                            child: const Text('Export Encrypted Backup'),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    ShadInput(
                      key: const Key('sync_backup_package_field'),
                      controller: _backupPackageController,
                      maxLines: 3,
                      placeholder: const Text('{"schema_version": 1, "salt": "...", "payload": "..."}'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ShadButton(
                            key: const Key('import_backup_button'),
                            onPressed: _handleImportE2EEBackup,
                            leading: const Icon(Icons.upload, size: 16),
                            backgroundColor: Colors.orange,
                            child: const Text('Import Encrypted Backup'),
                          ),
                        ),
                      ],
                    ),
                  ],
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
