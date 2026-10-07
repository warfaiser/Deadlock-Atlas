#!/usr/bin/env python3
"""Собирает готовый набор данных Atlas из сырого снимка Deadlock API.

Вход  (см. tools/fetch_raw.py):
    data/raw/heroes.json, heroes_all.json, items.json, builds.json,
    hero_<id>.json, patches.json, client_versions.json, meta.json,
    localizations/russian.json, localizations/english.json

Выход:
    data/heroes.json    — выпущенные герои: русские имена, роль, стиль, лор,
                          характеристики, оружие и способности
    data/items.json     — предметы магазина: русское имя, цена, тир, слот,
                          характеристики и описание эффекта
    data/builds.json    — по три популярные сборки сообщества на героя
                          с порядком покупок по группам
    data/upcoming.json  — герои, которых ещё не выпустили (по голосованию)
    data/meta.json      — дата снимка, версия клиента, патч и счётчики
    data/README.md      — описание формата

Запуск:
    python3 tools/build_dataset.py --raw data/raw --out data
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone

# ---------------------------------------------------------------------------
# Тексты, которых ещё нет в официальной русской локализации.
# Valve выпускает переводы с задержкой: у Буси (Baba, 6 октября 2026) и ещё у
# нескольких свежих способностей русский текст не успел появиться.
# Ниже — перевод проекта Deadlock Atlas.
# ---------------------------------------------------------------------------
RU_TEXTS: dict[str, dict[str, str]] = {
    "ability_baba_bubbling_brew": {
        "name": "Ниткопряд",
        "desc": (
            "Буся плетёт нить, которая следует за прицелом и взрывается вдоль своего пути, "
            "нанося спиритический урон и высасывая у врагов спиритическую мощь — для Буси она "
            "особенно эффективна.\n\nПока у Буси есть украденная спиритическая мощь, каждый "
            "попавший в цель выстрел наносит дополнительный спиритический урон."
        ),
        "t1": "+8 спиритического урона пули",
        "t2": "-12 сек. перезарядки\n+8 сек. длительности эффекта",
        "t3": "+1 заряд\nПри попадании: тянет врагов на 7 м",
    },
    "ability_baba_bench_run": {
        "name": "Бабушкины ходули",
        "desc": (
            "Ножки скамейки вытягиваются: Буся получает прибавку к скорости передвижения, выше "
            "прыгает, а также сопротивление отрицательным эффектам и ближнему бою.\n\n"
            "Лёгкий удар: пинок, отбрасывающий врагов.\n"
            "Тяжёлый удар: удар по земле — подбрасывает врагов, замедляет их и наносит "
            "спиритический урон.\n\nУдерживай приседание, чтобы зарядить высокий прыжок."
        ),
        "t1": "+2,5 м/с к скорости передвижения",
        "t2": "-7 сек. перезарядки",
        "t3": "+15% к сопротивлению урону\n+50% к краже здоровья от ближнего боя",
    },
    "ability_baba_hexing_brew": {
        "name": "Бабулино варево",
        "desc": (
            "Буся заваривает чайник магического чая: брошенное варево накладывает эффект по "
            "области, циклично меняясь между успокаивающим барьером, немотой и обжигающим "
            "ожогом, который наносит спиритический урон в секунду и снижает сопротивление "
            "спиритическому урону у врагов.\n\nНажми прицеливание, чтобы приостановить или "
            "продолжить заваривание."
        ),
        "t3": "+33,33% к силе эффекта варева",
    },
    "ability_baba_ultimate_2": {
        "name": "Накормить птиц",
        "desc": (
            "Буся осыпает цели перед собой хлебом, накладывая суммирующееся замедление.\n\n"
            "Когда канал завершается, стая голубей бомбит цель: наносит спиритический урон и "
            "превращает цель в голубя. Урон и длительность растут с числом крошек на цели."
        ),
        "t1": "+4 м к дальности применения\n+32% к максимальному замедлению",
        "t2": "+40 к максимальному урону",
        "t3": "+125 к максимальному урону\n+1,5 к спиритическому скалированию\n"
        "+0,5 сек. к максимальной длительности",
    },
    "citadel_ability_shiv_killing_blow": {
        "name": "Добивающий удар",
        "desc": (
            "Заточка выполняет смертельный удар: цель получает большой урон, а если её здоровье "
            "опустилось ниже порога, она погибает мгновенно. Чем выше шкала ярости, тем сильнее "
            "добивание."
        ),
        "t1": "+6 м к дальности\n+2 м/с при полной ярости",
        "t2": "+16% к урону при полной ярости\n-25 сек. перезарядки",
        "t3": "+10% к порогу здоровья врага",
    },
    "ability_necro_gravestone": {
        "name": "Загробный договор",
        "desc": (
            "Грейвс устанавливает надгробие, которое притягивает врагов и призывает вурдалаков. "
            "Вурдалаки набрасываются на всё в радиусе, замедляя врагов и нанося им урон."
        ),
        "t1": "+25% к скорости вурдалаков\n-15 сек. перезарядки",
        "t2": "+10 сек. к длительности\n-0,3 сек. ко времени появления",
        "t3": "При смерти цели: урон в размере +5% от текущего здоровья",
    },
    "ability_werewolf_kickflip": {
        "name": "Пинок",
        "desc": (
            "Сильвер с разворота бьёт ногой, отбрасывая врагов и нанося дополнительный урон. "
            "Попавшие под пинок герои получают метку."
        ),
        "t2": "При попадании по герою: восстанавливает 2 единицы выносливости",
        "t3": "+80 к дополнительному урону; получившие пинок враги наносят -35% урона в течение 5 с",
    },
    "ability_drifter_hunger": {
        "desc": (
            "Когда у вражеских героев мало здоровья, вы наносите им усиленный урон. Такие враги "
            "оставляют за собой кровавый след, пока двигаются."
        ),
    },
}

# ---------------------------------------------------------------------------
# Служебные словари
# ---------------------------------------------------------------------------
# Значения игровых токенов вида {g:citadel_inline_attribute:'SpiritDamage'}.
# Точные числа остаются в блоке «характеристики», поэтому в тексте достаточно
# названия эффекта.
ATTR_GENITIVES_RU: dict[str, str] = {
    "AbilityCooldown": "перезарядки",
    "BonusFireRate": "повышенной скорострельности",
    "BonusMoveSpeed": "увеличенной скорости передвижения",
    "BonusSpiritDamage": "доп. спиритического урона",
    "BonusSprintSpeed": "бонусной скорости бега",
    "BonusWeaponDamage": "доп. урона от оружия",
    "BulletDamage": "урона от пуль",
    "BulletResist": "сопротивляемости пулям",
    "CombatBarrier": "барьера",
    "Courage": "храбрости",
    "DamageAmp": "повышенного урона",
    "FireRate": "скорострельности",
    "Fortitude": "стойкости",
    "Heal": "лечения",
    "Healing": "лечения",
    "Heals": "лечения",
    "Health": "здоровья",
    "Immobilize": "обездвиживания",
    "KnockBack": "отбрасывания",
    "KnockUp": "подбрасывания",
    "MaxHealth": "макс. здоровья",
    "MeleeDamage": "урона ближнего боя",
    "MoveSpeed": "скорости передвижения",
    "Pull": "притягивания",
    "Pulling": "притягивания",
    "Pulls": "притягивания",
    "PureDamage": "чистого урона",
    "ReducedFireRate": "уменьшения скорострельности",
    "Regen": "восстановления",
    "Silence": "безмолвия",
    "Sleep": "сна",
    "Slow": "замедления",
    "SlowResistance": "сопротивляемости замедлению",
    "Spirit": "спиритической мощи",
    "SpiritDPS": "постепенного спиритического урона",
    "SpiritDamage": "спиритического урона",
    "SpiritResist": "сопротивляемости спиритизму",
    "StaminaRegenPerSecond": "восстановления выносливости",
    "Stun": "оглушения",
    "WeaponDPS": "постепенного урона от оружия",
    "WeaponDamage": "урона от оружия",
}


ATTR_NAMES_RU: dict[str, str] = {}  # заполняется из локализации: InlineAttribute_*
ATTR_GEN_RU: dict[str, str] = {}    # официальное имя → форма при числительном
HERO_NAME_RU = ""                   # имя героя для токена {s:hero_name}
CURRENT_ATTRS: dict[str, tuple[str, str]] = {}  # ключ атрибута → (имя, форма при числительном)

INLINE_ATTR_RU: dict[str, str] = {
    "spiritdamage": "спиритический урон",
    "spiritdps": "спиритический урон в секунду",
    "spiriticon": "спиритическая мощь",
    "bonusspiritdamage": "дополнительный спиритический урон",
    "weapondamage": "урон от оружия",
    "bonusweapondamage": "дополнительный урон от оружия",
    "bulletdamage": "урон пули",
    "meleedamage": "урон ближнего боя",
    "puredamage": "чистый урон",
    "heal": "лечение",
    "heals": "лечение",
    "healing": "лечение",
    "regen": "восстановление здоровья",
    "spiritresist": "сопротивление спиритическому урону",
    "bulletresist": "сопротивление пулевому урону",
    "maxhealth": "максимальный запас здоровья",
    "slow": "замедление",
    "stun": "оглушение",
    "silence": "немота",
    "pulls": "притягивание",
    "pull": "притягивание",
    "movespeed": "скорость передвижения",
    "bonusmovespeed": "скорость передвижения",
    "combatbarrier": "боевой барьер",
    "barrier": "барьер",
    "reducedfirerate": "снижение скорости стрельбы",
    "firerate": "скорострельность",
    "bonusfirerate": "дополнительная скорострельность",
    "immobilize": "обездвиживание",
    "slowresistance": "сопротивление замедлению",
    "spirit": "спиритическая мощь",
    "knockup": "подбрасывание",
    "debuffresist": "сопротивление отрицательным эффектам",
    "stamina": "выносливость",
}

PROPERTY_LABELS_RU: dict[str, str] = {
    "Stolen Spirit Effectiveness": "Эффективность кражи духа",
    "Spirit Stolen per Hit": "Кража духа за попадание",
    "Max Spirit Stolen": "Максимум украденного духа",
    "Max Stacks": "Максимум стаков",
    "Burst Delay": "Задержка взрыва",
    "Burst Interval": "Интервал взрывов",
    "Burn DPS": "Урон в секунду при горении",
    "Burn Spirit Resist": "Снижение сопр. спиритическому урону",
    "Initial Brew Time": "Начальное время заваривания",
    "Max Slow": "Максимальное замедление",
    "Max Pigeons Per Target": "Максимум голубей на цель",
    "Lock-on Time Per Pigeon": "Время прицеливания на голубя",
    "Time To Max Stacks": "Время до максимума стаков",
    "Damage Per Hit Increase": "Рост урона за попадание",
    "Heavy Melee Damage": "Урон тяжёлого удара",
    "Heavy Melee Movement Slow": "Замедление тяжёлым ударом",
    "Heavy Melee Slow Duration": "Длительность замедления тяжёлым ударом",
    "Melee Resist": "Сопротивление ближнему бою",
    "Light Kick Knockback": "Отбрасывание лёгким пинком",
}

BINDINGS_RU = {
    "Crouch": "приседание",
    "ADS": "прицеливание",
    "Jump": "прыжок",
    "Melee": "ближний бой",
    "Fire": "огонь",
    "Reload": "перезарядка",
    "Ability1": "умение 1",
    "Ability2": "умение 2",
    "Ability3": "умение 3",
    "Ability4": "умение 4",
    "MoveForward": "движение вперёд",
    "MoveBackward": "движение назад",
    "MoveLeft": "движение влево",
    "MoveRight": "движение вправо",
    "Interact": "взаимодействие",
    "Zoom": "приближение",
    "Scoreboard": "таблица счёта",
    "Shop": "магазин",
    "Attack": "атака",
    "AbilityMelee": "ближний бой",
    "AltCast": "альтернативное применение",
    "Mantle": "перелезание",
    "Roll": "перекат",
    "HeldItem": "использование предмета",
    "Zipline": "зиплайн",
    "OpenHeroSheet": "лист героя",
    "Ping": "метка",
    "PurchaseQuickbuy": "быстрая покупка",
}

HERO_TYPE_RU = {
    "marksman": "Стрелок",
    "mystic": "Мистик",
    "brawler": "Боец",
    "assassin": "Ассасин",
}

# Даты выпуска новых героев и расписание голосования (Valve, октябрь 2026).
NEW_HEROES = {
    "hero_ratking": {"released_at": "2026-10-02", "note": "Победитель первого голосования"},
    "hero_baba": {"released_at": "2026-10-06", "note": "Победитель второго голосования"},
}
# Даты релизов оставшихся героев известны, а порядок определяет голосование игроков,
# поэтому дату нельзя привязать к конкретному герою.
RELEASE_DATES = ["2026-10-09", "2026-10-13", "2026-10-16", "2026-10-20"]

PATCH_NAME = "City Never Sleeps"

TAG_RE = re.compile(r"<[^>]+>")
TOKEN_RE = re.compile(r"\{([a-z]):([^}]*)\}")
TOKEN_ARG_RE = re.compile(r"'([^']*)'")
BR_RE = re.compile(r"<br\s*/?>", re.I)
WS_RE = re.compile(r"[ \t]+")
NL_RE = re.compile(r"\n{3,}")
UNIT_RE = re.compile(r"^(-?[\d.,]+)\s*(m/s|m|s|%)$")
PUNCT_RE = re.compile(r"\s+([,.;:!?])")


# ---------------------------------------------------------------------------
# Текст
# ---------------------------------------------------------------------------
def attr_key(text: str) -> str:
    """Ключ для русских названий атрибутов: сохраняет кириллицу."""
    return re.sub(r"[^0-9a-zа-яё]+", "", (text or "").lower())


def normalize_key(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", (text or "").lower())


def strip_html(text: str) -> str:
    """Убирает разметку, оставляя читаемый текст."""
    if not text:
        return ""
    text = BR_RE.sub("\n", text)
    text = TAG_RE.sub("", text)
    text = html.unescape(text)
    text = text.replace("\u00a0", " ")
    text = WS_RE.sub(" ", text)
    text = "\n".join(line.strip() for line in text.split("\n"))
    text = NL_RE.sub("\n\n", text)
    return text.strip()


UNIT_RU = {"m": " м", "m/s": " м/с", "s": " с.", "%": "%"}


def measure(value, postfix: str | None) -> str:
    """Приводит значение свойства к виду «28%», «20 м», «4 с.»."""
    postfix = PROPERTY_LABELS_RU.get(postfix or "", postfix) or ""
    if isinstance(value, str):
        match = UNIT_RE.match(value.strip())
        if match:
            number, unit = match.groups()
            return f"{number}{postfix or UNIT_RU[unit]}"
    text = f"{value:g}" if isinstance(value, float) else str(value)
    return f"{text}{postfix}" if postfix else text


def format_bonus(bonus, postfix: str | None) -> str:
    """Улучшение предмета: «+45%», «-4 с.», «+3 м/с»."""
    postfix = PROPERTY_LABELS_RU.get(postfix or "", postfix) or ""
    if isinstance(bonus, str):
        match = UNIT_RE.match(bonus.strip())
        if match:
            number, unit = match.groups()
            sign = "" if number.startswith("-") else "+"
            return f"{sign}{number}{postfix or UNIT_RU[unit]}"
    try:
        number = float(bonus)
    except (TypeError, ValueError):
        return str(bonus)
    return f"{number:+g}{postfix}"


# Свойства, у которых ноль или минус означает «эффекта нет».
EMPTY_WHEN_ZERO = {
    "AbilityCooldown",
    "AbilityDuration",
    "AbilityCastRange",
    "AbilityCastDelay",
    "AbilityChannelTime",
    "AbilityPostCastDuration",
    "AbilityCharges",
    "AbilityCooldownBetweenCharge",
    "AbilityResourceCost",
    "ChannelMoveSpeed",
    "TechPower",
    "WeaponPower",
}


def stat_list(properties: dict) -> list[dict]:
    """Характеристики объекта: подпись + значение, без служебных полей."""
    result = []
    for name, prop in (properties or {}).items():
        label = PROPERTY_LABELS_RU.get(prop.get("label") or "", prop.get("label"))
        if not label:
            continue  # у служебных свойств нет подписи
        value = prop.get("value")
        if value in (None, "", 0, "0", 0.0, "0.0", -1, "-1","-1.0"):
            continue
        if name in EMPTY_WHEN_ZERO:
            try:
                if float(value) <= 0:
                    continue
            except (TypeError, ValueError):
                pass
        result.append({"label": label, "value": measure(value, prop.get("postfix"))})
    return result


def attribute_text(name: str, properties: dict) -> str:
    """Подпись атрибута: «значение + название (в форме при числительном)»."""
    target = normalize_key(name)
    value = ""
    for key, prop in (properties or {}).items():
        if normalize_key(key) == target:
            raw = prop.get("value")
            if raw not in (None, "", 0, "0", 0.0, "0.0", -1, "-1"):
                value = measure(raw, prop.get("postfix"))
            break
    pair = CURRENT_ATTRS.get(target)
    label = pair[0] if pair else INLINE_ATTR_RU.get(target, "")
    if value:
        if pair and pair[1]:
            return f"{value} {pair[1]}"
        return f"{value} {label}".strip() if label else value
    return label


def resolve_tokens(text: str, properties: dict) -> str:
    """Подставляет русские названия эффектов вместо игровых токенов."""

    def spaced(match: re.Match, text: str) -> str:
        if not text:
            return text
        if match.start() > 0:
            previous = match.string[match.start() - 1]
            if (previous.isalnum() and text[0].isalnum()) or (
                previous == "%" and text[0].isdigit()
            ):
                return " " + text
        return text

    def replace(match: re.Match) -> str:
        args = TOKEN_ARG_RE.findall(match.group(2))
        if not args:
            return ""
        key = args[0]
        kind = match.group(1)
        body = match.group(2)
        if "inline_attribute" in body:
            return spaced(match, attribute_text(key, properties))
        if "binding" in body:
            cleaned = key.split(".")[-1]
            return spaced(match, BINDINGS_RU.get(key, BINDINGS_RU.get(cleaned, cleaned)))
        if kind == "s":
            if key.lower() == "hero_name":
                return HERO_NAME_RU
            return spaced(match, attribute_text(key, properties))
        return ""  # {i:...} — динамическое число, подставляется движком

    return TOKEN_RE.sub(replace, text)


def tidy(text: str) -> str:
    text = re.sub(r"(%)\s*%", r"\1", text)
    text = re.sub(r"(с\.)\s*s\b", r"\1", text)
    text = re.sub(r"(\d)\s+(%|с\.)", r"\1\2", text)
    text = PUNCT_RE.sub(r"\1", text)
    text = re.sub(r"\(\s*\)", "", text)
    text = re.sub(r"\s{2,}", " ", text)
    text = re.sub(r"\n +", "\n", text)
    text = re.sub(r"\s+\.", ".", text)
    return text.strip()


def clean_text(text: str, properties: dict | None = None) -> str:
    if not text:
        return ""
    text = resolve_tokens(text, properties or {})
    return tidy(strip_html(text))


def replacement_map(name_map: dict[str, str]) -> list[tuple[re.Pattern, str]]:
    pairs = []
    for english, russian in name_map.items():
        if not english or not russian or english == russian:
            continue
        pairs.append((re.compile(rf"(?<![A-Za-z]){re.escape(english)}(?![A-Za-z])"), russian))
    return sorted(pairs, key=lambda pair: -len(pair[0].pattern))


def localize_names(text: str, pairs: list[tuple[re.Pattern, str]]) -> str:
    if not text:
        return ""
    for pattern, russian in pairs:
        text = pattern.sub(russian, text)
    return text


def has_cyrillic(text: str) -> bool:
    return bool(re.search("[а-яА-Я]", text or ""))


def compose_description(item: dict, upgrades: list[dict], stats: list[dict]) -> str:
    """Описание предмета из его улучшений, если у Valve нет готового текста."""
    bonuses = upgrades[0]["bonuses"] if upgrades else []
    parts = []
    for bonus in bonuses:
        label = (bonus.get("label") or "").strip()
        value = (bonus.get("value") or "").strip()
        if not label or not value:
            continue
        parts.append(f"{label[0].lower() + label[1:]} {value}")
    if not parts:
        for stat in stats[:5]:
            label = (stat.get("label") or "").strip()
            if label and stat.get("value"):
                parts.append(f"{label[0].lower() + label[1:]} {stat['value']}")
    if not parts:
        return ""
    prefix = "Активно" if item.get("is_active_item") else "Пассивно"
    if len(parts) == 1:
        return f"{prefix}: {parts[0]}."
    return f"{prefix}: " + ", ".join(parts) + "."


BUILD_LABEL_RE = re.compile(r"^#([A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+)$")


def build_label(text: str, loc_ru: dict, loc_en: dict) -> str:
    """Подписи сборок вида «#Citadel_HeroBuilds_EarlyGame» превращает в русский текст."""
    text = (text or "").strip()
    match = BUILD_LABEL_RE.match(text)
    if not match:
        return text
    key = match.group(1)
    local = loc_ru.get(key)
    if isinstance(local, str) and local.strip():
        return local.strip()
    english = loc_en.get(key)
    if isinstance(english, str) and english.strip():
        return english.strip()
    return re.sub(r"(?<!^)(?=[A-Z])", " ", key).replace("_", " ").strip()


