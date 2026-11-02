#!/usr/bin/env python3
"""Draws the extension's icons: the app icon in the sizes Safari asks for,
and a monochrome toolbar glyph (three tilted cards, like the app icon).
Safari tints the toolbar glyph itself, so only its alpha matters.
Run: python3 LanesSafari/Tests/make-icons.py (needs Pillow)."""
import pathlib
from PIL import Image, ImageDraw

here = pathlib.Path(__file__).resolve().parent
repo = here.parent.parent
out = here.parent / "Resources" / "icons"
out.mkdir(parents=True, exist_ok=True)

app = Image.open(repo / "scripts" / "AppIcon-1024.png").convert("RGBA")
for size in (48, 96, 128, 256, 512):
    app.resize((size, size), Image.LANCZOS).save(out / f"icon-{size}.png", optimize=True)


def glyph(size):
    scale = 8
    big = size * scale
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    s = big / 32.0
    # Three cards, back to front: outline for the back two, filled front.
    cards = [(7.5, 4.6, 0.55), (6.4, 9.4, 0.8), (5.3, 14.2, 1.0)]
    for i, (x, y, alpha) in enumerate(cards):
        layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        box = [x * s, y * s, (x + 19.5) * s, (y + 12.5) * s]
        a = int(255 * alpha)
        if i == len(cards) - 1:
            d.rounded_rectangle(box, radius=3.2 * s, fill=(0, 0, 0, a))
            # the little bar on the front card, cut out
            d.rounded_rectangle([(x + 3.2) * s, (y + 3.2) * s, (x + 9.5) * s, (y + 5.0) * s], radius=0.9 * s, fill=(0, 0, 0, 0))
        else:
            d.rounded_rectangle(box, radius=3.2 * s, outline=(0, 0, 0, a), width=int(1.7 * s))
        layer = layer.rotate(14, resample=Image.BICUBIC, center=(big / 2, big / 2))
        canvas = Image.alpha_composite(canvas, layer)
    return canvas.resize((size, size), Image.LANCZOS)


for size in (16, 19, 32, 38):
    glyph(size).save(out / f"toolbar-{size}.png", optimize=True)
print("ok")
