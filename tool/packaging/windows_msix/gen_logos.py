#!/usr/bin/env python3
"""Draw the MSIX visual assets from assets/brand/icon.png.

The package manifest names each logo once (Assets\\Square44x44Logo.png and so
on); the files here carry the scale and target-size qualifiers Windows picks
between through resources.pri, which windows_msix.ps1 builds with makepri.

Rerun after changing the master icon:

    python3 tool/packaging/windows_msix/gen_logos.py

Requires Pillow.
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
MASTER = os.path.join(ROOT, "assets", "brand", "icon.png")
OUT = os.path.join(HERE, "Assets")

# name -> (width, height) at scale 100
SQUARE = {
    "Square44x44Logo": 44,
    "Square150x150Logo": 150,
    "SmallTile": 71,
    "StoreLogo": 50,
}
SCALES = (100, 200, 400)
# The taskbar, Start list and Alt+Tab ask for these sizes directly.
TARGET_SIZES = (16, 24, 32, 48, 256)


def square(master, size):
    return master.resize((size, size), Image.LANCZOS)


def wide(master, width, height):
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    icon = square(master, height)
    canvas.paste(icon, ((width - height) // 2, 0), icon)
    return canvas


def main():
    master = Image.open(MASTER).convert("RGBA")
    os.makedirs(OUT, exist_ok=True)
    for old in os.listdir(OUT):
        if old.endswith(".png"):
            os.remove(os.path.join(OUT, old))

    for name, size in SQUARE.items():
        for scale in SCALES:
            px = size * scale // 100
            square(master, px).save(
                os.path.join(OUT, f"{name}.scale-{scale}.png"), optimize=True
            )
    for scale in SCALES:
        w, h = 310 * scale // 100, 150 * scale // 100
        wide(master, w, h).save(
            os.path.join(OUT, f"Wide310x150Logo.scale-{scale}.png"), optimize=True
        )
    for size in TARGET_SIZES:
        icon = square(master, size)
        for suffix in ("", "_altform-unplated", "_altform-lightunplated"):
            icon.save(
                os.path.join(OUT, f"Square44x44Logo.targetsize-{size}{suffix}.png"),
                optimize=True,
            )


if __name__ == "__main__":
    main()
