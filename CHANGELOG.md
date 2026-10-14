# VelvetDOS changelog

## 0.2.0 — October 14, 2026 (development preview)

- Added bounded MZ `.EXE` loading with relocation handling for small DOS EXEs.
- Added read-only `INT 21h` open, close, read and seek APIs (AH=3Dh/3Eh/3Fh/42h).
- Added basic MCB allocate/free/resize APIs (AH=48h/49h/4Ah).
- Added `EXEDEMO.EXE`, `READ.COM`, `MEMORY.COM` regression programs.
- All implementation code remains 8086 real-mode assembly; no Pascal.
- Verified source build/image structure locally; 86Box boot requires testing.

## 0.1.0 — October 14, 2026 (experimental foundation)

- Genuine BIOS-loaded real-mode 16-bit x86 boot sector and kernel.
- FAT12 1.44 MB floppy, 64 reserved loader sectors, read-only root directory.
- Shell commands HELP, DIR, VER, CLS and REBOOT.
- Native DOS COM loading, minimal PSP setup, FAT12 cluster chaining.
- Partial INT 21h API plus INT 20h termination.
- Three COM demos including a multiple-FAT12-cluster program.
- GPLv3-only source, GNU binutils Makefile, Python disk image packer.
- Eight FAT12/packager structural tests passed locally.

**Verification:** Native build and structural tests passed. Emulator boot and
interactive program execution have not been verified in the build environment
because QEMU and DOS hardware emulators were unavailable. This is a pre-alpha
prototype, not a general-purpose MS-DOS replacement.
