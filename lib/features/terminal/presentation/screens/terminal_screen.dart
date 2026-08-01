import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:xterm2/xterm.dart';

import '../../../settings/domain/models/app_settings_model.dart';
import '../../../settings/presentation/notifiers/settings_notifier.dart';
import '../../domain/models/terminal_tab_session.dart';
import '../widgets/mobile_extra_keys_bar.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  final TerminalTabSession session;
  final bool? showExtraKeys;

  const TerminalScreen({
    super.key,
    required this.session,
    this.showExtraKeys,
  });

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  // Dark Palette
  static final _darkTheme = TerminalTheme(
    cursor: const Color(0xFFA855F7),
    selection: const Color(0xFF3F3F46),
    foreground: const Color(0xFFF4F4F5),
    background: const Color(0xFF18181B),
    black: const Color(0xFF27272A),
    red: const Color(0xFFEF4444),
    green: const Color(0xFF22C55E),
    yellow: const Color(0xFFEAB308),
    blue: const Color(0xFF3B82F6),
    magenta: const Color(0xFFA855F7),
    cyan: const Color(0xFF06B6D4),
    white: const Color(0xFFE4E4E7),
    brightBlack: const Color(0xFF52525B),
    brightRed: const Color(0xFFF87171),
    brightGreen: const Color(0xFF4ADE80),
    brightYellow: const Color(0xFFFACC15),
    brightBlue: const Color(0xFF60A5FA),
    brightMagenta: const Color(0xFFC084FC),
    brightCyan: const Color(0xFF22D3EE),
    brightWhite: const Color(0xFFFAFAFA),
    searchHitBackground: const Color(0xFF6366F1),
    searchHitBackgroundCurrent: const Color(0xFFA855F7),
    searchHitForeground: const Color(0xFFFFFFFF),
  );

  // OLED Palette (True Black)
  static final _oledTheme = TerminalTheme(
    cursor: const Color(0xFF00E676),
    selection: const Color(0xFF263238),
    foreground: const Color(0xFFECEFF1),
    background: const Color(0xFF000000),
    black: const Color(0xFF212121),
    red: const Color(0xFFFF5252),
    green: const Color(0xFF00E676),
    yellow: const Color(0xFFFFD740),
    blue: const Color(0xFF40C4FF),
    magenta: const Color(0xFFE040FB),
    cyan: const Color(0xFF18FFFF),
    white: const Color(0xFFEEFFFF),
    brightBlack: const Color(0xFF424242),
    brightRed: const Color(0xFFFF8A80),
    brightGreen: const Color(0xFFB9F6CA),
    brightYellow: const Color(0xFFFFE57F),
    brightBlue: const Color(0xFF80D8FF),
    brightMagenta: const Color(0xFFEA80FC),
    brightCyan: const Color(0xFFA7FFEB),
    brightWhite: const Color(0xFFFFFFFF),
    searchHitBackground: const Color(0xFF00E676),
    searchHitBackgroundCurrent: const Color(0xFF18FFFF),
    searchHitForeground: const Color(0xFF000000),
  );

  // Catppuccin Macchiato Dark Terminal Theme Palette
  static final _catppuccinTheme = TerminalTheme(
    cursor: const Color(0xFFF4D9E1),
    selection: const Color(0xFF5B6078),
    foreground: const Color(0xFFCAD3F5),
    background: const Color(0xFF24273A),
    black: const Color(0xFF494D64),
    red: const Color(0xFFED8796),
    green: const Color(0xFFA6DA95),
    yellow: const Color(0xFFEED49F),
    blue: const Color(0xFF8AADF4),
    magenta: const Color(0xFFF5BDE6),
    cyan: const Color(0xFF8BD5CA),
    white: const Color(0xFFB8C0E0),
    brightBlack: const Color(0xFF5B6078),
    brightRed: const Color(0xFFED8796),
    brightGreen: const Color(0xFFA6DA95),
    brightYellow: const Color(0xFFEED49F),
    brightBlue: const Color(0xFF8AADF4),
    brightMagenta: const Color(0xFFF5BDE6),
    brightCyan: const Color(0xFF8BD5CA),
    brightWhite: const Color(0xFFA5ADCB),
    searchHitBackground: const Color(0xFFF5E0DC),
    searchHitBackgroundCurrent: const Color(0xFFF38BA8),
    searchHitForeground: const Color(0xFF1E1E2E),
  );

  // Nord Palette
  static final _nordTheme = TerminalTheme(
    cursor: const Color(0xFFD8DEE9),
    selection: const Color(0xFF434C5E),
    foreground: const Color(0xFFD8DEE9),
    background: const Color(0xFF2E3440),
    black: const Color(0xFF3B4252),
    red: const Color(0xFFBF616A),
    green: const Color(0xFFA3BE8C),
    yellow: const Color(0xFFEBCB8B),
    blue: const Color(0xFF81A1C1),
    magenta: const Color(0xFFB48EAD),
    cyan: const Color(0xFF88C0D0),
    white: const Color(0xFFE5E9F0),
    brightBlack: const Color(0xFF4C566A),
    brightRed: const Color(0xFFD08770),
    brightGreen: const Color(0xFFA3BE8C),
    brightYellow: const Color(0xFFEBCB8B),
    brightBlue: const Color(0xFF5E81AC),
    brightMagenta: const Color(0xFFB48EAD),
    brightCyan: const Color(0xFF8FBCBB),
    brightWhite: const Color(0xFFECEFF4),
    searchHitBackground: const Color(0xFF88C0D0),
    searchHitBackgroundCurrent: const Color(0xFF81A1C1),
    searchHitForeground: const Color(0xFF2E3440),
  );

  // Dracula Palette
  static final _draculaTheme = TerminalTheme(
    cursor: const Color(0xFFF8F8F2),
    selection: const Color(0xFF44475A),
    foreground: const Color(0xFFF8F8F2),
    background: const Color(0xFF282A36),
    black: const Color(0xFF21222C),
    red: const Color(0xFFFF5555),
    green: const Color(0xFF50FA7B),
    yellow: const Color(0xFFF1FA8C),
    blue: const Color(0xFFBD93F9),
    magenta: const Color(0xFFFF79C6),
    cyan: const Color(0xFF8BE9FD),
    white: const Color(0xFFF8F8F2),
    brightBlack: const Color(0xFF6272A4),
    brightRed: const Color(0xFFFF6E6E),
    brightGreen: const Color(0xFF69FF94),
    brightYellow: const Color(0xFFFFFFA5),
    brightBlue: const Color(0xFFD6ACFF),
    brightMagenta: const Color(0xFFFF92D0),
    brightCyan: const Color(0xFFA4FFFF),
    brightWhite: const Color(0xFFFFFFFF),
    searchHitBackground: const Color(0xFFBD93F9),
    searchHitBackgroundCurrent: const Color(0xFFFF79C6),
    searchHitForeground: const Color(0xFF282A36),
  );

  // Solarized Dark Palette
  static final _solarizedDarkTheme = TerminalTheme(
    cursor: const Color(0xFF93A1A1),
    selection: const Color(0xFF073642),
    foreground: const Color(0xFF839496),
    background: const Color(0xFF002B36),
    black: const Color(0xFF073642),
    red: const Color(0xFFDC322F),
    green: const Color(0xFF859900),
    yellow: const Color(0xFFB58900),
    blue: const Color(0xFF268BD2),
    magenta: const Color(0xFFD33682),
    cyan: const Color(0xFF2AA198),
    white: const Color(0xFFEEE8D5),
    brightBlack: const Color(0xFF002B36),
    brightRed: const Color(0xFFCB4B16),
    brightGreen: const Color(0xFF586E75),
    brightYellow: const Color(0xFF657B83),
    brightBlue: const Color(0xFF839496),
    brightMagenta: const Color(0xFF6C71C4),
    brightCyan: const Color(0xFF93A1A1),
    brightWhite: const Color(0xFFFDF6E3),
    searchHitBackground: const Color(0xFF2AA198),
    searchHitBackgroundCurrent: const Color(0xFF268BD2),
    searchHitForeground: const Color(0xFF002B36),
  );

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final settingsAsync = ref.watch(settingsNotifierProvider);
    final settings = settingsAsync.value ?? const AppSettingsModel();

    final theme = switch (settings.terminalPalette) {
      TerminalPalette.dark => _darkTheme,
      TerminalPalette.oled => _oledTheme,
      TerminalPalette.catppuccin => _catppuccinTheme,
      TerminalPalette.nord => _nordTheme,
      TerminalPalette.dracula => _draculaTheme,
      TerminalPalette.solarizedDark => _solarizedDarkTheme,
    };

    final shouldShowExtraKeys = widget.showExtraKeys ??
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);

    return Column(
      children: [
        if (session.isConnecting)
          LinearProgressIndicator(
            backgroundColor: theme.background,
            color: theme.blue,
          ),
        if (session.errorMessage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: ShadTheme.of(context).colorScheme.destructive,
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: ShadTheme.of(context).colorScheme.destructiveForeground,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Connection Error: ${session.errorMessage}',
                    style: TextStyle(
                      color: ShadTheme.of(context).colorScheme.destructiveForeground,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Container(
            color: theme.background,
            child: TerminalView(
              session.terminal,
              theme: theme,
              autofocus: true,
              cursorType: switch (settings.cursorStyle) {
                AppCursorStyle.block => TerminalCursorType.block,
                AppCursorStyle.underline => TerminalCursorType.underline,
                AppCursorStyle.bar => TerminalCursorType.verticalBar,
              },
              textStyle: TerminalStyle(
                fontSize: settings.fontSize,
                fontFamily: settings.fontFamily,
              ),
            ),
          ),
        ),
        if (shouldShowExtraKeys)
          MobileExtraKeysBar(
            terminal: session.terminal,
          ),
      ],
    );
  }
}
