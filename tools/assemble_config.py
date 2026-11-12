#!/usr/bin/env python3
"""Собирает единый конфиг GameConfig.lua из частей config_parts/*.lua (по алфавиту).

00_base.lua — исходный GameConfig v51 без финального `return GameConfig`;
остальные части добавляют разделы v52 (цены, длительности, цвета).
"""
import glob
import os
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
parts_dir = os.path.join(root, "config_parts")
out_path = os.path.join(root, "src", "ReplicatedStorage", "Modules", "GameConfig.lua")

if not os.path.isdir(parts_dir):
    sys.exit(0)

chunks = []
for path in sorted(glob.glob(os.path.join(parts_dir, "*.lua"))):
    with open(path, encoding="utf-8") as f:
        chunks.append(f.read().rstrip("\n") + "\n")

text = "\n".join(chunks) + "\nreturn GameConfig\n"
old = None
if os.path.exists(out_path):
    with open(out_path, encoding="utf-8") as f:
        old = f.read()
if old != text:
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
