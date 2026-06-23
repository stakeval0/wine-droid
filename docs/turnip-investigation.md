# Turnip investigation

This note records the current primary test device state and candidate paths for getting an
Adreno Vulkan driver working in the proot Ubuntu environment.

## Current primary test device evidence

- Device properties:
  - `ro.board.platform=kalama`
  - `ro.soc.model=SM8550`
  - `ro.hardware.vulkan=adreno`
  - `/sys/class/kgsl/kgsl-3d0/gpu_model` reports `Adreno740v2`
- `mesa-vulkan-drivers:armhf` installs `freedreno_icd.json`.
- `libvulkan_freedreno.so` exists for both native arm64 and armhf:
  - `/usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so`
  - `/usr/lib/arm-linux-gnueabihf/libvulkan_freedreno.so`
- `/dev/kgsl-3d0` is visible inside proot.
- Ubuntu package `vulkaninfo --summary` reported only `llvmpipe`.
- Forcing the Ubuntu package freedreno ICD failed:

```sh
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/freedreno_icd.json vulkaninfo --summary
```

Result:

```text
Failed to detect any valid GPUs in the current config
vkEnumeratePhysicalDevices failed with ERROR_INITIALIZATION_FAILED
```

So the Ubuntu Mesa package is present, but it is not the GPU acceleration path
for the primary test device.

## Adopted path: official Mesa source build

The installer now builds Mesa from the official upstream GitLab repository:

```text
https://gitlab.freedesktop.org/mesa/mesa.git
```

The tested tag is `mesa-26.1.3`, checked out at commit prefix `6984e91`.
The key Meson options are:

```sh
-Dvulkan-drivers=freedreno -Dfreedreno-kmds=kgsl,msm -Dgallium-drivers=zink,softpipe -Dglx=dri -Dgbm=enabled
```

Mesa's own `meson.options` lists `freedreno` as a Vulkan driver and `kgsl` as a
Freedreno KMD choice. This is the important part for Android devices: the primary test device
exposes Adreno through `/dev/kgsl-3d0`, not a normal desktop DRM node.
`msm` is also enabled so Mesa can build the GBM/GLX pieces required by zink.
Runtime acceleration still uses the KGSL-visible Adreno path.

The build installs to:

```text
/opt/wine-droid/mesa-turnip/mesa-26.1.3
/opt/wine-droid/mesa-turnip/current -> mesa-26.1.3
```

Native arm64 verification succeeded:

```sh
LD_LIBRARY_PATH=/opt/wine-droid/mesa-turnip/mesa-26.1.3/lib/aarch64-linux-gnu \
VK_ICD_FILENAMES=/opt/wine-droid/mesa-turnip/mesa-26.1.3/share/vulkan/icd.d/freedreno_icd.aarch64.json \
XDG_RUNTIME_DIR=/tmp \
vulkaninfo --summary
```

Observed result:

```text
deviceName = Turnip Adreno (TM) 740
driverID   = DRIVER_ID_MESA_TURNIP
driverName = turnip Mesa driver
driverInfo = Mesa 26.1.3 (git-6984e91b5f)
```

The armhf build produced the 32-bit Wine/Zink driver:

```text
/opt/wine-droid/mesa-turnip/mesa-26.1.3/lib/arm-linux-gnueabihf/libvulkan_freedreno.so
/opt/wine-droid/mesa-turnip/mesa-26.1.3/share/vulkan/icd.d/freedreno_icd.armv7.json
```

The 32-bit ICD is used by Wine-side OpenGL/Zink paths.

## Box64Droid comparison

Box64Droid does not appear to add special Vulkan startup flags in
`start-box64droid`; the major difference is that its rootfs contains custom
freedreno libraries under `/usr/local`:

```text
/usr/local/lib/aarch64-linux-gnu/libvulkan_freedreno.so
/usr/local/lib/arm-linux-gnueabihf/libvulkan_freedreno.so
/usr/local/share/vulkan/icd.d/freedreno_icd.aarch64.json
/usr/local/share/vulkan/icd.d/freedreno_icd.armv8.2l.json
```

The ICD JSON points directly at those `/usr/local/lib/...` libraries.

Running the comparison Box64Droid rootfs with the custom aarch64 ICD produced
`ERROR_INCOMPATIBLE_DRIVER` in `vulkaninfo`, so copying that rootfs state is not
the default path. It remains useful only as behavior evidence.

## Source facts

Mesa documents Turnip as the Vulkan driver for Adreno 6xx GPUs and notes that
Turnip and freedreno share core code while implementing separate Vulkan/OpenGL
state and command stream handling:

- https://docs.mesa3d.org/drivers/freedreno.html

This matters because package presence alone is not enough. The build must match
Android's KGSL device path on the primary test device, not only generic Linux DRM.

## Rejected or fallback paths

1. **Ubuntu package only**
   - Already tested.
   - Pros: simple and scriptable.
   - Cons: currently falls back to llvmpipe; forced freedreno ICD fails.
   - Status: not sufficient for GPU acceleration.

