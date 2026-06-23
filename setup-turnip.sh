#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "setup-turnip.sh must be run as root inside the proot Ubuntu rootfs." >&2
  exit 1
fi

MESA_TAG="${WINE_DROID_MESA_TAG:-mesa-26.1.3}"
BUILD_ROOT="${WINE_DROID_BUILD_ROOT:-/root/wine-droid-build}"
SRC_DIR="$BUILD_ROOT/mesa"
PREFIX_DIR="/opt/wine-droid/mesa-turnip/$MESA_TAG"
JOBS="${JOBS:-2}"
CROSS_FILE="$BUILD_ROOT/armhf-mesa-cross.ini"

export DEBIAN_FRONTEND=noninteractive

apt-get update
dpkg --add-architecture armhf
apt-get update

apt-get install -y \
  bison \
  ca-certificates \
  flex \
  g++ \
  g++-arm-linux-gnueabihf \
  gcc \
  gcc-arm-linux-gnueabihf \
  git \
  glslang-tools \
  libarchive-dev \
  libdrm-dev \
  libelf-dev \
  libexpat1-dev \
  libglvnd-dev \
  libgbm-dev \
  libvulkan-dev \
  libwayland-dev \
  libx11-dev \
  libx11-xcb-dev \
  libxcb-dri3-dev \
  libxcb-glx0-dev \
  libxcb-present-dev \
  libxcb-randr0-dev \
  libxcb-shm0-dev \
  libxcb-sync-dev \
  libxcb-xfixes0-dev \
  libxrandr-dev \
  libxshmfence-dev \
  libxml2-dev \
  libxxf86vm-dev \
  libzstd-dev \
  meson \
  ninja-build \
  pkg-config \
  python3-mako \
  python3-ply \
  python3-yaml \
  vulkan-tools \
  wayland-protocols \
  zlib1g-dev

apt-get install -y \
  libdrm-dev:armhf \
  libelf-dev:armhf \
  libexpat1-dev:armhf \
  libglvnd-dev:armhf \
  libgbm-dev:armhf \
  libvulkan-dev:armhf \
  libx11-dev:armhf \
  libx11-xcb-dev:armhf \
  libxcb1-dev:armhf \
  libxcb-dri3-dev:armhf \
  libxcb-glx0-dev:armhf \
  libxcb-present-dev:armhf \
  libxcb-randr0-dev:armhf \
  libxcb-shm0-dev:armhf \
  libxcb-sync-dev:armhf \
  libxcb-xfixes0-dev:armhf \
  libxrandr-dev:armhf \
  libxshmfence-dev:armhf \
  libxxf86vm-dev:armhf \
  libzstd-dev:armhf \
  zlib1g-dev:armhf

mkdir -p "$BUILD_ROOT"

if [ ! -d "$SRC_DIR/.git" ]; then
  git clone https://gitlab.freedesktop.org/mesa/mesa.git "$SRC_DIR"
fi

cd "$SRC_DIR"
git fetch --tags --force
git checkout "$MESA_TAG"

cat >"$CROSS_FILE" <<'EOF'
[binaries]
c = 'arm-linux-gnueabihf-gcc'
cpp = 'arm-linux-gnueabihf-g++'
ar = 'arm-linux-gnueabihf-gcc-ar'
strip = 'arm-linux-gnueabihf-strip'
pkg-config = 'pkg-config'

[properties]
pkg_config_libdir = ['/usr/lib/arm-linux-gnueabihf/pkgconfig', '/usr/share/pkgconfig']
sys_root = '/'
needs_exe_wrapper = true

[host_machine]
system = 'linux'
cpu_family = 'arm'
cpu = 'armv7'
endian = 'little'
EOF

# Mesa's Turnip driver is the official Freedreno Vulkan path. Android devices
# expose Adreno through KGSL rather than desktop DRM, so build with
# -Dfreedreno-kmds=kgsl. The armhf build is required by 32-bit Wine/Zink.
meson setup build-aarch64-kgsl --wipe \
  --wrap-mode=nofallback \
  --prefix="$PREFIX_DIR" \
  --libdir=lib/aarch64-linux-gnu \
  -Dplatforms=x11 \
  -Dvulkan-drivers=freedreno \
  -Dfreedreno-kmds=kgsl,msm \
  -Dgallium-drivers=zink,softpipe \
  -Dglx=dri \
  -Degl=enabled \
  -Dgbm=enabled \
  -Dllvm=disabled \
  -Dshared-glapi=enabled \
  -Dgles1=disabled \
  -Dgles2=enabled \
  -Dvalgrind=disabled \
  -Dlibunwind=disabled \
  -Dvideo-codecs=[]
ninja -C build-aarch64-kgsl -j "$JOBS"
ninja -C build-aarch64-kgsl install

meson setup build-armhf-kgsl --wipe \
  --cross-file "$CROSS_FILE" \
  --wrap-mode=nofallback \
  --prefix="$PREFIX_DIR" \
  --libdir=lib/arm-linux-gnueabihf \
  -Dplatforms=x11 \
  -Dvulkan-drivers=freedreno \
  -Dfreedreno-kmds=kgsl,msm \
  -Dgallium-drivers=zink,softpipe \
  -Dopengl=true \
  -Dglx=dri \
  -Degl=enabled \
  -Dgbm=enabled \
  -Dshared-glapi=enabled \
  -Dgles1=disabled \
  -Dgles2=disabled \
  -Dllvm=disabled \
  -Dvalgrind=disabled \
  -Dlibunwind=disabled \
  -Dvideo-codecs=[]
ninja -C build-armhf-kgsl -j "$JOBS"
ninja -C build-armhf-kgsl install

ln -sfn "$MESA_TAG" /opt/wine-droid/mesa-turnip/current

echo "Installed Mesa Turnip $MESA_TAG at $PREFIX_DIR."
echo "For 32-bit Wine/Zink use:"
echo "  LD_LIBRARY_PATH=$PREFIX_DIR/lib/arm-linux-gnueabihf:$PREFIX_DIR/lib/aarch64-linux-gnu"
echo "  VK_ICD_FILENAMES=$PREFIX_DIR/share/vulkan/icd.d/freedreno_icd.armv7.json"
