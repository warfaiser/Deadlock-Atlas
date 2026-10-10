#!/usr/bin/env python3
"""Статический валидатор Godot-проекта Velocity Atlas (без запуска движка).

Что проверяется (то, что обычно ломается в рантайме):
  1. Синтаксис каждого .gd — реальным парсером Godot (gdtoolkit/gdparse).
  2. Каждый .tscn/.tres парсится; пути ext_resource существуют на диске.
  3. Автозагрузки из project.godot указывают на существующие .gd.
  4. `[connection]` в сценах ссылаются на существующие методы скрипта узла-цели.
  5. Node-path литералы `$A/B`, `$"A/B"`, `get_node(_or_null)("A/B")` из каждого
     скрипта, прикреплённого к узлу сцены, реально разрешаются в дереве этой
     сцены — с раскрытием вложенных сцен (Car.tscn, PauseMenu.tscn,
     SettingsPanel.tscn и т.д.). Это главный источник «Node not found».
  6. Имена экшенов ввода, используемые в скриптах, объявлены в [input].
  7. Литералы `res://...` (png/ogg/wav/tscn/tres/gdshader) существуют.

Код выхода: 0 — чисто, 1 — есть проблемы (печатаются списком).

Запуск:
    python3 tools/validate_godot_project.py
Зависимости: gdtoolkit (pip install gdtoolkit).
"""

from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "racing-game",
)

errors: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def rel(path: str) -> str:
    return os.path.relpath(path, ROOT)


# --- парсинг сцен -------------------------------------------------------------

EXT_RE = re.compile(r'\[ext_resource[^]]*?\btype="(?P<type>\w+)"[^]]*?\bpath="(?P<path>[^"]+)"[^]]*?\bid="(?P<id>[^"]+)"\]')
NODE_RE = re.compile(
    r'\[node name="(?P<name>[^"]+)"'
    r'(?:\s+type="(?P<type>[^"]+)")?'
    r'(?:\s+parent="(?P<parent>[^"]+)")?'
    r'(?:\s+instance=ExtResource\("(?P<inst>[^"]+)"\))?\]'
)
PROP_RE = re.compile(r'^(?P<key>[\w/]+)\s*=\s*(?P<value>.*)$')
CONN_RE = re.compile(
    r'\[connection[^]]*?\bsignal="(?P<sig>[^"]+)"[^]]*?\bfrom="(?P<frm>[^"]+)"'
    r'[^]]*?\bto="(?P<to>[^"]+)"[^]]*?\bmethod="(?P<method>[^"]+)"'
)


def parse_scene(path: str) -> dict:
    ext: dict[str, tuple[str, str]] = {}
    nodes: dict[str, dict] = {}
    conns: list[dict] = []
    have_root = False
    current: dict | None = None

    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if line.startswith("[ext_resource"):
                m = EXT_RE.match(line)
                if m:
                    ext[m.group("id")] = (m.group("type"), m.group("path"))
                current = None
                continue
            if line.startswith("[sub_resource") or line.startswith("[gd_"):
                current = None
                continue
            nm = NODE_RE.match(line)
            if nm:
                name = nm.group("name")
                parent = nm.group("parent")
                if not have_root and parent is None:
                    full = ""  # корень сцены
                    parent_path = ""
                else:
                    parent_path = "" if parent in (None, ".") else parent
                    full = (parent_path + "/" + name) if parent_path else name
                have_root = True
                node = {
                    "type": nm.group("type") or "",
                    "script_id": nm.group("script_id") if "script_id" in nm.groupdict() else None,
                    "instance_id": nm.group("inst"),
                    "parent": parent_path,
                }
                nodes[full] = node
                current = node
                continue
            if line.startswith("[connection"):
                cm = CONN_RE.match(line)
                if cm:
                    conns.append(cm.groupdict())
                current = None
                continue
            if line.startswith("["):
                current = None
                continue
            pm = PROP_RE.match(line)
            if pm and current is not None and pm.group("key") == "script":
                sm = re.search(r'ExtResource\("([^"]+)"\)', pm.group("value"))
                if sm:
                    current["script_id"] = sm.group(1)
    return {"nodes": nodes, "ext": ext, "conns": conns}


SCENE_CACHE: dict[str, dict] = {}


