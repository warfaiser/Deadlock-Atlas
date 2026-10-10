#!/usr/bin/env python3
"""Генератор плейсхолдер-звуков для гоночного проекта (racing-game/assets/sounds).

Все файлы синтезируются процедурно (numpy + libsndfile) и сохраняются в OGG/Vorbis,
чтобы проект запускался сразу, без внешних ассетов. Любую дорожку можно заменить
своим файлом с тем же именем — игра подхватит его без правок кода.

Запуск:
    python3 tools/generate_racing_audio.py
Зависимости:
    pip install numpy soundfile
"""

from __future__ import annotations

import os

import numpy as np
import soundfile as sf

RATE = 44100
OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "racing-game",
    "assets",
    "sounds",
)


def _saw(phase: np.ndarray) -> np.ndarray:
    """Пиловидная волна из фазы (0..1)."""
    return 2.0 * (phase - np.floor(phase + 0.5))


def _envelope(length: float, attack: float, release: float) -> np.ndarray:
    n = int(length * RATE)
    env = np.ones(n, dtype=np.float32)
    a = max(1, int(attack * RATE))
    r = max(1, int(release * RATE))
    env[:a] = np.linspace(0.0, 1.0, a)
    env[-r:] *= np.linspace(1.0, 0.0, r)
    return env


def _normalize(sig: np.ndarray, peak: float = 0.85) -> np.ndarray:
    m = float(np.max(np.abs(sig)))
    if m < 1e-9:
        return np.zeros_like(sig, dtype=np.float32)
    return (sig / m * peak).astype(np.float32)


def _write(name: str, sig: np.ndarray, loop: bool = False) -> None:
    sig = _normalize(sig)
    path = os.path.join(OUT_DIR, name)
    sf.write(path, sig, RATE, format="OGG", subtype="VORBIS")
    print(f"  {name:20s} {len(sig) / RATE:5.2f}s  loop={loop}")


def engine_loop() -> np.ndarray:
    """Бесшовная петля двигателя: 4 цилиндра (пила) + рокот + шум впуска.

    Длительность ровно 2.0 с, все частоты кратны 1/2 Гц -> склейка без щелчка.
    Питч в игре меняется через pitch_scale, поэтому базовый тон низкий.
    """
    dur = 2.0
    t = np.arange(int(dur * RATE), dtype=np.float32) / RATE
    base = 44.0  # Гц — «холостой ход», в игре умножается на 0.7..2.0
    sig = np.zeros_like(t)
    for k, amp in ((1.0, 1.00), (2.0, 0.55), (3.0, 0.32), (4.0, 0.22), (6.0, 0.12)):
        # Небольшая расстройка между «цилиндрами» даёт живой рокот.
        detune = 1.0 + 0.004 * ((k % 3) - 1)
        sig += amp * _saw(base * k * detune * t)
    # Пульсация впуска 22 Гц (выстрелы цилиндров).
    sig *= 0.75 + 0.25 * np.sin(2 * np.pi * 22.0 * t)
    # Шум впуска, отфильтрованный простой скользящей средней.
    noise = np.random.default_rng(7).standard_normal(t.size).astype(np.float32)
    kernel = np.ones(64, dtype=np.float32) / 64.0
    noise = np.convolve(noise, kernel, mode="same") * 0.35
    return sig + noise


def tire_squeal() -> np.ndarray:
    """Петля визга резины: резонансный шум на ~1.6 кГц."""
    dur = 1.5
    t = np.arange(int(dur * RATE), dtype=np.float32) / RATE
    rng = np.random.default_rng(21)
    sig = rng.standard_normal(t.size).astype(np.float32)
    # Узкополосный фильтр: три прохода скользящей средней + синусовая модуляция.
    for width in (24, 12, 6):
        sig = np.convolve(sig, np.ones(width, dtype=np.float32) / width, mode="same")
    wobble = 1.0 + 0.12 * np.sin(2 * np.pi * 7.0 * t)
    sig *= wobble
    sig += 0.18 * np.sin(2 * np.pi * 1580.0 * t) * wobble
    return sig


def crash() -> np.ndarray:
    """Удар: низкий бамп + металлический шум с быстрым затуханием."""
    dur = 0.9
    t = np.arange(int(dur * RATE), dtype=np.float32) / RATE
    rng = np.random.default_rng(3)
    thump = np.sin(2 * np.pi * (70.0 - 40.0 * t) * t) * np.exp(-6.0 * t)
    metal = rng.standard_normal(t.size).astype(np.float32) * np.exp(-9.0 * t)
    metal += 0.5 * np.sin(2 * np.pi * 420.0 * t) * np.exp(-11.0 * t)
    metal += 0.35 * np.sin(2 * np.pi * 690.0 * t) * np.exp(-14.0 * t)
    return thump * 1.4 + metal * 0.9


def checkpoint() -> np.ndarray:
    """Короткий двухтональный сигнал прохождения чекпоинта."""
    dur = 0.32
    t = np.arange(int(dur * RATE), dtype=np.float32) / RATE
    sig = np.zeros_like(t)
    half = t.size // 2
    sig[:half] += np.sin(2 * np.pi * 880.0 * t[:half])
    sig[half:] += np.sin(2 * np.pi * 1320.0 * t[half:])
    return sig * _envelope(dur, 0.005, 0.06)


