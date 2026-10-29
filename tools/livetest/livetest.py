"""A-Life: Caravans live test: a local dedicated server and one client (no Steam) with Project A-Life, this mod and
the test driver mod ALCTest. The driver connects the client, clicks through character creation, and the server-side
driver runs the scenario: found a caravan near the player, render it, follow it while it drives, flag it down,
trade, hitch a ride, kill the driver (re-crew), release. Every step logs "[ALCTest] STEP <name> PASS|FAIL ...";
both consoles are scanned for Lua errors.

  python -I livetest.py start      fresh caches under tools/livetest/env, launch server + client, return
  python -I livetest.py wait [S]   follow until ALCTest_done.txt exists (default 1500 s), print the findings, kill
  python -I livetest.py log        print the [ALCTest] / [ALC] / error lines of both consoles
  python -I livetest.py kill       stop the processes

Refuses to start while a ProjectZomboid64.exe is running (the user may be playing).
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
GAME = r"G:\Steam\steamapps\common\ProjectZomboid"
JAVA = os.path.join(GAME, "jre64", "bin", "java.exe")
WSC = r"G:\Steam\steamapps\workshop\content\108600"
ENV = os.path.join(HERE, "env")
SRV = os.path.join(ENV, "srv")
CLI = os.path.join(ENV, "cli")
PIDS = os.path.join(ENV, "pids.json")
PORT = 17371
SERVER = "ALCTEST"
USER, PASS = "admin", "alctest"
ZB_MOD = os.path.join(WSC, "3619862853", "mods", "ZombieBuddy")
MODS = {
    # ZombieBuddy (Java agent + mod) exactly as the SmoothRide/ZombieSync live tests run it: without the agent the
    # test client never gets past the intro video to the main menu
    "ZombieBuddy": ZB_MOD,
    "ProjectALifeNPCs": os.path.join(WSC, "3803984183", "mods", "ProjectALifeNPCs"),
    "ALifeCaravans": REPO,
    "ALCTest": os.path.join(HERE, "ALCTest"),
}
ANTICHEATS = ["AntiCheatSafety", "AntiCheatSpeed", "AntiCheatNoClip", "AntiCheatHit", "AntiCheatPacketException",
              "AntiCheatPermission", "AntiCheatXP", "AntiCheatSafeHouse", "AntiCheatPlayer", "AntiCheatChecksum"]


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def game_running():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq ProjectZomboid64.exe", "/NH", "/FO", "CSV"], capture_output=True, text=True).stdout
    return "ProjectZomboid64.exe" in out


def copy_mods(cache):
    md = os.path.join(cache, "mods")
    for name, src in MODS.items():
        if not os.path.isdir(src):
            raise SystemExit("missing mod folder " + src)
        shutil.copytree(src, os.path.join(md, name),
                        ignore=shutil.ignore_patterns("c", "doc") if name == "ZombieBuddy"
                        else shutil.ignore_patterns(".git", "tools", "docs", "scratch", "dist", "__pycache__"))
    write(os.path.join(md, "default.txt"),
          "VERSION = 1,\n\nmods\n{\n" + "".join(f"    mod = {m},\n" for m in MODS) + "}\n\nmaps\n{\n}\n")
    write(os.path.join(md, "reset-mods-42_00.txt"),
          "If this file does not exist, default.txt will be reset to empty (no mods active).")


def options_ini():
    src = os.path.join(os.path.expanduser("~"), "Zomboid", "options.ini")
    lines = open(src, encoding="utf-8", errors="replace").read().splitlines() if os.path.isfile(src) else []
    over = {
        "fullScreen": "false", "borderless": "false", "width": "1280", "height": "720", "vsync": "false",
        "frameRate": "60", "soundVolume": "0", "musicVolume": "0", "ambientVolume": "0", "jumpScareVolume": "0",
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


def prepare():
    for d in (SRV, CLI):
        if os.path.isdir(d):
            shutil.rmtree(d)
        os.makedirs(d, exist_ok=True)
    copy_mods(SRV)
    write(os.path.join(SRV, "Server", SERVER + ".ini"), "\n".join([
        "Mods=" + ";".join(MODS), "WorkshopItems=", "Map=Muldraugh, KY", "Public=false", "Open=true",
        "PVP=false", "PauseEmpty=false", "SpawnPoint=10637,10267,0", "MaxPlayers=4", f"DefaultPort={PORT}",
        f"UDPPort={PORT + 1}", "DoLuaChecksum=false", "UPnP=false", "ServerWelcomeMessage=",
        "Password=", "AutoCreateUserInWhiteList=true", "SteamScoreboard=false", "SafetySystem=false",
    ] + [f"{a}=3" for a in ANTICHEATS]) + "\n")
    write(os.path.join(SRV, "Server", SERVER + "_SandboxVars.lua"),
          "SandboxVars = {\n    VERSION = 6,\n    Zombies = 6,\n    DayLength = 26,\n    StartTime = 2,\n"
          "    ZombieConfig = {\n        PopulationMultiplier = 0.0,\n        PopulationStartMultiplier = 0.0,\n"
          "        PopulationPeakMultiplier = 0.0,\n    },\n"
          "    ALifeCaravans = {\n        MaxCaravans = 1,\n        FoundIntervalMinutes = 1,\n        RenderRadius = 150,\n"
          "        ReleaseRadius = 230,\n        MinSpawnDistance = 40,\n        CruiseKmh = 30,\n        MaxVehicles = 3,\n"
          "        CrewMin = 4,\n        CrewMax = 5,\n        HaltSeconds = 90,\n        AmbushPercent = 0,\n        Debug = true,\n    },\n}\n")
    write(os.path.join(SRV, "Server", SERVER + "_spawnregions.lua"),
          'function SpawnRegions()\n\treturn {\n\t\t{ name = "Muldraugh, KY", file = "media/maps/Muldraugh, KY/spawnpoints.lua" },\n\t}\nend\n')
    copy_mods(CLI)
    write(os.path.join(CLI, "options.ini"), options_ini())
    zbcfg = os.path.join(ENV, "zbcfg_client")
    os.makedirs(zbcfg, exist_ok=True)
    json.dump({"trusted_authors": [], "auto_fix_mod_order": False, "fix_approval_dialog_cursor": True, "preload_mods": {}},
              open(os.path.join(zbcfg, "config.json"), "w"), indent=2)
    write(os.path.join(CLI, "Lua", "ALCTest.txt"), f"user={USER}\npass={PASS}\nip=127.0.0.1\nport={PORT}\n")


def popen(args, log):
    f = open(log, "w", encoding="utf-8", errors="replace")
    flags = subprocess.CREATE_NEW_PROCESS_GROUP | 0x00000008
    try:
        return subprocess.Popen(args, cwd=GAME, stdout=f, stderr=subprocess.STDOUT, creationflags=flags | 0x01000000)
    except OSError:
        return subprocess.Popen(args, cwd=GAME, stdout=f, stderr=subprocess.STDOUT, creationflags=flags)


def wait_for(path, pattern, timeout, proc=None):
    rx = re.compile(pattern)
    t0 = time.time()
    while time.time() - t0 < timeout:
        if proc is not None and proc.poll() is not None:
            return False
        if os.path.isfile(path):
            with open(path, encoding="utf-8", errors="replace") as f:
                if rx.search(f.read()):
                    return True
        time.sleep(3)
    return False


def start():
    if game_running():
        raise SystemExit("ProjectZomboid64.exe is running (the user may be playing); not starting the live test")
    kill()
    prepare()
    common = ["--enable-native-access=ALL-UNNAMED", "--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED",
              "-XX:-CreateCoredumpOnCrash", "-XX:-OmitStackTraceInFastThrow", "-XX:+UseZGC"]
    zbsrv = os.path.join(ENV, "zbcfg_server")
    os.makedirs(zbsrv, exist_ok=True)
    json.dump({"trusted_authors": [], "auto_fix_mod_order": False, "fix_approval_dialog_cursor": True, "preload_mods": {}},
              open(os.path.join(zbsrv, "config.json"), "w"), indent=2)
    srv = popen([JAVA, f"-agentlib:zbNative=policy=allow-all,config_dir={zbsrv}"] + common
                + ["-Xmx3072m", "-Djava.awt.headless=true", "-Djava.library.path=./natives/;./natives/win64/;./",
                                   "-cp", "./;projectzomboid.jar", "zombie.network.GameServer", "-cachedir=" + SRV,
                                   "-servername", SERVER, "-adminusername", USER, "-adminpassword", PASS, "-nosteam",
                                   "-port", str(PORT), "-udpport", str(PORT + 1)], os.path.join(ENV, "server.out.log"))
    pids = {"server": srv.pid}
    json.dump(pids, open(PIDS, "w"))
    print("server pid", srv.pid, "- waiting for SERVER STARTED", flush=True)
    if not wait_for(os.path.join(ENV, "server.out.log"), r"SERVER STARTED", 900, srv):
        print("server did not start; see env/server.out.log", flush=True)
        return
    zbcfg = os.path.join(ENV, "zbcfg_client")
    cli = popen([JAVA, f"-agentlib:zbNative=policy=allow-all,config_dir={zbcfg}", "-Djava.awt.headless=true"] + common
                + ["-Dzomboid.steam=0", "-Dzomboid.znetlog=1", "-Xmx4096m", "-Djava.library.path=./win64/;./",
                                                                "-cp", "./;projectzomboid.jar", "zombie.gameStates.MainScreenState",
                                                                "-cachedir=" + CLI, "-nosteam"], os.path.join(ENV, "client.out.log"))
    pids["client"] = cli.pid
    json.dump(pids, open(PIDS, "w"))
    print("client pid", cli.pid, flush=True)


RX_LINE = re.compile(r"\[ALCTest\]|\[ALC\]|ERROR: Lua|attempted index|stack traceback|Lua.*(error|Error)|ALifeCaravans.*(fail|error)", re.I)
RX_SKIP = re.compile(r"LuaManager: loading|Lua file|loadingLua|AngelCodeFont|FluidContainerScript|fmod", re.I)
RX_ERROR = re.compile(r"ERROR: Lua|attempted index|stack traceback|\[ALC\].*failed:|Lua error", re.I)


def console_lines(path):
    if not os.path.isfile(path):
        return []
    out = []
    for ln in open(path, encoding="utf-8", errors="replace"):
        if RX_LINE.search(ln) and not RX_SKIP.search(ln):
            out.append(ln.rstrip()[:300])
    return out


def log(verbose=True):
    for role, cache in (("server", SRV), ("client", CLI)):
        lines = console_lines(os.path.join(cache, "console.txt"))
        errors = [ln for ln in lines if RX_ERROR.search(ln)]
        steps = [ln for ln in lines if "[ALCTest] STEP" in ln or "[ALCTest] DONE" in ln]
        print(f"--- {role}: {len(lines)} lines, {len(errors)} errors, {len(steps)} steps")
        if verbose:
            for ln in lines:
                print("  " + ln)
        else:
            for ln in steps + errors:
                print("  " + ln)
    return 0


def wait(seconds):
    done = os.path.join(SRV, "Lua", "ALCTest_done.txt")
    t0 = time.time()
    last = 0
    while time.time() - t0 < seconds and not os.path.isfile(done):
        time.sleep(10)
        steps = [ln for ln in console_lines(os.path.join(SRV, "console.txt")) if "[ALCTest]" in ln]
        if len(steps) > last:
            for ln in steps[last:]:
                print(ln, flush=True)
            last = len(steps)
    print("done file:", os.path.isfile(done), "after", int(time.time() - t0), "s", flush=True)
    if os.path.isfile(done):
        print(open(done, encoding="utf-8", errors="replace").read())
    code = log(verbose=False)
    res = os.path.join(HERE, "results", time.strftime("%Y%m%d_%H%M%S"))
    os.makedirs(res, exist_ok=True)
    for role, cache in (("server", SRV), ("client", CLI)):
        src = os.path.join(cache, "console.txt")
        if os.path.isfile(src):
            shutil.copy(src, os.path.join(res, role + "_console.txt"))
    if os.path.isfile(done):
        shutil.copy(done, os.path.join(res, "ALCTest_done.txt"))
    print("results in", res)
    kill()
    return code


def alive(pid):
    out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH", "/FO", "CSV"], capture_output=True, text=True).stdout
    return f'"{pid}"' in out


def kill():
    if not os.path.isfile(PIDS):
        return
    pids = list(json.load(open(PIDS)).values())
    for pid in pids:
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True)
    t0 = time.time()
    while time.time() - t0 < 30 and any(alive(p) for p in pids):
        time.sleep(1)
    os.remove(PIDS)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "start"
    if cmd == "start":
        start()
    elif cmd == "wait":
        sys.exit(wait(int(sys.argv[2]) if len(sys.argv) > 2 else 1500))
    elif cmd == "log":
        log(True)
    elif cmd == "kill":
        kill()
