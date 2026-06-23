#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "setup-ubuntu.sh must be run as root inside the proot Ubuntu rootfs." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${WINE_DROID_BUILD_ROOT:-/root/wine-droid-build}"
JOBS="${JOBS:-6}"

export DEBIAN_FRONTEND=noninteractive
export TZ="${TZ:-Asia/Tokyo}"

apt-get update
apt-get upgrade -y
ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime

dpkg --add-architecture armhf
apt-get update

apt_install_best_effort() {
  # Ubuntu package names move between releases. Core build tools stay strict, but
  # optional runtime helpers are installed one-by-one so one missing package does
  # not abort the whole device setup.
  if apt-get install -y "$@"; then
    return 0
  fi

  echo "Retrying package install one-by-one; unavailable packages will be skipped." >&2
  for package in "$@"; do
    apt-get install -y "$package" || echo "Skipped unavailable package: $package" >&2
  done
}

apt-get install -y \
  apt-utils \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  ffmpeg \
  file \
  gcc-arm-linux-gnueabihf \
  git \
  locales \
  pulseaudio \
  tar \
  unzip \
  util-linux \
  wget \
  winbind \
  winetricks \
  x11-apps \
  xz-utils \
  xvfb

apt_install_best_effort \
  fonts-migmix \
  fonts-mona \
  fonts-monapo \
  fonts-takao \
  fonts-takao-gothic \
  fonts-takao-mincho \
  gstreamer1.0-libav:armhf \
  gstreamer1.0-plugins-bad:armhf \
  gstreamer1.0-plugins-base:armhf \
  gstreamer1.0-plugins-good:armhf \
  gstreamer1.0-plugins-ugly:armhf \
  gstreamer1.0-pulseaudio:armhf \
  libgl1-mesa-dri:armhf \
  libgl1-mesa-glx:armhf \
  libvulkan1:armhf \
  mesa-vulkan-drivers:armhf \
  vulkan-tools

mkdir -p "$BUILD_ROOT"

build_box64() {
  cd "$BUILD_ROOT"
  if [ ! -d box64/.git ]; then
    git clone https://github.com/ptitSeb/box64
  fi
  cd box64
  git pull --ff-only || true
  if [ -f "$SCRIPT_DIR/increase_slot.py" ]; then
    python3 "$SCRIPT_DIR/increase_slot.py" src/wrapped/wrappedlibx11.c --target 64 || true
  fi
  cmake -S . -B build -DARM_DYNAREC=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo
  cmake --build build -j "$JOBS"
  cmake --install build
}

build_box86() {
  cd "$BUILD_ROOT"
  if [ ! -d box86/.git ]; then
    git clone https://github.com/ptitSeb/box86
  fi
  cd box86
  git pull --ff-only || true
  if [ -f "$SCRIPT_DIR/increase_slot.py" ]; then
    python3 "$SCRIPT_DIR/increase_slot.py" src/wrapped/wrappedlibx11.c --target 64 || true
  fi
  cmake -S . -B build \
    -DCMAKE_C_COMPILER=arm-linux-gnueabihf-gcc \
    -DARM_DYNAREC=ON \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo
  cmake --build build -j "$JOBS"
  cmake --install build
}

install_wine() {
  "$SCRIPT_DIR/setup-wine.sh"
}

install_turnip() {
  if [ "${WINE_DROID_SKIP_TURNIP:-0}" = "1" ]; then
    echo "Skipping Turnip build because WINE_DROID_SKIP_TURNIP=1."
    return 0
  fi

  "$SCRIPT_DIR/setup-turnip.sh"
}

install_env() {
  sed -i 's/^# *ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/' /etc/locale.gen
  locale-gen ja_JP.UTF-8 || localedef -f UTF-8 -i ja_JP ja_JP.UTF-8

  cat >/etc/profile.d/wine-droid.sh <<'EOF'
export LANG=ja_JP.UTF-8
export LANGUAGE=ja_JP:ja
export LC_ALL=ja_JP.UTF-8
export DISPLAY=${DISPLAY:-:0}
export PULSE_SERVER=${PULSE_SERVER:-127.0.0.1}
export MESA_LOADER_DRIVER_OVERRIDE=${MESA_LOADER_DRIVER_OVERRIDE:-zink}
export MESA_VK_WSI_PRESENT_MODE=${MESA_VK_WSI_PRESENT_MODE:-mailbox}
export TU_DEBUG=${TU_DEBUG:-noconform}
export BOX64_ALLOWMISSINGLIBS=${BOX64_ALLOWMISSINGLIBS:-1}
export BOX86_ALLOWMISSINGLIBS=${BOX86_ALLOWMISSINGLIBS:-1}
export BOX64_DYNAREC_FASTROUND=${BOX64_DYNAREC_FASTROUND:-1}
export BOX86_DYNAREC_FASTROUND=${BOX86_DYNAREC_FASTROUND:-1}
export BOX64_DYNAREC_SAFEFLAGS=${BOX64_DYNAREC_SAFEFLAGS:-1}
export BOX86_DYNAREC_SAFEFLAGS=${BOX86_DYNAREC_SAFEFLAGS:-1}
export WINEDEBUG=${WINEDEBUG:--all}
export WINEESYNC=${WINEESYNC:-0}
export GALLIUM_HUD=${GALLIUM_HUD:-}
if [ -d /opt/wine-droid/mesa-turnip/current ]; then
  export LD_LIBRARY_PATH=/opt/wine-droid/mesa-turnip/current/lib/arm-linux-gnueabihf:/opt/wine-droid/mesa-turnip/current/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}
  export VK_ICD_FILENAMES=${VK_ICD_FILENAMES:-/opt/wine-droid/mesa-turnip/current/share/vulkan/icd.d/freedreno_icd.armv7.json}
  export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp}
fi
export PATH=/usr/local/bin:$PATH
EOF

  mkdir -p /apps/documents
}

build_box64
build_box86
install_wine
install_turnip
install_env

echo "Ubuntu setup complete. Run setup-winetricks.sh inside this rootfs before launching games."
