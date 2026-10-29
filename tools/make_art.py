"""Poster / icon / preview for A-Life: Caravans, in the style of the SmoothRide / ZombieSync / Reactive Survivors
art (dark grid, Bahnschrift, white + teal title, badges, teal glow, spaced caption): a two-car convoy on a road
with a survivor's car catching up behind it.

  python -I make_art.py      writes 42/poster.png, 42/icon.png and docs/preview.png (repo layout)
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
FONT = r"C:\Windows\Fonts\bahnschrift.ttf"
TEAL = (34, 211, 197)
WHITE = (240, 244, 246)
BG0, BG1 = (13, 18, 22), (22, 30, 36)
FAINT = (52, 66, 76)
AMBER = (232, 160, 70)
ROAD = (40, 50, 58)
LANE = (120, 130, 138)
TRUCK = (170, 180, 170)
RED = (224, 64, 52)


def font(size, style="Bold"):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name(style)
    except Exception:
        pass
    return f


def background(w, h):
    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        k = y / (h - 1)
        c = tuple(int(BG0[i] + (BG1[i] - BG0[i]) * k) for i in range(3))
        for x in range(w):
            px[x, y] = c
    d = ImageDraw.Draw(im)
    for x in range(0, w, 32):
        d.line([(x, 0), (x, h)], fill=(26, 35, 42))
    for y in range(0, h, 32):
        d.line([(0, y), (w, y)], fill=(26, 35, 42))
    return im


def spaced(d, xy, text, f, fill, spacing):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=f, fill=fill)
        x += d.textlength(ch, font=f) + spacing
    return x


def text_width(d, text, f, spacing):
    return sum(d.textlength(ch, font=f) for ch in text) + spacing * (len(text) - 1)


def fit(d, text, size, width, style="Bold"):
    f = font(size, style)
    while d.textlength(text, font=f) > width and size > 10:
        size -= 2
        f = font(size, style)
    return f


def car(d, x, y, w, h, fill, outline=None, lights=None):
    """side view, rear-left corner at (x, y), driving to the right"""
    body = [x, y - h * 0.55, x + w, y]
    d.rounded_rectangle(body, radius=int(h * 0.18), fill=fill, outline=outline)
    cab = [x + w * 0.22, y - h, x + w * 0.78, y - h * 0.5]
    d.rounded_rectangle(cab, radius=int(h * 0.2), fill=fill, outline=outline)
    win = [x + w * 0.28, y - h * 0.93, x + w * 0.72, y - h * 0.58]
    d.rounded_rectangle(win, radius=int(h * 0.12), fill=(20, 28, 34))
    r = h * 0.22
    for wx in (x + w * 0.22, x + w * 0.78):
        d.ellipse([wx - r, y - r, wx + r, y + r], fill=(18, 24, 28), outline=LANE, width=max(1, int(h * 0.05)))
    if lights:
        lr = h * 0.08
        d.ellipse([x + w - lr * 2, y - h * 0.42 - lr, x + w, y - h * 0.42 + lr], fill=lights)


def scene(im, s, road_y, cars, follow=None, rings=()):
    size = im.size[0]
    glow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    sharp = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sharp)
    # the road
    d.rectangle([int(16 * s), road_y - int(46 * s), size - int(16 * s), road_y + int(14 * s)], fill=ROAD + (255,))
    for x in range(int(24 * s), size - int(16 * s), int(44 * s)):
        d.line([(x, road_y - int(16 * s)), (x + int(22 * s), road_y - int(16 * s))], fill=LANE + (255,), width=max(1, int(3 * s)))
    for radius, alpha in rings:
        cx = cars[0][0] + cars[0][2] / 2
        box = [cx - radius, road_y - radius * 0.3, cx + radius, road_y + radius * 0.3]
        g.ellipse(box, outline=TEAL + (alpha,), width=max(2, int(5 * s)))
        d.ellipse(box, outline=TEAL + (alpha,), width=max(1, int(2 * s)))
    for (x, y, w, h, fill) in cars:
        car(d, x, y, w, h, fill + (255,), lights=AMBER + (255,))
        g.rectangle([x, y - h, x + w, y], outline=TEAL + (90,), width=max(2, int(4 * s)))
    if follow:
        x, y, w, h = follow
        car(d, x, y, w, h, WHITE + (255,), lights=WHITE + (255,))
        # speed lines behind the player's car
        for i in range(3):
            ly = y - h * (0.3 + 0.2 * i)
            d.line([(x - w * 0.55, ly), (x - w * 0.12, ly)], fill=TEAL + (200,), width=max(1, int(2 * s)))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(7 * s)))
    im.alpha_composite(sharp)


def badge(d, x, y, w, h, s, text, fill=None, outline=None, color=WHITE):
    if fill is not None:
        d.rounded_rectangle([x, y, x + w, y + h], radius=int(7 * s), fill=fill)
    else:
        d.rounded_rectangle([x, y, x + w, y + h], radius=int(7 * s), outline=outline, width=max(1, int(2 * s)))
    fb = font(int(24 * s), "SemiBold")
    tw = d.textlength(text, font=fb)
    d.text((x + (w - tw) / 2, y + int(5 * s)), text, font=fb, fill=color)


def poster(size=512):
    s = size / 512
    im = background(size, size).convert("RGBA")
    d = ImageDraw.Draw(im)
    f1 = fit(d, "A-LIFE", int(52 * s), int(452 * s))
    d.text((int(30 * s), int(22 * s)), "A-LIFE", font=f1, fill=WHITE)
    title = "CARAVANS"
    f2 = fit(d, title, int(96 * s), int(452 * s))
    glow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).text((int(28 * s), int(84 * s)), title, font=f2, fill=TEAL + (200,))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(10 * s)))
    d = ImageDraw.Draw(im)
    d.text((int(28 * s), int(84 * s)), title, font=f2, fill=TEAL)
    by, bh = int(176 * s), int(38 * s)
    badge(d, int(30 * s), by, int(74 * s), bh, s, "LUA", fill=TEAL, color=(10, 30, 32))
    badge(d, int(116 * s), by, int(80 * s), bh, s, "B42", outline=(200, 208, 214), color=(220, 226, 230))
    badge(d, int(208 * s), by, int(176 * s), bh, s, "TEST VERSION", outline=AMBER, color=AMBER)
    road_y = int(392 * s)
    cars = [
        (int(300 * s), road_y, int(118 * s), int(52 * s), TRUCK),
        (int(168 * s), road_y, int(104 * s), int(46 * s), TRUCK),
    ]
    scene(im, s, road_y, cars, follow=(int(52 * s), road_y, int(84 * s), int(40 * s)), rings=((150 * s, 90),))
    d = ImageDraw.Draw(im)
    fl = font(int(14 * s), "SemiBold")
    d.text((int(330 * s), int(404 * s)), "35 KM/H", font=fl, fill=(120, 190, 184))
    fc = font(int(19 * s), "SemiBold")
    cap = "FACTION CONVOYS ON THE ROAD"
    w = text_width(d, cap, fc, 3 * s)
    spaced(d, ((size - w) / 2, int(468 * s)), cap, fc, (190, 200, 210), 3 * s)
    return im.convert("RGB")


def icon(size=128):
    s = size / 128
    im = background(size, size).convert("RGBA")
    road_y = int(96 * s)
    cars = [(int(62 * s), road_y, int(54 * s), int(26 * s), TRUCK)]
    scene(im, s * 2, road_y, cars, follow=(int(8 * s), road_y, int(40 * s), int(20 * s)), rings=((40 * s, 120),))
    return im.convert("RGB")


if __name__ == "__main__":
    mod42 = os.path.join(PROJ, "42")
    docs = os.path.join(PROJ, "docs")
    os.makedirs(docs, exist_ok=True)
    p = poster(512)
    p.save(os.path.join(mod42, "poster.png"))
    p.save(os.path.join(docs, "preview.png"))
    icon(128).save(os.path.join(mod42, "icon.png"))
    print("written:", os.path.join(mod42, "poster.png"), os.path.join(mod42, "icon.png"), os.path.join(docs, "preview.png"))