2. **Termux glibc-prefix style Turnip**
   - Current Box64Droid native installer downloads a `glibc-prefix.tar.xz`
     release artifact and runs Wine/box64 from Termux's glibc prefix, not from a
     proot Ubuntu rootfs.
   - Reference:
     - `https://raw.githubusercontent.com/Ilya114/Box64Droid/main/installers/install.sh`
     - `https://raw.githubusercontent.com/Ilya114/Box64Droid/main/installers/native.py`
   - That artifact appears to be where its Adreno driver stack is bundled.
   - Pros: likely closest to the maintained Box64Droid path.
   - Cons: using the whole prefix would conflict with this project's
     self-built/proot direction. We need either a reproducible source build or a
     narrow driver artifact with clear provenance.
   - Status: not adopted. The project should not depend on an opaque copied
     driver stack when upstream Mesa source works.

3. **Build Mesa Turnip/freedreno for KGSL inside proot**
   - Adopted.
   - Builds both arm64 and armhf from Mesa source.
   - Uses `--wrap-mode=nofallback` so missing distro dependencies fail clearly
     instead of silently vendoring Meson subprojects.

4. **Use a prebuilt Turnip package**
   - Likely closer to what Box64Droid ships.
   - Must identify a reproducible upstream artifact and license/source.
   - Do not silently copy Box64Droid rootfs binaries into this project.
   - Status: fallback only if source build becomes too slow or fragile. Any
     artifact must have documented provenance and source.

5. **ADB-assisted diagnostics**
   - Useful for device and permission checks from the host:
     - `adb shell getprop ro.hardware`
     - `adb shell getprop ro.board.platform`
     - `adb shell getprop ro.soc.model`
     - `adb shell getprop ro.hardware.vulkan`
     - `adb shell ls -l /dev/kgsl-3d0 /dev/dri`
     - `adb shell cat /sys/class/kgsl/kgsl-3d0/gpu_model`
     - `adb shell dumpsys SurfaceFlinger | grep -i vulkan`
   - Useful if Termux/proot cannot see the same device nodes or properties.
   - ADB should be diagnostic first, not a required install dependency unless no
     Termux-side path works.

## Verified primary test device result

- Native GLX/Zink now succeeds when the aarch64 ICD and aarch64 DRI path are
  selected:

```text
OpenGL renderer string: zink Vulkan 1.4(Turnip Adreno (TM) 740 (MESA_TURNIP))
```

- The default launch environment still points `VK_ICD_FILENAMES` at the armv7
  ICD for 32-bit Wine/Zink. A native `glxinfo -B` run under that default can
  fail with `VK_ERROR_INCOMPATIBLE_DRIVER`; this is a diagnostic mismatch, not
  proof that Zink is unavailable. Use `diagnose-graphics.sh` and its
  `Native GLX via Zink` section for the native GLX indicator.
- GINKA reached the title screen and video playback on primary test device with:
  - Wine 9.0
  - WOW64 prefix (`WINEARCH=win64`)
  - `/opt/wine/bin/wine64`
  - self-built Mesa Turnip/Zink
  - `wmp9` installed enough to provide native `wmp`, `wmvcore`, and
    `l3codeca.acm` overrides
  - no native `quartz`

## Remaining checks

- Killing stale Termux X11/PulseAudio processes with
  `killall /system/bin/app_process pulseaudio` helped reset the X11 capture
  state. Keep this as a troubleshooting reset, not as part of normal install.
- Switching `/opt/wine` to Wine 10 was tested only as a compatibility
  experiment. GINKA should remain on Wine 9.x for now because Wine 10 is known
  to regress video playback for this game. The installer still keeps Wine
  version configurable for other games.
- Box64Droid differed from the initial primary test device test in several important
  ways:
  - Box64Droid starts proot directly with `env -i`, while this project uses
    `proot-distro login` plus explicit `--env` passthrough.
  - Box64Droid's default Wine prefix is `#arch=win64` (WOW64). The initial
    primary test device test used a pure `#arch=win32` prefix.
  - Box64Droid exports extra Box64/Box86 variables such as `BOX64_BASH`,
    `BOX86_BASH`, `BOX64_DYNAREC_BLEEDING_EDGE=1`,
    `BOX86_DYNAREC_BLEEDING_EDGE=1`, and `BOX64_DYNAREC_CALLRET=0`.
- The primary test device's WOW64 prefix `/root/.wine-wow64-ginka` initially did not have
  `wmp9` recorded in `winetricks.log`, and video playback reached
  `winegstreamer`/builtin media DLLs before failing. Re-running `wmp9` completed
  and added native `wmp`, `wmvcore`, and `l3codeca.acm` overrides. Winetricks
  warns that `wm9codecs` is not supported in win64 prefixes; this is expected
  and did not block GINKA video playback.
- Do not install native `quartz` for GINKA by default. It can affect DirectShow
  routing, but on GINKA it makes videos render upside down.

## Provisional install-script policy

- Keep `vulkan-tools` for verification. Do not rely on Ubuntu
  `mesa-vulkan-drivers:armhf` for acceleration on the primary test device.
- Do not claim GPU acceleration unless `vulkaninfo --summary` or GLX/Zink logs
  show an Adreno/Turnip device rather than `llvmpipe`.
- Use a WOW64 prefix by default. GINKA works there, and 32-bit prefixes are more
  likely to hit address-space limits in BURIKO-derived games.
- Do not hide `wmp9` failures with `|| true`; the setup must either install it
  or clearly fail before the user reaches a partially configured video runtime.
- Do not copy Box64Droid rootfs driver binaries into this project as the default
  path. They are useful evidence, but the installer uses reproducible Mesa
  source builds.
- ADB can be optional diagnostics. The Termux-only path should remain the
  default if possible.
