# VelvetDOS 0.2.0 (development preview)

VelvetDOS is a new GNU GPLv3-licensed project aiming for **binary compatibility
with DOS software** on IBM PC-compatible x86 computers. This milestone is a
proof-of-concept real-mode floppy OS, **not yet a full MS-DOS replacement**.

## What works in this development preview

All VelvetDOS 0.1.0 bootloader, FAT12, shell and `.COM` support remains.
The 0.2.0 preview adds:

- **Small MZ `.EXE` loading** with header validation and relocation fixing,
  limited to a single 64 KiB image loaded from the floppy root directory.
  Bare shell names search `.COM` before `.EXE`.
- **Read-only DOS file handles** through `INT 21h`: `AH=3Dh` (open),
  `3Eh` (close), `3Fh` (read), and `42h` (seek). Four concurrent file handles
  numbered 5 through 8; no folders or disk writes.
- **A basic MCB conventional-memory chain** with `AH=48h` (allocate),
  `49h` (free), and `4Ah` (resize). Programs own their initial memory block
  and generally must shrink it before they can allocate additional blocks.
- Additional test programs: `EXEDEMO.EXE` (relocation), `READ.COM`
  (open/read/seek/close across FAT12 sectors), `MEMORY.COM` (MCBs), and a
  multi-sector `README.TXT` fixture.

The entire boot/kernel/application foundation remains 8086 real-mode
assembly. **No Pascal or protected-mode dependency has been introduced.**

**Verification boundary:** the floppy image builds with GNU binutils, and
structural and packer tests run locally. We cannot claim 0.2.0 works in 86Box
until the interactive programs are actually tested there.

## Requirements (Linux)

- GNU Make, GNU binutils (`as`, `ld`), Python 3.
- QEMU (`qemu-system-i386`) **to actually run** the image.

The kernel is currently **entirely 16-bit x86 assembly** so this early
milestone needs no particular 16-bit C compiler. Future kernels can incorporate
16-bit C via a toolchain such as Open Watcom.

## Build and run

```sh
make image
make test
make run
```

`make run` boots from the generated `build/velvetdos-0.2.0.img`.
You can also use:

```sh
qemu-system-i386 -drive file=build/velvetdos-0.2.0.img,if=floppy,format=raw -boot a -m 16
```

At the `A:\>` prompt, try:

```
HELP
DIR
VER
HELLO
RETURN
CHAIN
EXEDEMO
READ
MEMORY
CLS
```

The build does **not** modify your computer's disks. Do not write this
experimental boot image to a physical drive containing anything important.

## Important limitations

**This is a pre-alpha, not a general DOS-compatible release.** Many DOS
programs will not run. The new MZ loader only accepts simple real-mode
executables that fit inside one 64 KiB image; large/multisegment MZ programs,
DOS overlays and protected-mode extenders are not supported.

- No subdirectories, file creation/writes, file sharing or device-file opens.
- No command-line argument tails, batch files, pipes, environment blocks,
  DOS path search, standard input redirection, or a standalone `COMMAND.COM`.
- The MCB implementation is provisional; no TSRs, resident drivers, EMS, XMS,
  UMBs, DPMI or full DOS process inheritance semantics.
- Disk access is BIOS CHS, 1.44 MB FAT12 and drive A: only.
- Many `INT 21h` calls, DOS internals, hardware protocols, and disk errors
  are still unsupported or simplified. BIOS and VGA behavior vary by emulator.
- `INT 21h AH=30h` advertises DOS 6.22 solely as a compatibility target, not
  an assertion of actual DOS 6.22 compatibility.
- The experimental boot format reserves 64 post-boot sectors for the kernel;
  it does not match Microsoft's DOS system boot layout.

Do not overwrite an existing disk with this experimental image.

## Repository layout

- `boot/boot.s`: FAT12 BIOS bootloader, 64-sector fixed-location loader
- `kernel/kernel.s`: console, FAT12 reader, COM loader and DOS interrupts
- `programs/*.s`: sample DOS .COM and small MZ .EXE program source
- `tools/mkfloppy.py`: FAT12 image constructor
- `tools/mkmz.py`: small test-only MZ executable wrapper
- `tests/test_image.py`: disk layout and executable integrity checks
- `docs/ROADMAP.md`: next compatibility milestones

## Licensing

GNU General Public License **version 3 only** (`COPYING`). Each original source
file is GPL-3.0-only. No Microsoft or FreeDOS code has been copied into this
prototype. BIOS/DOS public API behavior is used solely for compatibility.
