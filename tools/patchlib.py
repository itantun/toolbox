#!/usr/bin/env python3
"""Точечные правки существующих скриптов v51 -> v52 (поиск точной строки и замена).

Каждая правка обязана найти свой фрагмент ровно `count` раз — иначе скрипт падает,
чтобы ни одна правка не «потерялась» молча.
"""
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


class Patcher:
    def __init__(self, rel):
        self.path = os.path.join(ROOT, rel)
        with open(self.path, encoding="utf-8") as f:
            self.text = f.read()
        self.rel = rel

    def sub(self, old, new, count=1):
        found = self.text.count(old)
        if found != count:
            sys.exit("PATCH FAILED in %s: expected %d match(es), found %d for:\n%s" % (self.rel, count, found, old[:200]))
        self.text = self.text.replace(old, new)

    def save(self):
        with open(self.path, "w", encoding="utf-8", newline="\n") as f:
            f.write(self.text)
        print("patched " + self.rel)