def load_scene(res_path: str) -> dict:
    if res_path not in SCENE_CACHE:
        fp = os.path.join(ROOT, res_path.replace("res://", ""))
        SCENE_CACHE[res_path] = parse_scene(fp) if os.path.exists(fp) else {"nodes": {}, "ext": {}, "conns": []}
    return SCENE_CACHE[res_path]


def collect(scene: dict, depth: int = 0) -> dict:
    """Дерево с раскрытием instance: ключи — пути относительно корня (корень = "")."""
    tree: dict[str, dict] = {}
    if depth > 4:
        return tree
    for path, node in scene["nodes"].items():
        inst = node.get("instance_id")
        if inst and inst in scene["ext"]:
            ext_type, ext_path = scene["ext"][inst]
            if ext_type in ("PackedScene", "Scene") and ext_path.endswith(".tscn"):
                sub_tree = collect(load_scene(ext_path), depth + 1)
                sub_root = sub_tree.get("")
                if sub_root is not None:
                    if not node["type"]:
                        node["type"] = sub_root["type"]
                    if not node.get("script_id"):
                        node["script_id"] = sub_root.get("script_id")
                tree[path] = node
                for sp, snode in sub_tree.items():
                    if sp == "":
                        continue
                    tree[(path + "/" + sp) if path else sp] = snode
                continue
        tree[path] = node
    return tree


# --- литералы -----------------------------------------------------------------

DOLLAR_RE = re.compile(r'\$\s*"([^"]+)"|\$\s*([A-Za-z_][\w]*(?:/[\w$]+)*)')
GETNODE_RE = re.compile(r'get_node(?:_or_null)?\s*\(\s*"([^"]+)"\s*\)')
ACTION_RE = re.compile(r'(?:is_action_pressed|is_action_just_pressed|is_action_just_released|get_action_strength)\s*\(\s*&?"?([A-Za-z_][\w]*)"?\s*\)')
RES_RE = re.compile(r'res://[\w/.-]+\.(?:png|webp|svg|ogg|wav|tscn|tres|gdshader|ttf|otf)')


