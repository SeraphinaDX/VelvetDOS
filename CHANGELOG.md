# VelvetDOS changelog

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
