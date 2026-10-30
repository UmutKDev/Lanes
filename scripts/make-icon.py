#!/usr/bin/env python3
"""Draws Lanes's app icon: three lanes side by side on a dark tile, one per
account colour. Writes every size the macOS AppIcon set needs.

Usage: python3 scripts/make-icon.py  (needs Pillow)
"""
import json
import os

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "Lanes", "Assets.xcassets", "AppIcon.appiconset")
S = 4096  # drawn large, scaled down
LANES = [(0x3B, 0x82, 0xF6), (0xA8, 0x55, 0xF7), (0xF5, 0x9E, 0x0B)]


def vertical_gradient(size, top, bottom):
    img = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        img.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img.resize((size, size))


def draw():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Apple's macOS grid: an 824/1024 tile with a 185/1024 corner radius.
    tile = round(S * 824 / 1024)
    radius = round(S * 185 / 1024)
    origin = (S - tile) // 2

    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (origin, origin + S // 80, origin + tile, origin + tile + S // 80), radius, fill=(0, 0, 0, 110))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(S // 60)))

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((origin, origin, origin + tile, origin + tile), radius, fill=255)
    background = vertical_gradient(S, (0x26, 0x2A, 0x3B), (0x10, 0x12, 0x1C)).convert("RGBA")
    img.paste(background, (0, 0), mask)

    lane_w = round(tile * 0.16)
    gap = round(tile * 0.085)
    total = 3 * lane_w + 2 * gap
    left = origin + (tile - total) // 2
    top = origin + round(tile * 0.2)
    heights = [0.6, 0.6, 0.6]
    offsets = [0.06, 0.0, 0.12]
    for i, (color, h, off) in enumerate(zip(LANES, heights, offsets)):
        x = left + i * (lane_w + gap)
        y = top + round(tile * off)
        lane = vertical_gradient(S, tuple(min(255, c + 40) for c in color), color).convert("RGBA")
        lane_mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(lane_mask).rounded_rectangle(
            (x, y, x + lane_w, y + round(tile * h)), lane_w // 2, fill=255)
        img.paste(lane, (0, 0), lane_mask)
    return img


def main():
    master = draw()
    images = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
            images.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
