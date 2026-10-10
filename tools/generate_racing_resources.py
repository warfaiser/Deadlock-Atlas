#!/usr/bin/env python3
"""Генератор .tres-ресурсов гоночного проекта (машины и трассы).

Создаёт:
    racing-game/resources/cars/*.tres      — 5 машин (CarStats)
    racing-game/resources/tracks/*.tres    — 3 трассы (TrackData)
    racing-game/resources/car_stats.tres   — «эталонная» машина (копия Roadster)
    racing-game/resources/track_data.tres  — «эталонная» трасса (копия City Sprint)

Опорные точки трасс — замкнутые петли в метрах; Godot строит по ним
Catmull-Rom-кривую (TrackData.create_curve()), поэтому геометрия дороги,
Path3D для ботов и чекпоинты всегда совпадают.

Запуск:
    python3 tools/generate_racing_resources.py
"""

from __future__ import annotations

import math
import os
import shutil

ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "racing-game",
    "resources",
)

CARS = [
    {
        "id": "roadster",
        "display_name": "Roadster",
        "description": "Сбалансированный родстер: прощает ошибки и одинаково хорош "
        "на городе и на снегу. Лучший выбор для первого заезда.",
        "mass": 1200.0,
        "max_speed": 55.0,
        "drivetrain": 2,
        "engine_force_multiplier": 2.5,
        "brake_multiplier": 0.8,
        "max_steering": 0.5,
        "grip_front": 3.0,
        "grip_rear": 2.6,
        "drag": 0.35,
        "bars": (0.62, 0.60, 0.64, 0.62, 0.66),
        "body_color": (0.85, 0.12, 0.15),
        "accent_color": (0.10, 0.11, 0.14),
    },
    {
        "id": "muscle",
        "display_name": "V8 Muscle",
        "description": "Тяжёлый заднеприводный маслкар. Разгоняется как ракета, "
        "но заднюю ось срывает в занос на каждом выходе из поворота.",
        "mass": 1500.0,
        "max_speed": 60.0,
        "drivetrain": 0,
        "engine_force_multiplier": 5.6,
        "brake_multiplier": 0.7,
        "max_steering": 0.46,
        "grip_front": 2.9,
        "grip_rear": 2.3,
        "drag": 0.42,
        "bars": (0.72, 0.72, 0.45, 0.52, 0.50),
        "body_color": (0.05, 0.25, 0.55),
        "accent_color": (0.85, 0.85, 0.88),
    },
    {
        "id": "kart",
        "display_name": "Street Kart",
        "description": "Лёгкий карт: максимум управляемости и сцепления, "
        "минимум максимальной скорости. Король коротких техничных трасс.",
        "mass": 800.0,
        "max_speed": 45.0,
        "drivetrain": 0,
        "engine_force_multiplier": 3.8,
        "brake_multiplier": 0.95,
        "max_steering": 0.58,
        "grip_front": 3.2,
        "grip_rear": 2.9,
        "drag": 0.3,
        "bars": (0.45, 0.66, 0.86, 0.72, 0.86),
        "body_color": (0.95, 0.72, 0.10),
        "accent_color": (0.12, 0.12, 0.14),
    },
    {
        "id": "hypercar",
        "display_name": "Aurora GT",
        "description": "Гиперкар с полным приводом: рекордная скорость и разгон, "
        "но требует аккуратной траектории — ошибки стоят секунд.",
        "mass": 1350.0,
        "max_speed": 72.0,
        "drivetrain": 2,
        "engine_force_multiplier": 3.1,
        "brake_multiplier": 0.9,
        "max_steering": 0.44,
        "grip_front": 3.4,
        "grip_rear": 3.0,
        "drag": 0.3,
        "bars": (0.95, 0.86, 0.70, 0.76, 0.80),
        "body_color": (0.88, 0.88, 0.90),
        "accent_color": (0.06, 0.07, 0.10),
    },
    {
        "id": "rally",
        "display_name": "Tundra Rally",
        "description": "Раллийный полноприводник с цепкой подвеской. "
        "Не самый быстрый, зато стабильнее всех на снегу и в грязи.",
        "mass": 1400.0,
        "max_speed": 50.0,
        "drivetrain": 2,
        "engine_force_multiplier": 3.4,
        "brake_multiplier": 0.85,
        "max_steering": 0.55,
        "grip_front": 3.3,
        "grip_rear": 3.1,
        "drag": 0.45,
        "bars": (0.55, 0.62, 0.78, 0.68, 0.90),
        "body_color": (0.10, 0.45, 0.30),
        "accent_color": (0.90, 0.90, 0.85),
    },
]

