#!/usr/bin/env python3
"""Composite a tools/snap.lua dump into a PNG mockup of the Skyhex window.

usage: python3 -I tools/snap.py DUMP [--media Skyhex/Media] [-o out.png] [--scale 2]

Uses the addon's own TGAs (hex base, mask, edge, star badge) and the icon art straight
from the local WoW: Forever install (tools/casc.py), by the fileIDs and tints that
Media.lua sets, which the dump carries. Fonts are a system stand-in for Friz Quadrata,
so text widths are approximate.
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont, ImageOps

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from casc import icon_png  # noqa: E402
DIR_ANGLE = [-90, -30, 30, 90, 150, 210]
PEARL_DIRS = {1: [0, 2, 4], 2: [1, 3, 5]}
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def tint(img, rgb, k=1.0):
    r, g, b, a = img.split()
    return Image.merge("RGBA", (r.point(lambda v: v * rgb[0] * k), g.point(lambda v: v * rgb[1] * k),
                                b.point(lambda v: v * rgb[2] * k), a))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("--media", default="Skyhex/Media")
    ap.add_argument("-o", "--out")
    ap.add_argument("--scale", type=float, default=2.0)
    a = ap.parse_args()
    S = a.scale

    lines = [ln.rstrip("\n").split("|") for ln in open(a.dump, encoding="utf-8") if ln.strip()]
    looks = {}
    for p in lines:
        if p[0] == "look":
            looks[p[1]] = {"fid": int(p[2]), "rgb": tuple(float(v) for v in p[3].split(",")),
                           "tint": tuple(float(v) for v in p[4].split(",")), "desat": p[5] == "1"}
    lines = [p for p in lines if p[0] != "look"]
    win = [float(v) for v in lines[0][1].split()]
    W, H = int(win[2] * S), int(win[3] * S)
    x0, top = win[0], win[1] + win[3]

    def box(r):
        l, b, w, h = (float(v) for v in r.split())
        return (l - x0) * S, (top - (b + h)) * S, w * S, h * S

    media = {n: Image.open(os.path.join(a.media, n + ".tga")).convert("RGBA")
             for n in ("HexBase", "HexMask", "HexEdge", "HexGlow", "StarBadge", "Spark", "Pivot")}
    img = Image.new("RGBA", (W, H), (19, 21, 27, 245))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=(51, 56, 71, 255), width=max(1, int(S)))
    bx, by, bw, bh = box(lines[0][2])
    d.rectangle([bx - 4 * S, by - 4 * S, bx + bw + 4 * S, by + bh + 4 * S], fill=(11, 13, 17, 255))

    def paste(src, cx, cy, size):
        s = max(1, int(size))
        im = src.resize((s, s), Image.LANCZOS)
        img.alpha_composite(im, (int(cx - s / 2), int(cy - s / 2)))

    def font(size, bold=False):
        return ImageFont.truetype(FONT_BOLD if bold else FONT, int(size * S))

    overlay_after = []
    for parts in lines[1:]:
        kind = parts[0]
        if kind == "tile":
            x, y, w, h = box(parts[1])
            cx, cy = x + w / 2, y + h / 2
            tk, color, bonus, bomb, py = parts[2], int(parts[3]), parts[4] == "1", int(parts[5]), int(parts[6])
            key = "gem%d" % color if tk == "gem" else tk
            lk = looks[key]
            paste(tint(media["HexBase"], lk["rgb"], 0.78), cx, cy, w)
            icon = Image.open(icon_png(lk["fid"])).convert("RGBA")
            if lk["desat"]:
                gray = ImageOps.grayscale(icon.convert("RGB"))
                icon = Image.merge("RGBA", (gray, gray, gray, icon.split()[3]))
            iw, ih = icon.size
            icon = icon.crop((int(iw * 0.08), int(ih * 0.08), int(iw * 0.92), int(ih * 0.92)))
            isz = int(w * 0.84)
            icon = icon.resize((isz, isz), Image.LANCZOS)
            if lk["tint"] != (1.0, 1.0, 1.0):
                icon = tint(icon, lk["tint"])
            if bomb:
                icon = Image.eval(icon, lambda v: int(v * 0.72))
            mask = media["HexMask"].resize((isz, isz), Image.LANCZOS).split()[3]
            icon.putalpha(mask)
            img.alpha_composite(icon, (int(cx - isz / 2), int(cy - isz / 2)))
            if bonus:
                paste(tint(media["StarBadge"], (1.0, 0.95, 0.80)), cx, cy, w * 0.5)
            if bomb:
                paste(tint(media["HexGlow"], (1.0, 0.22, 0.18)), cx, cy, w)
                f = font(w / S * 0.45, True)
                col = (255, 115, 102) if bomb <= 3 else (255, 255, 255)
                d.text((cx, cy), str(bomb), font=f, fill=col, anchor="mm", stroke_width=int(2 * S), stroke_fill=(0, 0, 0))
            if tk == "pearl":
                import math
                s = w / 2
                for k in PEARL_DIRS[py]:
                    ang = math.radians(DIR_ANGLE[k])
                    d.line([(cx + math.cos(ang) * s * 0.55, cy + math.sin(ang) * s * 0.55),
                            (cx + math.cos(ang) * s * 0.9, cy + math.sin(ang) * s * 0.9)],
                           fill=(217, 184, 255), width=int(max(2, s / S * 0.16) * S))
        elif kind == "hl":
            x, y, w, h = box(parts[1])
            rgb = [float(v) for v in parts[2].split(",")]
            paste(tint(media["HexEdge"], rgb), x + w / 2, y + h / 2, w)
        elif kind == "alert":
            x, y, w, h = box(parts[1])
            ring = tint(media["HexEdge"], (1.0, 0.22, 0.18))
            ring.putalpha(ring.split()[3].point(lambda v: v * float(parts[2])))
            paste(ring, x + w / 2, y + h / 2, w)
        elif kind == "pivot":
            x, y, w, h = box(parts[1])
            paste(media["Pivot"], x + w / 2, y + h / 2, w)
        elif kind in ("overlay", "button") or (kind == "text" and overlay_after is not None and any(p[0] == "overlay" for p in lines[1:]) and parts in overlay_texts(lines)):
            overlay_after.append(parts)
        elif kind == "text":
            draw_text(d, box, parts, font)
    for parts in overlay_after:
        if parts[0] == "overlay":
            x, y, w, h = box(parts[1])
            ov = Image.new("RGBA", (int(w), int(h)), (8, 9, 13, 214))
            img.alpha_composite(ov, (int(x), int(y)))
        elif parts[0] == "button":
            x, y, w, h = box(parts[1])
            d.rounded_rectangle([x, y, x + w, y + h], radius=3 * S, fill=(120, 18, 14), outline=(200, 160, 60), width=int(S))
            d.text((x + w / 2, y + h / 2), parts[2], font=font(12, True), fill=(255, 210, 0), anchor="mm")
        else:
            draw_text(d, box, parts, font)
    img.save(a.out or a.dump.replace(".txt", ".png"))
    print(a.out or a.dump.replace(".txt", ".png"))


def overlay_texts(lines):
    out, seen = [], False
    for p in lines[1:]:
        if p[0] == "overlay":
            seen = True
        elif seen and p[0] == "text":
            out.append(p)
    return out


def draw_text(d, box, parts, font):
    x, y, w, h = box(parts[1])
    size, rgb, justify, text = int(parts[2]), parts[3], parts[4], parts[5].replace("\\n", "\n")
    col = tuple(int(float(v) * 255) for v in rgb.split(","))
    f = font(size)
    if justify == "RIGHT":
        d.multiline_text((x + w, y), text, font=f, fill=col, anchor="ra", align="right")
    elif justify == "LEFT" or w < 1:
        d.multiline_text((x, y), text, font=f, fill=col, anchor="la")
    else:
        # wrap to the box width the way a FontString with a set width does
        out = []
        for para in text.split("\n"):
            line = ""
            for word in para.split(" "):
                trial = (line + " " + word).strip()
                if d.textlength(trial, font=f) > w and line:
                    out.append(line)
                    line = word
                else:
                    line = trial
            out.append(line)
        d.multiline_text((x + w / 2, y), "\n".join(out), font=f, fill=col, anchor="ma", align="center", spacing=6)


if __name__ == "__main__":
    main()
