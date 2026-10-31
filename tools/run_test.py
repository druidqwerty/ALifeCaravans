"""Run the lupa simulation tests of A-Life: Caravans. Exit 1 on any failure.

tools/test_alc.lua - stubs Project A-Life (driving sessions, vehicle arrivals, catalog, road graph, registry,
speech, radio) and the game (cell with a synthetic road, vehicles with seats/fuel/engine, scripts, players,
events, commands, map UI), loads the mod in single-player mode, and checks: boot and hooks, the 0.1.0 ledger
migration, sandbox settings, vehicle choice, road scouting, the barter rules, founding (named leaders, stock,
ambush), fast ledger travel with easing, map markers, a four-car convoy rendered in two units, formation speeds,
route extension and restart, stuck recovery, hail/news/deals/ride/wait/escort/farewell, threaten (fold+flee /
fight), attack reactions, driver death and re-crewing, car abandonment, ambushes, radio chatter, riders and
release, the raider toll, the client menu and headlight-flash hails, and that every speech line exists in EN and RU.
Also compiles every Lua file and checks the JSON translations decode as UTF-8 with identical key sets.
"""
import glob
import json
import os
import re
import sys

import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
MOD_ROOT = os.path.dirname(HERE).replace("\\", "/")
TRANSLATE = os.path.join(MOD_ROOT, "42", "media", "lua", "shared", "Translate")


def load(lang, name):
    with open(os.path.join(TRANSLATE, lang, name), "rb") as handle:
        raw = handle.read()
    return json.loads(raw.decode("utf-8"))


def main():
    failed = 0
    for path in sorted(glob.glob(os.path.join(MOD_ROOT, "42", "media", "lua", "**", "*.lua"), recursive=True)):
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        # Lupa accepts Lua 5.2+ goto, but PZ's Kahlua parser rejects it before
        # the file can run. Keep this source-level regression even when the
        # simulation itself compiles successfully.
        executable = re.sub(r"--\[\[.*?\]\]|--[^\n]*", "", source, flags=re.S)
        executable = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', '""', executable)
        for match in re.finditer(r"\bgoto\b|::[A-Za-z_][A-Za-z0-9_]*::", executable):
            line = executable.count("\n", 0, match.start()) + 1
            print("FAIL Kahlua unsupported goto/label", path, "line", line)
            failed += 1
        try:
            lupa.LuaRuntime().compile(source)
        except Exception as error:  # noqa: BLE001
            print("FAIL syntax", path, error)
            failed += 1
    translations = {}
    sandbox_path = os.path.join(MOD_ROOT, "42", "media", "sandbox-options.txt")
    with open(sandbox_path, encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if "--" in line:
                print("FAIL CustomSandboxOptions comment", sandbox_path, "line", line_number)
                failed += 1
    for name in ("IG_UI.json", "UI.json", "Sandbox.json"):
        en, ru = load("EN", name), load("RU", name)
        if set(en) != set(ru):
            print("FAIL translation keys differ in", name, sorted(set(en) ^ set(ru)))
            failed += 1
        for key, value in list(en.items()) + list(ru.items()):
            if not str(value).strip():
                print("FAIL empty translation", name, key)
                failed += 1
        translations.update(en)
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    with open(sandbox_path, encoding="utf-8") as handle:
        for key in re.findall(r"translation\s*=\s*([\w_]+)", handle.read()):
            if "Sandbox_" + key not in translations:
                print("FAIL missing Sandbox translation", key)
                failed += 1
    lua.globals().MOD_ROOT = MOD_ROOT
    table = lua.table()
    for key, value in translations.items():
        table[key] = value
    lua.globals().TRANSLATIONS = table
    with open(os.path.join(HERE, "test_alc.lua"), encoding="utf-8") as handle:
        source = handle.read()
    print("== test_alc.lua")
    failed += lua.execute(source) or 0
    print("TOTAL failed =", failed)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
