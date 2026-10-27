# Mu-Silicium for the Nubia RedMagic 11 Pro (NX809J)

Port of [Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium)
(UEFI) to the NX809J (SM8850 "Kaanapali"), based on its OnePlus 15
(`infiniti`, same SoC) port. It boots Linux: Arch Linux ARM through
systemd-boot, with the mainline kernel from
[nx809j-mainline](https://github.com/Reixo0/nx809j-mainline). Started from
`boot_a`, or, next to Android, from the Canoe boot manager through
`esp-dispatch` (see nx809j-mainline's `uefi/README.md`, "Dual boot with
Canoe").

| File | What it is |
|---|---|
| `nx809jPkg/` | Device package (goes to `Platforms/ZTE/nx809jPkg`): memory map (OnePlus 15 map plus the Nubia RamConsole at 0xE2000000, where the kernel keeps pstore), configuration map (from `xbl_config`), 1216x2688 framebuffer, SMBIOS, driver lists |
| `nx809j.toml` | Build config: FD at 0xC6900000, boot image v4 with the `os_version` the NX809J ABL requires |
| `fv-extract.py` | Extracts the drivers from the phone's `uefi` partition (ELF with LZMA firmware volumes) |
| `patch-dxe.py` | The OnePlus 15 driver patches, located again in this phone's firmware build; each checks the bytes it replaces |
| `Binaries/nx809j/` | `.inf` files only; `make-binaries.sh` puts the phone's own drivers next to them |
| `build.sh` | Builds `out/Mu-nx809j.img` (with the AVB hash footer ABL wants) |
| `esp-dispatch/` | `BOOTAA64.EFI` that starts Mu-Silicium from the Qualcomm UEFI (a Canoe entry, or superfastboot's "Boot to ESP") and, under Mu, systemd-boot; `extract-mu-fd.py` gets its `MU.fd` from `out/Mu-nx809j.img` |
| `include/efi-mini.h` | Minimal freestanding EFI definitions for the small loaders here |
| `probe/` | Debugging: `AblProbe.c` (`ABL_PROBE=1` build shows ABL's hand-off) and `abldump/` (kernel module that dumps it from Linux) |
| `android-loader/` | Experiment: start Android's kernel from Mu-Silicium. Android's TrustZone services (qseecomd, KeyMint) and the ADSP fail after Mu has run Qualcomm's TZ drivers a second time, so it is not used |

The drivers are Qualcomm/Nubia binaries from the phone, so they are never in
git: `make-binaries.sh` builds them from a dump of the `uefi_a` partition.

## Building

Host packages: clang, lld, nasm, mono. Then:

```bash
git clone https://github.com/Project-Silicium/Mu-Silicium
git -C Mu-Silicium submodule update --init --recursive Common Mu_Basecore Silicium-ACPI Silicon
python3 -m venv mu-venv
mu-venv/bin/pip install -r Mu-Silicium/pip-requirements.txt
UEFI_IMG=uefi_a.img DTB=kaanapali-nubia-nx809j.dtb AVBTOOL=path/to/avbtool.py ./build.sh
```

* `UEFI_IMG`: the phone's `uefi_a` partition (e.g. `dd` from a rooted
  Android, or EDL).
* `DTB`: the NX809J device tree from nx809j-mainline's kernel build; UEFI
  hands it to Linux.
* `AVBTOOL`: `avbtool.py` from AOSP `external/avb`.
* `MU` / `PY` point elsewhere if Mu-Silicium or the venv live outside this
  directory. The `Binaries` submodule (every device's blobs) is not needed.
* `DEBUG` as the argument prints the UEFI log on the screen.

`out/Mu-nx809j.img` goes to `boot_a` (`fastboot flash boot_a`); `fastboot boot`
never reaches the kernel on this phone. For dual boot, `esp-dispatch/build.sh`
builds the dispatcher and `esp-dispatch/extract-mu-fd.py out/Mu-nx809j.img
MU.fd` the FD it loads (`\nx809j\mu\MU.fd` next to it).

## License

BSD-2-Clause-Patent, like Mu-Silicium.
