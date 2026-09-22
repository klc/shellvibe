import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:xterm3/xterm.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/theme/ui_font.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/mosh_prediction_mode.dart';
import '../../../../core/sync/backup_scope.dart';
import '../../../../core/sync/backup_scope_store.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../../app/restored_data.dart';
import '../../../account/presentation/widgets/account_settings_section.dart';
import '../../../cloud_backup/presentation/widgets/cloud_backup_section.dart';
import '../../../cloud_backup/presentation/widgets/sync_section.dart';
import '../../../device_link/presentation/widgets/paired_devices_settings_section.dart';
import '../../../mcp/presentation/widgets/mcp_access_settings_section.dart';
import '../../../terminal/domain/models/terminal_font.dart';
import '../../../terminal/domain/models/terminal_palette.dart';
import '../../../terminal/domain/models/terminal_palette_data.dart';
import '../../../terminal/presentation/utils/terminal_font_resolver.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../../vault/presentation/notifiers/vault_notifier.dart';
import '../../domain/models/app_settings_model.dart';
import '../../domain/models/settings_section.dart';
import '../../domain/services/backup_file_service.dart';
import '../notifiers/settings_notifier.dart';
import 'about_settings_section.dart';
import 'backup_scope_picker.dart';
import 'known_hosts_settings_section.dart';

/// The controls of a single [SettingsSection], with nothing around them.
///
/// Both layouts show exactly one section at a time — the wide one in its work
/// panel, the compact one on a pushed page — so the controls live here rather
/// than in either screen, and neither can drift from the other.
class SettingsSectionView extends ConsumerStatefulWidget {
  const SettingsSectionView({
    super.key,
    required this.section,
    this.padding = const EdgeInsets.fromLTRB(24, 0, 24, 24),
  });

  final SettingsSection section;

  /// The scroll view's padding: the wide layout sits inside a panel that has
  /// already paid for its own gutter, the compact one has not.
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<SettingsSectionView> createState() =>
      _SettingsSectionViewState();
}

