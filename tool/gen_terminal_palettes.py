#!/usr/bin/env python3
"""Generate lib/features/terminal/domain/models/terminal_palette_data.dart.

11 existing themes are transcribed verbatim from terminal_screen.dart;
17 new themes are parsed from mbadolato/iTerm2-Color-Schemes .itermcolors
(plist) files in /tmp/schemes.
"""
import pathlib
import glob
import os
import plistlib

SCHEME_DIR = "/tmp/schemes"

import os
import urllib.parse
import urllib.request

API = "https://api.github.com/repos/mbadolato/iTerm2-Color-Schemes/contents/schemes"


def ensure_scheme_files():
    """Download any missing .itermcolors via the GitHub contents API."""
    os.makedirs(SCHEME_DIR, exist_ok=True)
    for _, _, filename in NEW_THEMES:
        local = os.path.join(SCHEME_DIR, filename)
        if os.path.exists(local):
            continue
        quoted = urllib.parse.quote(filename)
        req = urllib.request.Request(
            f"{API}/{quoted}",
            headers={"Accept": "application/vnd.github.raw+json"},
        )
        with urllib.request.urlopen(req) as resp:
            with open(local, "wb") as f:
                f.write(resp.read())
        print(f"fetched {filename}")


# Relative to the repository root, so this runs anywhere the repo is checked out.
REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = str(REPO_ROOT / "lib/features/terminal/domain/models/terminal_palette_data.dart")

# (enumValue, label, filename) — order defines Settings dropdown order.
NEW_THEMES = [
    ("catppuccinMocha", "Catppuccin Mocha", "Catppuccin Mocha.itermcolors"),
    ("catppuccinLatte", "Catppuccin Latte", "Catppuccin Latte.itermcolors"),
    ("rosePine", "Rosé Pine", "Rose Pine.itermcolors"),
    ("rosePineMoon", "Rosé Pine Moon", "Rose Pine Moon.itermcolors"),
    ("kanagawaWave", "Kanagawa Wave", "Kanagawa Wave.itermcolors"),
    ("everforestDark", "Everforest Dark", "Everforest Dark Med.itermcolors"),
    ("ayuMirage", "Ayu Mirage", "Ayu Mirage.itermcolors"),
    ("material", "Material", "Material.itermcolors"),
    ("doomOne", "Doom One", "Doom One.itermcolors"),
    ("nightOwl", "Night Owl", "Night Owl.itermcolors"),
    ("synthwave84", "SynthWave '84", "Synthwave.itermcolors"),
    ("horizon", "Horizon", "Horizon.itermcolors"),
    ("snazzy", "Snazzy", "Snazzy.itermcolors"),
    ("githubDarkDimmed", "GitHub Dark Dimmed", "GitHub Dark Dimmed.itermcolors"),
    ("solarizedLight", "Solarized Light", "iTerm2 Solarized Light.itermcolors"),
    ("gruvboxLight", "Gruvbox Light", "Gruvbox Light.itermcolors"),
    ("oneLight", "One Light", "Atom One Light.itermcolors"),
]

