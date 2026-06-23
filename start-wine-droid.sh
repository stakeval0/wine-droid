#!/usr/bin/env bash
set -euo pipefail

if [ -z "${PREFIX:-}" ] || [ ! -x "${PREFIX}/bin/proot-distro" ]; then
  echo "start-wine-droid.sh must be run inside Termux after setup-termux.sh." >&2
  exit 1
fi

DISTRO="${WINE_DROID_DISTRO:-wine-droid}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPLAY_VALUE="${DISPLAY:-:0}"
PULSE_HOST="${WINE_DROID_PULSE_HOST:-127.0.0.1}"
APPS_DIR="${WINE_DROID_APPS_DIR:-${WINE_DROID_STORAGE_DIR:-$HOME/apps}}"
X11_LOG="${WINE_DROID_X11_LOG:-$PREFIX/tmp/termux-x11.log}"
PULSE_LOG="${WINE_DROID_PULSE_LOG:-$PREFIX/tmp/pulseaudio.log}"
TURNIP_PREFIX="${WINE_DROID_TURNIP_PREFIX:-/opt/wine-droid/mesa-turnip/current}"
ENV_EXPORT_NAMES=()

start_x11() {
  if ! pgrep -f "termux-x11.*${DISPLAY_VALUE}" >/dev/null 2>&1; then
    # Run Termux X11 in a detached subshell so proot commands can finish; otherwise
    # a quick command such as "true" may wait forever on the inherited child.
    ( nohup termux-x11 "$DISPLAY_VALUE" >"$X11_LOG" 2>&1 < /dev/null & )
    sleep 2
  fi
}

start_pulse() {
  pulseaudio --start --exit-idle-time=-1 >"$PULSE_LOG" 2>&1 || true
  if ! pactl list short modules 2>/dev/null | awk '
    $2 == "module-native-protocol-tcp" &&
    $0 ~ /auth-ip-acl=127[.]0[.]0[.]1/ &&
    $0 ~ /auth-anonymous=1/ { found = 1 }
    END { exit found ? 0 : 1 }
  '; then
    pactl load-module module-native-protocol-tcp \
      "auth-ip-acl=127.0.0.1" \
      "auth-anonymous=1" >/dev/null 2>&1 || true
  fi
}

build_bind_args() {
  BIND_ARGS=()
  for pair in \
    "$SCRIPT_DIR:/wine-droid" \
    "$PREFIX/tmp:/tmp" \
    "$APPS_DIR:/apps"
  do
    src="${pair%%:*}"
    if [ -e "$src" ]; then
      BIND_ARGS+=(--bind "$pair")
    fi
  done
}

