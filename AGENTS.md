# AGENTS.md

This workspace is for local VIM4 Yocto development. Keep changes here under
`/home/wangkai/github/vim4`; the original checkout under
`/home/wangkai/github/yocto` should be treated as the reference copy.

## Workspace

- Root: `/home/wangkai/github/vim4`
- Build directory: `/home/wangkai/github/vim4/build`
- Downloads: `/home/wangkai/github/vim4/downloads`
- Sstate cache: `/home/wangkai/github/vim4/sstate-cache`
- Main VIM4 machine/config: `mesont7c-kvim4-5.15`
- Main image recipe: `amlogic-yocto`

This checkout includes the submodules needed for development. If changing a
submodule, make the branch inside that submodule and commit there first.

## Important Source Locations

- Kernel: `aml-comp/kernel/aml-5.15`
- Kernel common drivers: `aml-comp/kernel/aml-5.15/common_drivers`
- Media modules: `aml-comp/kernel/aml-5.15/common_drivers/drivers/media_modules`
- U-Boot: `aml-comp/uboot`
- Khadas custom package: `meta-meson/recipes-khadas/khadas-custom`
- VIM4 image recipe layer: `meta-aml-cfg/recipes-core/images`

Known inherited submodule dirtiness from the original checkout:

- `aml-comp/kernel/aml-5.15` shows `common_drivers` modified as a nested
  submodule pointer/worktree.
- `aml-comp/kernel/aml-5.15/common_drivers` shows `drivers/media_modules`
  modified as a nested submodule pointer/worktree.

Do not reset or discard these unless explicitly requested.

## Build

The host shell build currently fails because the environment script expects
`python` to be Python 2. Use the provided Docker builder image instead.

Build only VIM4:

```sh
docker run --rm \
  -v /home/wangkai/github/vim4:/workspace \
  -w /workspace \
  -e LOCAL_UID=$(id -u) \
  -e LOCAL_GID=$(id -g) \
  streambox-builder \
  /bin/bash -lc 'source meta-meson/aml-setenv.sh mesont7c-kvim4-5.15 && bitbake amlogic-yocto'
```

Last known successful build:

- Date: 2026-05-17
- Result: `7874` tasks attempted, all succeeded
- Warnings: `44`
- Deploy directory:
  `/home/wangkai/github/vim4/build/tmp/deploy/images/mesont7c-kvim4-5.15`

Main outputs from that build:

- `vim4-yocto-260517.img`
- `vim4-yocto-260517.img.xz`
- `software.swu`
- `boot.img`
- `recovery.img`
- `vendor.ext4.img2simg`

Common non-fatal warnings seen during the build:

- `meta-security` warns because `security` is not in `DISTRO_FEATURES`.
- WSLv2 storage warning.
- Patch fuzz warnings for some GStreamer and Weston patches.
- QA warnings such as `already-stripped`, `ldflags`, `file-rdeps`,
  `license-file-missing`, obsolete `GPLv2`, and one `host-user-contaminated`
  warning for `liblog`.

## Fan Control Notes

VIM4 fan control is handled through the Khadas MCU driver, not a standard
Linux `pwm-fan` hwmon PWM interface.

Runtime sysfs interface:

- `/sys/class/fan/enable`
- `/sys/class/fan/mode`
- `/sys/class/fan/level`
- `/sys/class/fan/speed`
- `/sys/class/fan/temp`

Typical command examples on the board:

```sh
echo 1 > /sys/class/fan/enable
echo 0 > /sys/class/fan/mode
echo 1 > /sys/class/fan/level
echo 2 > /sys/class/fan/level
echo 3 > /sys/class/fan/level
```

After the local fan-speed change, VIM4 also supports direct percent control:

```sh
echo 1 > /sys/class/fan/enable
echo 0 > /sys/class/fan/mode
echo 20 > /sys/class/fan/speed
echo 100 > /sys/class/fan/speed
cat /sys/class/fan/speed
```

`speed` accepts `0..100`. It maps linearly to the VIM4 MCU v2 fan value:

- `0` -> off, MCU value `0x00`
- `50` -> old low, MCU value `0x32`
- `72` -> old mid, MCU value `0x48`
- `100` -> old high, MCU value `0x64`

Values `1..49` are below the old `low` setting and may not reliably start the
fan on every unit.

Measured VIM4 fan behavior:

- `5%` starts spinning.
- Around `35%` becomes noticeably noisy.

The local automatic mode uses the percent interface on VIM4/VIM1S instead of
the old four-step `0/low/mid/high` mapping. With the default trigger
temperatures (`level0=60`, `level1=80`, `level2=100`), the current curve is:

- `<45C`: `0%`
- `45C..55C`: `5%..25%`
- `55C..60C`: `25%..35%`
- `60C..80C`: `35%..70%`
- `80C..100C`: `70%..100%`
- `>=100C`: `100%`

Auto mode also limits speed changes to `5%` per fan work cycle, except when
starting from or dropping to `0%`.

Kernel implementation:

- `aml-comp/kernel/aml-5.15/drivers/misc/khadas-mcu.c`

VIM4 fan levels map to MCU register values in that driver:

- off: `0x00`
- low: `0x32`
- mid: `0x48`
- high: `0x64`

To make the minimum speed lower than the current `low` setting, change the
VIM4 low-speed MCU value in the driver and rebuild the image. Be careful:
going too low may make the fan fail to start reliably.

## Development Rules

- Prefer small, testable changes.
- Follow existing layer and recipe patterns.
- Do not modify generated build output unless the task explicitly asks for it.
- Do not run destructive git commands such as `git reset --hard` or
  `git checkout --` against user changes.
- For kernel changes, edit the relevant submodule directly and rebuild
  `amlogic-yocto` for `mesont7c-kvim4-5.15`.
