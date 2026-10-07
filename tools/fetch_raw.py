#!/usr/bin/env python3
"""Снимок игровых данных Deadlock из Deadlock API.

Складывает сырые ответы API в каталог data/raw/:

    heroes_all.json            — все герои из файлов игры (включая тех, кого ещё не выпустили)
    heroes.json                — выпущенные (активные) герои — те, что доступны в игре
    items.json                 — предметы магазина с русскими названиями и описаниями
    hero_<id>.json             — предметы и способности конкретного героя (русский)
    hero_<id>_en.json          — то же на английском (для героев без русской локализации)
    builds.json                — словарь {hero_id: [самые популярные и свежие сборки сообщества]}
    localizations/russian.json — официальная русская локализация игры
    localizations/english.json — английская локализация (для сверки названий)
    patches.json               — лента патчей
    client_versions.json       — версии клиента игры
    meta.json                  — дата снимка, версия игры и счётчики

Запуск:
    python3 tools/fetch_raw.py [--lang russian] [--out data/raw] [--builds-distinct 8]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

API = "https://api.deadlock-api.com"
USER_AGENT = "Deadlock-Atlas/1.0 (+https://github.com/warfaiser/Deadlock-Atlas)"
LOCALIZATION_URL = (
    "https://raw.githubusercontent.com/deadlock-wiki/deadlock-data/master"
    "/data/localizations/{lang}.json"
)
# Порядок выдачи сборок: сначала самые популярные за неделю, затем недавно обновлённые.
BUILDS_POOL_SORTS = ("weekly_favorites", "updated_at")

# Герои, которых ещё не выпустили: русская локализация способностей для них
# может появиться позже, поэтому дополнительно тянем английский вариант.
UNRELEASED = ("hero_nurse", "hero_chessmaster", "hero_deadpack", "hero_artist", "hero_baba")


def api_get(path: str, **params) -> object:
    """GET-запрос к Deadlock API с повторами и понятными ошибками."""
    query = urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
    url = f"{API}{path}" + (f"?{query}" if query else "")
    last_error: Exception | None = None
    for attempt in range(1, 6):
        request = urllib.request.Request(
            url,
            headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.loads(response.read().decode("utf-8"))
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError) as error:
            last_error = error
            wait = min(2 ** attempt, 20)
            print(f"  ! попытка {attempt} не удалась ({error}); повтор через {wait} c", file=sys.stderr)
            time.sleep(wait)
    raise SystemExit(f"Не удалось получить {url}: {last_error}")


def save(out_dir: str, name: str, payload: object) -> int:
    path = os.path.join(out_dir, f"{name}.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=1)
        handle.write("\n")
    size_kb = os.path.getsize(path) // 1024
    print(f"  → {os.path.basename(path)} ({size_kb} КБ)")
    return size_kb


def download_json(url: str) -> object:
    """Прямая загрузка JSON (локализации игры из deadlock-data)."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.loads(response.read().decode("utf-8"))


def dedup_builds(rows: list, keep: int) -> list:
    """Оставляет по одной (самой свежей) версии каждой сборки — не больше keep штук."""
    newest: dict[int, dict] = {}
    order: list[int] = []
    for row in rows:
        hero_build = row.get("hero_build") or {}
        build_id = hero_build.get("hero_build_id")
        if build_id is None:
            continue
        known = newest.get(build_id)
        if known is None:
            order.append(build_id)
            newest[build_id] = row
        elif (hero_build.get("version") or 0) > ((known.get("hero_build") or {}).get("version") or 0):
            newest[build_id] = row
    return [newest[build_id] for build_id in order[:keep]]


