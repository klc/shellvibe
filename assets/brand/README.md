# Brand assets — not covered by the source licence

The image files in this directory are ShellVibe's identity, not its source
code. [`LICENSE`](../../LICENSE) does not grant any right to use them, and
[`TRADEMARK.md`](../../TRADEMARK.md) sets out the terms that do apply.

They live in their own directory precisely so that the boundary is visible in
the file tree: a fork replaces the contents of `assets/brand/` and keeps
everything else.

| File                          | Role                                                                                          |
| :---------------------------- | :-------------------------------------------------------------------------------------------- |
| `icon.png`                    | The master. A rounded plate inside ~10% padding; also the in-app mark.                          |
| `icon_ios.png`                | The plate at full bleed and flattened, because iOS applies its own mask and rejects alpha.      |
| `icon_android_foreground.png` | The glyph alone inside the adaptive-icon safe zone, composited over the background colour.      |
| `tray_macos.png`              | The glyph alone in black, 36px: a macOS menu bar template image, tinted by the system.          |
| `tray.png`, `tray.ico`        | The plate at 64px (and 16–64px in the `.ico`) for the Linux and Windows system trays.           |
| `tray_tunnel.*`, `tray_error.*`, `tray_macos_tunnel.png`, `tray_macos_error.png` | The tray icons with a badge: a forward is up, or something failed out of sight. Cut from the files above by `tool/gen_tray_icons.py`; macOS takes a dot and a triangle because a template image cannot carry colour. |

The tray icons are cut from `icon.png` by hand, not by `flutter_launcher_icons`;
redo them when the master changes, then run `python3 tool/gen_tray_icons.py` to
cut the badged variants from them. Regenerate the platform icons after
changing any of these:

```bash
dart run flutter_launcher_icons
```

The generated icons under `android/`, `ios/`, `macos/`, `windows/` and `web/`
are derived from these files and carry the same restriction.
