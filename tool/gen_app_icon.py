#!/usr/bin/env python3
"""Draw the ShellVibe app icon and its per-platform variants.

The mark is the shell prompt itself: a monospace chevron followed by a block
cursor, indigo on a dark plate. Everything below is that design's geometry
expressed against a 160px reference tile, so the proportions stay fixed no
matter which canvas a variant renders at.

Three files come out of one run:

  * icon.png                    — the master. A rounded plate inside ~10%
                                  transparent padding, which is the shape macOS
                                  and Windows expect.
  * icon_ios.png                — the plate at full bleed, flattened. iOS masks
                                  the corners itself and rejects alpha.
  * icon_android_foreground.png — the glyph alone, centred inside the adaptive
                                  icon safe zone, over a transparent canvas.

After changing anything here:

    python3 tool/gen_app_icon.py
    dart run flutter_launcher_icons
    python3 tool/gen_app_icon.py --patch-small

The last pass redraws the 16px icons, which flutter_launcher_icons can only
downsample. Requires Pillow.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
FONT = os.path.join(ASSETS, "fonts", "nerd", "JetBrainsMonoNerdFontMono-Regular.ttf")
SIZE = 1024

# The design's reference tile. Every measurement below is in its units.
TILE = 160.0
PLATE_RADIUS = 36.0
CHEVRON_SIZE = 66.0  # font-size of the '>'
CHEVRON_WEIGHT = 0.012  # stroke added to the 400 cut to read as the design's 500
CURSOR_W = 22.0
CURSOR_H = 52.0
CURSOR_RADIUS = 4.0
GAP = 10.0  # between the chevron's ink and the cursor
GLOW_BLUR = 12.0  # the CSS glow is a 24px blur radius, i.e. sigma 12
PLATE_BORDER = 1.0

# The master keeps the plate inside 10% padding on every side.
PAD = 0.0977  # 100/1024, matching the icon this replaces

PLATE_TOP = (28, 32, 50)  # #1C2032
PLATE_BOTTOM = (16, 18, 32)  # #101220
ACCENT = (139, 147, 255)  # #8B93FF
GLOW_ALPHA = 0.45
BORDER = (255, 255, 255, 23)  # rgba(255,255,255,0.09)
HIGHLIGHT = (255, 255, 255, 23)  # the inset top highlight

# Android masks adaptive icons down to the middle 66%; 58% leaves a little air.
SAFE_ZONE = 0.58

# Generated icons small enough that only the cursor survives, and whether each
# one keeps the master's padding. See patch_small.
SMALL_TARGETS = (
    ("macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png", True),
    ("web/favicon.png", False),
)

# Supersampling factor. The chevron is a thin diagonal and the plate's corners
# are large radii, so both want more than the rasteriser's own antialiasing.
SS = 4


def _gradient(size, top, bottom):
    """A vertical gradient, one row at a time."""
    column = Image.new("RGB", (1, size))
    pixels = column.load()
    for y in range(size):
        f = y / (size - 1)
        pixels[0, y] = tuple(
            round(top[i] + (bottom[i] - top[i]) * f) for i in range(3)
        )
    return column.resize((size, size), Image.NEAREST)


def _chevron_mask(box, unit):
    """The '>' rendered from JetBrains Mono, cropped to its own ink.

    Returns the mask and the size it occupies, so the caller can lay the mark
    out from the glyph's real ink rather than from the font's advance width.
    """
    size = round(CHEVRON_SIZE * unit)
    font = ImageFont.truetype(FONT, size)
    # Draw into a scratch canvas large enough that no side of the glyph clips.
    scratch = Image.new("L", (box, box), 0)
    # The bundled JetBrains Mono is the 400 cut and the design sets the chevron
    # at 500, so thicken the stroke to make up the difference.
    ImageDraw.Draw(scratch).text(
        (box // 2, box // 2),
        ">",
        font=font,
        fill=255,
        anchor="mm",
        stroke_width=round(size * CHEVRON_WEIGHT),
        stroke_fill=255,
    )
    return scratch.crop(scratch.getbbox())


def _mark(canvas, unit, glow):
    """Draw the chevron and cursor, centred, onto an RGBA canvas."""
    chevron = _chevron_mask(canvas.size[0], unit)
    cursor_w = round(CURSOR_W * unit)
    cursor_h = round(CURSOR_H * unit)
    gap = round(GAP * unit)

    width = chevron.width + gap + cursor_w
    left = (canvas.size[0] - width) // 2
    middle = canvas.size[1] // 2

    ink = Image.new("L", canvas.size, 0)
    ink.paste(chevron, (left, middle - chevron.height // 2))
    ImageDraw.Draw(ink).rounded_rectangle(
        (
            left + chevron.width + gap,
            middle - cursor_h // 2,
            left + width - 1,
            middle + cursor_h - cursor_h // 2 - 1,
        ),
        radius=round(CURSOR_RADIUS * unit),
        fill=255,
    )

    if glow:
        halo = Image.new("RGBA", canvas.size, ACCENT + (0,))
        halo.putalpha(
            ink.filter(ImageFilter.GaussianBlur(GLOW_BLUR * unit)).point(
                lambda v: round(v * GLOW_ALPHA)
            )
        )
        canvas.alpha_composite(halo)

    mark = Image.new("RGBA", canvas.size, ACCENT + (0,))
    mark.putalpha(ink)
    canvas.alpha_composite(mark)
    return ink


def _plate(side, rounded):
    """The gradient plate, with its hairline border and top highlight."""
    plate = _gradient(side, PLATE_TOP, PLATE_BOTTOM).convert("RGBA")
    unit = side / TILE
    if rounded:
        mask = Image.new("L", (side, side), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, side - 1, side - 1), radius=round(PLATE_RADIUS * unit), fill=255
        )
        plate.putalpha(mask)

    if not rounded:
        # A full-bleed plate has no edge of its own: iOS rounds it, and a
        # border or top highlight would only draw a seam inside that mask.
        return plate

    border = max(1, round(PLATE_BORDER * unit))
    draw = ImageDraw.Draw(plate)
    draw.rounded_rectangle(
        (0, 0, side - 1, side - 1),
        radius=round(PLATE_RADIUS * unit),
        outline=BORDER,
        width=border,
    )
    # inset 0 1px 0 — a highlight along the top edge, kept clear of the corner
    # arcs so it fades into the border instead of ending on a hard cap.
    inset = round(PLATE_RADIUS * unit)
    draw.rectangle((inset, border, side - 1 - inset, border * 2 - 1), fill=HIGHLIGHT)
    return plate


def _tile(side, rounded):
    """A full plate with the mark on it, at `side` pixels."""
    plate = _plate(side * SS, rounded)
    _mark(plate, side * SS / TILE, glow=True)
    return plate.resize((side, side), Image.LANCZOS)


def write_master():
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    inset = round(SIZE * PAD)
    canvas.alpha_composite(_tile(SIZE - inset * 2, rounded=True), (inset, inset))
    path = os.path.join(ASSETS, "icon.png")
    canvas.save(path)
    return path


def write_ios():
    path = os.path.join(ASSETS, "icon_ios.png")
    _tile(SIZE, rounded=False).convert("RGB").save(path)
    return path


def write_android_foreground():
    side = SIZE * SS
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    # The safe zone is the whole budget for the mark, so lay it out on a canvas
    # sized to the mark's own reference width and scale that down into place.
    _mark(canvas, side / TILE, glow=False)
    glyph = canvas.crop(canvas.getbbox())
    scale = SIZE * SAFE_ZONE / max(glyph.size)
    glyph = glyph.resize(
        (round(glyph.width * scale), round(glyph.height * scale)), Image.LANCZOS
    )
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.alpha_composite(
        glyph, ((SIZE - glyph.width) // 2, (SIZE - glyph.height) // 2)
    )
    path = os.path.join(ASSETS, "icon_android_foreground.png")
    out.save(path)
    return path


def patch_small():
    """Redraw the 16px icons as the cursor alone.

    The design drops the chevron below 20px, where the two shapes fall into
    each other. flutter_launcher_icons has no per-size hook, so this runs after
    it and overwrites the sizes it downsampled into mush.
    """
    work = 256  # drawn here, then resized down to whatever the target is
    unit = work / TILE
    tile = _plate(work, rounded=True)
    # The cursor keeps its width but grows to the height the whole mark had, so
    # the tile stays as filled as it is at the sizes above this one.
    half_w, half_h = round(CURSOR_W * unit / 2), round(CHEVRON_SIZE * unit / 2)
    middle = work // 2
    ImageDraw.Draw(tile).rounded_rectangle(
        (middle - half_w, middle - half_h, middle + half_w, middle + half_h),
        radius=round(CURSOR_RADIUS * unit),
        fill=ACCENT + (255,),
    )

    written = []
    for relative, padded in SMALL_TARGETS:
        path = os.path.join(ROOT, *relative.split("/"))
        if not os.path.exists(path):
            continue
        side = Image.open(path).size[0]
        inset = round(side * PAD) if padded else 0
        out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        out.alpha_composite(
            tile.resize((side - inset * 2,) * 2, Image.LANCZOS), (inset, inset)
        )
        out.save(path)
        written.append(path)
    return written


def main():
    if "--patch-small" in sys.argv:
        paths = patch_small()
    else:
        paths = [write_master(), write_ios(), write_android_foreground()]
    for path in paths:
        print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