build_env_args() {
  turnip_ld_library_path="$TURNIP_PREFIX/lib/arm-linux-gnueabihf:$TURNIP_PREFIX/lib/aarch64-linux-gnu"
  turnip_gl_drivers_path="$TURNIP_PREFIX/lib/arm-linux-gnueabihf/dri:$TURNIP_PREFIX/lib/aarch64-linux-gnu/dri"
  turnip_gbm_backends_path="$TURNIP_PREFIX/lib/arm-linux-gnueabihf/gbm:$TURNIP_PREFIX/lib/aarch64-linux-gnu/gbm"
  turnip_icd="$TURNIP_PREFIX/share/vulkan/icd.d/freedreno_icd.armv7.json"
  default_ld_library_path="${LD_LIBRARY_PATH:-}"
  default_libgl_drivers_path="${LIBGL_DRIVERS_PATH:-}"
  default_gbm_backends_path="${GBM_BACKENDS_PATH:-}"
  default_vk_icd="${VK_ICD_FILENAMES:-}"
  default_xdg_runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"

  # These paths live inside the proot rootfs, so Termux cannot test them before
  # login. Passing them is harmless before Turnip is installed and makes Wine's
  # 32-bit Zink path use the armv7 ICD and DRI drivers once setup-turnip.sh has
  # run. Native diagnostics must override these to aarch64 explicitly.
  if [ -z "$default_ld_library_path" ]; then
    default_ld_library_path="$turnip_ld_library_path"
  fi
  if [ -z "$default_libgl_drivers_path" ]; then
    default_libgl_drivers_path="$turnip_gl_drivers_path"
  fi
  if [ -z "$default_gbm_backends_path" ]; then
    default_gbm_backends_path="$turnip_gbm_backends_path"
  fi
  if [ -z "$default_vk_icd" ]; then
    default_vk_icd="$turnip_icd"
  fi

  ENV_EXPORT_NAMES=(
    DISPLAY
    PULSE_SERVER
    MESA_LOADER_DRIVER_OVERRIDE
    MESA_VK_WSI_PRESENT_MODE
    TU_DEBUG
    ZINK_DESCRIPTORS
    ZINK_DEBUG
    BOX64_ALLOWMISSINGLIBS
    BOX86_ALLOWMISSINGLIBS
    BOX64_DYNAREC_FASTROUND
    BOX86_DYNAREC_FASTROUND
    BOX64_DYNAREC_SAFEFLAGS
    BOX86_DYNAREC_SAFEFLAGS
    WINEDEBUG
    WINEESYNC
    LD_LIBRARY_PATH
    LIBGL_DRIVERS_PATH
    GBM_BACKENDS_PATH
    VK_ICD_FILENAMES
    XDG_RUNTIME_DIR
  )

  ENV_ARGS=(
    --env "DISPLAY=$DISPLAY_VALUE"
    --env "PULSE_SERVER=$PULSE_HOST"
    --env "MESA_LOADER_DRIVER_OVERRIDE=${MESA_LOADER_DRIVER_OVERRIDE:-zink}"
    --env "MESA_VK_WSI_PRESENT_MODE=${MESA_VK_WSI_PRESENT_MODE:-mailbox}"
    --env "TU_DEBUG=${TU_DEBUG:-noconform}"
    --env "ZINK_DESCRIPTORS=${ZINK_DESCRIPTORS:-lazy}"
    --env "ZINK_DEBUG=${ZINK_DEBUG:-compact}"
    --env "BOX64_ALLOWMISSINGLIBS=${BOX64_ALLOWMISSINGLIBS:-1}"
    --env "BOX86_ALLOWMISSINGLIBS=${BOX86_ALLOWMISSINGLIBS:-1}"
    --env "BOX64_DYNAREC_FASTROUND=${BOX64_DYNAREC_FASTROUND:-1}"
    --env "BOX86_DYNAREC_FASTROUND=${BOX86_DYNAREC_FASTROUND:-1}"
    --env "BOX64_DYNAREC_SAFEFLAGS=${BOX64_DYNAREC_SAFEFLAGS:-1}"
    --env "BOX86_DYNAREC_SAFEFLAGS=${BOX86_DYNAREC_SAFEFLAGS:-1}"
    --env "WINEDEBUG=${WINEDEBUG:--all}"
    --env "WINEESYNC=${WINEESYNC:-0}"
    --env "LD_LIBRARY_PATH=$default_ld_library_path"
    --env "LIBGL_DRIVERS_PATH=$default_libgl_drivers_path"
    --env "GBM_BACKENDS_PATH=$default_gbm_backends_path"
    --env "VK_ICD_FILENAMES=$default_vk_icd"
    --env "XDG_RUNTIME_DIR=$default_xdg_runtime_dir"
  )

  # Keep explicit prefix/architecture choices across the Termux -> proot boundary.
  # proot-distro does not reliably preserve arbitrary caller environment.
  #
  # Keep run-game knobs here too; they are Termux-side launch settings, not
  # Ubuntu defaults, so they must be deliberately passed into the container.
  for name in \
    WINEPREFIX \
    WINEARCH \
    WINEDLLOVERRIDES \
    WINE_DROID_RESOLUTION \
    WINE_DROID_CPUSET \
    WINE_DROID_LAUNCH_MODE \
    WINE_DROID_WINE \
    WINE_DROID_LOG_FILE \
    WINE_DROID_DEBUG_CHANNELS \
    WINE \
    WINESERVER
  do
    if [ -n "${!name:-}" ]; then
      ENV_ARGS+=(--env "$name=${!name}")
      ENV_EXPORT_NAMES+=("$name")
    fi
  done
}

build_export_command() {
  EXPORT_PREFIX="export"
  for name in "${ENV_EXPORT_NAMES[@]}"; do
    EXPORT_PREFIX+=" $name"
  done
  EXPORT_COMMAND="$EXPORT_PREFIX; exec \"\$@\""
  EXPORT_SHELL_COMMAND="$EXPORT_PREFIX; exec /bin/bash -l \"\$@\""
}

usage() {
  echo "Usage: $0 [--shell] [ubuntu-command ...]"
  echo "Examples:"
  echo "  $0 --shell"
  echo "  $0 run-game.sh /apps/GINKA/Game.exe"
}

mkdir -p "$APPS_DIR" "$PREFIX/tmp"
unset LD_PRELOAD
start_x11
start_pulse
build_bind_args
build_env_args
build_export_command

if [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ $# -eq 0 ] || [ "${1:-}" = "--shell" ]; then
  shift || true
  # Start a login shell after exporting the launch environment so ad-hoc
  # troubleshooting commands see the same Wine/Turnip settings as run-game.
  set -- /bin/bash -lc "$EXPORT_SHELL_COMMAND" bash "$@"
else
  if [ -x "$SCRIPT_DIR/$1" ]; then
    first="/wine-droid/$1"
    shift
    set -- "$first" "$@"
  fi
  set -- /bin/bash -lc "$EXPORT_COMMAND" bash "$@"
fi

exec proot-distro login "${BIND_ARGS[@]}" "${ENV_ARGS[@]}" "$DISTRO" -- "$@"