# Existing 11 themes — transcribed verbatim from terminal_screen.dart.
EXISTING = """    TerminalPaletteData(
      palette: TerminalPalette.dark,
      label: 'Dark Default',
      theme: TerminalTheme(
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
      ),
    ),
    TerminalPaletteData(
      palette: TerminalPalette.oled,
      label: 'OLED True Black',
      theme: TerminalTheme(
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
      ),
    ),
    TerminalPaletteData(
      palette: TerminalPalette.catppuccin,
      label: 'Catppuccin Macchiato',
      theme: TerminalTheme(
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
      ),
    ),
    TerminalPaletteData(
      palette: TerminalPalette.nord,
      label: 'Nord',
      theme: TerminalTheme(
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
      ),
    ),
    TerminalPaletteData(
      palette: TerminalPalette.dracula,
      label: 'Dracula',
      theme: TerminalTheme(
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
      ),
    ),
    TerminalPaletteData(
      palette: TerminalPalette.solarizedDark,
      label: 'Solarized Dark',
      theme: TerminalTheme(
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
      ),
    ),
    TerminalPaletteData(
      palette: TerminalPalette.tokyoNight,
      label: 'Tokyo Night',
      theme: TerminalTheme(
        cursor: const Color(0xFF7AA2F7),
        selection: const Color(0xFF33467C),
        foreground: const Color(0xFFA9B1D6),
        background: const Color(0xFF1A1B26),
        black: const Color(0xFF15161E),
        red: const Color(0xFFF7768E),
        green: const Color(0xFF9ECE6A),
        yellow: const Color(0xFFE0AF68),
        blue: const Color(0xFF7AA2F7),
        magenta: const Color(0xFFBB9AF7),
        cyan: const Color(0xFF7DCFFF),
        white: const Color(0xFFA9B1D6),
        brightBlack: const Color(0xFF414868),
        brightRed: const Color(0xFFF7768E),
        brightGreen: const Color(0xFF9ECE6A),
        brightYellow: const Color(0xFFE0AF68),
        brightBlue: const Color(0xFF7AA2F7),
        brightMagenta: const Color(0xFFBB9AF7),
        brightCyan: const Color(0xFF7DCFFF),
        brightWhite: const Color(0xFFC0CAF5),
        searchHitBackground: const Color(0xFF7AA2F7),
        searchHitBackgroundCurrent: const Color(0xFFBB9AF7),
        searchHitForeground: const Color(0xFF1A1B26),
      ),
    ),
    TerminalPaletteData(
      palette: TerminalPalette.gruvboxDark,
      label: 'Gruvbox Dark',
      theme: TerminalTheme(
        cursor: const Color(0xFFFE8019),
        selection: const Color(0xFF504945),
        foreground: const Color(0xFFEBDBB2),
        background: const Color(0xFF282828),
        black: const Color(0xFF282828),
        red: const Color(0xFFCC241D),
        green: const Color(0xFF98971A),
        yellow: const Color(0xFFD79921),
        blue: const Color(0xFF458588),
        magenta: const Color(0xFFB16286),
        cyan: const Color(0xFF689D6A),
        white: const Color(0xFFA89984),
        brightBlack: const Color(0xFF928374),
        brightRed: const Color(0xFFFB4934),
        brightGreen: const Color(0xFFB8BB26),
        brightYellow: const Color(0xFFFABD2F),
        brightBlue: const Color(0xFF83A598),
        brightMagenta: const Color(0xFFD3869B),
        brightCyan: const Color(0xFF8EC07C),
        brightWhite: const Color(0xFFEBDBB2),
        searchHitBackground: const Color(0xFFFE8019),
        searchHitBackgroundCurrent: const Color(0xFFFABD2F),
        searchHitForeground: const Color(0xFF282828),
      ),
    ),
    TerminalPaletteData(
      palette: TerminalPalette.oneDark,
      label: 'One Dark',
      theme: TerminalTheme(
        cursor: const Color(0xFF528BFF),
        selection: const Color(0xFF3E4451),
        foreground: const Color(0xFFABB2BF),
        background: const Color(0xFF282C34),
        black: const Color(0xFF1E2127),
        red: const Color(0xFFE06C75),
        green: const Color(0xFF98C379),
        yellow: const Color(0xFFE5C07B),
        blue: const Color(0xFF61AFEF),
        magenta: const Color(0xFFC678DD),
        cyan: const Color(0xFF56B6C2),
        white: const Color(0xFFABB2BF),
        brightBlack: const Color(0xFF5C6370),
        brightRed: const Color(0xFFBE5046),
        brightGreen: const Color(0xFF98C379),
        brightYellow: const Color(0xFFD19A66),
        brightBlue: const Color(0xFF61AFEF),
        brightMagenta: const Color(0xFFC678DD),
        brightCyan: const Color(0xFF56B6C2),
        brightWhite: const Color(0xFFFFFFFF),
        searchHitBackground: const Color(0xFF61AFEF),
        searchHitBackgroundCurrent: const Color(0xFFC678DD),
        searchHitForeground: const Color(0xFF282C34),
      ),
    ),
    TerminalPaletteData(
      palette: TerminalPalette.monokai,
      label: 'Monokai Pro',
      theme: TerminalTheme(
        cursor: const Color(0xFFFFD866),
        selection: const Color(0xFF403E41),
        foreground: const Color(0xFFFCFCFA),
        background: const Color(0xFF2D2A2E),
        black: const Color(0xFF2D2A2E),
        red: const Color(0xFFFF6188),
        green: const Color(0xFFA9DC76),
        yellow: const Color(0xFFFFD866),
        blue: const Color(0xFF78DCE8),
        magenta: const Color(0xFFAB9DF2),
        cyan: const Color(0xFF78DCE8),
        white: const Color(0xFFFCFCFA),
        brightBlack: const Color(0xFF727072),
        brightRed: const Color(0xFFFF6188),
        brightGreen: const Color(0xFFA9DC76),
        brightYellow: const Color(0xFFFFD866),
        brightBlue: const Color(0xFF78DCE8),
        brightMagenta: const Color(0xFFAB9DF2),
        brightCyan: const Color(0xFF78DCE8),
        brightWhite: const Color(0xFFFFFFFF),
        searchHitBackground: const Color(0xFFFFD866),
        searchHitBackgroundCurrent: const Color(0xFFFF6188),
        searchHitForeground: const Color(0xFF2D2A2E),
      ),
    ),
    TerminalPaletteData(
      palette: TerminalPalette.cyberpunk,
      label: 'Cyberpunk',
      theme: TerminalTheme(
        cursor: const Color(0xFF00FF9F),
        selection: const Color(0xFF3A1C71),
        foreground: const Color(0xFF00F0FF),
        background: const Color(0xFF120E24),
        black: const Color(0xFF100C1E),
        red: const Color(0xFFFF0055),
        green: const Color(0xFF00FF9F),
        yellow: const Color(0xFFFFE600),
        blue: const Color(0xFF00F0FF),
        magenta: const Color(0xFFFF007F),
        cyan: const Color(0xFF00FFFF),
        white: const Color(0xFFFFFFFF),
        brightBlack: const Color(0xFF4A3E6D),
        brightRed: const Color(0xFFFF3377),
        brightGreen: const Color(0xFF33FFAF),
        brightYellow: const Color(0xFFFFEB33),
        brightBlue: const Color(0xFF33F3FF),
        brightMagenta: const Color(0xFFFF3399),
        brightCyan: const Color(0xFF33FFFF),
        brightWhite: const Color(0xFFFFFFFF),
        searchHitBackground: const Color(0xFF00FF9F),
        searchHitBackgroundCurrent: const Color(0xFFFF007F),
        searchHitForeground: const Color(0xFF120E24),
      ),
    ),"""