class _SettingsSectionViewState extends ConsumerState<SettingsSectionView> {
  final _masterPasswordController = TextEditingController();
  final _vaultPasswordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => ShellVibeEmptyState(
        icon: LucideIcons.triangleAlert,
        title: 'Settings could not be loaded',
        description: '$err',
      ),
      data: (settings) => ListView(
        padding: widget.padding,
        children: _sectionChildren(
          widget.section,
          settings,
          ref.read(settingsProvider.notifier),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _masterPasswordController.dispose();
    _vaultPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleTestBiometrics() async {
    final service = ref.read(biometricLockServiceProvider);
    final canCheck = await service.canCheckBiometrics();
    if (!canCheck) {
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(
            description: Text(
              'Biometric authentication is not available on this device.',
            ),
          ),
        );
      }
      return;
    }

    final success = await service.authenticate(
      localizedReason: 'Test ${AppConstants.appName} Biometric Lock',
    );
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
      if (restoredSettings != null) {
        await ref
            .read(settingsProvider.notifier)
            .applyRestoredSettings(restoredSettings);
      }

      // The import wrote straight to the database; the list notifiers are
      // still holding what they read at startup and would keep showing the old
      // hosts and identities until the app was restarted.
      invalidateRestoredDataFor(ref);

      if (mounted) {
        ShadToaster.of(context).show(
          result.secretsRecovered
              ? const ShadToast(
                  description: Text(
                    'Zero-Knowledge Backup Imported & Restored Successfully!',
                  ),
                )
              : ShadToast.destructive(
                  description: Text(
                    result.warning ??
                        'Backup restored, but stored secrets could not be recovered.',
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

  List<Widget> _sectionChildren(
    SettingsSection section,
    AppSettingsModel settings,
    SettingsNotifier notifier,
  ) {
    switch (section) {
      case SettingsSection.appearance:
        return [
          // --- Section 1: Application Appearance ---
          _buildSectionHeader('App Theme & Appearance', LucideIcons.palette),
          ShadCard(
            child: Column(
              children: [
                ListTile(
                  title: const Text('App Theme Mode'),
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
                      ShadOption(
                        value: ThemeMode.system,
                        child: Text('System'),
                      ),
                    ],
                    onChanged: (mode) {
                      if (mode != null) {
                        notifier.setThemeMode(mode);
                      }
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('App UI Color Palette'),
                  subtitle: Text(
                    'Current: ${settings.palette.name.toUpperCase()}',
                  ),
                  trailing: ShadSelect<AppPalette>(
                    key: const Key('settings_palette_dropdown'),
                    initialValue: settings.palette,
                    selectedOptionBuilder: (context, value) {
                      switch (value) {
                        case AppPalette.dark:
                          return const Text('ShellVibe Graphite');
                        case AppPalette.oled:
                          return const Text('ShellVibe OLED');
                        case AppPalette.teal:
                          return const Text('ShellVibe Teal');
                        case AppPalette.catppuccin:
                          return const Text('Catppuccin');
                        case AppPalette.nord:
                          return const Text('Nord');
                        case AppPalette.dracula:
                          return const Text('Dracula');
                        case AppPalette.solarizedDark:
                          return const Text('Solarized Dark');
                        case AppPalette.tokyoNight:
                          return const Text('Tokyo Night');
                        case AppPalette.gruvbox:
                          return const Text('Gruvbox');
                        case AppPalette.oneDark:
                          return const Text('One Dark');
                      }
                    },
                    options: const [
                      // OLED leads because it is the default the app ships
                      // with; the list under it stays alphabetical.
                      ShadOption(
                        value: AppPalette.oled,
                        child: Text('ShellVibe OLED'),
                      ),
                      ShadOption(
                        value: AppPalette.dark,
                        child: Text('ShellVibe Graphite'),
                      ),
                      ShadOption(
                        value: AppPalette.teal,
                        child: Text('ShellVibe Teal'),
                      ),
                      ShadOption(
                        value: AppPalette.catppuccin,
                        child: Text('Catppuccin'),
                      ),
                      ShadOption(
                        value: AppPalette.dracula,
                        child: Text('Dracula'),
                      ),
                      ShadOption(
                        value: AppPalette.gruvbox,
                        child: Text('Gruvbox'),
                      ),
                      ShadOption(value: AppPalette.nord, child: Text('Nord')),
                      ShadOption(
                        value: AppPalette.oneDark,
                        child: Text('One Dark'),
                      ),
                      ShadOption(
                        value: AppPalette.solarizedDark,
                        child: Text('Solarized Dark'),
                      ),
                      ShadOption(
                        value: AppPalette.tokyoNight,
                        child: Text('Tokyo Night'),
                      ),
                    ],
                    onChanged: (palette) {
                      if (palette != null) {
                        notifier.setPalette(palette);
                      }
                    },
                  ),
                ),
                const Divider(),

                ListTile(
                  title: const Text('App UI Font'),
                  subtitle: const Text(
                    'The interface only. Terminal output keeps its own face.',
                  ),
                  trailing: ShadSelect<String>(
                    key: const Key('settings_ui_font_dropdown'),
                    initialValue: settings.uiFontFamily,
                    selectedOptionBuilder: (context, value) {
                      return Text(UiFont.of(value).label);
                    },
                    options: [
                      for (final f in kUiFonts)
                        ShadOption(
                          value: f.id,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(f.label),
                              // The bundled face is the one that survives a
                              // first launch with no network; the rest are
                              // fetched once and cached.
                              if (f.source == UiFontSource.bundled) ...[
                                const SizedBox(width: 6),
                                const ShadBadge.secondary(
                                  child: Text('Offline'),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                    onChanged: (font) {
                      if (font != null) {
                        notifier.setUiFontFamily(font);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // A phone has no tray and no window to close.
          if (!isMobilePlatform) ...[
            _buildSectionHeader('Window', LucideIcons.appWindow),
            ShadCard(
              child: Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  key: const Key('settings_keep_running_in_tray_switch'),
                  title: Text(
                    defaultTargetPlatform == TargetPlatform.macOS
                        ? 'Show in the Menu Bar'
                        : 'Keep Running in the System Tray',
                  ),
                  subtitle: Text(
                    defaultTargetPlatform == TargetPlatform.macOS
                        ? 'A menu bar icon shows active tunnels and sessions '
                              'and brings the window back.'
                        : 'Closing the window hides it to the tray, so '
                              'tunnels and sessions keep running. Quit from '
                              'the tray menu.',
                  ),
                  value: settings.keepRunningInTray,
                  onChanged: (val) => notifier.setKeepRunningInTray(val),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ];
      case SettingsSection.terminal:
        return [
          // --- Section 2: Terminal Customization & Theme ---
          _buildSectionHeader(
            'Terminal Theme & Shell',
            LucideIcons.squareTerminal,
          ),
          ShadCard(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Terminal Color Scheme'),
                  subtitle: Text(
                    'Current: ${TerminalPaletteData.of(settings.terminalPalette).label}',
                  ),
                  trailing: ShadSelect<TerminalPalette>(
                    key: const Key('settings_terminal_palette_dropdown'),
                    initialValue: settings.terminalPalette,
                    selectedOptionBuilder: (context, value) {
                      return Text(TerminalPaletteData.of(value).label);
                    },
                    options: [
                      for (final p in kTerminalPalettes)
                        ShadOption(
                          value: p.palette,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PaletteSwatch(theme: p.theme),
                              const SizedBox(width: 8),
                              Text(p.label),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (palette) {
                      if (palette != null) {
                        notifier.setTerminalPalette(palette);
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: _TerminalThemePreview(
                    theme: TerminalPaletteData.themeOf(
                      settings.terminalPalette,
                    ),
                    fontFamily: resolveTerminalFontFamily(settings.fontFamily),
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Mosh Prediction'),
                  subtitle: const Text(
                    'Show locally predicted input on high-latency Mosh links',
                  ),
                  trailing: ShadSelect<MoshPredictionMode>(
                    key: const Key('settings_mosh_prediction_dropdown'),
                    initialValue: settings.moshPrediction,
                    selectedOptionBuilder: (context, value) {
                      switch (value) {
                        case MoshPredictionMode.never:
                          return const Text('Never');
                        case MoshPredictionMode.adaptive:
                          return const Text('Adaptive');
                        case MoshPredictionMode.always:
                          return const Text('Always');
                      }
                    },
                    options: const [
                      ShadOption(
                        value: MoshPredictionMode.never,
                        child: Text('Never'),
                      ),
                      ShadOption(
                        value: MoshPredictionMode.adaptive,
                        child: Text('Adaptive'),
                      ),
                      ShadOption(
                        value: MoshPredictionMode.always,
                        child: Text('Always'),
                      ),
                    ],
                    onChanged: (mode) {
                      if (mode != null) {
                        notifier.setMoshPrediction(mode);
                      }
                    },
                  ),
                ),
                const Divider(),

                ListTile(
                  title: const Text('Font Family'),
                  subtitle: const Text('Terminal sessions only'),
                  trailing: ShadSelect<String>(
                    key: const Key('settings_font_family_dropdown'),
                    initialValue: settings.fontFamily,
                    selectedOptionBuilder: (context, value) {
                      return Text(TerminalFont.of(value).label);
                    },
                    options: [
                      for (final f in kTerminalFonts)
                        ShadOption(
                          value: f.id,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(f.label),
                              if (f.source ==
                                  TerminalFontSource.bundledNerdFont) ...[
                                const SizedBox(width: 6),
                                const ShadBadge.secondary(child: Text('NF')),
                              ],
                            ],
                          ),
                        ),
                    ],
                    onChanged: (font) {
                      if (font != null) {
                        notifier.setFontFamily(font);
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: _FontPreview(
                    fontFamily: resolveTerminalFontFamily(settings.fontFamily),
                    ligatures: settings.enableLigatures,
                  ),
                ),
                const Divider(),

                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    key: const Key('settings_font_ligatures_switch'),
                    title: const Text('Font Ligatures'),
                    subtitle: const Text(
                      'Enable programming ligatures (e.g. ->, ==, !=, =>)',
                    ),
                    value: settings.enableLigatures,
                    onChanged: (val) => notifier.setEnableLigatures(val),
                  ),
                ),
                const Divider(),

                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    key: const Key('settings_bold_bright_switch'),
                    title: const Text('Bold Text Uses Bright Colors'),
                    subtitle: const Text(
                      'Draw bold text in the bright variant of its color '
                      '(ANSI 0-7 remapped to 8-15)',
                    ),
                    value: settings.drawBoldTextWithBrightColors,
                    onChanged: (val) =>
                        notifier.setDrawBoldTextWithBrightColors(val),
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
                  title: const Text('Line Height'),
                  subtitle: Slider(
                    key: const Key('settings_line_height_slider'),
                    min: 1.0,
                    max: 2.0,
                    divisions: 20,
                    value: settings.lineHeightFactor,
                    label: '${settings.lineHeightFactor.toStringAsFixed(2)}x',
                    onChanged: (val) => notifier.setLineHeightFactor(val),
                  ),
                  trailing: Text(
                    '${settings.lineHeightFactor.toStringAsFixed(2)}x',
                  ),
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
                      ShadOption(
                        value: AppCursorStyle.block,
                        child: Text('Block'),
                      ),
                      ShadOption(
                        value: AppCursorStyle.underline,
                        child: Text('Underline'),
                      ),
                      ShadOption(value: AppCursorStyle.bar, child: Text('Bar')),
                    ],
                    onChanged: (style) {
                      if (style != null) {
                        notifier.setCursorStyle(style);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildTerminalPreview(settings),
        ];
      case SettingsSection.security:
        return [
          // --- Section 2: Security & Biometrics ---
          _buildSectionHeader(
            'Security & Biometric Controls',
            LucideIcons.shieldCheck,
          ),
          ShadCard(
            child: Column(
              children: [
                ListTile(
                  title: const Text(
                    'Biometric Lock (FaceID / TouchID / Windows Hello)',
                  ),
                  subtitle: const Text(
                    'Verify identity on app launch or resume',
                  ),
                  trailing: ShellVibeButton(
                    key: const Key('test_biometrics_button'),
                    label: 'Test Lock',
                    onPressed: _handleTestBiometrics,
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
                      if (sec != null) {
                        notifier.setAutoLockTimer(sec);
                      }
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Clipboard Auto-Clear'),
                  subtitle: const Text(
                    'Clear copied sensitive passwords/keys after timer',
                  ),
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
                      if (sec != null) {
                        notifier.setClipboardAutoClear(sec);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Known Host Keys', LucideIcons.fingerprint),
          const KnownHostsSettingsSection(),
        ];
      case SettingsSection.vault:
        return [
          // --- Section 3: Vault Master Password ---
          _buildSectionHeader('Vault Master Password', LucideIcons.lockKeyhole),
          _buildVaultMasterPasswordCard(),
        ];
      case SettingsSection.deviceLink:
        return [
          _buildSectionHeader('Paired Devices', LucideIcons.smartphone),
          const PairedDevicesSettingsSection(),
        ];
      case SettingsSection.aiAccess:
        return [
          _buildSectionHeader('AI Access', LucideIcons.bot),
          const McpAccessSettingsSection(),
        ];
      case SettingsSection.account:
        return [
          _buildSectionHeader('Account', LucideIcons.circleUser),
          const AccountSettingsSection(),
        ];
      case SettingsSection.sync:
        return [
          _buildSectionHeader('Automatic Sync', LucideIcons.cloudCog),
          const SyncSection(),
        ];
      case SettingsSection.backup:
        return [
          _buildSectionHeader('Cloud Backup', LucideIcons.cloudUpload),
          const CloudBackupSection(),
          const SizedBox(height: 24),
          // --- Section 4: Zero-Knowledge E2EE Cloud Sync ---
          _buildSectionHeader('Encrypted File Backup', LucideIcons.cloudCog),
          ShadCard(
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
                  placeholder: const Text(
                    'Enter password to encrypt/decrypt backup',
                  ),
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
          ),
        ];
      case SettingsSection.about:
        return [
          _buildSectionHeader('About', LucideIcons.info),
          const AboutSettingsSection(),
        ];
    }
  }

  /// Live preview so a font, size or ligature change is visible in place —
  /// there is no save step to confirm it against.
  Widget _buildTerminalPreview(AppSettingsModel settings) {
    final tokens = ShellVibeTokens.resolve(context);
    final style = TextStyle(
      fontFamily: settings.fontFamily,
      fontSize: settings.fontSize,
      height: 1.55,
      fontFeatures: settings.enableLigatures
          ? const [FontFeature.enable('calt'), FontFeature.enable('liga')]
          : const [FontFeature.disable('calt'), FontFeature.disable('liga')],
    );
    return Container(
      key: const Key('settings_terminal_preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r'ops@edge-01:~$ grep -R "timeout" --include=*.yaml .',
            style: style.copyWith(color: tokens.textPrimary),
          ),
          Text(
            'config/app.yaml:12:  timeout: 30s',
            style: style.copyWith(color: tokens.textMuted),
          ),
          Text(
            'if x != y --> retry()',
            style: style.copyWith(color: tokens.brand),
          ),
        ],
      ),
    );
  }

  Widget _buildVaultMasterPasswordCard() {
    final vaultStatus = ref.watch(vaultProvider).value?.status;
    final isConfigured =
        vaultStatus != null && vaultStatus != VaultStatus.unconfigured;

    return ShadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isConfigured
                ? 'Your vault key is protected by a master password. It is required '
                      'after every app restart before identity secrets can be used. '
                      'Removing it returns the key to the operating system keychain, '
                      'so the app stops asking — and stops being protected by the '
                      'password.'
                : 'Without a master password your vault key is protected only by the '
                      'operating system keychain. Setting one wraps the key with '
                      'Argon2id + AES-256-GCM. Existing identities stay readable.',
            style: TextStyle(
              fontSize: 13,
              color: ShellVibeTokens.resolve(context).textMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (isConfigured) ...[
            ShellVibeButton.secondary(
              key: const Key('lock_vault_button'),
              label: vaultStatus == VaultStatus.locked
                  ? 'Vault Locked'
                  : 'Lock Vault Now',
              icon: LucideIcons.lock,
              onPressed: vaultStatus == VaultStatus.locked
                  ? null
                  : () => ref.read(vaultProvider.notifier).lock(),
            ),
            const SizedBox(height: 12),
            ShadInput(
              key: const Key('remove_master_password_field'),
              controller: _vaultPasswordController,
              obscureText: true,
              placeholder: const Text('Current master password'),
            ),
            const SizedBox(height: 12),
            ShellVibeButton.danger(
              key: const Key('remove_master_password_button'),
              label: 'Remove Master Password',
              icon: LucideIcons.lockOpen,
              onPressed: _handleRemoveMasterPassword,
            ),
          ] else ...[
            ShadInput(
              key: const Key('vault_master_password_field'),
              controller: _vaultPasswordController,
              obscureText: true,
              placeholder: const Text('New master password (min 8 characters)'),
            ),
            const SizedBox(height: 12),
            ShellVibeButton(
              key: const Key('set_master_password_button'),
              label: 'Set Master Password',
              icon: LucideIcons.lockKeyhole,
              onPressed: _handleSetMasterPassword,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleRemoveMasterPassword() async {
    final password = _vaultPasswordController.text;
    if (password.isEmpty) {
      ShadToaster.of(context).show(
        const ShadToast.destructive(
          description: Text('Enter your current master password to remove it.'),
        ),
      );
      return;
    }

    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (dialogContext) => ShadDialog.alert(
        title: const Text('Remove master password?'),
        description: const Text(
          'Your vault key goes back to the operating system keychain. The app '
          'will no longer ask for a password at startup, and anyone with '
          'access to your unlocked account can use your identity secrets.',
        ),
        actions: adaptiveDialogActions(context, [
          ShellVibeButton.secondary(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          ShellVibeButton.danger(
            key: const Key('confirm_remove_master_password_button'),
            label: 'Remove',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(context),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final removed = await ref
          .read(vaultProvider.notifier)
          .removeMasterPassword(password);
      // The controller may already be disposed if the screen left the tree
      // while the (isolate-backed) verification was running.
      if (!mounted) return;
      if (!removed) {
        ShadToaster.of(context).show(
          const ShadToast.destructive(
            description: Text(
              'Wrong master password, or too many failed attempts.',
            ),
          ),
        );
        return;
      }
      _vaultPasswordController.clear();
      ShadToaster.of(context).show(
        const ShadToast(
          description: Text(
            'Master password removed. The vault no longer locks on restart.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Failed to remove master password: $e'),
          ),
        );
      }
    }
  }

  Future<void> _handleSetMasterPassword() async {
    final password = _vaultPasswordController.text;
    if (password.length < 8) {
      ShadToaster.of(context).show(
        const ShadToast.destructive(
          description: Text('Master password must be at least 8 characters.'),
        ),
      );
      return;
    }

    try {
      await ref.read(vaultProvider.notifier).setup(password);
      // The controller may already be disposed if the screen left the tree
      // while the (isolate-backed) setup was running.
      if (!mounted) return;
      _vaultPasswordController.clear();
      ShadToaster.of(context).show(
        const ShadToast(
          description: Text(
            'Master password set. The vault now locks on app restart.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Failed to set master password: $e'),
          ),
        );
      }
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tokens.brand),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact 8-color ANSI strip used in the theme dropdown rows.
class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({required this.theme});

  final TerminalTheme theme;

  @override
  Widget build(BuildContext context) {
    // Rounded chips with air between them: a palette is a set of colours, and
    // a solid 88px bar reads as one colour band instead of eight choices.
    return SizedBox(
      width: 96,
      height: 14,
      child: Row(
        children: [
          for (final color in _themeAnsiColors(theme).take(8)) ...[
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(width: 3),
          ],
        ],
      ),
    );
  }
}

/// The 16 ANSI colors of a scheme, base then bright.
List<Color> _themeAnsiColors(TerminalTheme theme) => [
  theme.black,
  theme.red,
  theme.green,
  theme.yellow,
  theme.blue,
  theme.magenta,
  theme.cyan,
  theme.white,
  theme.brightBlack,
  theme.brightRed,
  theme.brightGreen,
  theme.brightYellow,
  theme.brightBlue,
  theme.brightMagenta,
  theme.brightCyan,
  theme.brightWhite,
];

/// Live preview of the selected terminal color scheme.
class _TerminalThemePreview extends StatelessWidget {
  const _TerminalThemePreview({required this.theme, required this.fontFamily});

  final TerminalTheme theme;

  /// The font the terminal itself will use, so this preview and the font
  /// preview right below it don't disagree about what a session looks like.
  final String fontFamily;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    // The preview is a small terminal, so it is built like one: a chrome strip
    // naming what is being previewed, then the opaque body under it.
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        boxShadow: tokens.shadowPanel,
      ),
      // Drawn over the child: a clipped child covers a background border along
      // the corner arcs and breaks the outline there.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.brand.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            color: tokens.terminalChrome,
            child: Row(
              children: [
                const ShellVibeStatusDot(
                  state: ShellVibeDotState.online,
                  size: 6,
                ),
                const SizedBox(width: 8),
                Text(
                  'preview',
                  style: shellvibeMono(
                    context,
                    size: 11,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            color: theme.background,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final color in _themeAnsiColors(theme)) ...[
                      Expanded(child: Container(height: 8, color: color)),
                      const SizedBox(width: 2),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  r'$> ssh deploy  grep "port"  ./run.sh',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontFamilyFallback: kTerminalFontFamilyFallback,
                    fontSize: 13,
                    color: theme.foreground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live preview of the selected terminal font.
class _FontPreview extends StatelessWidget {
  const _FontPreview({required this.fontFamily, required this.ligatures});

  final String fontFamily;

  /// Mirrors the ligature setting: with it off the sample must show `!=` and
  /// `=>` as separate glyphs, exactly as a session would.
  final bool ligatures;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ShadTheme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.muted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        kFontPreviewText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: kTerminalFontFamilyFallback,
          fontSize: 15,
          height: 1.4,
          color: colorScheme.foreground,
          fontFeatures: [
            FontFeature('liga', ligatures ? 1 : 0),
            FontFeature('calt', ligatures ? 1 : 0),
          ],
        ),
      ),
    );
  }
}
