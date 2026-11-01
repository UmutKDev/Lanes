#!/usr/bin/env python3
"""Writes every size the macOS AppIcon set needs from scripts/AppIcon-1024.png.

The icon is drawn in scripts/AppIcon.svg: three glass panes in the account
colours, stacked and tilted, the front one the account in use. After
changing the SVG, render it to a transparent 1024 x 1024 PNG (any SVG
renderer, e.g. a browser screenshot with no background) as
scripts/AppIcon-1024.png, then run:

    python3 scripts/make-icon.py  (needs Pillow)
"""
import json
import os

from PIL import Image

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "Lanes", "Assets.xcassets", "AppIcon.appiconset")


def main():
    master = Image.open(os.path.join(HERE, "AppIcon-1024.png")).convert("RGBA")
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
