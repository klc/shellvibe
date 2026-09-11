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

Regenerate the platform icons after changing any of these:

```bash
dart run flutter_launcher_icons
```

The generated icons under `android/`, `ios/`, `macos/`, `windows/` and `web/`
are derived from these files and carry the same restriction.
