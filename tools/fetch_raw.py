#!/usr/bin/env python3
"""Снимок игровых данных Deadlock из Deadlock API.

Складывает сырые ответы API в каталог data/raw/:

    heroes_all.json      — все герои из файлов игры (включая тех, кого ещё не выпустили)
    heroes.json          — выпущенные (активные) герои — те, что есть в игре
    items.json           — предметы магазина с русскими названиями и описаниями
    builds.json          — словарь {hero_id: [самые популярные сборки сообщества]}
    patches.json         — лента патчей
    client_versions.json — версии клиента игры
    meta.json            — дата снимка, версия игры и счётчики

Запуск:
    python3 tools/fetch_raw.py [--lang russian] [--out data/raw] [--builds-per-hero 6]
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
    print(f"  → {path} ({size_kb} КБ)")
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
    parser.add_argument("--builds-per-hero", type=int, default=6, help="сколько сборок брать на героя")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)

    print("1/6 версии клиента …")
    client_versions = api_get("/v1/assets/client-versions")
    save(args.out, "client_versions", client_versions)

    print("2/6 все герои из файлов игры …")
    heroes_all = as_list(api_get("/v1/assets/heroes", language=args.lang))
    save(args.out, "heroes_all", heroes_all)

    print("3/6 выпущенные герои …")
    heroes = as_list(api_get("/v1/assets/heroes", language=args.lang, only_active="true"))
    save(args.out, "heroes", heroes)

    print("4/6 предметы …")
    items = as_list(api_get("/v1/assets/items", language=args.lang))
    save(args.out, "items", items)

    print(f"5/6 сборки: до {args.builds_per_hero} самых популярных на героя …")
    builds: dict[str, list] = {}
    for hero in heroes:
        hero_id = hero.get("id")
        if hero_id is None:
            continue
        found = api_get(
            "/v1/builds",
            hero_id=hero_id,
            limit=args.builds_per_hero,
            sort_by="weekly_favorites",
            sort_direction="desc",
        )
        found_list = as_list(found)
        builds[str(hero_id)] = found_list
        weekly = [build.get("num_weekly_favorites") or 0 for build in found_list]
        print(f"   • {str(hero.get('name')):<24} {len(found_list):>2} сборок, избранное за неделю: {weekly}")
        time.sleep(0.2)
    save(args.out, "builds", builds)

    print("6/6 патчи …")
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
            "heroes_with_builds": sum(1 for value in builds.values() if value),
            "builds": sum(len(value) for value in builds.values()),
        },
    }
    save(args.out, "meta", meta)
    print("Готово:", json.dumps(meta["counts"], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
