#!/usr/bin/env python3
"""Builds or deploys the Galactic Bazaar mod from the working tree.

  tools/build.py package               -> dist/galactic-bazaar_<version>.zip
  tools/build.py deploy <mods-folder>  -> <mods-folder>/galactic-bazaar/ (a plain copy)

The shipped files are the tracked and untracked, non-ignored files of the working tree, minus
those marked `export-ignore` in .gitattributes. Standard library only.
"""
import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD_FOLDER = "galactic-bazaar"


def git(*args, stdin=None):
    return subprocess.run(["git", *args], cwd=ROOT, input=stdin, capture_output=True,
                          text=True, check=True).stdout


def shipped_files():
    candidates = [p for p in git("ls-files", "-co", "--exclude-standard").splitlines()
                  if (ROOT / p).is_file()]
    attrs = git("check-attr", "--stdin", "export-ignore", stdin="\n".join(candidates))
    ignored = {line.split(": ")[0] for line in attrs.splitlines() if line.endswith(": set")}
    return sorted(p for p in candidates if p not in ignored)


def mod_version():
    info = json.loads((ROOT / "info.json").read_text(encoding="utf-8"))
    if info.get("name") != MOD_FOLDER:
        sys.exit(f"info.json name is {info.get('name')!r}, expected {MOD_FOLDER!r}")
    return info["version"]


def package():
    top = f"{MOD_FOLDER}_{mod_version()}"
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    archive = dist / f"{top}.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in shipped_files():
            zf.write(ROOT / path, f"{top}/{path}")
    print(archive.relative_to(ROOT))


def deploy(mods_folder):
    mods = Path(mods_folder).resolve()
    if not (mods / "mod-list.json").is_file():
        sys.exit(f"{mods} has no mod-list.json: not a Factorio mods folder")
    target = mods / MOD_FOLDER
    if target.is_symlink():
        sys.exit(f"{target} is a symlink: remove it first, deploy writes a plain copy")
    files = shipped_files()
    wanted = {target / p for p in files}
    if target.is_dir():
        for existing in sorted(target.rglob("*"), reverse=True):
            if existing.is_file() and existing not in wanted:
                existing.unlink()
            elif existing.is_dir() and not any(existing.iterdir()):
                existing.rmdir()
    for path in files:
        destination = target / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / path, destination)
    print(f"{len(files)} files -> {target}")


def main(argv):
    if argv[:1] == ["package"] and len(argv) == 1:
        package()
    elif argv[:1] == ["deploy"] and len(argv) == 2:
        deploy(argv[1])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
