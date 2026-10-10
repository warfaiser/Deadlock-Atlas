#!/usr/bin/env python3
"""Генератор картинок для UI гоночного проекта (ImageMagick).

Создаёт:
    assets/ui/icons/car_<id>.png     — иконка машины (силуэт в цвете кузова)
    assets/ui/icons/track_<id>.png   — схема трассы сверху (по опорным точкам)

Картинки намеренно простые и процедурные: их можно заменить своими файлами
с теми же именами, игра подхватит их без правок кода.

Запуск:
    python3 tools/generate_racing_icons.py
Зависимости: ImageMagick (`convert` в PATH).
"""

from __future__ import annotations

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from generate_racing_resources import CARS, TRACKS  # noqa: E402

OUT_DIR = os.path.join(
    os.path.dirname(HERE),
    "racing-game",
    "assets",
    "ui",
    "icons",
)

THEME_COLORS = {
    0: {"ground": "#2b2f38", "accent": "#e8b25a"},   # город: вечерний асфальт
    1: {"ground": "#8a7042", "accent": "#ffe9a8"},   # пустыня: песок
    2: {"ground": "#d7e2ee", "accent": "#3f6ea5"},   # снег
}


def run(args: list[str]) -> None:
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError("ImageMagick failed: %s\n%s" % (" ".join(args), result.stderr))


def hex_color(rgb: tuple[float, float, float]) -> str:
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(c * 255)))) for c in rgb)


def make_car_icon(car: dict) -> str:
    body = hex_color(car["body_color"])
    accent = hex_color(car["accent_color"])
    path = os.path.join(OUT_DIR, f"car_{car['id']}.png")
    run([
        "convert", "-size", "256x160", "xc:none",
        # тень
        "-fill", "rgba(0,0,0,0.35)", "-draw", "roundrectangle 26,120 230,140 10,10",
        # кузов
        "-fill", body, "-stroke", "rgba(255,255,255,0.35)", "-strokewidth", "3",
        "-draw", "roundrectangle 30,52 226,124 18,18",
        # кабина
        "-fill", "rgba(150,200,255,0.85)", "-stroke", "none",
        "-draw", "roundrectangle 78,62 168,94 10,10",
        # акцентная полоса
        "-fill", accent, "-draw", "rectangle 30,100 226,112",
        # колёса
        "-fill", "#101014",
        "-draw", "circle 74,126 74,146", "-draw", "circle 182,126 182,146",
        "-fill", "#8d99ae",
        "-draw", "circle 74,126 74,134", "-draw", "circle 182,126 182,134",
        # фары
        "-fill", "#fff3c4", "-draw", "circle 218,74 218,80",
        path,
    ])
    return path


def make_track_preview(track: dict) -> str:
    colors = THEME_COLORS[track["theme"]]
    points = track["points"]
    xs = [p[0] for p in points]
    ys = [p[2] for p in points]
    width, height = 340, 200
    pad = 26.0
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    span_x = max(1e-3, max_x - min_x)
    span_y = max(1e-3, max_y - min_y)
    scale = min((width - 2 * pad) / span_x, (height - 2 * pad) / span_y)

    def project(point: tuple[float, float, float]) -> tuple[float, float]:
        x = pad + (point[0] - min_x) * scale + ((width - 2 * pad) - span_x * scale) / 2
        y = pad + (point[2] - min_y) * scale + ((height - 2 * pad) - span_y * scale) / 2
        return round(x, 2), round(y, 2)

    projected = [project(p) for p in points]
    # Замыкаем петлю: последняя точка соединяется с первой.
    polyline = " ".join(f"{x},{y}" for x, y in projected + [projected[0]])
    asphalt_width = max(6.0, track["road_width"] * scale * 0.42)
    path = os.path.join(OUT_DIR, f"track_{track['id']}.png")
    run([
        "convert", "-size", f"{width}x{height}",
        f"gradient:{colors['ground']}-#12151c",
        "-fill", "none",
        # обочина
        "-stroke", "rgba(0,0,0,0.55)", "-strokewidth", str(asphalt_width + 6),
        "-draw", f"polyline {polyline}",
        # асфальт
        "-stroke", "#23262c", "-strokewidth", str(asphalt_width),
        "-draw", f"polyline {polyline}",
        # разметка
        "-stroke", "rgba(255,255,255,0.55)", "-strokewidth", "1.4",
        "-draw", f"polyline {polyline}",
        # старт/финиш
        "-fill", colors["accent"], "-stroke", "none",
        "-draw", "circle %g,%g %g,%g" % (projected[0][0], projected[0][1],
                                        projected[0][0] + 4, projected[0][1]),
        path,
    ])
    return path


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Генерация иконок ->", OUT_DIR)
    for car in CARS:
        print("  ", os.path.basename(make_car_icon(car)))
    for track in TRACKS:
        print("  ", os.path.basename(make_track_preview(track)))


if __name__ == "__main__":
    main()
