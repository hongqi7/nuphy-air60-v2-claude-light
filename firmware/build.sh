#!/bin/bash
# Build the Claude-light firmware from NuPhy's open-source QMK tree.
#   ./build.sh           Air60 V2 (default)
#   ./build.sh halo65    Halo65 V2 (experimental, not yet tested on hardware)
# Needs: git, uv (or pip), Homebrew. Output: ./nuphy_<board>_ansi_via.bin
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM_COMMIT=f1856912d603800eaca227ae2e1c5c8548fdf261
SRC="$HERE/qmk_firmware"

case "${1:-air60}" in
    air60)  BOARD=air60_v2;  PATCH=claude-light.patch ;;
    halo65) BOARD=halo65_v2; PATCH=halo65-claude-light.patch ;;
    *) echo "usage: build.sh [air60|halo65]" >&2; exit 2 ;;
esac

# Homebrew's arm-none-eabi-gcc ships without newlib; QMK's macOS toolchain does
brew list osx-cross/arm/arm-gcc-bin@8 >/dev/null 2>&1 || brew install osx-cross/arm/arm-gcc-bin@8
command -v qmk >/dev/null || uv tool install qmk
export PATH="$(brew --prefix arm-gcc-bin@8)/bin:$PATH"

if [ ! -d "$SRC" ]; then
    git clone --single-branch -b nuphy-keyboards https://github.com/nuphy-src/qmk_firmware.git "$SRC"
    git -C "$SRC" checkout -q "$UPSTREAM_COMMIT"
    git -C "$SRC" submodule update --init --depth 1 lib/chibios lib/chibios-contrib lib/printf lib/lufa
fi
# each patch touches its own board only; apply it once
if git -C "$SRC" apply --check "$HERE/$PATCH" 2>/dev/null; then
    git -C "$SRC" apply "$HERE/$PATCH"
fi

QMK_PY="$(dirname "$(readlink -f "$(command -v qmk)")")/python"
uv pip install --python "$QMK_PY" -r "$SRC/requirements.txt" >/dev/null 2>&1 || true

(cd "$SRC" && QMK_HOME="$SRC" make "nuphy/$BOARD/ansi:via" SKIP_GIT=yes)
cp "$SRC/nuphy_${BOARD}_ansi_via.bin" "$HERE/"
echo "built: $HERE/nuphy_${BOARD}_ansi_via.bin"