def countdown() -> np.ndarray:
    """3-2-1-GO: три коротких бипа и длинный высокий на «GO»."""
    total = 3.2
    t = np.arange(int(total * RATE), dtype=np.float32) / RATE
    sig = np.zeros_like(t)

    def beep(start: float, length: float, freq: float, amp: float = 0.9) -> None:
        a = int(start * RATE)
        b = min(t.size, a + int(length * RATE))
        seg = t[a:b] - start
        sig[a:b] += amp * np.sin(2 * np.pi * freq * seg) * _envelope(length, 0.004, 0.02)[: b - a]

    beep(0.0, 0.18, 620.0)
    beep(1.0, 0.18, 620.0)
    beep(2.0, 0.18, 620.0)
    beep(3.0, 0.2, 990.0)
    return sig


def ui_click() -> np.ndarray:
    t = np.arange(int(0.07 * RATE), dtype=np.float32) / RATE
    sig = np.sin(2 * np.pi * 1180.0 * t) * np.exp(-55.0 * t)
    sig += 0.35 * np.sin(2 * np.pi * 2360.0 * t) * np.exp(-70.0 * t)
    return sig


def ui_hover() -> np.ndarray:
    t = np.arange(int(0.05 * RATE), dtype=np.float32) / RATE
    return np.sin(2 * np.pi * 760.0 * t) * np.exp(-60.0 * t) * 0.6


def music_menu() -> np.ndarray:
    """Спокойный луп для меню: пэд из аккордов Am - F - C - G (8 с)."""
    dur = 8.0
    t = np.arange(int(dur * RATE), dtype=np.float32) / RATE
    chords = [
        (220.00, 261.63, 329.63),  # Am
        (174.61, 220.00, 261.63),  # F
        (130.81, 196.00, 261.63),  # C
        (196.00, 246.94, 293.66),  # G
    ]
    sig = np.zeros_like(t)
    seg = t.size // len(chords)
    for i, chord in enumerate(chords):
        a = i * seg
        b = (i + 1) * seg if i < len(chords) - 1 else t.size
        for j, f in enumerate(chord):
            wave = 0.5 * np.sin(2 * np.pi * f * t[a:b]) + 0.5 * _saw(f * 0.5 * t[a:b])
            sig[a:b] += wave * (0.22 / (j + 1))
        # Мягкий арпеджио поверх пэда.
        arp = np.zeros(b - a, dtype=np.float32)
        step = int(0.25 * RATE)
        for k in range((b - a) // step):
            f = chord[k % len(chord)] * 2.0
            s = slice(k * step, (k + 1) * step)
            tt = np.arange(s.stop - s.start, dtype=np.float32) / RATE
            arp[s] += np.sin(2 * np.pi * f * tt) * np.exp(-6.0 * tt) * 0.3
        sig[a:b] += arp
    # Плавный кроссфейд начала и конца для бесшовного лупа.
    fade = int(0.08 * RATE)
    ramp = np.linspace(0.0, 1.0, fade, dtype=np.float32)
    sig[:fade] *= ramp
    sig[-fade:] *= ramp[::-1]
    return sig


def music_race() -> np.ndarray:
    """Драйвовый луп гонки: басовая пульсация 8 долей + аккорды (8 с)."""
    dur = 8.0
    t = np.arange(int(dur * RATE), dtype=np.float32) / RATE
    sig = np.zeros_like(t)
    bpm = 140.0
    beat = 60.0 / bpm
    bass_notes = [55.0, 55.0, 65.41, 49.0]  # A1 A1 C2 G1
    step = int(beat * 0.5 * RATE)
    for i in range(t.size // step):
        a = i * step
        b = min(t.size, a + step)
        f = bass_notes[(i // 4) % len(bass_notes)]
        tt = np.arange(b - a, dtype=np.float32) / RATE
        pulse = _saw(f * tt) * np.exp(-9.0 * tt)
        sig[a:b] += pulse * 0.5
        if i % 4 == 2:  # короткий хэт на слабую долю
            noise = np.random.default_rng(100 + i).standard_normal(b - a).astype(np.float32)
            sig[a:b] += noise * np.exp(-40.0 * tt) * 0.18
    chord_t = np.zeros_like(t)
    for f in (110.0, 130.81, 164.81):
        chord_t += 0.16 * (0.5 * np.sin(2 * np.pi * f * t) + 0.5 * _saw(f * t))
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * (1.0 / dur) * t)
    sig += chord_t * swell
    fade = int(0.08 * RATE)
    ramp = np.linspace(0.0, 1.0, fade, dtype=np.float32)
    sig[:fade] *= ramp
    sig[-fade:] *= ramp[::-1]
    return sig


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"Генерация звуков -> {OUT_DIR}")
    _write("engine_loop.ogg", engine_loop(), loop=True)
    _write("tire_squeal.ogg", tire_squeal(), loop=True)
    _write("crash.ogg", crash())
    _write("checkpoint.ogg", checkpoint())
    _write("countdown.ogg", countdown())
    _write("ui_click.ogg", ui_click())
    _write("ui_hover.ogg", ui_hover())
    _write("music_menu.ogg", music_menu(), loop=True)
    _write("music_race.ogg", music_race(), loop=True)


if __name__ == "__main__":
    main()
