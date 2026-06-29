#!/usr/bin/env bash
set -euo pipefail

if [ -z "${PREFIX:-}" ] || [ ! -x "${PREFIX}/bin/pkg" ]; then
  echo "setup-termux.sh must be run inside Termux." >&2
  exit 1
fi

DISTRO="${WINE_DROID_DISTRO:-wine-droid}"
MAIN_MIRROR="${WINE_DROID_TERMUX_MAIN_MIRROR:-https://packages-cf.termux.dev/apt/termux-main}"

ensure_main_repo() {
  # Fresh or recovered Termux installs can have an empty sources.list; keep pkg usable
  # without entering the interactive mirror selector during scripted setup.
  mkdir -p "$PREFIX/etc/apt"
  if [ ! -s "$PREFIX/etc/apt/sources.list" ] || ! grep -q '^deb ' "$PREFIX/etc/apt/sources.list"; then
    cat >"$PREFIX/etc/apt/sources.list" <<EOF
deb $MAIN_MIRROR stable main
EOF
  fi
}

ensure_main_repo
pkg update
pkg install -y x11-repo
pkg install -y \
  libandroid-shmem \
  mesa \
  mesa-vulkan-icd-swrast \
  proot \
  pulseaudio \
  proot-distro \
  termux-am \
  termux-api \
  termux-x11-nightly \
  vulkan-loader \
  vulkan-loader-generic

mkdir -p "$HOME/apps"

proot_distro_dir() {
  if [ -d "$PREFIX/var/lib/proot-distro/containers/$DISTRO" ]; then
    return 0
  fi
  if [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO" ]; then
    return 0
  fi
  return 1
}

if proot_distro_dir; then
  reinstall="${WINE_DROID_REINSTALL_DISTRO:-}"
  if [ -z "$reinstall" ] && [ -t 0 ]; then
    printf "proot-distro rootfs '%s' already exists. Reinstall it? This deletes that rootfs only. [y/N] " "$DISTRO" >&2
    read -r answer
    case "$answer" in
      y|Y|yes|YES) reinstall=1 ;;
      *) reinstall=0 ;;
    esac
  fi

  if [ "$reinstall" = "1" ]; then
    proot-distro remove "$DISTRO"
  fi
fi

if ! proot_distro_dir; then
  proot-distro install --override-alias "$DISTRO" ubuntu
fi

echo "Termux setup complete. Put games under ~/apps so they appear as /apps inside Ubuntu."
