#!/usr/bin/env python3
"""Снимок игровых данных Deadlock из Deadlock API.

Складывает сырые ответы API в каталог data/raw/:

    heroes_all.json            — все герои из файлов игры (включая тех, кого ещё не выпустили)
    heroes.json                — выпущенные (активные) герои — те, что доступны в игре
    items.json                 — предметы магазина с русскими названиями и описаниями
    hero_<id>.json             — предметы и способности конкретного героя (русский)
    hero_<id>_en.json          — то же на английском (для героев без русской локализации)
    builds.json                — словарь {hero_id: [самые популярные сборки сообщества]}
    patches.json               — лента патчей
    client_versions.json       — версии клиента игры
    meta.json                  — дата снимка, версия игры и счётчики

Запуск:
    python3 tools/fetch_raw.py [--lang russian] [--out data/raw] [--builds-per-hero 25]
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
    parser.add_argument("--builds-per-hero", type=int, default=25, help="сколько строк сборок запрашивать на героя")
    parser.add_argument("--skip-hero-details", action="store_true", help="не тянуть предметы и способности по героям")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)

    print("1/7 версии клиента …")
    save(args.out, "client_versions", api_get("/v1/assets/client-versions"))

    print("2/7 все герои из файлов игры …")
    heroes_all = as_list(api_get("/v1/assets/heroes", language=args.lang))
    save(args.out, "heroes_all", heroes_all)

    print("3/7 выпущенные герои …")
    heroes = as_list(api_get("/v1/assets/heroes", language=args.lang, only_active="true"))
    save(args.out, "heroes", heroes)

    print("4/7 предметы магазина …")
    items = as_list(api_get("/v1/assets/items", language=args.lang))
    save(args.out, "items", items)

    hero_details: dict[str, int] = {}
    if not args.skip_hero_details:
        print("5/7 способности и предметы по каждому герою …")
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
        print("5/7 способности и предметы по героям — пропущено")

    print(f"6/7 сборки: до {args.builds_per_hero} строк на героя (версии одной сборки повторяются) …")
    builds: dict[str, list] = {}
    for hero in heroes:
        hero_id = hero.get("id")
        if hero_id is None:
            continue
        found = as_list(
            api_get(
                "/v1/builds",
                hero_id=hero_id,
                limit=args.builds_per_hero,
                sort_by="weekly_favorites",
                sort_direction="desc",
            )
        )
        builds[str(hero_id)] = found
        weekly = [build.get("num_weekly_favorites") or 0 for build in found]
        print(f"   • {str(hero.get('name')):<24} {len(found):>2} сборок, избранное за неделю: {weekly}")
        time.sleep(0.2)
    save(args.out, "builds", builds)

    print("7/7 патчи …")
    try:
        save(args.out, "patches", api_get("/v1/patches"))
    except SystemExit as error:
        print(f"  ! патчи недоступны: {error}", file=sys.stderr)

    meta = {
        "fetched_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "language": args.lang,
        "builds_per_hero": args.builds_per_hero,
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