def hex_color(comps):
    """(Red/Green/Blue Component floats 0-1) -> 0xFFRRGGBB."""
    r = int(round(comps["Red Component"] * 255))
    g = int(round(comps["Green Component"] * 255))
    b = int(round(comps["Blue Component"] * 255))
    return f"0xFF{r:02X}{g:02X}{b:02X}"


def load_scheme(path):
    with open(path, "rb") as f:
        data = plistlib.load(f)
    return data


def gen_entry(enum_value, label, scheme):
    ansi = [f"const Color({hex_color(scheme[f'Ansi {i} Color'])})" for i in range(16)]
    bg = hex_color(scheme["Background Color"])
    fg = hex_color(scheme["Foreground Color"])
    cursor = hex_color(scheme.get("Cursor Color", scheme["Foreground Color"]))
    selection = hex_color(scheme.get("Selection Color", scheme["Ansi 8 Color"]))
    names = [
        "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
        "brightBlack", "brightRed", "brightGreen", "brightYellow",
        "brightBlue", "brightMagenta", "brightCyan", "brightWhite",
    ]
    color_lines = "\n".join(
        f"        {name}: {ansi[i]},"
        for i, name in enumerate(names)
    )
    label_esc = label.replace("'", "\\'")
    return f"""    TerminalPaletteData(
      palette: TerminalPalette.{enum_value},
      label: '{label_esc}',
      theme: TerminalTheme(
        cursor: const Color({cursor}),
        selection: const Color({selection}),
        foreground: const Color({fg}),
        background: const Color({bg}),
        {color_lines}
        searchHitBackground: const Color({hex_color(scheme['Ansi 4 Color'])}),
        searchHitBackgroundCurrent: const Color({hex_color(scheme['Ansi 3 Color'])}),
        searchHitForeground: const Color({bg}),
      ),
    ),"""


def main():
    ensure_scheme_files()
    new_entries = []
    for enum_value, label, filename in NEW_THEMES:
        path = os.path.join(SCHEME_DIR, filename)
        scheme = load_scheme(path)
        new_entries.append(gen_entry(enum_value, label, scheme))

    dart = f"""// Terminal color scheme registry.
//
// Existing themes are transcribed from the original definitions in
// terminal_screen.dart; new themes are parsed from the
// mbadolato/iTerm2-Color-Schemes collection (.itermcolors).
// Regenerate the new entries with `python3 tool/gen_terminal_palettes.py`;
// the hex values in this file are the source of truth.
import 'package:flutter/material.dart';
import 'package:xterm3/xterm.dart';

import 'terminal_palette.dart';

/// A selectable terminal color scheme shown in Settings.
class TerminalPaletteData {{
  const TerminalPaletteData({{
    required this.palette,
    required this.label,
    required this.theme,
  }});

  final TerminalPalette palette;
  final String label;
  final TerminalTheme theme;

  static TerminalPaletteData of(TerminalPalette palette) =>
      kTerminalPalettes.firstWhere((p) => p.palette == palette);

  static TerminalTheme themeOf(TerminalPalette palette) => of(palette).theme;
}}

/// All selectable terminal color schemes, in Settings dropdown order.
const kTerminalPalettes = <TerminalPaletteData>[
{EXISTING}
{chr(10).join(new_entries)}
];
"""
    with open(OUT, "w") as f:
        f.write(dart)
    print(f"Wrote {OUT}: {len(dart)} chars, {11 + len(new_entries)} entries")


if __name__ == "__main__":
    main()