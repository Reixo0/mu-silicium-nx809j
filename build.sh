#!/bin/sh
# Builds Mu-Silicium (UEFI) for the NX809J into out/Mu-nx809j.img, a boot
# image for boot_a (or, as MU.fd, for esp-dispatch).
#
# Usage: UEFI_IMG=... DTB=... [FB_MARKER=1] [ABL_PROBE=1] ./build.sh [RELEASE|DEBUG]
#   DEBUG prints the UEFI log on the screen.
#   FB_MARKER=1: the boot shim paints a white band over the top of the
#   screen before starting UEFI (shows that ABL ran it).
#   ABL_PROBE=1 (DEBUG only): shows what ABL handed over (device tree,
#   ramdisk, bootconfig) and waits 20 s; see probe/AblProbe.c.
#   SKIP_DXE="Name ...": leave these Qualcomm drivers out (experiments;
#   the image gets a -skip suffix).
#
# Needs (paths can be overridden):
#   UEFI_IMG  the phone's uefi_a partition (its Qualcomm drivers; never in git)
#   DTB       the NX809J mainline device tree (kaanapali-nubia-nx809j.dtb)
#   MU        Mu-Silicium checkout with its submodules except Binaries
#             (default ./Mu-Silicium)
#   PY        python with Mu-Silicium/pip-requirements.txt (default
#             ./mu-venv/bin/python3)
#   AVBTOOL   avbtool.py from AOSP external/avb (default: avbtool in PATH)
# and nasm and mono on the host.
set -eu
top=$(cd "$(dirname "$0")" && pwd)
mu=${MU:-$top/Mu-Silicium}
py=${PY:-$top/mu-venv/bin/python3}
uefi_img=${UEFI_IMG:?set UEFI_IMG to the uefi_a partition image}
dtb=${DTB:?set DTB to kaanapali-nubia-nx809j.dtb}
avbtool=${AVBTOOL:-avbtool}
target=${1:-RELEASE}
img=$top/out/Mu-nx809j.img
[ "${ABL_PROBE:-0}" = 1 ] && img=$top/out/Mu-nx809j-probe.img
[ -n "${SKIP_DXE:-}" ] && img=${img%.img}-skip.img

# Our package, config and DTB inside the Mu tree
mkdir -p "$mu/Platforms/ZTE"
ln -sfn "$top/nx809jPkg" "$mu/Platforms/ZTE/nx809jPkg"
ln -sf "$top/nx809j.toml" "$mu/Resources/Configs/nx809j.toml"
cp "$dtb" "$top/nx809jPkg/FdtBlob/kaanapali-nubia-nx809j.dtb"
# Appended to the kernel for ABL's board matching (ABL on this phone passes
# its own downstream DTB anyway).
cp "$dtb" "$mu/Resources/DTBs/nx809j.dtb"

"$top/make-binaries.sh" "$uefi_img" "$mu"

cd "$mu"
inc=$top/nx809jPkg/Include
cp "$inc/DXE.inc" "$inc/.DXE.inc.orig"
cp "$inc/APRIORI.inc" "$inc/.APRIORI.inc.orig"
trap 'git -C "$mu" checkout -q BootShim/BootShim.S Silicon/Silicium/SiliciumPkg/Sec/Sec.c
	mv "$inc/.DXE.inc.orig" "$inc/DXE.inc"; mv "$inc/.APRIORI.inc.orig" "$inc/APRIORI.inc"' EXIT
for d in ${SKIP_DXE:-}; do
	sed -i "s|^\(  INF .*/Drivers/$d/\)|#\1|" "$inc/DXE.inc" "$inc/APRIORI.inc"
done
if [ "${FB_MARKER:-0}" = 1 ]; then
	# Fill the first 300 lines of the 1216-pixel framebuffer that ABL
	# left at 0xFC800000. x1 (payload address) must survive, and no
	# "ldr =" constants: their literal pool would land at _Payload, where
	# the FD is appended. 1216 * 4 * 300 / 8 = 0x2c880.
	sed -i 's/^_Start:$/_Start:\
  movz  x7, #0xfc80, lsl #16\
  movz  x8, #0xc880\
  movk  x8, #0x2, lsl #16\
  mov   x9, #-1\
1:str   x9, [x7], #8\
  subs  x8, x8, #1\
  b.ne  1b/' BootShim/BootShim.S
fi
if [ "${ABL_PROBE:-0}" = 1 ]; then
	# Keep ABL's registers (x1 is already the payload address here) and
	# the shim's address in FD_Reserved (0xC6800000) for AblProbe.
	sed -i 's/^_Start:$/_Start:\
  movz  x7, #0xc680, lsl #16\
  stp   x0, x1, [x7]\
  stp   x2, x3, [x7, #16]\
  adr   x8, _Head\
  str   x8, [x7, #32]/' BootShim/BootShim.S
	sec=Silicon/Silicium/SiliciumPkg/Sec/Sec.c
	# (Sec.c has CRLF line ends)
	sed -i "s|^#include \"Sec.h\"\r\?\$|&\\n#include \"$top/probe/AblProbe.c\"|" $sec
	sed -i 's/^  PrintFirmwareVersion ();\r\?$/&\n  AblProbe ();/' $sec
	grep -q AblProbe $sec
fi
"$py" build_uefi.py -d nx809j -r "$target"

# The NX809J ABL wants the unsigned AVB hash footer that stock boot_a has
# (as nx809j-mainline's scripts/mkboot.sh does for Linux).
mkdir -p "$top/out"
cp Mu-nx809j.img "$img"
"$avbtool" add_hash_footer \
	--image "$img" --partition_name boot \
	--partition_size 100663296 --algorithm NONE \
	--prop com.android.build.boot.os_version:16 \
	--prop com.android.build.boot.security_patch:2026-08-01
ls -l "$img"
