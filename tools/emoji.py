#!/usr/bin/env python3
"""Build data/emoji.tsv from emojibase-data (MIT, names from Unicode CLDR).

Line: emoji <TAB> English name <TAB> English keywords <TAB> Russian name <TAB> Russian keywords,
in Unicode order. Skin tone variants and bare components are left out.
    python3 tools/emoji.py [VERSION]
"""
import json
import sys
import urllib.request
from pathlib import Path

VERSION = sys.argv[1] if len(sys.argv) > 1 else "16.0.3"
URL = "https://cdn.jsdelivr.net/npm/emojibase-data@{}/{}/compact.json"
COMPONENT = 2
OUT = Path(__file__).resolve().parent.parent / "data" / "emoji.tsv"


def fetch(lang):
    with urllib.request.urlopen(URL.format(VERSION, lang), timeout=30) as r:
        return json.load(r)


def clean(s):
    return " ".join(str(s).split())


en = fetch("en")
ru = {e["hexcode"]: e for e in fetch("ru")}
rows = []
for e in en:
    if e.get("group") in (None, COMPONENT):
        continue
    r = ru.get(e["hexcode"], {})
    rows.append((e.get("order", 0), "\t".join([
        e["unicode"],
        clean(e.get("label", "")),
        clean(" ".join(e.get("tags", []))),
        clean(r.get("label", "")),
        clean(" ".join(r.get("tags", []))),
    ])))
rows.sort()
OUT.parent.mkdir(exist_ok=True)
OUT.write_text("".join(line + "\n" for _, line in rows), encoding="utf-8")
print(f"{len(rows)} emoji -> {OUT}")
