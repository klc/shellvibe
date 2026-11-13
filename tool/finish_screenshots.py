#!/usr/bin/env python3
"""Frame and scale the captures from integration_test/site_screenshots_test.dart.

The test writes 2560x1600 PNGs of the Flutter view only; the macOS window
buttons are native and never reach it. This draws them where the hidden
title bar leaves room for them, scales to 1280x800 and writes:

  docs/screenshots/<name>.png        the README images
  <site>/<name>[-crop].webp          with --site, the shellvibe.dev images:
                                     lossless, cropped from the top

  python3 tool/finish_screenshots.py --site ../shellvibe-server/public/img/shots
"""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "build" / "screenshots"
DOCS = ROOT / "docs" / "screenshots"

# Site image -> height kept from the top of the 1280x800 shot. None: whole.
SITE = {
    "terminal-split": None,
    "sftp": None,
    "ai-access": None,
    "pane-menu-crop": 700,
    "command-palette-crop": 523,
    "hosts-crop": 380,
    "tunnels-crop": 370,
    "snippets-crop": 310,
    "workspaces-crop": 380,
    "vault-crop": 320,
    "terminal-settings-crop": 700,
}

# Close, minimise, zoom: centres and radius at 1x, as macOS draws them.
LIGHTS = [((13, 12.5), "#FF5F57"), ((31.5, 12.5), "#FEBC2E"), ((50, 12.5), "#28C840")]
RADIUS = 5.75


def finish(path: Path) -> Image.Image:
    im = Image.open(path).convert("RGB")
    scale = im.width / 1280
    draw = ImageDraw.Draw(im)
    for (x, y), colour in LIGHTS:
        r = RADIUS * scale
        draw.ellipse(
            (x * scale - r, y * scale - r, x * scale + r, y * scale + r),
            fill=colour,
        )
    return im.resize((1280, 800), Image.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--site", type=Path, help="shellvibe.dev public/img/shots")
    args = parser.parse_args()

    shots = {p.stem: finish(p) for p in sorted(SRC.glob("*.png"))}
    if not shots:
        raise SystemExit(f"no captures in {SRC}; run the integration test first")

    DOCS.mkdir(parents=True, exist_ok=True)
    for name, im in shots.items():
        im.save(DOCS / f"{name}.png", optimize=True)

    if args.site:
        for target, height in SITE.items():
            im = shots[target.removesuffix("-crop")]
            if height:
                im = im.crop((0, 0, 1280, height))
            im.save(args.site / f"{target}.webp", lossless=True, method=6)
        # Open Graph scrapers still read PNG more reliably than WebP.
        shots["terminal-split"].save(args.site / "terminal-split.png", optimize=True)

    print(f"{len(shots)} shots -> {DOCS}" + (f", {args.site}" if args.site else ""))


if __name__ == "__main__":
    main()
