#!/usr/bin/env python3
"""Инструмент для работы с файлом места Roblox (.rbxlx).

  extract <place.rbxlx> <src>            — выгрузить все скрипты места в дерево src/ (имена как в Rojo)
  build   <place.rbxlx> <src> <out>      — собрать новое место: заменить/добавить скрипты из src/
  sourcemap <src> <out.json>             — sourcemap для luau-lsp (проверка типов)

Соответствие имён файлов и классов:
  X.lua         -> ModuleScript
  X.server.lua  -> Script
  X.client.lua  -> LocalScript
"""
import json
import os
import sys
import xml.etree.ElementTree as ET

ET.register_namespace("xsi", "http://www.w3.org/2001/XMLSchema-instance")

SCRIPT_CLASSES = {"Script": ".server.lua", "LocalScript": ".client.lua", "ModuleScript": ".lua"}

# Скрипты, которые в месте лежат в двух экземплярах: сборка копирует один исходник в оба места.
MIRRORS = {
    "StarterGui/MinerClientBootstrap/ClientController.client.lua":
        "StarterPlayer/StarterPlayerScripts/ClientController.client.lua",
}

# Класс контейнера, если его нет в месте и его нужно создать по пути из src/.
CONTAINER_CLASSES = {
    "StarterPlayerScripts": "StarterPlayerScripts",
    "StarterCharacterScripts": "StarterCharacterScripts",
}


def prop(item, name):
    props = item.find("Properties")
    if props is None:
        return None
    for p in props:
        if p.get("name") == name:
            return p
    return None


def item_name(item):
    p = prop(item, "Name")
    return (p.text or "") if p is not None else item.get("class")


def children(item):
    return [c for c in item if c.tag == "Item"]


def split_file_name(fn):
    for cls, ext in (("Script", ".server.lua"), ("LocalScript", ".client.lua"), ("ModuleScript", ".lua")):
        if fn.endswith(ext):
            return fn[: -len(ext)], cls
    return None, None


def cmd_extract(place, src):
    root = ET.parse(place).getroot()
    count = 0

    def walk(item, path):
        nonlocal count
        cls = item.get("class")
        name = item_name(item)
        if cls in SCRIPT_CLASSES:
            rel = os.path.join(*path, name + SCRIPT_CLASSES[cls])
            if rel.replace(os.sep, "/") in MIRRORS:
                return
            dst = os.path.join(src, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            source = prop(item, "Source")
            with open(dst, "w", encoding="utf-8", newline="\n") as f:
                f.write((source.text or "") if source is not None else "")
            count += 1
        for c in children(item):
            walk(c, path + [name])

    for it in root:
        if it.tag == "Item":
            walk(it, [])
    print("extracted %d scripts into %s" % (count, src))


def find_child(parent, name):
    for c in children(parent):
        if item_name(c) == name:
            return c
    return None


def make_item(cls, name):
    it = ET.Element("Item", {"class": cls})
    props = ET.SubElement(it, "Properties")
    n = ET.SubElement(props, "string", {"name": "Name"})
    n.text = name
    return it


def set_source(item, text):
    source = prop(item, "Source")
    if source is None:
        source = ET.SubElement(item.find("Properties"), "ProtectedString", {"name": "Source"})
    source.text = text


def cmd_build(place, src, out):
    tree = ET.parse(place)
    root = tree.getroot()
    files = {}
    for dirpath, _dirs, names in os.walk(src):
        for fn in names:
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, src).replace(os.sep, "/")
            base, cls = split_file_name(fn)
            if cls:
                files[rel] = full
    for mirror, origin in MIRRORS.items():
        if origin in files:
            files[mirror] = files[origin]

    replaced, added = 0, 0
    for rel in sorted(files):
        parts = rel.split("/")
        base, cls = split_file_name(parts[-1])
        node = None
        for it in root:
            if it.tag == "Item" and item_name(it) == parts[0]:
                node = it
                break
        if node is None:
            raise SystemExit("service not found in place: " + parts[0])
        for seg in parts[1:-1]:
            nxt = find_child(node, seg)
            if nxt is None:
                nxt = make_item(CONTAINER_CLASSES.get(seg, "Folder"), seg)
                node.append(nxt)
            node = nxt
        with open(files[rel], encoding="utf-8") as f:
            text = f.read()
        existing = None
        for c in children(node):
            if item_name(c) == base and c.get("class") in SCRIPT_CLASSES:
                existing = c
                break
        if existing is not None:
            existing.set("class", cls)
            set_source(existing, text)
            replaced += 1
        else:
            it = make_item(cls, base)
            set_source(it, text)
            node.append(it)
            added += 1
    tree.write(out, encoding="utf-8", xml_declaration=False)
    print("built %s: %d scripts replaced, %d added" % (out, replaced, added))


def cmd_sourcemap(src, out):
    def node_for(path, name, cls):
        return {"name": name, "className": cls, "children": []}

    game = {"name": "game", "className": "DataModel", "children": []}
    index = {(): game}

    def ensure(parts):
        key = tuple(parts)
        if key in index:
            return index[key]
        parent = ensure(parts[:-1])
        name = parts[-1]
        cls = name if len(parts) == 1 else CONTAINER_CLASSES.get(name, "Folder")
        if name == "MinerClientBootstrap":
            cls = "ScreenGui"
        n = node_for(parts, name, cls)
        parent["children"].append(n)
        index[key] = n
        return n

    rels = []
    for dirpath, _dirs, names in os.walk(src):
        for fn in names:
            base, cls = split_file_name(fn)
            if cls:
                rels.append((os.path.relpath(os.path.join(dirpath, fn), src).replace(os.sep, "/"), base, cls))
    for rel, base, cls in sorted(rels):
        parts = rel.split("/")
        parent = ensure(parts[:-1])
        parent["children"].append({
            "name": base, "className": cls,
            "filePaths": [os.path.join(src, rel).replace(os.sep, "/")],
        })
    for svc in ("Workspace", "Players", "Lighting", "ReplicatedStorage", "ServerScriptService", "StarterGui", "StarterPlayer"):
        ensure([svc])
    with open(out, "w", encoding="utf-8") as f:
        json.dump(game, f, indent=1)
    print("sourcemap written: " + out)


def main():
    if len(sys.argv) >= 4 and sys.argv[1] == "extract":
        cmd_extract(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 5 and sys.argv[1] == "build":
        cmd_build(sys.argv[2], sys.argv[3], sys.argv[4])
    elif len(sys.argv) >= 4 and sys.argv[1] == "sourcemap":
        cmd_sourcemap(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
