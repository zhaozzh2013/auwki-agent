"""生成 AUWKI Agent 应用图标：1024/512 PNG + 多尺寸 ICO。"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "windows" / "runner" / "resources"
SIZE = 1024


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size):
    indigo = (79, 70, 229)
    violet = (124, 58, 237)
    sky = (14, 165, 233)
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        c1 = lerp(indigo, violet, t)
        c2 = lerp(violet, sky, t)
        for x in range(size):
            d.point((x, y), fill=lerp(c1, c2, x / (size - 1)))
    return img


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def draw_star(d, cx, cy, r, ratio=0.22, fill=(255, 255, 255)):
    inner = r * ratio
    pts = [
        (cx, cy - r),
        (cx + inner, cy - inner),
        (cx + r, cy),
        (cx + inner, cy + inner),
        (cx, cy + r),
        (cx - inner, cy + inner),
        (cx - r, cy),
        (cx - inner, cy - inner),
    ]
    d.polygon(pts, fill=fill)


def make_icon(size):
    base = gradient(size)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(base, (0, 0), rounded_mask(size, int(200 * size / 1024)))
    d = ImageDraw.Draw(canvas)

    s = size / 1024.0
    glow = (255, 255, 255, 38)
    d.ellipse((560 * s, 130 * s, 920 * s, 490 * s), fill=glow)
    d.ellipse((60 * s, 600 * s, 360 * s, 900 * s), fill=glow)

    white = (255, 255, 255, 255)
    draw_star(d, 512 * s, 512 * s, 300 * s, 0.22, white)
    draw_star(d, 300 * s, 330 * s, 92 * s, 0.24, white)
    draw_star(d, 720 * s, 330 * s, 62 * s, 0.24, white)
    return canvas


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    base = make_icon(SIZE)
    base.save(OUT / "app_icon_1024.png")
    base.resize((512, 512), Image.LANCZOS).save(OUT / "app_icon_512.png")
    base.save(
        OUT / "app_icon.ico",
        format="ICO",
        sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (256, 256)],
    )
    print("icon generated:", OUT / "app_icon.ico")


if __name__ == "__main__":
    main()
