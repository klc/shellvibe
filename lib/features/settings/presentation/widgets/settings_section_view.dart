import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:xterm3/xterm.dart';

import '../../../../app/notifications/notification_providers.dart';
import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/theme/ui_font.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/mosh_prediction_mode.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../account/presentation/widgets/account_settings_section.dart';
import '../../../cloud_backup/presentation/widgets/cloud_backup_section.dart';
import '../../../cloud_backup/presentation/widgets/sync_section.dart';
import '../../../device_link/presentation/widgets/paired_devices_settings_section.dart';
import '../../../mcp/presentation/widgets/mcp_access_settings_section.dart';
import '../../../terminal/domain/models/terminal_font.dart';
import '../../../terminal/domain/models/terminal_palette.dart';
import '../../../terminal/domain/models/terminal_palette_data.dart';
import '../../../terminal/presentation/utils/terminal_font_resolver.dart';
import '../../domain/models/app_settings_model.dart';
import '../../domain/models/settings_section.dart';
import '../notifiers/settings_notifier.dart';
import 'about_settings_section.dart';
import 'keyboard_shortcuts_settings_section.dart';
import 'known_hosts_settings_section.dart';
import 'file_backup_section.dart';
import 'launch_at_login_tile.dart';
import 'vault_master_password_section.dart';

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
                    selectedOptionBuilder: (context, value) =>
                        _ThemeModeLabel(mode: value),
                    options: [
                      for (final mode in const [
                        ThemeMode.dark,
                        ThemeMode.light,
                        ThemeMode.system,
                      ])
                        ShadOption(
                          value: mode,
                          child: _ThemeModeLabel(mode: mode),
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
                    selectedOptionBuilder: (context, value) =>
                        Text(value.label),
                    options: [
                      for (final p in _kPaletteOrder)
                        ShadOption(value: p, child: Text(p.label)),
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
                        ShadOption(value: f.id, child: Text(f.label)),
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
                child: Column(
                  children: [
                    SwitchListTile(
                      key: const Key('settings_keep_running_in_tray_switch'),
                      title: Text(
                        defaultTargetPlatform == TargetPlatform.macOS
                            ? 'Show in the Menu Bar'
                            : 'Keep Running in the System Tray',
                      ),
                      subtitle: Text(
                        defaultTargetPlatform == TargetPlatform.macOS
                            ? 'A menu bar icon shows active tunnels and '
                                  'sessions and brings the window back.'
                            : 'Closing the window hides it to the tray, so '
                                  'tunnels and sessions keep running. Quit '
                                  'from the tray menu.',
                      ),
                      value: settings.keepRunningInTray,
                      onChanged: (val) => notifier.setKeepRunningInTray(val),
                    ),
                    LaunchAtLoginTile(trayEnabled: settings.keepRunningInTray),
                    SwitchListTile(
                      key: const Key('settings_desktop_notifications_switch'),
                      title: const Text('Desktop Notifications'),
                      subtitle: const Text(
                        'Notify when a session drops, a tunnel stops or a '
                        'terminal asks for attention while the window is '
                        'hidden or in the background.',
                      ),
                      value: settings.desktopNotifications,
                      onChanged: (val) {
                        notifier.setDesktopNotifications(val);
                        // macOS asks for permission the first time it is
                        // needed, which is now if it is being turned on.
                        if (val) {
                          ref
                              .read(notificationPresenterProvider)
                              .ensurePermission()
                              .ignore();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ];
      case SettingsSection.terminal:
        // "Match App Theme" has no colours of its own: its swatch, icon and
        // preview are those of the scheme it resolves to right now.
        final resolvedTerminal = TerminalPaletteData.of(
          settings.resolvedTerminalPalette(Theme.of(context).brightness),
        );
        final followsApp = settings.terminalPalette == TerminalPalette.matchApp;
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
                    followsApp
                        ? 'Current: ${resolvedTerminal.label}, following the app theme'
                        : 'Current: ${resolvedTerminal.label}',
                  ),
                  trailing: ShadSelect<TerminalPalette>(
                    key: const Key('settings_terminal_palette_dropdown'),
                    initialValue: settings.terminalPalette,
                    selectedOptionBuilder: (context, value) {
                      if (value == TerminalPalette.matchApp) {
                        return _IconLabel(
                          icon: _brightnessIcon(
                            isLight: resolvedTerminal.isLight,
                          ),
                          label: 'Match App Theme',
                        );
                      }
                      final data = TerminalPaletteData.of(value);
                      return _IconLabel(
                        icon: _brightnessIcon(isLight: data.isLight),
                        label: data.label,
                      );
                    },
                    options: [
                      ShadOption(
                        value: TerminalPalette.matchApp,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PaletteSwatch(theme: resolvedTerminal.theme),
                            const SizedBox(width: 10),
                            const _IconLabel(
                              icon: LucideIcons.sunMoon,
                              label: 'Match App Theme',
                            ),
                          ],
                        ),
                      ),
                      for (final p in kTerminalPalettes)
                        ShadOption(
                          value: p.palette,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PaletteSwatch(theme: p.theme),
                              const SizedBox(width: 10),
                              _IconLabel(
                                icon: _brightnessIcon(isLight: p.isLight),
                                label: p.label,
                              ),
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
                    theme: resolvedTerminal.theme,
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
                    selectedOptionBuilder: (context, value) =>
                        Text(value.label),
                    options: [
                      for (final m in MoshPredictionMode.values)
                        ShadOption(value: m, child: Text(m.label)),
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
                    min: kTerminalFontSizeMin,
                    max: kTerminalFontSizeMax,
                    divisions: (kTerminalFontSizeMax - kTerminalFontSizeMin)
                        .toInt(),
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
                    selectedOptionBuilder: (context, value) =>
                        Text(value.label),
                    options: [
                      for (final c in AppCursorStyle.values)
                        ShadOption(value: c, child: Text(c.label)),
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
                    selectedOptionBuilder: (context, value) =>
                        Text(_kAutoLockLabels[value] ?? 'Disabled'),
                    options: [
                      for (final e in _kAutoLockLabels.entries)
                        ShadOption(value: e.key, child: Text(e.value)),
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
                    selectedOptionBuilder: (context, value) =>
                        Text(_kClipboardClearLabels[value] ?? 'Disabled'),
                    options: [
                      for (final e in _kClipboardClearLabels.entries)
                        ShadOption(value: e.key, child: Text(e.value)),
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
      case SettingsSection.keyboard:
        return [
          _buildSectionHeader('Keyboard Shortcuts', LucideIcons.keyboard),
          const KeyboardShortcutsSettingsSection(),
        ];
      case SettingsSection.vault:
        return [
          // --- Section 3: Vault Master Password ---
          _buildSectionHeader('Vault Master Password', LucideIcons.lockKeyhole),
          const VaultMasterPasswordSection(),
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
          const FileBackupSection(),
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
      // settings.fontFamily is a font id, not a family name.
      fontFamily: resolveTerminalFontFamily(settings.fontFamily),
      fontFamilyFallback: kTerminalFontFamilyFallback,
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

/// OLED leads because it is the default the app ships with; the list under
/// it stays alphabetical.
const _kPaletteOrder = [
  AppPalette.oled,
  AppPalette.dark,
  AppPalette.teal,
  AppPalette.catppuccin,
  AppPalette.dracula,
  AppPalette.gruvbox,
  AppPalette.nord,
  AppPalette.oneDark,
  AppPalette.solarizedDark,
  AppPalette.tokyoNight,
];

/// Seconds to label, in menu order. Zero is off.
const _kAutoLockLabels = {
  0: 'Disabled',
  30: '30 Seconds',
  60: '1 Minute',
  300: '5 Minutes',
};

const _kClipboardClearLabels = {
  0: 'Disabled',
  15: '15 Seconds',
  30: '30 Seconds',
  60: '60 Seconds',
};

/// A sun or a moon in front of a scheme's name, so light and dark schemes can
/// be told apart in the alphabetical list without reading the swatches.
IconData _brightnessIcon({required bool isLight}) =>
    isLight ? LucideIcons.sun : LucideIcons.moon;

/// A muted icon set tight against its label, for dropdown rows.
class _IconLabel extends StatelessWidget {
  const _IconLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: ShellVibeTokens.resolve(context).textMuted),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _ThemeModeLabel extends StatelessWidget {
  const _ThemeModeLabel({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      ThemeMode.dark => const _IconLabel(icon: LucideIcons.moon, label: 'Dark'),
      ThemeMode.light => const _IconLabel(
        icon: LucideIcons.sun,
        label: 'Light',
      ),
      ThemeMode.system => const _IconLabel(
        icon: LucideIcons.monitor,
        label: 'System',
      ),
    };
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
        // A childless DecoratedBox takes the smallest height it is allowed,
        // and a Row hands its children a loose one: without the stretch the
        // chips lay out at zero height and the swatch is an empty gap.
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
