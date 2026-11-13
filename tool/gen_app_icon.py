#!/usr/bin/env python3
"""Draw the ShellVibe app icon, its per-platform variants and the tray icons.

The mark is the shell prompt itself: a heavy chevron followed by a block
cursor, off-white and amber on a flat graphite plate. No gradient, no glow.
Every measurement below is in the units of a 100px reference tile, so the
proportions stay fixed whatever canvas a variant renders at.

One run writes, into assets/brand/:

  * icon.png                    — the master. A rounded plate inside ~10%
                                  transparent padding, which is the shape macOS
                                  and Windows expect. Also the in-app mark.
  * icon_light.png              — the master on a pale plate: the in-app mark
                                  under the light theme.
  * icon_ios.png                — the plate at full bleed, flattened. iOS masks
                                  the corners itself and rejects alpha.
  * icon_android_foreground.png — the glyph alone, centred inside the adaptive
                                  icon safe zone, over a transparent canvas.
  * tray.png, tray.ico          — the plate at full bleed, 64px and 16–64px,
                                  for the Windows and Linux trays.
  * tray_macos.png              — the glyph alone in black: a menu bar template
                                  image the system tints.

After changing anything here:

    python3 tool/gen_app_icon.py
    python3 tool/gen_tray_icons.py
    dart run flutter_launcher_icons
    python3 tool/gen_app_icon.py --patch-small

The last pass redraws the 16px launcher icons, which flutter_launcher_icons can
only downsample. Requires Pillow.
"""
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRAND = os.path.join(ROOT, "assets", "brand")
SIZE = 1024

# The reference tile. Every measurement below is in its units.
TILE = 100.0
PLATE_RADIUS = 22.0
PLATE_BORDER = 0.6

# The chevron is a stroked polyline with round caps and joins; the cursor a
# block exactly as tall as the chevron's ink, round caps included (its
# centreline plus half the stroke above and below).
CHEVRON = ((27.0, 33.0), (45.0, 50.0), (27.0, 67.0))
CHEVRON_STROKE = 9.0
CURSOR = (55.0, 28.5, 72.0, 71.5)
CURSOR_RADIUS = 2.0

# The menu bar template has no plate to frame it, so its glyph is heavier and
# fills the box.
TEMPLATE_CHEVRON = ((18.0, 26.0), (42.0, 50.0), (18.0, 74.0))
TEMPLATE_STROKE = 13.0
TEMPLATE_CURSOR = (56.0, 19.5, 80.0, 80.5)
TEMPLATE_CURSOR_RADIUS = 3.0

# The master keeps the plate inside 10% padding on every side.
PAD = 0.0977  # 100/1024, matching the icon this replaces

PLATE = (28, 28, 28)  # #1C1C1C
BORDER = (255, 255, 255, 23)  # rgba(255,255,255,0.09)
INK = (237, 237, 234)  # #EDEDEA
ACCENT = (229, 162, 60)  # #E5A23C

# The in-app mark under the light theme: the same drawing inverted, with the
# light theme's own accent so the cursor reads on a pale plate.
LIGHT = {
    "plate": (246, 246, 244),  # #F6F6F4
    "border": (0, 0, 0, 26),  # rgba(0,0,0,0.1)
    "ink": (26, 26, 24),  # #1A1A18
    "accent": (154, 90, 0),  # #9A5A00
}
DARK = {"plate": PLATE, "border": BORDER, "ink": INK, "accent": ACCENT}

# Android masks adaptive icons down to the middle 66%; 58% leaves a little air.
SAFE_ZONE = 0.58

TRAY_PNG = 64
TRAY_ICO_SIZES = (16, 24, 32, 48, 64)
TRAY_MACOS = 36

# Below this the chevron and the cursor fall into each other, so the small
# tile keeps the cursor alone.
SMALL = 20

# Generated icons small enough that only the cursor survives, and whether each
# one keeps the master's padding. See patch_small.
SMALL_TARGETS = (
    ("macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png", True),
)

# Supersampling factor. The chevron is a diagonal and the plate's corners are
# large radii, so both want more than the rasteriser's own antialiasing.
SS = 4


def _centre_shift(chevron, stroke, cursor):
    """How far right to move the mark so its ink sits centred in the tile."""
    left = min(x for x, _ in chevron) - stroke / 2
    return TILE / 2 - (left + cursor[2]) / 2


def _draw_mark(draw, unit, chevron, stroke, cursor, radius, ink, accent, dx=0.0):
    """The chevron and cursor at `unit` pixels per tile unit."""
    dx += _centre_shift(chevron, stroke, cursor)
    points = [((x + dx) * unit, y * unit) for x, y in chevron]
    width = round(stroke * unit)
    draw.line(points, fill=ink, width=width, joint="curve")
    # Pillow has no round line caps; a disc on each end stands in for them.
    r = width / 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - r, y - r, x + r, y + r), fill=ink)
    x0, y0, x1, y1 = cursor
    draw.rounded_rectangle(
        ((x0 + dx) * unit, y0 * unit, (x1 + dx) * unit, y1 * unit),
        radius=round(radius * unit),
        fill=accent,
    )