def load_json(path: str, default=None):
    if not os.path.exists(path):
        if default is None:
            raise SystemExit(f"Не найден файл {path}")
        return default
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


# ---------------------------------------------------------------------------
# Сборка
# ---------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(description="Сборка набора данных Atlas")
    parser.add_argument("--raw", default="data/raw", help="каталог сырого снимка")
    parser.add_argument("--out", default="data", help="каталог готового набора")
    parser.add_argument("--builds-per-hero", type=int, default=3, help="сборок на героя")
    parser.add_argument("--builds-max-age-days", type=int, default=90, help="свежесть сборок в днях")
    args = parser.parse_args()

    raw, out = args.raw, args.out
    os.makedirs(out, exist_ok=True)

    loc_ru = load_json(os.path.join(raw, "localizations", "russian.json"), {})
    loc_en = load_json(os.path.join(raw, "localizations", "english.json"), {})
    api_heroes = load_json(os.path.join(raw, "heroes.json"), [])
    api_heroes_all = load_json(os.path.join(raw, "heroes_all.json"), [])
    api_items = load_json(os.path.join(raw, "items.json"), [])
    api_builds = load_json(os.path.join(raw, "builds.json"), {})
    client_versions = load_json(os.path.join(raw, "client_versions.json"), [])
    snapshot = load_json(os.path.join(raw, "meta.json"), {})
    patches = load_json(os.path.join(raw, "patches.json"), [])

    # Официальные названия встроенных атрибутов («Спиритический урон» и т. п.).
    for key, value in loc_ru.items():
        if key.startswith("InlineAttribute_") and isinstance(value, str):
            ATTR_NAMES_RU[normalize_key(key[len("InlineAttribute_"):])] = value
    for token, gent in ATTR_GENITIVES_RU.items():
        name = ATTR_NAMES_RU.get(normalize_key(token))
        if name:
            ATTR_GEN_RU[attr_key(name)] = gent
    for token, name in ATTR_NAMES_RU.items():
        CURRENT_ATTRS[token] = (name, ATTR_GEN_RU.get(attr_key(name), ""))

    snapshot_date = (snapshot.get("fetched_at") or datetime.now(timezone.utc).isoformat())[:10]
    client_version = max(client_versions) if client_versions else None

    # Имена героев по-английски → по-русски: чтобы в описаниях способностей
    # английские имена не оставались («Rat King» → «Крысиный король»).
    hero_names = [
        (loc_en.get(hero["class_name"]), loc_ru.get(hero["class_name"]))
        for hero in api_heroes_all
        if loc_en.get(hero["class_name"]) and loc_ru.get(hero["class_name"])
    ]
    name_pairs = replacement_map(dict(hero_names))

    # -----------------------------------------------------------------
    # Предметы
    # -----------------------------------------------------------------
    shop = [item for item in api_items if item.get("type") == "upgrade" and not item.get("disabled")]
    by_id: dict[int, dict] = {item["id"]: item for item in api_items}
    weapons = {item["class_name"]: item for item in api_items if item.get("type") == "weapon"}

    def tier_upgrades(item: dict) -> list[dict]:
        properties = item.get("properties") or {}
        tiers = []
        for index, upgrade in enumerate(item.get("upgrades") or [], start=1):
            bonuses = []
            for upgrade_property in upgrade.get("property_upgrades") or []:
                name = upgrade_property.get("name")
                bonus = upgrade_property.get("bonus")
                if bonus in (None, "", "0", 0, 0.0):
                    continue
                prop = properties.get(name) or {}
                label = PROPERTY_LABELS_RU.get(prop.get("label") or "", prop.get("label")) or name
                bonuses.append({"label": label, "value": format_bonus(bonus, prop.get("postfix"))})
            if bonuses:
                tiers.append({"tier": index, "bonuses": bonuses})
        return tiers

    def item_description(item: dict) -> tuple[str, str]:
        class_name = item["class_name"]
        properties = item.get("properties") or {}
        official = loc_ru.get(f"{class_name}_desc")
        if official:
            text = clean_text(official, properties)
            if text and has_cyrillic(text):
                return localize_names(text, name_pairs), "official"
        api_desc = (item.get("description") or {}).get("desc")
        if api_desc:
            text = clean_text(api_desc, properties)
            if text and has_cyrillic(text):
                return localize_names(text, name_pairs), "official"
        return "", ""

    items = []
    for item in sorted(shop, key=lambda entry: (entry.get("item_tier") or 0, entry.get("cost") or 0)):
        class_name = item["class_name"]
        description, description_source = item_description(item)
        stats = stat_list(item.get("properties") or {})
        upgrades = tier_upgrades(item)
        if not description:
            description = compose_description(item, upgrades, stats)
            description_source = "generated" if description else ""
        items.append(
            {
                "id": item["id"],
                "class_name": class_name,
                "name": item.get("name"),
                "name_en": loc_en.get(class_name) or "",
                "cost": item.get("cost"),
                "tier": item.get("item_tier"),
                "slot": item.get("item_slot_type"),
                "activation": item.get("activation"),
                "is_active": bool(item.get("is_active_item")),
                "description": description,
                "description_source": description_source,
                "stats": stats,
                "upgrades": upgrades,
                "image": item.get("image_webp") or item.get("image"),
                "shop_image": item.get("shop_image_webp") or item.get("shop_image"),
            }
        )

    # -----------------------------------------------------------------
    # Герои и способности
    # -----------------------------------------------------------------
    def ability_entry(entry: dict) -> dict | None:
        class_name = entry["class_name"]
        properties = entry.get("properties") or {}
        override = RU_TEXTS.get(class_name) or {}
        ru_official = loc_ru.get(f"{class_name}_desc")
        api_desc = (entry.get("description") or {}).get("desc") or ""

        if override.get("desc"):
            description, description_source = override["desc"], "translated"
        elif ru_official:
            description = localize_names(clean_text(ru_official, properties), name_pairs)
            description_source = "official"
        elif api_desc:
            description = localize_names(clean_text(api_desc, properties), name_pairs)
            description_source = "official"
        else:
            description, description_source = "", ""

        name = entry.get("name") or loc_ru.get(class_name) or ""
        if override.get("name"):
            name = override["name"]
        elif not re.search(r"[а-яА-Я]", name):
            name = loc_ru.get(class_name) or name

        upgrades = []
        for tier in (1, 2, 3):
            tier_text = override.get(f"t{tier}", "")
            if not tier_text:
                tier_text = clean_text(loc_ru.get(f"{class_name}_t{tier}_desc") or "", properties)
            if not tier_text:
                tier_text = clean_text(
                    (entry.get("description") or {}).get(f"t{tier}_desc") or "", properties
                )
            if tier_text:
                upgrades.append({"tier": tier, "text": localize_names(tier_text, name_pairs)})

        return {
            "id": entry.get("id"),
            "class_name": class_name,
            "name": name,
            "name_en": loc_en.get(class_name) or entry.get("name"),
            "type": entry.get("ability_type"),
            "description": description,
            "description_source": description_source,
            "upgrades": upgrades,
            "stats": stat_list(properties)[:12],
            "image": entry.get("image_webp") or entry.get("image"),
            "start_trained": bool(entry.get("start_trained")),
        }

    def weapon_entry(class_name: str | None) -> dict | None:
        if not class_name:
            return None
        weapon = weapons.get(class_name)
        if not weapon:
            return None
        info = weapon.get("weapon_info") or {}

        def number(key: str, digits: int = 1):
            value = info.get(key)
            if value in (None, 0, 0.0):
                return None
            return round(value, digits) if isinstance(value, float) else value

        speed = number("bullet_speed", 0)
        return {
            "class_name": class_name,
            "name": weapon.get("name"),
            "image": weapon.get("image_webp") or weapon.get("image"),
            "bullet_damage": number("bullet_damage", 2),
            "pellets": number("bullets", 0),
            "shots_per_second": number("shots_per_second", 2),
            "dps": number("damage_per_second", 1),
            "clip_size": number("clip_size", 0),
            "reload_time": number("reload_duration", 2),
            "bullet_speed": round(speed * 0.0254) if speed else None,
        }

    heroes = []
    global HERO_NAME_RU
    for hero in api_heroes:
        hero_id = hero["id"]
        details = load_json(os.path.join(raw, f"hero_{hero_id}.json"), [])
        starting = hero.get("starting_stats") or {}
        hero_items = hero.get("items") or {}
        HERO_NAME_RU = hero.get("name") or loc_ru.get(hero.get("class_name") or "") or ""

        def stat(key: str):
            return (starting.get(key) or {}).get("value")

        abilities = [
            ability
            for ability in (
                ability_entry(entry)
                for entry in details
                if entry.get("type") == "ability"
                and entry.get("ability_type") not in ("melee", "innate")
            )
            if ability
        ]
        order = {"signature": 1, "ultimate": 2}
        abilities.sort(key=lambda ability: (order.get(ability["type"], 0), ability["id"] or 0))

        popular = hero.get("popular_items") or {}
        popular_items = {
            phase: [
                {
                    "id": entry.get("item_id"),
                    "name": (by_id.get(entry.get("item_id")) or {}).get("name") or entry.get("class_name"),
                    "pick_pct": round(entry.get("pick_pct") or 0, 1),
                    "winrate_pct": round(entry.get("winrate_pct") or 0, 1),
                }
                for entry in entries
            ]
            for phase, entries in popular.items()
            if phase in ("early_game", "mid_game", "late_game")
        }

        class_name = hero["class_name"]
        heroes.append(
            {
                "id": hero_id,
                "class_name": class_name,
                "name": hero.get("name"),
                "name_en": loc_en.get(class_name) or hero.get("search_name") or "",
                "search_name": hero.get("search_name"),
                "type": HERO_TYPE_RU.get(hero.get("hero_type"), hero.get("hero_type")),
                "hero_type": hero.get("hero_type"),
                "complexity": hero.get("complexity"),
                "role": hero.get("description", {}).get("role") or None,
                "playstyle": hero.get("description", {}).get("playstyle") or None,
                "lore": localize_names(hero.get("description", {}).get("lore") or "", name_pairs),
                "tags": hero.get("tags") or [],
                "gun_tag": hero.get("gun_tag"),
                "released": True,
                "release": NEW_HEROES.get(class_name),
                "images": hero.get("images") or {},
                "colors": hero.get("colors") or {},
                "stats": {
                    "health": stat("max_health"),
                    "health_regen": stat("base_health_regen"),
                    "move_speed": stat("max_move_speed"),
                    "sprint_speed": stat("sprint_speed"),
                    "stamina": stat("stamina"),
                    "light_melee": stat("light_melee_damage"),
                    "heavy_melee": stat("heavy_melee_damage"),
                },
                "weapon": weapon_entry(hero_items.get("weapon_primary")),
                "abilities": abilities,
                "popular_items": popular_items,
            }
        )

    # -----------------------------------------------------------------
    # Герои на голосовании
    # -----------------------------------------------------------------
    upcoming = []
    for hero in api_heroes_all:
        if hero.get("development_state") != "pre_release":
            continue
        class_name = hero.get("class_name") or ""
        upcoming.append(
            {
                "id": hero.get("id"),
                "class_name": class_name,
                "name": loc_ru.get(class_name) or hero.get("name"),
                "name_en": loc_en.get(class_name) or hero.get("name"),
                "hero_type": HERO_TYPE_RU.get(hero.get("hero_type")) or None,
                "tags": hero.get("tags") or [],
                "complexity": hero.get("complexity"),
                "images": hero.get("images") or {},
                "vote": {"state": "голосование", "date": None},
            }
        )
    upcoming.sort(key=lambda hero: hero["name"] or "")

    # -----------------------------------------------------------------
    # Сборки
    # -----------------------------------------------------------------
    now = datetime.now(timezone.utc)
    fresh_after = (now - timedelta(days=args.builds_max_age_days)).timestamp()

    def build_entry(raw_build: dict) -> dict:
        hero_build = raw_build["hero_build"]
        groups = []
        seen_items: set[int] = set()
        for category in hero_build["details"].get("mod_categories") or []:
            entries = []
            for mod in category.get("mods") or []:
                item = by_id.get(mod["ability_id"])
                if not item:
                    continue
                seen_items.add(item["id"])
                entries.append(
                    {
                        "id": item["id"],
                        "name": item.get("name"),
                        "cost": item.get("cost"),
                        "tier": item.get("item_tier"),
                        "slot": item.get("item_slot_type"),
                        "annotation": build_label(mod.get("annotation"), loc_ru, loc_en) or None,
                        "imbue_target": mod.get("imbue_target_ability_id") or None,
                    }
                )
            if not entries:
                continue
            groups.append(
                {
                    "title": build_label(category.get("name"), loc_ru, loc_en),
                    "note": clean_text(
                        build_label(category.get("description"), loc_ru, loc_en)
                    ),
                    "optional": bool(category.get("optional")),
                    "items": entries,
                }
            )

        skill_order = [
            {"ability_id": change.get("ability_id"), "level": abs(int(change.get("delta") or 0))}
            for change in ((hero_build["details"].get("ability_order") or {}).get("currency_changes") or [])
            if change.get("currency_type") == 1 and (change.get("delta") or 0) < 0
        ]

        updated = datetime.fromtimestamp(hero_build["last_updated_timestamp"], timezone.utc)
        published = (
            datetime.fromtimestamp(hero_build["publish_timestamp"], timezone.utc)
            if hero_build.get("publish_timestamp")
            else None
        )
        return {
            "id": hero_build["hero_build_id"],
            "name": hero_build.get("name"),
            "author_id": hero_build.get("author_account_id"),
            "description": clean_text(hero_build.get("description") or ""),
            "language": hero_build.get("language"),
            "version": hero_build.get("version"),
            "updated": updated.date().isoformat(),
            "updated_timestamp": hero_build["last_updated_timestamp"],
            "published": published.date().isoformat() if published else None,
            "weekly_favorites": raw_build.get("num_weekly_favorites") or 0,
            "favorites": raw_build.get("num_favorites") or 0,
            "unique_items": len(seen_items),
            "groups": groups,
            "skill_order": skill_order,
        }

    def pick_builds(candidates: list[dict]) -> list[dict]:
        """Три сборки на героя: две самые популярные и одна самая свежая."""
        picked: list[dict] = []
        used_ids: set[int] = set()
        used_names: set[str] = set()

        by_popularity = sorted(
            candidates,
            key=lambda build: (build["weekly_favorites"], build["updated_timestamp"]),
            reverse=True,
        )
        fresh = sorted(
            (build for build in candidates if build["updated_timestamp"] >= fresh_after),
            key=lambda build: (build["weekly_favorites"], build["updated_timestamp"]),
            reverse=True,
        )

        def take(pool: list[dict], unique_names: bool) -> None:
            for build in pool:
                if len(picked) >= args.builds_per_hero:
                    return
                if build["id"] in used_ids:
                    continue
                key = normalize_key(build["name"])
                if unique_names and key and key in used_names:
                    continue
                build["fresh"] = build["updated_timestamp"] >= fresh_after
                picked.append(build)
                used_ids.add(build["id"])
                used_names.add(key)

        take(by_popularity[: max(1, args.builds_per_hero - 1)], True)
        take(fresh, True)
        take(by_popularity, False)
        take(candidates, False)
        return picked[: args.builds_per_hero]

    builds: dict[str, list] = {}
    for hero in heroes:
        prepared: dict[int, dict] = {}
        for entry in api_builds.get(str(hero["id"])) or []:
            build = build_entry(entry)
            # API отдаёт отдельные строки на каждую версию сборки — оставляем свежую.
            known = prepared.get(build["id"])
            if not known or (build["version"] or 0) >= (known["version"] or 0):
                if known:
                    build["weekly_favorites"] = max(build["weekly_favorites"], known["weekly_favorites"])
                prepared[build["id"]] = build
        candidates = sorted(
            prepared.values(),
            key=lambda build: (build["weekly_favorites"], build["updated_timestamp"]),
            reverse=True,
        )
        builds[str(hero["id"])] = pick_builds(candidates)

    # -----------------------------------------------------------------
    # Запись
    # -----------------------------------------------------------------
    counts = {
        "heroes": len(heroes),
        "upcoming": len(upcoming),
        "abilities": sum(len(hero["abilities"]) for hero in heroes),
        "items": len(items),
        "builds": sum(len(value) for value in builds.values()),
    }
    meta = {
        "snapshot": snapshot_date,
        "fetched_at": snapshot.get("fetched_at"),
        "client_version": client_version,
        "patch": {
            "name": PATCH_NAME,
            "title": patches[0]["title"] if patches else None,
            "published": patches[0]["pub_date"] if patches else None,
            "link": patches[0].get("link") if patches else None,
        },
        "language": "ru",
        "source": "Deadlock API (https://deadlock-api.com/)",
        "counts": counts,
        "notes": [
            "Названия, описания, характеристики и лор — официальная русская локализация игры.",
            "Способности и предметы без официального русского текста переведены проектом Atlas "
            "(поле description_source: translated / generated).",
            "Сборки — работы игроков из мастерской Deadlock: порядок покупок, заметки и "
            "идентификатор для копирования сохранены. На каждого героя выбраны две самые "
            "популярные за неделю и одна самая свежая.",
            "Оставшиеся герои City Never Sleeps выходят 9, 13, 16 и 20 октября — порядок "
            "определяет голосование игроков.",
        ],
    }

    def write(name: str, payload) -> None:
        path = os.path.join(out, name)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=1)
            handle.write("\n")
        print(f"  → {path} ({os.path.getsize(path) // 1024} КБ)")

    write("heroes.json", {"snapshot": snapshot_date, "source": meta["source"], "heroes": heroes})
    write("items.json", {"snapshot": snapshot_date, "source": meta["source"], "items": items})
    write("builds.json", {"snapshot": snapshot_date, "source": meta["source"], "builds": builds})
    write(
        "upcoming.json",
        {
            "snapshot": snapshot_date,
            "source": meta["source"],
            "releases": RELEASE_DATES,
            "heroes": upcoming,
        },
    )
    write("meta.json", meta)
    print("Готово:", json.dumps(counts, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
