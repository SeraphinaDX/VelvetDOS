# VelvetDOS 0.1.0 (experimental foundation)

VelvetDOS is a new GNU GPLv3-licensed project aiming for **binary compatibility
with DOS software** on IBM PC-compatible x86 computers. This milestone is a
proof-of-concept real-mode floppy OS, **not yet a full MS-DOS replacement**.

## What works in this first foundation

- Bootable 1.44 MB FAT12 floppy image using a real BIOS 16-bit bootstrap.
- A real-mode kernel with interrupt vector installation for `INT 20h/21h`.
- Internal commands: `HELP`, `DIR`, `VER`, `CLS`, `REBOOT`.
- Read-only FAT12 root-directory enumeration and FAT12 cluster chaining.
- Load and execute **root-directory `.COM` programs** (up to 65024 bytes).
- Initializes a minimal DOS Program Segment Prefix (PSP) and sets up a COM stack.
- Process exit via `INT 20h`, `INT 21h AH=4Ch`, `AH=00h`, and near `RET`.
- Partial `INT 21h` console API: `AH=01h`, `02h`, `07h`, `08h`, `09h`, `0Ah`,
  `19h`, `30h`, `40h` (stdout/stderr only), `4Dh`, plus termination.
- Three example genuine 16-bit programs: `HELLO.COM`, `RETURN.COM`,
  and multi-cluster `CHAIN.COM`.
- Dependency-free FAT12 disk packer and structural tests.

## Requirements (Linux)

- GNU Make, GNU binutils (`as`, `ld`), Python 3.
- QEMU (`qemu-system-i386`) **to actually run** the image.

The kernel is currently **entirely 16-bit x86 assembly** so this first
milestone needs no particular 16-bit C compiler. Future kernels can incorporate
16-bit C via a toolchain such as Open Watcom.

## Build and run

```sh
make image
make test
make run
```

`make run` boots from the generated `build/velvetdos-0.1.0.img`.
You can also use:

```sh
qemu-system-i386 -drive file=build/velvetdos-0.1.0.img,if=floppy,format=raw -boot a -m 16
```

At the `A:\>` prompt, try:

```
HELP
DIR
VER
HELLO
RETURN
CHAIN
CLS
```

The build does **not** modify your computer's disks. Do not write this
experimental boot image to a physical drive containing anything important.

## Important limitations

**This is an early bootable kernel, not a claim of compatibility with all DOS
programs.** Most DOS programs will not run yet.

- No `.EXE` MZ loading, subdirectories, command arguments, pipes, or batch files.
- No writable filesystem, file handles for disk files, DOS memory allocation,
  TSR lifecycle, environment blocks, DOS device drivers, EMS/XMS, or DPMI.
- No implementation of many documented or undocumented DOS calls.
- Disk reads use BIOS CHS for a 1.44 MB floppy. Drive selection is limited to A:.
- No hardware probing, robust disk retries, real memory ownership management,
  secure process isolation, or fault recovery.
- DOS applications that directly use BIOS or supported emulated hardware may
  work partially, but hardware compatibility is outside this milestone.
- System clock, locale, error handling, and disk media-change handling are incomplete.
- MS-DOS version 6.22 is advertised by `INT 21h AH=30h` **only as a target
  interface**; do not interpret this as API completeness.

This is an educational/prototyping kernel. The disk-image layout reserves 64
sectors after the FAT12 boot sector for the kernel; this **does not** match how
MS-DOS itself lays out its operating system files.

## Repository layout

- `boot/boot.s`: FAT12 BIOS bootloader, 64-sector fixed-location loader
- `kernel/kernel.s`: console, FAT12 reader, COM loader and DOS interrupts
- `programs/*.s`: sample DOS .COM program source
- `tools/mkfloppy.py`: FAT12 image constructor
- `tests/test_image.py`: disk layout and executable integrity checks
- `docs/ROADMAP.md`: next compatibility milestones

## Licensing

GNU General Public License **version 3 only** (`COPYING`). Each original source
file is GPL-3.0-only. No Microsoft or FreeDOS code has been copied into this
prototype. BIOS/DOS public API behavior is used solely for compatibility.