TRACKS = [
    {
        "id": "city",
        "display_name": "City Sprint",
        "description": "Короткая городская трасса с узкими поворотами, отбойниками "
        "вплотную и вечерним солнцем между зданий.",
        "theme": 0,
        "difficulty": 3,
        "laps": 3,
        "road_width": 11.0,
        "checkpoint_count": 6,
        "surface_grip": 1.0,
        "scenery_count": 260,
        "scenery_min": 14.0,
        "scenery_max": 110.0,
        "time_of_day": 17.5,
        "fog_density": 0.018,
        "asphalt": (0.12, 0.12, 0.14),
        "ground": (0.16, 0.17, 0.20),
        "fog": (0.58, 0.55, 0.60),
        "sky_top": (0.14, 0.20, 0.40),
        "sky_horizon": (0.74, 0.52, 0.42),
        "sun_energy": 1.0,
        "bots": (4, 7),
        "points": [
            (0, 0, -120), (60, 0, -120), (120, 0, -80), (120, 0, 0), (80, 0, 40),
            (140, 0, 80), (140, 0, 140), (60, 0, 180), (-20, 0, 160), (-80, 0, 120),
            (-140, 0, 100), (-160, 0, 20), (-120, 0, -60), (-60, 0, -100),
        ],
    },
    {
        "id": "desert",
        "display_name": "Desert Run",
        "description": "Широкая пустынная трасса с длинными дугами и плавными "
        "подъёмами. Максимальная скорость решает, но песок держит хуже асфальта.",
        "theme": 1,
        "difficulty": 2,
        "laps": 2,
        "road_width": 14.0,
        "checkpoint_count": 5,
        "surface_grip": 0.95,
        "scenery_count": 190,
        "scenery_min": 18.0,
        "scenery_max": 150.0,
        "time_of_day": 12.5,
        "fog_density": 0.008,
        "asphalt": (0.20, 0.18, 0.16),
        "ground": (0.55, 0.44, 0.28),
        "fog": (0.86, 0.78, 0.62),
        "sky_top": (0.24, 0.46, 0.78),
        "sky_horizon": (0.86, 0.80, 0.68),
        "sun_energy": 1.4,
        "bots": (3, 6),
        "points": [
            (0, 0, -220), (140, 2, -200), (240, 6, -120), (260, 10, 20),
            (200, 14, 120), (60, 10, 180), (-80, 6, 200), (-200, 2, 140),
            (-260, 0, 20), (-220, -2, -120), (-120, 0, -200),
        ],
    },
    {
        "id": "snow",
        "display_name": "Snow Pass",
        "description": "Заснеженный перевал: постоянные перепады высот, шпильки "
        "и очень скользкое покрытие. Лучший круг здесь стоит дорого.",
        "theme": 2,
        "difficulty": 4,
        "laps": 3,
        "road_width": 10.0,
        "checkpoint_count": 6,
        "surface_grip": 0.7,
        "scenery_count": 340,
        "scenery_min": 12.0,
        "scenery_max": 90.0,
        "time_of_day": 9.5,
        "fog_density": 0.032,
        "asphalt": (0.16, 0.17, 0.20),
        "ground": (0.82, 0.86, 0.92),
        "fog": (0.86, 0.89, 0.96),
        "sky_top": (0.38, 0.54, 0.78),
        "sky_horizon": (0.86, 0.89, 0.93),
        "sun_energy": 1.0,
        "bots": (3, 7),
        "points": [
            (0, 0, -160), (80, 4, -140), (140, 10, -60), (100, 16, 20),
            (160, 22, 90), (80, 26, 160), (-20, 20, 150), (-90, 12, 180),
            (-150, 6, 100), (-180, 2, 10), (-140, -2, -80), (-60, -4, -140),
        ],
    },
]


def catmull_rom_length(points: list[tuple[float, float, float]], scale: float = 0.25,
                      step: float = 2.0) -> float:
    """Приближённая длина замкнутой Catmull-Rom петли (как в Godot Curve3D)."""
    n = len(points)

    def point_at(i: int, t: float) -> tuple[float, float, float]:
        p0 = points[(i - 1) % n]
        p1 = points[i % n]
        p2 = points[(i + 1) % n]
        p3 = points[(i + 2) % n]
        out = []
        for axis in range(3):
            m1 = (p2[axis] - p0[axis]) * scale * 2.0
            m2 = (p3[axis] - p1[axis]) * scale * 2.0
            t2 = t * t
            t3 = t2 * t
            out.append(
                (2 * t3 - 3 * t2 + 1) * p1[axis]
                + (t3 - 2 * t2 + t) * m1
                + (-2 * t3 + 3 * t2) * p2[axis]
                + (t3 - t2) * m2
            )
        return tuple(out)

    total = 0.0
    for i in range(n):
        prev = points[i]
        seg_len = math.dist(points[i], points[(i + 1) % n])
        steps = max(2, int(seg_len / step))
        for s in range(1, steps + 1):
            cur = point_at(i, s / steps)
            total += math.dist(prev, cur)
            prev = cur
    return total