def _plate(side, rounded, colors=DARK):
    """The flat plate with its hairline border."""
    plate = Image.new("RGBA", (side, side), colors["plate"] + (255,))
    if not rounded:
        # A full-bleed plate has no edge of its own: iOS rounds it, and a
        # border would only draw a seam inside that mask.
        return plate
    unit = side / TILE
    radius = round(PLATE_RADIUS * unit)
    mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, side - 1, side - 1), radius=radius, fill=255
    )
    plate.putalpha(mask)
    ImageDraw.Draw(plate).rounded_rectangle(
        (0, 0, side - 1, side - 1),
        radius=radius,
        outline=colors["border"],
        width=max(1, round(PLATE_BORDER * unit)),
    )
    return plate


def _tile(side, rounded, colors=DARK):
    """A full plate with the mark on it, at `side` pixels."""
    big = side * SS
    plate = _plate(big, rounded, colors)
    _draw_mark(
        ImageDraw.Draw(plate),
        big / TILE,
        CHEVRON,
        CHEVRON_STROKE,
        CURSOR,
        CURSOR_RADIUS,
        colors["ink"],
        colors["accent"],
    )
    return plate.resize((side, side), Image.LANCZOS)


def _small_tile(side):
    """The plate with the cursor alone, grown to the mark's height."""
    work = 256  # drawn here, then resized down
    unit = work / TILE
    tile = _plate(work, rounded=True)
    x0, y0, x1, y1 = CURSOR
    half_w = (x1 - x0) / 2 * unit
    half_h = (y1 - y0) / 2 * unit * 1.15
    middle = work / 2
    ImageDraw.Draw(tile).rounded_rectangle(
        (middle - half_w, middle - half_h, middle + half_w, middle + half_h),
        radius=round(CURSOR_RADIUS * unit),
        fill=ACCENT + (255,),
    )
    return tile.resize((side, side), Image.LANCZOS)


def write_master():
    paths = []
    for name, colors in (("icon.png", DARK), ("icon_light.png", LIGHT)):
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        inset = round(SIZE * PAD)
        canvas.alpha_composite(
            _tile(SIZE - inset * 2, rounded=True, colors=colors), (inset, inset)
        )
        path = os.path.join(BRAND, name)
        canvas.save(path)
        paths.append(path)
    return paths


def write_ios():
    path = os.path.join(BRAND, "icon_ios.png")
    _tile(SIZE, rounded=False).convert("RGB").save(path)
    return [path]


def write_android_foreground():
    side = SIZE * SS
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    _draw_mark(
        ImageDraw.Draw(canvas),
        side / TILE,
        CHEVRON,
        CHEVRON_STROKE,
        CURSOR,
        CURSOR_RADIUS,
        INK,
        ACCENT,
    )
    glyph = canvas.crop(canvas.getbbox())
    scale = SIZE * SAFE_ZONE / max(glyph.size)
    glyph = glyph.resize(
        (round(glyph.width * scale), round(glyph.height * scale)), Image.LANCZOS
    )
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.alpha_composite(glyph, ((SIZE - glyph.width) // 2, (SIZE - glyph.height) // 2))
    path = os.path.join(BRAND, "icon_android_foreground.png")
    out.save(path)
    return [path]


def write_tray():
    png = os.path.join(BRAND, "tray.png")
    _tile(TRAY_PNG, rounded=True).save(png)

    frames = [
        _small_tile(s) if s < SMALL else _tile(s, rounded=True)
        for s in TRAY_ICO_SIZES
    ]
    ico = os.path.join(BRAND, "tray.ico")
    frames[-1].save(
        ico,
        format="ICO",
        sizes=[(s, s) for s in TRAY_ICO_SIZES],
        append_images=frames[:-1],
    )

    # Template image: only alpha matters, so draw black on transparent.
    big = TRAY_MACOS * SS
    mac = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    black = (0, 0, 0, 255)
    _draw_mark(
        ImageDraw.Draw(mac),
        big / TILE,
        TEMPLATE_CHEVRON,
        TEMPLATE_STROKE,
        TEMPLATE_CURSOR,
        TEMPLATE_CURSOR_RADIUS,
        black,
        black,
    )
    macos = os.path.join(BRAND, "tray_macos.png")
    mac.resize((TRAY_MACOS, TRAY_MACOS), Image.LANCZOS).save(macos)
    return [png, ico, macos]


def patch_small():
    """Redraw the 16px launcher icons as the cursor alone.

    flutter_launcher_icons has no per-size hook, so this runs after it and
    overwrites the sizes it downsampled into mush.
    """
    written = []
    for relative, padded in SMALL_TARGETS:
        path = os.path.join(ROOT, *relative.split("/"))
        if not os.path.exists(path):
            continue
        side = Image.open(path).size[0]
        inset = round(side * PAD) if padded else 0
        out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        out.alpha_composite(_small_tile(side - inset * 2), (inset, inset))
        out.save(path)
        written.append(path)
    return written


def main():
    if "--patch-small" in sys.argv:
        paths = patch_small()
    else:
        paths = (
            write_master() + write_ios() + write_android_foreground() + write_tray()
        )
    for path in paths:
        print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