def as_list(payload: object) -> list:
    """API отдаёт героев списком, но подстрахуемся от словаря."""
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        return list(payload.values())
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description="Снимок данных Deadlock из Deadlock API")
    parser.add_argument("--lang", default="russian", help="язык локализации (по умолчанию russian)")
    parser.add_argument("--out", default="data/raw", help="куда складывать сырые JSON")
    parser.add_argument("--builds-distinct", type=int, default=10, help="сколько разных сборок брать на героя")
    parser.add_argument("--builds-pages", type=int, default=2, help="сколько страниц по 100 строк листать")
    parser.add_argument("--skip-hero-details", action="store_true", help="не тянуть предметы и способности по героям")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)

    print("1/8 версии клиента …")
    save(args.out, "client_versions", api_get("/v1/assets/client-versions"))

    print("2/8 все герои из файлов игры …")
    heroes_all = as_list(api_get("/v1/assets/heroes", language=args.lang))
    save(args.out, "heroes_all", heroes_all)

    print("3/8 выпущенные герои …")
    heroes = as_list(api_get("/v1/assets/heroes", language=args.lang, only_active="true"))
    save(args.out, "heroes", heroes)

    print("4/8 предметы магазина …")
    items = as_list(api_get("/v1/assets/items", language=args.lang))
    save(args.out, "items", items)

    hero_details: dict[str, int] = {}
    if not args.skip_hero_details:
        print("5/8 способности и предметы по каждому герою …")
        for hero in heroes:
            hero_id = hero.get("id")
            class_name = hero.get("class_name")
            if hero_id is None:
                continue
            details = as_list(api_get(f"/v1/assets/items/by-hero-id/{hero_id}", language=args.lang))
            hero_details[str(hero_id)] = len(details)
            save(args.out, f"hero_{hero_id}", details)
            if class_name in UNRELEASED:
                details_en = as_list(api_get(f"/v1/assets/items/by-hero-id/{hero_id}", language="english"))
                save(args.out, f"hero_{hero_id}_en", details_en)
            print(f"   • {str(hero.get('name')):<24} {len(details):>2} записей")
            time.sleep(0.15)
    else:
        print("5/8 способности и предметы по героям — пропущено")

    print(f"6/8 сборки: до {args.builds_distinct} разных сборок на героя (популярные и свежие) …")
    popular_quota = max(1, args.builds_distinct // 2)

    def build_pool(hero_id: int, sort_by: str, wanted: int) -> list:
        """Страницы выдачи /v1/builds по одному герою и критерию сортировки."""
        rows: list = []
        seen: set[int] = set()
        for page in range(args.builds_pages):
            chunk = as_list(
                api_get(
                    "/v1/builds",
                    hero_id=hero_id,
                    limit=100,
                    start=page * 100,
                    sort_by=sort_by,
                    sort_direction="desc",
                )
            )
            if not chunk:
                break
            rows.extend(chunk)
            for build in chunk:
                build_id = (build.get("hero_build") or {}).get("hero_build_id")
                if build_id is not None:
                    seen.add(build_id)
            if len(seen) >= wanted:
                break
            time.sleep(0.2)
        return rows

    builds: dict[str, list] = {}
    for hero in heroes:
        hero_id = hero.get("id")
        if hero_id is None:
            continue
        picked = dedup_builds(
            build_pool(hero_id, "weekly_favorites", popular_quota), popular_quota
        )
        have = {(row.get("hero_build") or {}).get("hero_build_id") for row in picked}
        fresh = dedup_builds(build_pool(hero_id, "updated_at", args.builds_distinct), args.builds_distinct)
        for row in fresh:
            if len(picked) >= args.builds_distinct:
                break
            build_id = (row.get("hero_build") or {}).get("hero_build_id")
            if build_id is None or build_id in have:
                continue
            picked.append(row)
            have.add(build_id)
        builds[str(hero_id)] = picked
        weekly = [build.get("num_weekly_favorites") or 0 for build in picked]
        print(f"   • {str(hero.get('name')):<24} {len(picked):>2} сборок, избранное за неделю: {weekly}")
        time.sleep(0.2)
    save(args.out, "builds", builds)

    print("7/8 локализации игры (официальный русский текст) …")
    loc_dir = os.path.join(args.out, "localizations")
    os.makedirs(loc_dir, exist_ok=True)
    for lang in ("russian", "english"):
        try:
            payload = download_json(LOCALIZATION_URL.format(lang=lang))
        except Exception as error:  # noqa: BLE001 — без локализаций снимок тоже полезен
            print(f"  ! локализация {lang} недоступна: {error}", file=sys.stderr)
            continue
        path = os.path.join(loc_dir, f"{lang}.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=1)
            handle.write("\n")
        print(f"  → localizations/{lang}.json ({os.path.getsize(path) // 1024} КБ)")

    print("8/8 патчи …")
    try:
        save(args.out, "patches", api_get("/v1/patches"))
    except SystemExit as error:
        print(f"  ! патчи недоступны: {error}", file=sys.stderr)

    meta = {
        "fetched_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "language": args.lang,
        "builds_distinct": args.builds_distinct,
        "source": "Deadlock API (https://deadlock-api.com/)",
        "counts": {
            "heroes_all": len(heroes_all),
            "heroes": len(heroes),
            "items": len(items),
            "heroes_with_details": len(hero_details),
            "hero_details": sum(hero_details.values()),
            "heroes_with_builds": sum(1 for value in builds.values() if value),
            "builds": sum(len(value) for value in builds.values()),
        },
    }
    save(args.out, "meta", meta)
    print("Готово:", json.dumps(meta["counts"], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
