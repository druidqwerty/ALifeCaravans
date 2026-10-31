"""Compile only our bridge; game/ZombieBuddy are compile-only dependencies."""
from pathlib import Path
import os
import subprocess
import shutil
import tempfile
import zipfile

repo = Path(__file__).resolve().parent.parent
game = Path(os.environ.get("PZ_GAME_DIR", "G:/Steam/steamapps/common/ProjectZomboid"))
configured = os.environ.get("PZ_JDK_DIR")
java_home = os.environ.get("JAVA_HOME")
javac = str(Path(configured) / "javac.exe") if configured else (
    str(Path(java_home) / "bin/javac.exe") if java_home else shutil.which("javac"))
if not javac:
    raise SystemExit("JDK25 required: set PZ_JDK_DIR to its bin directory or JAVA_HOME")
sources = sorted((repo / "src/main/java").rglob("*.java"))
assert sources
target = repo / "42/media/java/ALifeCaravans.jar"
target.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="alc-native-") as build:
    subprocess.run([javac, "--release", "25", "-encoding", "UTF-8",
                    "-cp", str(game / "projectzomboid.jar") + ";" + str(game / "ZombieBuddy.jar"),
                    "-d", build] + [str(p) for p in sources], check=True)
    classes = sorted(Path(build).rglob("*.class"))
    assert classes and all(p.relative_to(build).as_posix().startswith("com/druid/alifecaravans/") for p in classes)
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as jar:
        for path in classes:
            info = zipfile.ZipInfo(path.relative_to(build).as_posix(), (2026,10,31,0,0,0))
            info.compress_type = zipfile.ZIP_DEFLATED
            jar.writestr(info, path.read_bytes())
print("Built", target.name, "with", len(classes), "own classes; no game classes bundled")
