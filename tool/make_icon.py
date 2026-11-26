#!/usr/bin/env python3
"""Generates the QANIS launcher icon: an amber 'sniffer' bird with signal arcs.

Draws at 8x and downsamples for clean edges, then writes every Android density
plus the two asset previews.
"""
import math, os
from PIL import Image, ImageDraw, ImageFilter

SS = 8                      # supersampling
AMBER = (232, 163, 61)      # #E8A33D
AMBER_DIM = (232, 163, 61, 150)
AMBER_FAINT = (232, 163, 61, 80)
CHAR = (38, 38, 38)         # #262626 background
CHAR_DEEP = (28, 28, 28)
EYE = (28, 24, 20)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def bez(points, steps=60):
    """Cubic bezier through 4 control points."""
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = points
    out = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        x = mt**3 * x0 + 3 * mt**2 * t * x1 + 3 * mt * t**2 * x2 + t**3 * x3
        y = mt**3 * y0 + 3 * mt**2 * t * y1 + 3 * mt * t**2 * y2 + t**3 * y3
        out.append((x, y))
    return out


def bird_shapes(s):
    """Returns the polygons of a swift in flight (108-space scaled by s)."""
    def p(x, y):
        return (x * s, y * s)

    # body: thin at the tail, full at the chest, head and beak at the front
    body = []
    body += bez([p(36, 55), p(48, 50), p(58, 48), p(66, 47)])       # back
    body += bez([p(66, 47), p(72, 44), p(77, 42), p(80, 41.5)])     # back -> head
    body += bez([p(80, 41.5), p(86, 40.5), p(90, 44), p(89.5, 48)])  # head
    body += [p(97, 50.5), p(89.5, 53)]                              # beak
    body += bez([p(89.5, 53), p(87, 57.5), p(81, 59), p(75, 57.5)])  # jaw
    body += bez([p(75, 57.5), p(64, 60), p(52, 64), p(42, 66)])      # belly
    body += bez([p(42, 66), p(38, 64), p(36, 59), p(36, 55)])        # tail root

    # forked tail, overlapping the body so there is no seam
    tail = [p(40, 55), p(18, 52), p(24, 60), p(19, 68), p(40, 65)]

    # upper wing rooted inside the body
    wu = []
    wu += bez([p(56, 51), p(56, 37), p(49, 27), p(40, 20)])
    wu += bez([p(40, 20), p(45, 30), p(52, 40), p(63, 51)])
    wu += [p(56, 51)]

    # lower wing rooted inside the body
    wl = []
    wl += bez([p(60, 56), p(58, 66), p(52, 74), p(44, 80)])
    wl += bez([p(44, 80), p(48, 70), p(55, 62), p(67, 56)])
    wl += [p(60, 56)]

    head = []
    beak = []
    return body, wu, wl, tail, head, beak


def draw_icon(size, with_background=True, monochrome=False, padding=0.0):
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")

    if with_background:
        # charcoal disc with a soft amber glow behind the bird
        d.rectangle([0, 0, s, s], fill=CHAR + (255,))
        glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow, "RGBA")
        r = s * 0.34
        cx, cy = s * 0.52, s * 0.5
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(232, 163, 61, 30))
        glow = glow.filter(ImageFilter.GaussianBlur(s * 0.06))
        img.alpha_composite(glow)

    scale = 1.0 - padding
    off = (s - s * scale) / 2.0

    def T(poly):
        return [((x * scale) + off, (y * scale) + off) for x, y in poly]

    body, wu, wl, tail, head, beak = bird_shapes(s / 108.0 * scale)
    shift = off

    def T(x, y):
        return ((x * s / 108.0) * scale + off, (y * s / 108.0) * scale + off)

    def S(poly):
        return [(x + shift, y + shift) for x, y in poly]

    body, wu, wl, tail, head, beak = S(body), S(wu), S(wl), S(tail), S(head), S(beak)

    if monochrome:
        solid = (255, 255, 255, 255)
        # keep the silhouette readable: bird only, no arcs
        for poly in (tail, wl, wu, body, beak):
            if len(poly) >= 3:
                d.polygon(poly, fill=solid)
        out = img.resize((size, size), Image.LANCZOS)
        return out

    # signal arcs behind the bird (it is "sniffing" the air)
    ax, ay = T(26.5, 66.5)
    for rad, alpha, width in [(0.105, 130, 0.021), (0.185, 90, 0.019), (0.265, 55, 0.017)]:
        rr = s * rad * scale
        box = [ax - rr, ay - rr, ax + rr, ay + rr]
        d.arc(box, start=118, end=222, fill=(232, 163, 61, alpha), width=max(2, int(s * width)))

    for poly in (tail, wl, wu, body):
        if len(poly) >= 3:
            d.polygon(poly, fill=AMBER + (255,))
    if len(beak) >= 3:
        d.polygon(beak, fill=(255, 196, 110, 255))

    # eye
    er = s * 0.0125 * scale
    ex, ey = T(88.0, 47.2)
    d.ellipse([ex - er, ey - er, ex + er, ey + er], fill=EYE + (255,))

    return img.resize((size, size), Image.LANCZOS)


def main():
    res = os.path.join(ROOT, "android/app/src/main/res")
    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    adaptive = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

    for name, px in densities.items():
        folder = os.path.join(res, f"mipmap-{name}")
        os.makedirs(folder, exist_ok=True)
        # legacy square icon (rounded by the launcher)
        draw_icon(px).convert("RGB").save(os.path.join(folder, "ic_launcher.png"))
        # round icon
        icon = draw_icon(px)
        mask = Image.new("L", (px * 4, px * 4), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, px * 4 - 1, px * 4 - 1], fill=255)
        mask = mask.resize((px, px), Image.LANCZOS)
        rounded = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        rounded.paste(icon, (0, 0), mask)
        rounded.save(os.path.join(folder, "ic_launcher_round.png"))

    for name, px in adaptive.items():
        folder = os.path.join(res, f"mipmap-{name}")
        os.makedirs(folder, exist_ok=True)
        # background layer: flat charcoal with the faint glow
        bg = Image.new("RGBA", (px, px), CHAR + (255,))
        g = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        gd = ImageDraw.Draw(g, "RGBA")
        r = px * 0.42
        gd.ellipse([px * 0.5 - r, px * 0.5 - r, px * 0.5 + r, px * 0.5 + r], fill=(232, 163, 61, 40))
        bg.alpha_composite(g.filter(ImageFilter.GaussianBlur(px * 0.05)))
        bg.convert("RGB").save(os.path.join(folder, "ic_launcher_background.png"))
        # foreground: bird only, inside the 66% safe zone
        draw_icon(px, with_background=False, padding=0.30).save(
            os.path.join(folder, "ic_launcher_foreground.png"))
        # monochrome (themed icons)
        draw_icon(px, with_background=False, monochrome=True, padding=0.30).save(
            os.path.join(folder, "ic_launcher_monochrome.png"))

    os.makedirs(os.path.join(ROOT, "assets"), exist_ok=True)
    draw_icon(512).convert("RGB").save(os.path.join(ROOT, "assets/icon.png"))
    draw_icon(432, with_background=False, padding=0.30).save(os.path.join(ROOT, "assets/icon_foreground.png"))

    # multi-resolution .ico (Windows / desktop packaging, store listings)
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    frames = [draw_icon(n) for n in ico_sizes]
    frames[-1].save(
        os.path.join(ROOT, "assets/icon.ico"),
        format="ICO",
        sizes=[(n, n) for n in ico_sizes],
        append_images=frames[:-1],
    )
    print("icons written (png + ico)")


if __name__ == "__main__":
    main()
