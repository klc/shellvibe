#!/usr/bin/env python3
"""Cut the tray icon's state variants from the base icons.

The tray shows three states (see `TrayIconState` in
lib/app/window/tray_icon_state.dart): the plain icon, a tunnel forwarding, and
an error that happened while the window was out of sight. The plain icons are
hand-cut from icon.png (see assets/brand/README.md); the variants are those
same files with a badge in the bottom-right corner, so the glyph never moves
between states.

  * macOS menu bar (tray_macos*.png) is a template image: the system tints it
    from its alpha alone, so colour cannot carry the state. The badge is a
    shape instead: a dot for "tunnel active", a triangle for "error", each
    inside a transparent ring that keeps it apart from the glyph.
  * Windows and Linux (tray*.png, tray*.ico) keep the plate and take a green
    dot for "tunnel active" and a red one for "error", on a dark ring.

Re-run after the base icons change:

    python3 tool/gen_tray_icons.py

Requires Pillow.
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRAND = os.path.join(ROOT, "assets", "brand")

# Drawn at this multiple and downsampled, so the badge edges are anti-aliased
# at 16px as well as at 64px.
SCALE = 8

GREEN = (34, 197, 94, 255)
RED = (239, 68, 68, 255)
RING = (14, 16, 22, 255)


def _badge_mask(size, triangle, ring):
    """A mask of the badge (and, with [ring], of the clearance around it)."""
    big = size * SCALE
    mask = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(mask)
    radius = size * (0.21 if triangle else 0.22) * SCALE
    if ring:
        radius += size * 0.06 * SCALE
    # Centre in the bottom-right corner, far enough in that the ring is not
    # clipped by the canvas edge.
    cx = cy = size * 0.73 * SCALE
    if triangle:
        # Triangle, point up: reads as "attention" without colour.
        draw.polygon(
            [
                (cx, cy - radius),
                (cx + radius * 1.05, cy + radius * 0.8),
                (cx - radius * 1.05, cy + radius * 0.8),
            ],
            fill=255,
        )
    else:
        draw.ellipse(
            [cx - radius, cy - radius, cx + radius, cy + radius], fill=255
        )
    return mask.resize((size, size), Image.LANCZOS)


def _with_badge(base, kind, color):
    """[base] with a badge of [kind]. [color] None means template mode."""
    size = base.width
    out = base.convert("RGBA")
    # Only a template needs the shape to say what colour would.
    triangle = color is None and kind == "error"
    ring = _badge_mask(size, triangle, ring=True)
    badge = _badge_mask(size, triangle, ring=False)

    if color is None:
        # Template: punch the clearance out of the glyph, then lay the badge
        # in solid black. Only alpha matters to the system.
        alpha = out.getchannel("A")
        alpha = Image.composite(Image.new("L", out.size, 0), alpha, ring)
        alpha = Image.composite(Image.new("L", out.size, 255), alpha, badge)
        black = Image.new("RGBA", out.size, (0, 0, 0, 255))
        black.putalpha(alpha)
        return black

    out.paste(Image.new("RGBA", out.size, RING), mask=ring)
    out.paste(Image.new("RGBA", out.size, color), mask=badge)
    return out


VARIANTS = {"tunnel": GREEN, "error": RED}


def main():
    mac = Image.open(os.path.join(BRAND, "tray_macos.png"))
    for kind in VARIANTS:
        _with_badge(mac, kind, None).save(
            os.path.join(BRAND, f"tray_macos_{kind}.png")
        )

    png = Image.open(os.path.join(BRAND, "tray.png"))
    for kind, color in VARIANTS.items():
        _with_badge(png, kind, color).save(os.path.join(BRAND, f"tray_{kind}.png"))

    ico = Image.open(os.path.join(BRAND, "tray.ico"))
    sizes = sorted(ico.ico.sizes())
    for kind, color in VARIANTS.items():
        frames = [_with_badge(ico.ico.getimage(s), kind, color) for s in sizes]
        frames[-1].save(
            os.path.join(BRAND, f"tray_{kind}.ico"),
            format="ICO",
            sizes=sizes,
            append_images=frames[:-1],
        )


if __name__ == "__main__":
    main()
