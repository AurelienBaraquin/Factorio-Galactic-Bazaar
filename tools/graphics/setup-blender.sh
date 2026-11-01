#!/usr/bin/env bash
# Installs the pinned Blender LTS used by the render pipeline (docs/graphics-pipeline.md) under
# ~/.local/opt/blender-<version>/, outside the repository. Idempotent: does nothing when that
# version is already installed. No root access; needs curl, sha256sum and tar with xz.
# The archive is checked against the SHA256 pinned below and against the official checksum file.
set -euo pipefail

VERSION="4.5.15"
SHA256="0d2b8bb2efe97e6c8eb57de6b7322f8800e1984e3125b60decca5f6771e4773e"
ARCHIVE="blender-${VERSION}-linux-x64.tar.xz"
BASE_URL="https://download.blender.org/release/Blender${VERSION%.*}"
PREFIX="${HOME}/.local/opt"
TARGET="${PREFIX}/blender-${VERSION}"

if [ -x "${TARGET}/blender" ]; then
  echo "Blender ${VERSION} already installed: ${TARGET}/blender"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

official="$(curl -fsSL "${BASE_URL}/blender-${VERSION}.sha256" | awk -v f="$ARCHIVE" '$2 == f { print $1 }')"
if [ "$official" != "$SHA256" ]; then
  echo "The official checksum file gives '${official}' for ${ARCHIVE}, not the pinned ${SHA256}" >&2
  exit 1
fi

curl -fL --progress-bar -o "${work}/${ARCHIVE}" "${BASE_URL}/${ARCHIVE}"
echo "${SHA256}  ${work}/${ARCHIVE}" | sha256sum --check --strict

mkdir -p "$PREFIX" "${work}/extract"
tar -xJf "${work}/${ARCHIVE}" -C "${work}/extract"
# A folder without the executable is what an interrupted earlier run leaves: replace it.
rm -rf "$TARGET"
mv -T "${work}/extract/blender-${VERSION}-linux-x64" "$TARGET"
"${TARGET}/blender" --version | head -n 1
