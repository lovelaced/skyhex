#!/usr/bin/env python3
"""Build the Skyhex icon: six cut gems in a hex flower around a black pearl, drawn the way
the board draws tiles (the addon's hex rim and mask over the game's own icon art, read
from the local WoW: Forever install by tools/casc.py), on a dusk gradient.

usage: python3 -I tools/mkicon.py     writes assets/logo.png (512) and Skyhex/Media/Icon.tga (64)
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from casc import icon_png  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "Skyhex", "Media")
S = 1024  # work size; scaled down at the end

# clockwise from the top: (fileID, rim rgb, icon tint), matching Media.lua's modern set
RING = [
    (1990988, (0.86, 0.16, 0.16), (1, 0.72, 0.72)),  # red
    (1990986, (0.95, 0.50, 0.12), None),             # orange
    (1990989, (0.96, 0.78, 0.16), None),             # yellow
    (1990985, (0.30, 0.72, 0.20), (0.7, 1, 0.7)),    # green
    (1990984, (0.18, 0.52, 0.92), None),             # blue
    (1990987, (0.66, 0.30, 0.84), None),             # purple
]
PEARL = (970844, (0.30, 0.18, 0.42), None)


def tint(img, rgb):
    r, g, b, a = img.split()
    return Image.merge("RGBA", (r.point(lambda v: v * rgb[0]), g.point(lambda v: v * rgb[1]),
                                b.point(lambda v: v * rgb[2]), a))


def tile(spec, size):
    fid, rim, itint = spec
    base = Image.open(os.path.join(MEDIA, "HexBase.tga")).convert("RGBA")
    out = tint(base, tuple(c * 0.78 for c in rim)).resize((size, size), Image.LANCZOS)
    icon = Image.open(icon_png(fid)).convert("RGBA")
    w, h = icon.size
    icon = icon.crop((int(w * 0.08), int(h * 0.08), int(w * 0.92), int(h * 0.92)))
    isz = int(size * 0.84)
    # the game's icons are 64 px, so they get a light sharpen after scaling up
    icon = icon.resize((isz, isz), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=4, percent=70, threshold=2))
    if itint:
        icon = tint(icon, itint)
    mask = Image.open(os.path.join(MEDIA, "HexMask.tga")).convert("RGBA").resize((isz, isz), Image.LANCZOS)
    icon.putalpha(mask.split()[3])
    out.alpha_composite(icon, ((size - isz) // 2, (size - isz) // 2))
    return out


def background():
    img = Image.new("RGBA", (S, S))
    px = img.load()
    top, bottom = (22, 26, 58), (64, 34, 78)  # night blue into dusk violet
    for y in range(S):
        t = y / (S - 1)
        row = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(S):
            px[x, y] = row + (255,)
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse([S * 0.18, S * 0.18, S * 0.82, S * 0.82], fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.12))
    img.alpha_composite(Image.merge("RGBA", (Image.new("L", (S, S), 120), Image.new("L", (S, S), 150),
                                             Image.new("L", (S, S), 230), glow)))
    return img


def main():
    img = background()
    R = S * 0.175            # hex radius: the flower spans about 5.2 R
    size = int(2 * R)        # tile frames are 2R square, like the board's
    gap = 1.04               # a hairline between tiles
    centers = [(S / 2, S / 2)]
    for k in range(6):       # neighbors of a flat-top hex sit at 90, 30, -30... degrees
        a = math.radians(-90 + 60 * k)
        d = math.sqrt(3) * R * gap
        centers.append((S / 2 + d * math.cos(a), S / 2 + d * math.sin(a)))
    specs = [PEARL] + RING

    shadow = Image.new("L", (S, S), 0)
    mask = Image.open(os.path.join(MEDIA, "HexMask.tga")).convert("RGBA").resize((size, size)).split()[3]
    for cx, cy in centers:
        shadow.paste(mask, (int(cx - size / 2), int(cy - size / 2 + S * 0.02)), mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.02))
    img.alpha_composite(Image.merge("RGBA", (Image.new("L", (S, S), 0),) * 3 + (shadow.point(lambda v: v * 0.6),)))

    for (cx, cy), spec in zip(centers, specs):
        t = tile(spec, size)
        img.alpha_composite(t, (int(cx - size / 2), int(cy - size / 2)))

    os.makedirs(os.path.join(ROOT, "assets"), exist_ok=True)
    logo = img.convert("RGB").resize((512, 512), Image.LANCZOS)
    logo.save(os.path.join(ROOT, "assets", "logo.png"), optimize=True)
    small = img.resize((64, 64), Image.LANCZOS)
    small.save(os.path.join(MEDIA, "Icon.tga"), compression=None)
    print("assets/logo.png, Skyhex/Media/Icon.tga")


if __name__ == "__main__":
    main()
