#!/usr/bin/env bash
set -euo pipefail

export WINEARCH="${WINEARCH:-win64}"
export DISPLAY="${DISPLAY:-:0}"
export PULSE_SERVER="${PULSE_SERVER:-127.0.0.1}"
export WINEDEBUG="${WINEDEBUG:--all}"
CALLER_WINE="${WINE:-}"
export WINESERVER="${WINESERVER:-/opt/wine/bin/wineserver}"

while [ $# -gt 0 ]; do
  case "$1" in
    --arch64)
      export WINEARCH=win64
      shift
      ;;
    --arch32)
      export WINEARCH=win32
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [ -n "$CALLER_WINE" ]; then
  export WINE="$CALLER_WINE"
elif [ "$WINEARCH" = "win32" ] && command -v wine-box86 >/dev/null 2>&1; then
  export WINE="$(command -v wine-box86)"
elif [ "$WINEARCH" = "win32" ]; then
  export WINE="${WINE_DROID_WINE:-/opt/wine/bin/wine}"
else
  export WINE="${WINE_DROID_WINE:-/opt/wine/bin/wine64}"
fi

build_wine_command() {
  if [ ! -x "$WINE" ]; then
    echo "Wine launcher not found or not executable: $WINE" >&2
    echo "Run /wine-droid/setup-wine.sh first, or set WINE_DROID_WINE to an existing Wine launcher." >&2
    exit 1
  fi

  case "$(file -L "$WINE")" in
    *"ELF 32-bit"*"Intel 80386"*|*"ELF 32-bit"*"Intel i386"*)
      WINE_CMD=(box86 "$WINE")
      ;;
    *"ELF 64-bit"*"x86-64"*)
      WINE_CMD=(box64 "$WINE")
      ;;
    *)
      WINE_CMD=("$WINE")
      ;;
  esac
}

run_wine() {
  xvfb-run -a "${WINE_CMD[@]}" "$@"
}

run_winetricks() {
  xvfb-run -a box64 winetricks -q "$@"
}

build_wine_command
mkdir -p "$HOME/.cache/winetricks" /apps/documents

# When Wine is upgraded, an existing prefix may show Mono/Gecko prompts before
# the game can launch. Run the prefix update under Xvfb and disable those
# installers so setup remains noninteractive. Install real components later only
# for games that need them.
WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}" run_wine wineboot -u
"$WINESERVER" -w || true

# Debian's winetricks package asks for confirmation before self-update. Keep the
# installer noninteractive by default; opt in only when explicitly requested.
if [ "${WINE_DROID_WINETRICKS_SELF_UPDATE:-0}" = "1" ]; then
  xvfb-run -a box64 winetricks --self-update || true
fi

run_winetricks cjkfonts fakejapanese_ipamona d3dx9 d3dx10 d3dx11_43

# Keep the default prefix 64-bit/WOW64. BURIKO-derived games are more likely to
# hit 32-bit address-space limits, while GINKA works in a 64-bit prefix. wmp9 is
# still useful for native wmp/wmvcore/l3codeca overrides, but winetricks warns
# that wm9codecs itself is not supported in win64 prefixes.
#
# Do not install quartz here. It can route video playback through native
# DirectShow, but GINKA renders those videos upside down with native quartz.
run_winetricks wmp9
prefix="${WINEPREFIX:-$HOME/.wine}"
if ! grep -qx 'wmp9' "$prefix/winetricks.log" 2>/dev/null; then
  echo "wmp9 did not finish; refusing to hide a partial video-runtime setup." >&2
  exit 1
fi
run_winetricks settings sound=pulse

run_wine reg add "HKCU\\Software\\Wine\\X11 Driver" /v UseXRandR /t REG_SZ /d N /f
run_wine reg add "HKCU\\Software\\Wine\\X11 Driver" /v UseXVidMode /t REG_SZ /d N /f

documents="$prefix/drive_c/users/$(whoami)/Documents"
if [ -e "$documents" ] && [ ! -L "$documents" ]; then
  rm -rf "$documents"
fi
ln -sfn /apps/documents "$documents"

echo "Wine prefix setup complete: WINEARCH=${WINEARCH}, prefix=${WINEPREFIX:-$HOME/.wine}"
