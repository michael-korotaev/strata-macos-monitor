#!/usr/bin/env python3
"""Вырезает панель монитора из снимка экрана.

Снимок экрана содержит поповер и чужие окна за ним. Скрипт находит прямоугольник
панели по её фоновому цвету, отбрасывает «стрелку», торчащую над верхним краем,
и вырезает панель со сглаженными скруглёнными углами на прозрачном фоне.

Готовый кадр потом причесывается отдельным инструментом (prettyshot) — градиент,
отступы, тень.

    python3 scripts/panel-shot.py raw.png panel.png
"""
import sys
from PIL import Image, ImageDraw

PANEL_COLOR = (55, 55, 55)     # фон поповера в тёмной теме
TOLERANCE = 4                   # допуск по цвету (пиксели дизерингованные)
CORNER_RADIUS = 24              # радиус скругления в пикселях кадра (2x)
SUPERSAMPLE = 4                 # сглаживание маски скругления


def close(pixel, color, tolerance=TOLERANCE):
    return all(abs(pixel[i] - color[i]) <= tolerance for i in range(3))


def longest_run(px, y, w, color):
    """Самый длинный ряд пикселей заданного цвета в строке."""
    best = (0, -1)
    start = None
    for x in range(w):
        if close(px[x, y], color):
            if start is None:
                start = x
        else:
            if start is not None and x - start > best[1] - best[0]:
                best = (start, x - 1)
            start = None
    if start is not None and w - start > best[1] - best[0]:
        best = (start, w - 1)
    return best


def find_panel(image, color=PANEL_COLOR):
    """Прямоугольник панели без «стрелки».

    Ряд считается частью панели, только если он не короче 70 % самой длинной
    строки: у «стрелки» над панелью ряд короткий, и она отсекается.
    """
    px = image.load()
    w, h = image.size
    rows = []
    for y in range(h):
        x0, x1 = longest_run(px, y, w, color)
        if x1 >= x0:
            rows.append((y, x0, x1))
    if not rows:
        return None
    widest = max(x1 - x0 for _, x0, x1 in rows)
    body = [r for r in rows if (r[2] - r[1]) >= widest * 0.7]
    if not body:
        return None
    x0 = min(r[1] for r in body)
    x1 = max(r[2] for r in body)
    y0 = min(r[0] for r in body)
    y1 = max(r[0] for r in body)
    if (x1 - x0) > w * 0.985 or (y1 - y0) > h * 0.985:
        return None
    return x0, y0, x1, y1


def rounded_mask(size, radius=CORNER_RADIUS):
    """Сглаженная маска скруглённого прямоугольника."""
    w, h = size
    big = Image.new("L", (w * SUPERSAMPLE, h * SUPERSAMPLE), 0)
    draw = ImageDraw.Draw(big)
    draw.rounded_rectangle(
        [0, 0, w * SUPERSAMPLE - 1, h * SUPERSAMPLE - 1],
        radius=radius * SUPERSAMPLE,
        fill=255,
    )
    return big.resize((w, h), Image.Resampling.LANCZOS)


def extract(src, dst):
    image = Image.open(src).convert("RGB")
    box = find_panel(image)
    if box is None:
        print("не нашёл поповер", file=sys.stderr)
        return False
    x0, y0, x1, y1 = box
    crop = image.crop((x0, y0, x1 + 1, y1 + 1)).convert("RGBA")
    crop.putalpha(rounded_mask(crop.size))
    crop.save(dst)
    print(f"{src} -> {dst}: панель {crop.size[0]}x{crop.size[1]}")
    return True


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(0 if extract(sys.argv[1], sys.argv[2]) else 1)
