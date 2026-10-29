"""Real-engine load check: starts one Project Zomboid client (no Steam, no server) at the main menu with
Project A-Life and this mod enabled in a fresh cache, waits until the Lua of the mods has loaded, then scans
console.txt for Lua errors and for this mod's lines. The game loads every enabled mod's Lua, sandbox-options.txt
and translations at the main menu, so this catches require/path/syntax/translation problems in Kahlua that the
lupa simulation cannot. It does not start a world.

  python -I pz_loadcheck.py start      fresh cache under tools/loadcheck/run, launch, print pid
  python -I pz_loadcheck.py wait [S]   wait up to S seconds for the main menu, print the findings, kill the game
  python -I pz_loadcheck.py log | kill
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
GAME = r"G:\Steam\steamapps\common\ProjectZomboid"
JAVA = os.path.join(GAME, "jre64", "bin", "java.exe")
WSC = r"G:\Steam\steamapps\workshop\content\108600"
ROOT = os.path.join(HERE, "loadcheck", "run")
CACHE = os.path.join(ROOT, "cache")
PIDFILE = os.path.join(ROOT, "pid.json")
MODS = {
    "ProjectALifeNPCs": os.path.join(WSC, "3803984183", "mods", "ProjectALifeNPCs"),
    "ALifeCaravans": REPO,
}


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def options_ini():
    src = os.path.join(os.path.expanduser("~"), "Zomboid", "options.ini")
    lines = open(src, encoding="utf-8", errors="replace").read().splitlines() if os.path.isfile(src) else []
    over = {
        "fullScreen": "false", "borderless": "false", "width": "1024", "height": "600", "vsync": "false",
        "frameRate": "30", "soundVolume": "0", "musicVolume": "0", "ambientVolume": "0", "jumpScareVolume": "0",
        "vehicleEngineVolume": "0", "voiceVolumeMic": "0", "voiceVolumePlayers": "0",
        "doneNewSaveFolder": "true", "tutorialDone": "true", "language": "EN",
    }
    out, seen = [], set()
    for ln in lines:
        k = ln.split("=", 1)[0]
        if k in over:
            out.append(f"{k}={over[k]}")
            seen.add(k)
        else:
            out.append(ln)
    out += [f"{k}={v}" for k, v in over.items() if k not in seen]
    return "\n".join(out) + "\n"


def start():
    kill()
    if os.path.isdir(CACHE):
        shutil.rmtree(CACHE)
    md = os.path.join(CACHE, "mods")
    for name, src in MODS.items():
        if not os.path.isdir(src):
            raise SystemExit("missing mod folder " + src)
        shutil.copytree(src, os.path.join(md, name), ignore=shutil.ignore_patterns(".git", "tools", "docs", "scratch", "dist"))
    write(os.path.join(md, "default.txt"),
          "VERSION = 1,\n\nmods\n{\n" + "".join(f"    mod = {m},\n" for m in MODS) + "}\n\nmaps\n{\n}\n")
    write(os.path.join(md, "reset-mods-42_00.txt"),
          "If this file does not exist, default.txt will be reset to empty (no mods active).")
    write(os.path.join(CACHE, "options.ini"), options_ini())
    log = open(os.path.join(ROOT, "client.out.log"), "w", encoding="utf-8", errors="replace")
    args = [JAVA, "-Djava.awt.headless=true", "--enable-native-access=ALL-UNNAMED",
            "--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED", "-XX:-CreateCoredumpOnCrash",
            "-XX:-OmitStackTraceInFastThrow", "-XX:+UseZGC", "-Dzomboid.steam=0", "-Xmx4096m",
            "-Djava.library.path=./win64/;./", "-cp", "./;projectzomboid.jar", "zombie.gameStates.MainScreenState",
            "-cachedir=" + CACHE, "-nosteam"]
    flags = subprocess.CREATE_NEW_PROCESS_GROUP | 0x00000008
    p = subprocess.Popen(args, cwd=GAME, stdout=log, stderr=subprocess.STDOUT, creationflags=flags | 0x01000000)
    json.dump({"pid": p.pid}, open(PIDFILE, "w"))
    print("client pid", p.pid, "cache", CACHE)


def console_path():
    return os.path.join(CACHE, "console.txt")


def findings():
    rx = re.compile(r"\[ALC\]|ALifeCaravans|ALC_|ERROR: Lua|attempted index|Lua\s.*(error|stack)|sandbox-options|Sandbox\.json|"
                    r"IG_UI\.json|UI\.json|translation", re.I)
    skip = re.compile(r"LuaManager: loading|Lua file|loadingLua|ZombieBuddy", re.I)
    p = console_path()
    if not os.path.isfile(p):
        print("no console.txt yet")
        return []
    out = []
    for ln in open(p, encoding="utf-8", errors="replace"):
        if rx.search(ln) and not skip.search(ln):
            out.append(ln.rstrip()[:400])
    return out


def main_menu_reached():
    p = console_path()
    if not os.path.isfile(p):
        return False
    txt = open(p, encoding="utf-8", errors="replace").read()
    return "MainScreenState" in txt and ("LuaManager: loading" in txt or "Loading: Translate" in txt or "loaded" in txt) and \
        ("ALifeCaravans" in txt)


def wait(seconds):
    t0 = time.time()
    seen_mod = False
    while time.time() - t0 < seconds:
        p = console_path()
        if os.path.isfile(p):
            txt = open(p, encoding="utf-8", errors="replace").read()
            if "ALC_Boot" in txt or "ALifeCaravans/ALC_Boot" in txt:
                seen_mod = True
            if seen_mod and ("MainScreenState" in txt and "FMOD" not in txt[-4000:] and len(txt) > 20000):
                pass
            if re.search(r"MainScreen.*(ready|entered)|JoypadManager|UIManager.*init|GameWindow.*init", txt) and seen_mod:
                time.sleep(15)
                break
        time.sleep(5)
    print("waited", int(time.time() - t0), "s; mod lua seen:", seen_mod)
    lines = findings()
    errors = [ln for ln in lines if re.search(r"ERROR|attempted index|stack traceback|error", ln, re.I)]
    for ln in lines:
        print(ln)
    print("--- errors:", len(errors))
    kill()
    return 1 if errors or not seen_mod else 0


def kill():
    if not os.path.isfile(PIDFILE):
        return
    pid = json.load(open(PIDFILE))["pid"]
    subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True)
    for _ in range(30):
        out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH", "/FO", "CSV"], capture_output=True, text=True).stdout
        if f'"{pid}"' not in out:
            break
        time.sleep(1)
    os.remove(PIDFILE)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "start"
    if cmd == "start":
        start()
    elif cmd == "log":
        for ln in findings():
            print(ln)
    elif cmd == "wait":
        sys.exit(wait(int(sys.argv[2]) if len(sys.argv) > 2 else 240))
    elif cmd == "kill":
        kill()
