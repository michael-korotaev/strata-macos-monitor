#!/usr/bin/env python3
"""Вырезает поповер из скриншота и ставит его на чистый фон.

Скриншоты меню-бара снимаются с рабочего стола, за окном видны чужие окна.
Скрипт находит границы поповера по цвету его фона, вырезает его и собирает
кадр на однотонном фоне в цветах иконки приложения.

    python3 scripts/clean-screenshot.py in.png out.png
"""
import sys
from collections import Counter
from PIL import Image, ImageDraw

BG_TOP = (59, 126, 161)
BG_BOTTOM = (18, 32, 48)
margin = 16


PANEL_COLOR = (55, 55, 55)   # фон поповера macOS


def find_panel(image: Image.Image):
    """Ищет прямоугольник поповера по сплошному фоновому цвету."""
    px = image.load()
    w, h = image.size

    rows = []
    for y in range(h):
        run = longest_run(px, y, w, PANEL_COLOR, 120)
        if run:
            rows.append((y, run))
    if not rows:
        return None

    top = rows[0][0]
    bottom = rows[-1][0]
    left = min(r[1][0] for r in rows)
    right = max(r[1][1] for r in rows)
    box = (left, top, right, bottom)
    if (right - left) > w * 0.985 or (bottom - top) > h * 0.985:
        return None
    return box


def close(pixel, color, tolerance=4):
    return all(abs(pixel[i] - color[i]) <= tolerance for i in range(3))


def longest_run(px, y, w, color, minimum):
    """Самый длинный ряд пикселей заданного цвета в строке (с допуском)."""
    best = (0, 0)
    start = None
    for x in range(w):
        if close(px[x, y], color):
            if start is None:
                start = x
        else:
            if start is not None and x - start >= minimum:
                if x - start > best[1] - best[0]:
                    best = (start, x - 1)
            start = None
    if start is not None and w - start >= minimum and w - start > best[1] - best[0]:
        best = (start, w - 1)
    return best if best[1] > best[0] else None


def gradient(size):
    canvas = Image.new('RGB', size)
    draw = ImageDraw.Draw(canvas)
    for y in range(size[1]):
        t = y / max(size[1] - 1, 1)
        color = tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3))
        draw.line([(0, y), (size[0], y)], fill=color)
    return canvas


def main(src: str, dst: str):
    image = Image.open(src).convert('RGB')
    box = find_panel(image)
    if box is None:
        print('не нашёл поповер, копирую как есть')
        image.save(dst)
        return

    x0, y0, x1, y1 = box
    pad = 8
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(image.width - 1, x1 + pad), min(image.height - 1, y1 + pad)
    crop = image.crop((x0, y0, x1 + 1, y1 + 1))
    w, h = crop.size

    mask = Image.new('L', (w, h), 0)
    draw = ImageDraw.Draw(mask)
    radius = 26
    draw.rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)

    canvas = gradient((w + 2 * margin, h + 2 * margin))
    canvas.paste(crop, (margin, margin), mask)
    canvas.save(dst)
    print(f'{src} -> {dst}: панель {w}x{h}, кадр {canvas.size[0]}x{canvas.size[1]}')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