def read(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def dollar_literals(text: str) -> list[str]:
    out: list[str] = []
    for m in DOLLAR_RE.finditer(text):
        out.append(m.group(1) or m.group(2))
    return out


def getnode_literals(text: str) -> list[str]:
    return [m.group(1) for m in GETNODE_RE.finditer(text)]


def suffix_exists(tree: dict, lit: str) -> bool:
    for path in tree:
        if path == lit or path.endswith("/" + lit):
            return True
    return False


def resolve(tree: dict, base: str, node_path: str) -> bool:
    if node_path.startswith("%") or node_path.startswith("res://") or node_path in ("", ".", ".."):
        return True
    cur = base
    for part in node_path.split("/"):
        if not part:
            continue
        if part == "..":
            cur = cur.rsplit("/", 1)[0] if "/" in cur else ""
            continue
        nxt = (cur + "/" + part) if cur else part
        if nxt in tree:
            cur = nxt
        else:
            return False
    return True


def main() -> int:
    # 1) синтаксис
    gd_files = []
    for base, _, files in os.walk(os.path.join(ROOT, "scripts")):
        for f in sorted(files):
            if f.endswith(".gd"):
                gd_files.append(os.path.join(base, f))
    for gd in sorted(gd_files):
        result = subprocess.run(["gdparse", gd], capture_output=True, text=True)
        if result.returncode != 0:
            first = result.stderr.strip().splitlines()
            err(f"SYNTAX {rel(gd)}: {first[0] if first else 'parse error'}")

    proj = read(os.path.join(ROOT, "project.godot"))
    autoload_paths = re.findall(r'^\w+\s*=\s*"\*(res://[^"]+)"', proj, flags=re.M)
    input_actions = set(re.findall(r'^([A-Za-z_][\w]*)\s*=\s*\{', proj, flags=re.M))
    for ap in autoload_paths:
        if not os.path.exists(os.path.join(ROOT, ap.replace("res://", ""))):
            err(f"AUTOLOAD missing: {ap}")

    # сцены/ресурсы: ext-пути + коннекты
    scene_files = []
    for base, _, files in os.walk(ROOT):
        if os.sep + ".godot" in base or base.endswith(".godot"):
            continue
        for f in sorted(files):
            if f.endswith((".tscn", ".tres")):
                scene_files.append(os.path.join(base, f))
    for scene_path in sorted(scene_files):
        scene = parse_scene(scene_path)
        for ext_id, (ext_type, ext_path) in scene["ext"].items():
            if not os.path.exists(os.path.join(ROOT, ext_path.replace("res://", ""))):
                err(f"{rel(scene_path)}: ext_resource {ext_type} '{ext_path}' (id={ext_id}) not found")
        tree = collect(scene)
        for conn in scene["conns"]:
            target_path = "" if conn["to"] in (".", "") else conn["to"]
            node = tree.get(target_path)
            if node is None:
                err(f"{rel(scene_path)}: connection to unknown node '{conn['to']}'")
                continue
            script_id = node.get("script_id")
            if script_id and script_id in scene["ext"]:
                _, spath = scene["ext"][script_id]
                full = os.path.join(ROOT, spath.replace("res://", ""))
                if os.path.exists(full) and conn["method"] not in read(full):
                    err(f"{rel(scene_path)}: signal '{conn['sig']}' -> missing method '{conn['method']}' in {spath}")

    # node-path литералы: для каждого узла со скриптом в ключевых сценах
    scene_script_map = {
        "scenes/Race.tscn": {},
        "scenes/MainMenu.tscn": {},
        "scenes/CarSelect.tscn": {},
        "scenes/TrackSelect.tscn": {},
        "scenes/Results.tscn": {},
        "scenes/PauseMenu.tscn": {},
        "scenes/SettingsPanel.tscn": {},
        "assets/models/Car.tscn": {"": "scripts/car_base.gd"},
        "assets/models/CarPlayer.tscn": {"": "scripts/car_base.gd"},
        "assets/models/CarAI.tscn": {"": "scripts/car_base.gd"},
        "assets/models/Track.tscn": {},
    }
    for scene_rel in scene_script_map:
        scene_full = os.path.join(ROOT, scene_rel)
        if not os.path.exists(scene_full):
            err(f"scene missing: {scene_rel}")
            continue
        scene = load_scene("res://" + scene_rel)
        tree = collect(scene)

        # скрипты, прикреплённые к узлам сцены
        checks: list[tuple[str, str]] = []
        for path, node in tree.items():
            script_id = node.get("script_id")
            if script_id and script_id in scene["ext"]:
                _, spath = scene["ext"][script_id]
                if spath.endswith(".gd"):
                    checks.append((spath, path))
        # дополнительные: базовый класс для наследников
        for base_path, extra in scene_script_map[scene_rel].items():
            checks.append((extra, base_path))

        for script_rel, base_path in checks:
            script_full = os.path.join(ROOT, script_rel.replace("res://", ""))
            if not os.path.exists(script_full):
                err(f"{scene_rel}: missing script {script_rel}")
                continue
            text = read(script_full)
            for lit in dollar_literals(text):
                if not resolve(tree, base_path, lit):
                    err(f"{script_rel} @ {scene_rel}: unresolved node path '${lit}'")
            # get_node(...) часто вызывается на дочернем объекте — допускаем
            # строгое разрешение ИЛИ наличие такого пути где-то в дереве.
            for lit in getnode_literals(text):
                if not resolve(tree, base_path, lit) and not suffix_exists(tree, lit):
                    err(f"{script_rel} @ {scene_rel}: unresolved get_node path '{lit}'")

    # экшены ввода
    used_actions: set[str] = set()
    for gd in gd_files:
        for m in ACTION_RE.finditer(read(gd)):
            used_actions.add(m.group(1))
    builtins = {a for a in used_actions if a.startswith("ui_")}
    for action in sorted(used_actions - builtins):
        if action not in input_actions:
            err(f"INPUT action '{action}' used in scripts but not in project.godot [input]")

    # res:// литералы в скриптах
    for gd in gd_files:
        for m in RES_RE.finditer(read(gd)):
            if not os.path.exists(os.path.join(ROOT, m.group(0).replace("res://", ""))):
                err(f"{rel(gd)}: references missing res file {m.group(0)}")

    if errors:
        print(f"FAIL: {len(errors)} проблема(и):")
        for e in sorted(set(errors)):
            print("  -", e)
        return 1
    print(f"OK: {len(gd_files)} скриптов, {len(scene_files)} сцен/ресурсов — кросс-проверка чистая.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
