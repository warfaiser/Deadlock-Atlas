#!/usr/bin/env python3
"""Загрузка свежего снимка игровых данных Deadlock из Deadlock API.

Скрипт складывает сырые ответы API в data/raw/:
    heroes.json    — список героев (с официальными русскими именами и способностями)
    items.json     — список предметов (с русскими названиями и описаниями)
    builds.json    — по три самые популярные сборки сообщества на каждого героя
    patches.json   — список патчей (для отметки актуальной версии)
    meta.json      — служебная информация: дата снимка, счётчики, параметры запросов

Запуск:
    python3 tools/fetch_raw.py [--lang russian] [--out data/raw] [--builds-per-hero 3]
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
            with urllib.request.urlopen(request, timeout=90) as response:
                raw = response.read().decode("utf-8")
            return json.loads(raw)
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Снимок данных Deadlock из Deadlock API")
    parser.add_argument("--lang", default="russian", help="язык локализации (по умолчанию russian)")
    parser.add_argument("--out", default="data/raw", help="куда складывать сырые JSON")
    parser.add_argument("--builds-per-hero", type=int, default=3, help="сколько сборок брать на героя")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)

    print("1/4 герои …")
    heroes = api_get("/v1/assets/heroes", language=args.lang)
    save(args.out, "heroes", heroes)

    print("2/4 предметы …")
    items = api_get("/v1/assets/items", language=args.lang)
    save(args.out, "items", items)

    print(f"3/4 сборки: по {args.builds_per_hero} самых популярных на героя …")
    builds: dict[str, list] = {}
    hero_list = heroes if isinstance(heroes, list) else list(heroes.values())
    for hero in hero_list:
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
        builds[str(hero_id)] = found
        weekly = [b.get("num_weekly_favorites") for b in found] if isinstance(found, list) else []
        print(f"   • {hero.get('name', hero_id):<24} {len(found) if isinstance(found, list) else 0} сборок {weekly}")
        time.sleep(0.2)
    save(args.out, "builds", builds)

    print("4/4 патчи …")
    try:
        patches = api_get("/v1/patches")
        save(args.out, "patches", patches)
    except SystemExit as error:
        print(f"  ! патчи недоступны: {error}", file=sys.stderr)

    meta = {
        "fetched_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "language": args.lang,
        "builds_per_hero": args.builds_per_hero,
        "source": "Deadlock API (https://deadlock-api.com/)",
        "counts": {
            "heroes": len(hero_list),
            "items": len(items) if isinstance(items, list) else None,
            "heroes_with_builds": sum(1 for value in builds.values() if value),
            "builds": sum(len(value) for value in builds.values() if isinstance(value, list)),
        },
    }
    save(args.out, "meta", meta)
    print("Готово:", json.dumps(meta["counts"], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
