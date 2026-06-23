#!/usr/bin/env bash
set -euo pipefail

DEBUG=false
RESOLUTION="${WINE_DROID_RESOLUTION:-1920x1080}"
CPUSET="${WINE_DROID_CPUSET:-4-7}"
LOG_FILE="${WINE_DROID_LOG_FILE:-/apps/wine-droid.log}"
WINE_LAUNCHER="${WINE_DROID_WINE:-/opt/wine/bin/wine64}"
LAUNCH_MODE="${WINE_DROID_LAUNCH_MODE:-start}"

usage() {
  echo "Usage: $0 [--debug] [--start|--desktop] [--resolution WIDTHxHEIGHT] [/apps/.../Game.exe]"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --debug)
      DEBUG=true
      shift
      ;;
    --start)
      LAUNCH_MODE=start
      shift
      ;;
    --desktop)
      LAUNCH_MODE=desktop
      shift
      ;;
    --resolution)
      if [ $# -lt 2 ]; then
        echo "--resolution requires WIDTHxHEIGHT." >&2
        usage >&2
        exit 2
      fi
      RESOLUTION="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [ $# -ne 1 ]; then
  usage >&2
  exit 2
fi

exe="$1"
if [ ! -f "$exe" ]; then
  echo "Windows executable not found: $exe" >&2
  exit 1
fi

export DISPLAY="${DISPLAY:-:0}"
export PULSE_SERVER="${PULSE_SERVER:-127.0.0.1}"
export MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-zink}"
export MESA_VK_WSI_PRESENT_MODE="${MESA_VK_WSI_PRESENT_MODE:-mailbox}"
export TU_DEBUG="${TU_DEBUG:-noconform}"
export BOX64_ALLOWMISSINGLIBS="${BOX64_ALLOWMISSINGLIBS:-1}"
export BOX86_ALLOWMISSINGLIBS="${BOX86_ALLOWMISSINGLIBS:-1}"
export BOX64_DYNAREC_FASTROUND="${BOX64_DYNAREC_FASTROUND:-1}"
export BOX86_DYNAREC_FASTROUND="${BOX86_DYNAREC_FASTROUND:-1}"
export BOX64_DYNAREC_SAFEFLAGS="${BOX64_DYNAREC_SAFEFLAGS:-1}"
export BOX86_DYNAREC_SAFEFLAGS="${BOX86_DYNAREC_SAFEFLAGS:-1}"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEESYNC="${WINEESYNC:-0}"
if [ -d /opt/wine-droid/mesa-turnip/current ]; then
  export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-/opt/wine-droid/mesa-turnip/current/lib/arm-linux-gnueabihf:/opt/wine-droid/mesa-turnip/current/lib/aarch64-linux-gnu}"
  export LIBGL_DRIVERS_PATH="${LIBGL_DRIVERS_PATH:-/opt/wine-droid/mesa-turnip/current/lib/arm-linux-gnueabihf/dri:/opt/wine-droid/mesa-turnip/current/lib/aarch64-linux-gnu/dri}"
  export GBM_BACKENDS_PATH="${GBM_BACKENDS_PATH:-/opt/wine-droid/mesa-turnip/current/lib/arm-linux-gnueabihf/gbm:/opt/wine-droid/mesa-turnip/current/lib/aarch64-linux-gnu/gbm}"
  export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/opt/wine-droid/mesa-turnip/current/share/vulkan/icd.d/freedreno_icd.armv7.json}"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
fi

wine_box() {
  case "$(file -L "$WINE_LAUNCHER")" in
    *"ELF 32-bit"*"Intel 80386"*|*"ELF 32-bit"*"Intel i386"*)
      echo box86
      ;;
    *"ELF 64-bit"*"x86-64"*)
      echo box64
      ;;
    *)
      echo "Cannot determine Wine launcher architecture: $WINE_LAUNCHER" >&2
      exit 1
      ;;
  esac
}

exe_dir="$(cd "$(dirname "$exe")" && pwd)"
exe_name="$(basename "$exe")"
box_cmd="$(wine_box)"

case "$LAUNCH_MODE" in
  start)
    # Kirikiri games expect their install directory as current directory. Wine's
    # start /unix path lets Wine receive a Unix path through start.exe while
    # still waiting for the launched Windows process to exit.
    cmd=(taskset -c "$CPUSET" "$box_cmd" "$WINE_LAUNCHER" start /wait /unix "$exe_dir/$exe_name")
    ;;
  desktop)
    cmd=(taskset -c "$CPUSET" "$box_cmd" "$WINE_LAUNCHER" explorer "/desktop=shell,${RESOLUTION}" "$exe_dir/$exe_name")
    ;;
  *)
    echo "Unknown WINE_DROID_LAUNCH_MODE: $LAUNCH_MODE" >&2
    exit 2
    ;;
esac

if [ "$DEBUG" = true ]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  export WINEDEBUG="${WINE_DROID_DEBUG_CHANNELS:-+timestamp,+pid,+tid,+seh,+loaddll}"
  {
    printf 'wine-droid debug run\n'
    printf 'exe=%s\n' "$exe"
    printf 'resolution=%s cpuset=%s launcher=%s box=%s mode=%s\n' "$RESOLUTION" "$CPUSET" "$WINE_LAUNCHER" "$box_cmd" "$LAUNCH_MODE"
    ( cd "$exe_dir" && "${cmd[@]}" )
  } >"$LOG_FILE" 2>&1
else
  cd "$exe_dir"
  exec "${cmd[@]}"
fi
