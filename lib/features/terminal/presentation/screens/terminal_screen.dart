import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../domain/models/terminal_tab_session.dart';
import '../widgets/mobile_extra_keys_bar.dart';

class TerminalScreen extends StatefulWidget {
  final TerminalTabSession session;
  final bool showExtraKeys;

  const TerminalScreen({
    super.key,
    required this.session,
    this.showExtraKeys = true,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  // Catppuccin Macchiato Dark Terminal Theme Palette
  static final _terminalTheme = TerminalTheme(
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

  @override
  Widget build(BuildContext context) {
    final session = widget.session;

    return Column(
      children: [
        if (session.isConnecting)
          const LinearProgressIndicator(
            backgroundColor: Color(0xFF24273A),
            color: Color(0xFF8AADF4),
          ),
        if (session.errorMessage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.red.shade900,
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Connection Error: ${session.errorMessage}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Container(
            color: const Color(0xFF24273A),
            child: TerminalView(
              session.terminal,
              theme: _terminalTheme,
              textStyle: const TerminalStyle(
                fontSize: 14,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        if (widget.showExtraKeys)
          MobileExtraKeysBar(
            terminal: session.terminal,
          ),
      ],
    );
  }
}
