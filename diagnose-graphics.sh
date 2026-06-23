#!/usr/bin/env bash
set -u

# Troubleshooting helper for comparing graphics plumbing between devices.
# Run it inside the Ubuntu rootfs, preferably through start-wine-droid.sh so the
# same /tmp X11 socket bind and Wine/Turnip environment are visible.

section() {
  printf '\n== %s ==\n' "$1"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

run() {
  printf '$ %s\n' "$*"
  "$@" 2>&1 || printf '[exit %s]\n' "$?"
}

show_env() {
  section "Environment"
  for name in \
    DISPLAY \
    XDG_RUNTIME_DIR \
    LD_LIBRARY_PATH \
    LIBGL_DRIVERS_PATH \
    GBM_BACKENDS_PATH \
    VK_ICD_FILENAMES \
    MESA_LOADER_DRIVER_OVERRIDE \
    MESA_VK_WSI_PRESENT_MODE \
    TU_DEBUG \
    GALLIUM_DRIVER \
    ZINK_DESCRIPTORS \
    ZINK_DEBUG
  do
    eval "value=\${$name-}"
    printf '%s=%s\n' "$name" "$value"
  done
}

show_x11() {
  section "X11"
  run ls -ld /tmp /tmp/.X11-unix
  run ls -l /tmp/.X11-unix

  if have xwininfo; then
    run sh -lc 'DISPLAY="${DISPLAY:-:0}" xwininfo -root | sed -n "1,30p"'
  else
    printf 'xwininfo: not installed\n'
  fi

  if have xdpyinfo; then
    run sh -lc 'DISPLAY="${DISPLAY:-:0}" xdpyinfo -queryExtensions | grep -E "DRI3|GLX|Present|RANDR" || true'
  else
    printf 'xdpyinfo: not installed\n'
  fi
}

show_glx() {
  section "GLX"
  if ! have glxinfo; then
    printf 'glxinfo: not installed\n'
    return
  fi

  tmp="${TMPDIR:-/tmp}/wine-droid-glxinfo.$$.log"
  DISPLAY="${DISPLAY:-:0}" glxinfo -B >"$tmp" 2>&1
  rc=$?
  sed -n '1,80p' "$tmp"
  printf 'glxinfo_exit=%s\n' "$rc"

  if grep -q 'couldn.t find RGB GLX visual or fbconfig' "$tmp"; then
    printf 'glx_status=fail-no-rgb-visual-or-fbconfig\n'
  elif grep -q 'DRI3 not available' "$tmp"; then
    printf 'glx_status=warn-dri3-not-available\n'
  elif grep -q '^direct rendering: Yes' "$tmp"; then
    printf 'glx_status=ok-direct-rendering\n'
  elif [ "$rc" -eq 0 ]; then
    printf 'glx_status=ok\n'
  else
    printf 'glx_status=fail\n'
  fi
  rm -f "$tmp"

  turnip="/opt/wine-droid/mesa-turnip/current"
  native_icd="$turnip/share/vulkan/icd.d/freedreno_icd.aarch64.json"
  native_dri="$turnip/lib/aarch64-linux-gnu/dri"
  native_gbm="$turnip/lib/aarch64-linux-gnu/gbm"
  native_lib="$turnip/lib/aarch64-linux-gnu"

  if [ -f "$native_icd" ] && [ -d "$native_dri" ]; then
    section "Native GLX via Zink"
    printf 'purpose=check the aarch64 GLX/Zink path; the default launch environment is armv7 for 32-bit Wine/Zink\n'
    tmp="${TMPDIR:-/tmp}/wine-droid-native-glxinfo.$$.log"
    DISPLAY="${DISPLAY:-:0}" \
      LD_LIBRARY_PATH="$native_lib" \
      LIBGL_DRIVERS_PATH="$native_dri" \
      GBM_BACKENDS_PATH="$native_gbm" \
      VK_ICD_FILENAMES="$native_icd" \
      MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-zink}" \
      GALLIUM_DRIVER="${GALLIUM_DRIVER:-zink}" \
      glxinfo -B >"$tmp" 2>&1
    rc=$?
    sed -n '1,80p' "$tmp"
    printf 'native_glxinfo_exit=%s\n' "$rc"
    if grep -q '^direct rendering: Yes' "$tmp"; then
      printf 'native_glx_status=ok-direct-rendering\n'
    elif [ "$rc" -eq 0 ]; then
      printf 'native_glx_status=ok\n'
    else
      printf 'native_glx_status=fail\n'
    fi
    rm -f "$tmp"
  fi
}

show_vulkan() {
  section "Vulkan"
  if ! have vulkaninfo; then
    printf 'vulkaninfo: not installed\n'
    return
  fi

  configured_icd="${VK_ICD_FILENAMES-}"
  native_icd="/opt/wine-droid/mesa-turnip/current/share/vulkan/icd.d/freedreno_icd.aarch64.json"

  printf 'configured_vk_icd=%s\n' "$configured_icd"
  if [ -n "$configured_icd" ]; then
    run sh -lc 'vulkaninfo --summary | sed -n "1,80p"'
  else
    printf 'configured_vk_icd_status=not-set\n'
  fi

  if [ -f "$native_icd" ]; then
    printf 'native_vk_icd=%s\n' "$native_icd"
    run sh -lc "VK_ICD_FILENAMES='$native_icd' vulkaninfo --summary | sed -n '1,120p'"
  else
    printf 'native_vk_icd_status=missing: %s\n' "$native_icd"
  fi

  section "Turnip Files"
  run sh -lc 'readlink -f /opt/wine-droid/mesa-turnip/current 2>/dev/null || true'
  run sh -lc 'find -L /opt/wine-droid/mesa-turnip/current -maxdepth 5 \( -name "libvulkan_freedreno.so" -o -name "freedreno_icd*.json" \) -print 2>/dev/null | sort'
  run sh -lc 'find -L /opt/wine-droid/mesa-turnip/current /usr/lib -maxdepth 5 \( -name "zink_dri.so" -o -name "libgbm.so*" -o -name "gbm.pc" \) -print 2>/dev/null | sort'
}

show_kgsl() {
  section "KGSL"
  run ls -l /dev/kgsl-3d0
  run ls -ld /sys/class/kgsl
  run sh -lc 'ls -l /sys/class/kgsl 2>&1 | sed -n "1,80p"'
}

show_wine_prefix() {
  section "Wine Prefix"
  prefix="${WINEPREFIX:-$HOME/.wine}"
  printf 'WINEPREFIX=%s\n' "$prefix"
  run sh -lc "test -f '$prefix/user.reg' && grep -n '\\[Software\\\\\\\\Wine\\\\\\\\DllOverrides\\]' -A40 '$prefix/user.reg' | sed -n '1,80p' || true"
  run sh -lc "find '$prefix/drive_c/windows' -iname d3d9.dll -o -iname dxgi.dll -o -iname d3dx9_43.dll -o -iname quartz.dll -o -iname wmvcore.dll 2>/dev/null | sort"
}

show_env
show_x11
show_glx
show_vulkan
show_kgsl
show_wine_prefix
