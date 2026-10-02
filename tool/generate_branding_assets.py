"""P02 — RailMate BD launcher icon + splash mark generator.

Generates a teal, rounded, train/rail launcher mark (no tiny text) at every
Android density, plus adaptive-icon layers and the native splash bitmap.

Run:  python tool/generate_branding_assets.py
Deterministic: no randomness, no network. Re-running reproduces byte-identical
output so CI/evidence hashes stay stable.
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw

# Brand palette (mirrors lib/design/tokens/app_colors.dart).
DEEP_TEAL = (14, 90, 102)  # #0E5A66 primary
DEEPER = (10, 67, 76)  # #0A434C
ACCENT = (30, 158, 106)  # #1E9E6A success green
WHITE = (255, 255, 255)

RES = os.path.join("android", "app", "src", "main", "res")

# Launcher icon sizes per density bucket.
LAUNCHER = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
# Adaptive foreground: 108dp canvas, 72dp visible safe zone.
FOREGROUND = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}
# Play-store style large icon.
PLAY_STORE = 512


def _rounded_mask(size: int, radius_ratio: float = 0.22) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=int(size * radius_ratio), fill=255
    )
    return mask


def _draw_mark(draw: ImageDraw.ImageDraw, size: int, colour: tuple, rail: tuple) -> None:
    """Draw the RailMate BD mark: a train nose on rails inside a circle cue.

    Geometry is expressed as fractions of `size` so every density and the
    adaptive foreground render identically.
    """
    cx = size / 2.0
    body_w = size * 0.50
    body_h = size * 0.42
    top = size * 0.24

    # Train body (rounded, flat bottom).
    draw.rounded_rectangle(
        (cx - body_w / 2, top, cx + body_w / 2, top + body_h),
        radius=size * 0.10,
        fill=colour,
    )
    # Windshield.
    draw.rounded_rectangle(
        (
            cx - body_w * 0.30,
            top + body_h * 0.16,
            cx + body_w * 0.30,
            top + body_h * 0.46,
        ),
        radius=size * 0.035,
        fill=DEEPER,
    )
    # Two headlights.
    lamp_r = size * 0.035
    lamp_y = top + body_h * 0.74
    for sign in (-1, 1):
        draw.ellipse(
            (
                cx + sign * body_w * 0.28 - lamp_r,
                lamp_y - lamp_r,
                cx + sign * body_w * 0.28 + lamp_r,
                lamp_y + lamp_r,
            ),
            fill=rail,
        )
    # Rails: two converging sleepers below the body.
    rail_y = top + body_h + size * 0.055
    draw.rounded_rectangle(
        (cx - size * 0.20, rail_y, cx - size * 0.155, rail_y + size * 0.20),
        radius=size * 0.01,
        fill=rail,
    )
    draw.rounded_rectangle(
        (cx + size * 0.155, rail_y, cx + size * 0.20, rail_y + size * 0.20),
        radius=size * 0.01,
        fill=rail,
    )
    # Sleeper ties connecting the rails.
    for offset in (size * 0.01, size * 0.085, size * 0.16):
        draw.rounded_rectangle(
            (
                cx - size * 0.20,
                rail_y + offset,
                cx + size * 0.20,
                rail_y + offset + size * 0.018,
            ),
            radius=size * 0.009,
            fill=rail,
        )


def build_launcher(size: int) -> Image.Image:
    """Legacy square/rounded launcher icon: teal plate + white mark."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    plate = Image.new("RGBA", (size, size), DEEP_TEAL + (255,))
    img.paste(plate, (0, 0), _rounded_mask(size))
    mark_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    _draw_mark(ImageDraw.Draw(mark_layer), size, WHITE, ACCENT)
    img.alpha_composite(mark_layer)
    return img


def build_adaptive_foreground(size: int) -> Image.Image:
    """Adaptive foreground: mark scaled into the 72dp safe zone, transparent."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    safe = int(size * (72 / 108))
    offset = (size - safe) // 2
    mark = Image.new("RGBA", (safe, safe), (0, 0, 0, 0))
    _draw_mark(ImageDraw.Draw(mark), safe, WHITE, ACCENT)
    img.alpha_composite(mark, (offset, offset))
    return img


def build_splash_logo(size: int) -> Image.Image:
    """Splash mark on transparent: used by the native launch_background."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    _draw_mark(ImageDraw.Draw(img), size, WHITE, ACCENT)
    return img


def main() -> None:
    for folder, size in LAUNCHER.items():
        out = os.path.join(RES, folder, "ic_launcher.png")
        build_launcher(size).save(out, "PNG", optimize=True)
        print(f"launcher  {out} ({size}px)")

    for folder, size in FOREGROUND.items():
        out = os.path.join(RES, folder, "ic_launcher_foreground.png")
        build_adaptive_foreground(size).save(out, "PNG", optimize=True)
        print(f"adaptive {out} ({size}px)")

    splash = build_splash_logo(288)
    out = os.path.join(RES, "drawable-xxhdpi", "splash_logo.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    splash.save(out, "PNG", optimize=True)
    print(f"splash    {out} (288px)")

    play = build_launcher(PLAY_STORE)
    out = os.path.join("docs", "branding", "play_store_icon_512.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    play.save(out, "PNG", optimize=True)
    print(f"play      {out} (512px)")


if __name__ == "__main__":
    main()