def fmt_vec3_array(points: list[tuple[float, float, float]]) -> str:
    values = []
    for x, y, z in points:
        values.append(f"{x:g}, {y:g}, {z:g}")
    return "PackedVector3Array(" + ", ".join(values) + ")"


def fmt_color(rgb: tuple[float, float, float]) -> str:
    return "Color(%g, %g, %g, 1)" % rgb


def write(path: str, body: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(body)
    print("  ", os.path.relpath(path, os.path.dirname(ROOT)))


def car_tres(car: dict) -> str:
    speed, accel, handling, brakes, grip = car["bars"]
    return f"""[gd_resource type="Resource" script_class="CarStats" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/data/car_stats.gd" id="1_stats"]

[resource]
script = ExtResource("1_stats")
id = &"{car['id']}"
display_name = "{car['display_name']}"
icon_path = "res://assets/ui/icons/car_{car['id']}.png"
description = "{car['description']}"
bar_speed = {speed}
bar_acceleration = {accel}
bar_handling = {handling}
bar_brakes = {brakes}
bar_grip = {grip}
mass = {car['mass']}
max_engine_force = 800.0
engine_force_multiplier = {car['engine_force_multiplier']}
brake_force = 40.0
brake_multiplier = {car['brake_multiplier']}
max_steering = {car['max_steering']}
max_speed = {car['max_speed']}
drivetrain = {car['drivetrain']}
suspension_stiffness = 40.0
suspension_travel = 0.3
damping_compression = 0.6
damping_relaxation = 0.9
wheel_friction_front = {car['grip_front']}
wheel_friction_rear = {car['grip_rear']}
wheel_roll_influence = 0.1
wheel_radius = 0.35
wheel_rest_length = 0.12
drag_coefficient = {car['drag']}
health_max = 100.0
damage_speed_loss = 0.4
body_color = {fmt_color(car['body_color'])}
accent_color = {fmt_color(car['accent_color'])}
light_color = Color(1, 0.93, 0.75, 1)
"""


def track_tres(track: dict) -> str:
    return f"""[gd_resource type="Resource" script_class="TrackData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/data/track_data.gd" id="1_track"]

[resource]
script = ExtResource("1_track")
id = &"{track['id']}"
display_name = "{track['display_name']}"
preview_path = "res://assets/ui/icons/track_{track['id']}.png"
description = "{track['description']}"
control_points = {fmt_vec3_array(track['points'])}
road_width = {track['road_width']}
bake_interval = 2.0
tangent_scale = 0.25
barrier_height = 1.0
laps = {track['laps']}
difficulty = {track['difficulty']}
checkpoint_count = {track['checkpoint_count']}
bots_min = {track['bots'][0]}
bots_max = {track['bots'][1]}
surface_grip = {track['surface_grip']}
theme = {track['theme']}
scenery_count = {track['scenery_count']}
scenery_min_distance = {track['scenery_min']}
scenery_max_distance = {track['scenery_max']}
time_of_day = {track['time_of_day']}
asphalt_color = {fmt_color(track['asphalt'])}
marking_color = Color(0.92, 0.92, 0.88, 1)
ground_color = {fmt_color(track['ground'])}
fog_color = {fmt_color(track['fog'])}
fog_density = {track['fog_density']}
sky_top_color = {fmt_color(track['sky_top'])}
sky_horizon_color = {fmt_color(track['sky_horizon'])}
sun_energy = {track['sun_energy']}
"""


def main() -> None:
    print("Генерация ресурсов ->", ROOT)
    write(os.path.join(ROOT, "car_stats.tres"), car_tres(CARS[0]))
    write(os.path.join(ROOT, "track_data.tres"), track_tres(TRACKS[0]))
    for car in CARS:
        write(os.path.join(ROOT, "cars", f"{car['id']}.tres"), car_tres(car))
    for track in TRACKS:
        write(os.path.join(ROOT, "tracks", f"{track['id']}.tres"), track_tres(track))
        length = catmull_rom_length(track["points"])
        print(f"     длина петли ≈ {length:.0f} м, точек {len(track['points'])}")
    # Эталонные файлы дублируют первые записи каталога.
    shutil.copyfile(os.path.join(ROOT, "cars", f"{CARS[0]['id']}.tres"),
                    os.path.join(ROOT, "car_stats.tres"))
    shutil.copyfile(os.path.join(ROOT, "tracks", f"{TRACKS[0]['id']}.tres"),
                    os.path.join(ROOT, "track_data.tres"))


if __name__ == "__main__":
    main()
