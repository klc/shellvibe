import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/terly_tokens.dart';
import '../../../../app/widgets/terly_ui.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../../vault/presentation/notifiers/vault_notifier.dart';
import '../../domain/models/app_settings_model.dart';
import '../notifiers/settings_notifier.dart';

/// Width at which the fixed section navigation replaces one long scroll.
const double _kSectionNavBreakpoint = 820;

/// The wireframe's settings sections, in navigation order.
enum SettingsSection {
  appearance('Appearance', LucideIcons.palette),
  terminal('Terminal', LucideIcons.squareTerminal),
  security('Security', LucideIcons.shieldCheck),
  vault('Vault', LucideIcons.lockKeyhole),
  sync('Sync', LucideIcons.cloudCog);

  const SettingsSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _masterPasswordController = TextEditingController();
  final _backupPackageController = TextEditingController();
  final _vaultPasswordController = TextEditingController();
  SettingsSection _activeSection = SettingsSection.appearance;

  @override
  void dispose() {
    _masterPasswordController.dispose();
    _backupPackageController.dispose();
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
      localizedReason: 'Test Terly2 Biometric Lock',
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
          description: Text(
            'Please provide both Master Password and Backup Package JSON.',
          ),
        ),
      );
      return;
    }

    try {
      final db = ref.read(appDatabaseProvider);
      final syncService = ref.read(e2eeCloudSyncServiceProvider);
      final result = await syncService.importEncryptedBackup(
        backupPackageJson: backupJson,
        db: db,
        masterPassword: password,
      );

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

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide enough for the fixed section navigation the wireframe asks for;
        // below it the same sections become one grouped scroll.
        final showSectionNav = constraints.maxWidth >= _kSectionNavBreakpoint;
        return Scaffold(
          body: settingsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => TerlyEmptyState(
              icon: LucideIcons.triangleAlert,
              title: 'Settings could not be loaded',
              description: '$err',
            ),
            data: (settings) {
              final notifier = ref.read(settingsProvider.notifier);
              if (!showSectionNav) {
                return Column(
                  children: [
                    const TerlyPageHeader(
                      icon: LucideIcons.settings2,
                      title: 'Settings & Preferences',
                      description:
                          'Application, terminal, security and sync controls',
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          for (final section in SettingsSection.values) ...[
                            ..._sectionChildren(section, settings, notifier),
                            const SizedBox(height: 20),
                          ],
                          // Tunnels, snippets and workspaces are not among the
                          // five mobile tabs, so this is their entry point.
                          ..._buildToolsGroup(context),
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  const TerlyWorkToolbar(
                    title: 'Settings',
                    meta: 'changes apply immediately',
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSectionNav(context),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                            children: _sectionChildren(
                              _activeSection,
                              settings,
                              notifier,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSectionNav(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Container(
      width: tokens.sectionNavWidth,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(right: BorderSide(color: tokens.border)),
      ),
      child: ListView(
        children: [
          for (final section in SettingsSection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: TerlyNavItem(
                itemKey: Key('settings_section_${section.name}'),
                icon: section.icon,
                label: section.label,
                selected: section == _activeSection,
                onTap: () => setState(() => _activeSection = section),
              ),
            ),
        ],
      ),
    );
  }

  /// Secondary modules that have no mobile tab of their own.
  List<Widget> _buildToolsGroup(BuildContext context) {
    return [
      _buildSectionHeader('Tools', LucideIcons.blocks),
      ShadCard(
        child: Column(
          children: [
            for (final entry in const [
              ('/tunnels', 'Tunnels', LucideIcons.network),
              ('/snippets', 'Snippets & Runbooks', LucideIcons.zap),
              ('/workspaces', 'Workspaces', LucideIcons.panelTop),
            ])
              // ShadCard paints its own background, so the tile needs a
              // transparent Material of its own for ink to stay visible.
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  key: Key('settings_tool_${entry.$1.substring(1)}'),
                  leading: Icon(entry.$3, size: 18),
                  title: Text(entry.$2),
                  trailing: const Icon(LucideIcons.chevronRight, size: 16),
                  onTap: () => GoRouter.maybeOf(context)?.go(entry.$1),
                ),
              ),
          ],
        ),
      ),
    ];
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
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current: ${settings.palette.name.toUpperCase()}'),
                      if (settings.themeMode == ThemeMode.light) ...[
                        const SizedBox(height: 4),
                        const ShadBadge.secondary(
                          child: Text(
                            'Light mode uses default Light Slate theme',
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: ShadSelect<AppPalette>(
                    key: const Key('settings_palette_dropdown'),
                    initialValue: settings.palette,
                    selectedOptionBuilder: (context, value) {
                      switch (value) {
                        case AppPalette.dark:
                          return const Text('Terly Graphite');
                        case AppPalette.oled:
                          return const Text('Terly OLED');
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
                      ShadOption(
                        value: AppPalette.dark,
                        child: Text('Terly Graphite'),
                      ),
                      ShadOption(
                        value: AppPalette.oled,
                        child: Text('Terly OLED'),
                      ),
                      ShadOption(
                        value: AppPalette.catppuccin,
                        child: Text('Catppuccin'),
                      ),
                      ShadOption(value: AppPalette.nord, child: Text('Nord')),
                      ShadOption(
                        value: AppPalette.dracula,
                        child: Text('Dracula'),
                      ),
                      ShadOption(
                        value: AppPalette.solarizedDark,
                        child: Text('Solarized Dark'),
                      ),
                      ShadOption(
                        value: AppPalette.tokyoNight,
                        child: Text('Tokyo Night'),
                      ),
                      ShadOption(
                        value: AppPalette.gruvbox,
                        child: Text('Gruvbox'),
                      ),
                      ShadOption(
                        value: AppPalette.oneDark,
                        child: Text('One Dark'),
                      ),
                    ],
                    onChanged: (palette) {
                      if (palette != null) {
                        notifier.setPalette(palette);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
                    'Current: ${settings.terminalPalette.name.toUpperCase()}',
                  ),
                  trailing: ShadSelect<TerminalPalette>(
                    key: const Key('settings_terminal_palette_dropdown'),
                    initialValue: settings.terminalPalette,
                    selectedOptionBuilder: (context, value) {
                      switch (value) {
                        case TerminalPalette.dark:
                          return const Text('Dark Default');
                        case TerminalPalette.oled:
                          return const Text('OLED True Black');
                        case TerminalPalette.catppuccin:
                          return const Text('Catppuccin Macchiato');
                        case TerminalPalette.nord:
                          return const Text('Nord');
                        case TerminalPalette.dracula:
                          return const Text('Dracula');
                        case TerminalPalette.solarizedDark:
                          return const Text('Solarized Dark');
                        case TerminalPalette.tokyoNight:
                          return const Text('Tokyo Night');
                        case TerminalPalette.gruvboxDark:
                          return const Text('Gruvbox Dark');
                        case TerminalPalette.oneDark:
                          return const Text('One Dark');
                        case TerminalPalette.monokai:
                          return const Text('Monokai Pro');
                        case TerminalPalette.cyberpunk:
                          return const Text('Cyberpunk');
                      }
                    },
                    options: const [
                      ShadOption(
                        value: TerminalPalette.dark,
                        child: Text('Dark Default'),
                      ),
                      ShadOption(
                        value: TerminalPalette.oled,
                        child: Text('OLED True Black'),
                      ),
                      ShadOption(
                        value: TerminalPalette.catppuccin,
                        child: Text('Catppuccin Macchiato'),
                      ),
                      ShadOption(
                        value: TerminalPalette.nord,
                        child: Text('Nord'),
                      ),
                      ShadOption(
                        value: TerminalPalette.dracula,
                        child: Text('Dracula'),
                      ),
                      ShadOption(
                        value: TerminalPalette.solarizedDark,
                        child: Text('Solarized Dark'),
                      ),
                      ShadOption(
                        value: TerminalPalette.tokyoNight,
                        child: Text('Tokyo Night'),
                      ),
                      ShadOption(
                        value: TerminalPalette.gruvboxDark,
                        child: Text('Gruvbox Dark'),
                      ),
                      ShadOption(
                        value: TerminalPalette.oneDark,
                        child: Text('One Dark'),
                      ),
                      ShadOption(
                        value: TerminalPalette.monokai,
                        child: Text('Monokai Pro'),
                      ),
                      ShadOption(
                        value: TerminalPalette.cyberpunk,
                        child: Text('Cyberpunk'),
                      ),
                    ],
                    onChanged: (palette) {
                      if (palette != null) {
                        notifier.setTerminalPalette(palette);
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
                      switch (value) {
                        case 'JetBrainsMono':
                          return const Text('JetBrains Mono');
                        case 'FiraCode':
                          return const Text('Fira Code');
                        case 'SourceCodePro':
                          return const Text('Source Code Pro');
                        case 'Inconsolata':
                          return const Text('Inconsolata');
                        case 'Hack':
                          return const Text('Hack');
                        case 'CascadiaCode':
                          return const Text('Cascadia Code');
                        case 'SpaceMono':
                          return const Text('Space Mono');
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
                      ShadOption(
                        value: 'RobotoMono',
                        child: Text('Roboto Mono'),
                      ),
                      ShadOption(
                        value: 'JetBrainsMono',
                        child: Text('JetBrains Mono'),
                      ),
                      ShadOption(value: 'FiraCode', child: Text('Fira Code')),
                      ShadOption(
                        value: 'SourceCodePro',
                        child: Text('Source Code Pro'),
                      ),
                      ShadOption(
                        value: 'Inconsolata',
                        child: Text('Inconsolata'),
                      ),
                      ShadOption(value: 'Hack', child: Text('Hack')),
                      ShadOption(
                        value: 'CascadiaCode',
                        child: Text('Cascadia Code'),
                      ),
                      ShadOption(value: 'SpaceMono', child: Text('Space Mono')),
                      ShadOption(value: 'Inter', child: Text('Inter')),
                      ShadOption(value: 'Courier', child: Text('Courier')),
                    ],
                    onChanged: (font) {
                      if (font != null) {
                        notifier.setFontFamily(font);
                      }
                    },
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
        ];
      case SettingsSection.vault:
        return [
          // --- Section 3: Vault Master Password ---
          _buildSectionHeader('Vault Master Password', LucideIcons.lockKeyhole),
          _buildVaultMasterPasswordCard(),
        ];
      case SettingsSection.sync:
        return [
          // --- Section 4: Zero-Knowledge E2EE Cloud Sync ---
          _buildSectionHeader(
            'Zero-Knowledge E2EE Cloud Sync',
            LucideIcons.cloudCog,
          ),
          ShadCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Encrypt database records locally with AES-256-GCM using Argon2id key derivation.',
                  style: TextStyle(
                    fontSize: 13,
                    color: TerlyTokens.resolve(context).textMuted,
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ShadButton(
                        key: const Key('export_backup_button'),
                        onPressed: _handleExportE2EEBackup,
                        leading: const Icon(LucideIcons.download, size: 16),
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
                  placeholder: const Text(
                    '{"schema_version": 1, "salt": "...", "payload": "..."}',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ShadButton(
                        key: const Key('import_backup_button'),
                        onPressed: _handleImportE2EEBackup,
                        leading: const Icon(LucideIcons.upload, size: 16),
                        backgroundColor: TerlyTokens.resolve(context).warning,
                        child: const Text('Import Encrypted Backup'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ];
    }
  }

  /// Live preview so a font, size or ligature change is visible in place —
  /// there is no save step to confirm it against.
  Widget _buildTerminalPreview(AppSettingsModel settings) {
    final tokens = TerlyTokens.resolve(context);
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
                      'after every app restart before identity secrets can be used.'
                : 'Without a master password your vault key is protected only by the '
                      'operating system keychain. Setting one wraps the key with '
                      'Argon2id + AES-256-GCM. Existing identities stay readable.',
            style: TextStyle(
              fontSize: 13,
              color: TerlyTokens.resolve(context).textMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (isConfigured)
            Row(
              children: [
                Expanded(
                  child: ShadButton.outline(
                    key: const Key('lock_vault_button'),
                    onPressed: vaultStatus == VaultStatus.locked
                        ? null
                        : () => ref.read(vaultProvider.notifier).lock(),
                    leading: const Icon(LucideIcons.lock, size: 16),
                    child: Text(
                      vaultStatus == VaultStatus.locked
                          ? 'Vault Locked'
                          : 'Lock Vault Now',
                    ),
                  ),
                ),
              ],
            )
          else ...[
            ShadInput(
              key: const Key('vault_master_password_field'),
              controller: _vaultPasswordController,
              obscureText: true,
              placeholder: const Text('New master password (min 8 characters)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ShadButton(
                    key: const Key('set_master_password_button'),
                    onPressed: _handleSetMasterPassword,
                    leading: const Icon(LucideIcons.lockKeyhole, size: 16),
                    child: const Text('Set Master Password'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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
    final tokens = TerlyTokens.resolve(context);
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
