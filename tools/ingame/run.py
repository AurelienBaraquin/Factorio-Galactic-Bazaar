#!/usr/bin/env python3
"""Runs the in-game check in the Windows Factorio client, from WSL (docs/ingame-check.md).

  tools/ingame/run.py [--locale fr] [--locale en] [--factorio <factorio.exe>] [--timeout <seconds>]

For each locale (both by default) it builds a sandbox in %LOCALAPPDATA%\\Temp\\gb-ingame-check (its own
config, write-data and mods folders: the player's saves, settings and mods are never read or
written), deploys the mod there with tests/ingame_check and the gb-ingame-check helper mod, starts
the client on the helper's empty scenario, waits for the check's done.json, stops that client (only
the process whose command line names the sandbox's config), and copies the screenshots and
report.json to tools/ingame/.work/<locale>/. Exits 1 when a name or window text is not translated,
when the check recorded an error, or on timeout. Standard library only.
"""
import argparse
import importlib.util
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
HELPER = Path(__file__).resolve().parent / "gb-ingame-check"
WORK = Path(__file__).resolve().parent / ".work"
STEAM_FACTORIO = "/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe"
SANDBOX_NAME = "gb-ingame-check"
DISABLED = ["space-age", "quality", "elevated-rails"]
POLL_SECONDS = 2


def load_build():
    spec = importlib.util.spec_from_file_location("build", ROOT / "tools" / "build.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def windows_path(path):
    return subprocess.run(["wslpath", "-w", str(path)], capture_output=True, text=True, check=True).stdout.strip()


def sandbox_root():
    local = subprocess.run(["cmd.exe", "/c", "echo %LOCALAPPDATA%"], cwd="/mnt/c", capture_output=True,
                           text=True, check=True).stdout.strip()
    root = Path(subprocess.run(["wslpath", "-u", local], capture_output=True, text=True,
                               check=True).stdout.strip()) / "Temp" / SANDBOX_NAME
    if "Roaming" in root.parts:
        sys.exit(f"refusing sandbox {root}: inside the player's Factorio data")
    return root


def prepare(sandbox, locale):
    mods, data = sandbox / "mods", sandbox / "data"
    mods.mkdir(parents=True, exist_ok=True)
    data.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(data / "script-output" / "gb-ingame", ignore_errors=True)
    (sandbox / "config.ini").write_text(
        "[path]\nread-data=__PATH__executable__/../../data\n"
        f"write-data={windows_path(data)}\n[general]\nlocale={locale}\n", encoding="utf-8")
    entries = [{"name": "base", "enabled": True}, {"name": "galactic-bazaar", "enabled": True},
               {"name": HELPER.name, "enabled": True}]
    entries += [{"name": name, "enabled": False} for name in DISABLED]
    (mods / "mod-list.json").write_text(json.dumps({"mods": entries}, indent=2), encoding="utf-8")
    load_build().deploy(mods)
    target = mods / "galactic-bazaar" / "tests" / "ingame_check"
    shutil.rmtree(target, ignore_errors=True)
    shutil.copytree(ROOT / "tests" / "ingame_check", target)
    shutil.rmtree(mods / HELPER.name, ignore_errors=True)
    shutil.copytree(HELPER, mods / HELPER.name)


def stop(sandbox):
    """Stops only the clients started with this sandbox's config; returns their process ids."""
    config = windows_path(sandbox / "config.ini").replace("'", "''")
    script = ("Get-CimInstance Win32_Process -Filter \"Name='factorio.exe'\" | "
              f"Where-Object {{ $_.CommandLine -like '*{config}*' }} | "
              "ForEach-Object { Stop-Process -Id $_.ProcessId -Force; $_.ProcessId }")
    out = subprocess.run(["powershell.exe", "-NoProfile", "-Command", script], cwd="/mnt/c",
                         capture_output=True, text=True).stdout
    return [line.strip() for line in out.splitlines() if line.strip()]


def run(sandbox, factorio, timeout):
    done = sandbox / "data" / "script-output" / "gb-ingame" / "done.json"
    command = [factorio, "--config", windows_path(sandbox / "config.ini"), "--mod-directory",
               windows_path(sandbox / "mods"), "--load-scenario", f"{HELPER.name}/check", "--disable-audio"]
    # Steam restarts the client under its own process: the check is followed through its files.
    subprocess.Popen(command, cwd="/mnt/c", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            if done.is_file():
                time.sleep(POLL_SECONDS)  # screenshots of the last tick are written after it
                return True
            time.sleep(POLL_SECONDS)
        return False
    finally:
        stop(sandbox)


def collect(sandbox, locale, finished):
    target = WORK / locale
    shutil.rmtree(target, ignore_errors=True)
    output = sandbox / "data" / "script-output" / "gb-ingame"
    if output.is_dir():
        shutil.copytree(output, target)
    target.mkdir(parents=True, exist_ok=True)
    log = sandbox / "data" / "factorio-current.log"
    if log.is_file():
        shutil.copy2(log, target / "factorio-current.log")
    if not finished:
        print(f"[{locale}] timed out: no done.json; see {target / 'factorio-current.log'}")
        progress = target / "progress.txt"
        if progress.is_file():
            print(f"[{locale}] last steps:\n" + "".join(progress.read_text(encoding="utf-8").splitlines(True)[-5:]))
        return False
    report = json.loads((target / "report.json").read_text(encoding="utf-8"))
    print(f"[{locale}] {len(report['screenshots'])} screenshots, {report['checked']} texts checked -> {target}")
    for entry in report["missing"]:
        print(f"[{locale}] NOT TRANSLATED ({entry['kind']}): {entry['string']}")
    for error in report["errors"]:
        print(f"[{locale}] ERROR: {error}")
    for entry in report["no_description"]:
        print(f"[{locale}] no description (shown as none): {entry['kind']}")
    return not report["missing"] and not report["errors"]


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--locale", action="append", choices=["fr", "en"])
    parser.add_argument("--factorio", default=STEAM_FACTORIO)
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args(argv)
    if not Path(args.factorio).is_file():
        sys.exit(f"{args.factorio} not found: pass --factorio")
    sandbox = sandbox_root()
    leftover = stop(sandbox)
    if leftover:
        print(f"stopped a leftover check client: {', '.join(leftover)}")
    ok = True
    for locale in args.locale or ["fr", "en"]:
        prepare(sandbox, locale)
        ok = collect(sandbox, locale, run(sandbox, args.factorio, args.timeout)) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
