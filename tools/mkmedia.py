#!/usr/bin/env python3
"""Generate Skyhex's textures as 32-bit uncompressed TGA (the format WoW loads).

usage: python3 tools/mkmedia.py [outDir]

Every hex texture is 128x128 with a flat-top hexagon spanning the full width (corner
to corner) and 86.6% of the height, centered. Drawn into a square of side 2*size the
hexagon lines up with the board's hex of that size. Shapes are supersampled 4x and
downscaled for smooth edges.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "Skyhex/Media"
N = 128
SS = 4


def hex_points(cx, cy, r):
    return [(cx + r * math.cos(math.radians(60 * k)), cy + r * math.sin(math.radians(60 * k))) for k in range(6)]


def hex_alpha(r_frac):
    """L-mode supersampled hexagon of radius r_frac * (N/2)."""
    size = N * SS
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    d.polygon(hex_points(size / 2, size / 2, r_frac * size / 2), fill=255)
    return img


def down(img):
    return img.resize((N, N), Image.LANCZOS)


def save(name, rgba):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".tga")
    rgba.save(path, compression=None)
    print(path)


def white_with_alpha(alpha):
    out = Image.new("RGBA", (N, N), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def hex_mask():
    # slightly inside the full hex so neighboring tiles keep a hairline gap
    save("HexMask", white_with_alpha(down(hex_alpha(0.94))))


def hex_base():
    """Tintable tile body: soft top-lit gradient with a lighter rim."""
    size = N * SS
    alpha = hex_alpha(0.97)
    grad = Image.new("L", (size, size))
    gp = grad.load()
    for y in range(size):
        v = int(255 - 70 * (y / size))
        for x in range(size):
            gp[x, y] = v
    rim = Image.new("L", (size, size), 0)
    ImageDraw.Draw(rim).polygon(hex_points(size / 2, size / 2, 0.97 * size / 2), fill=255)
    inner = Image.new("L", (size, size), 0)
    ImageDraw.Draw(inner).polygon(hex_points(size / 2, size / 2, 0.86 * size / 2), fill=255)
    ring = Image.new("L", (size, size), 0)
    ring.paste(rim)
    ring.paste(0, mask=inner)
    lum = Image.composite(Image.new("L", (size, size), 255), grad, ring.point(lambda a: a * 0.55))
    rgba = Image.merge("RGBA", (lum, lum, lum, alpha))
    save("HexBase", rgba.resize((N, N), Image.LANCZOS))


def hex_edge(name, outer, inner, blur=0):
    size = N * SS
    a = hex_alpha(outer)
    b = hex_alpha(inner)
    ring = Image.new("L", (size, size), 0)
    ring.paste(a)
    ring.paste(0, mask=b)
    if blur:
        ring = ring.filter(ImageFilter.GaussianBlur(blur * SS))
    save(name, white_with_alpha(down(ring)))


def star_points(size, outer, inner):
    pts = []
    for k in range(10):
        a = math.radians(-90 + 36 * k)
        r = (outer if k % 2 == 0 else inner) * size
        pts.append((size / 2 + r * math.cos(a), size / 2 + r * math.sin(a) + 0.04 * size))
    return pts


def star_badge():
    """White star with a dark outline baked in, so a gold tint still reads on gold gems."""
    size = N * SS
    outline = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(outline)
    d.polygon(star_points(size, 0.48, 0.22), fill=255)
    d.line(star_points(size, 0.48, 0.22) + [star_points(size, 0.48, 0.22)[0]], fill=255, width=int(0.07 * size), joint="curve")
    fill = Image.new("L", (size, size), 0)
    ImageDraw.Draw(fill).polygon(star_points(size, 0.40, 0.18), fill=255)
    lum = Image.new("L", (size, size), 0)
    lum.paste(255, mask=fill)
    rgba = Image.merge("RGBA", (lum, lum, lum, outline))
    save("StarBadge", rgba.resize((N, N), Image.LANCZOS))


def pivot():
    """Rotation marker: white dot with a dark ring, readable on any gem."""
    size = N * SS
    alpha = Image.new("L", (size, size), 0)
    ImageDraw.Draw(alpha).ellipse([size * 0.18, size * 0.18, size * 0.82, size * 0.82], fill=255)
    lum = Image.new("L", (size, size), 0)
    ImageDraw.Draw(lum).ellipse([size * 0.3, size * 0.3, size * 0.7, size * 0.7], fill=255)
    rgba = Image.merge("RGBA", (lum, lum, lum, alpha.point(lambda v: v * 0.92)))
    save("Pivot", rgba.resize((N, N), Image.LANCZOS))


def spark():
    """Soft round glow for clears and toasts."""
    img = Image.new("L", (N, N))
    p = img.load()
    for y in range(N):
        for x in range(N):
            d = math.hypot(x - N / 2 + 0.5, y - N / 2 + 0.5) / (N / 2)
            p[x, y] = int(255 * max(0.0, 1 - d) ** 2.2)
    save("Spark", white_with_alpha(img))


if __name__ == "__main__":
    hex_mask()
    hex_base()
    hex_edge("HexEdge", 0.98, 0.86)
    hex_edge("HexGlow", 1.0, 0.93, blur=1.5)
    star_badge()
    pivot()
    spark()
