# VelvetDOS 0.6.0 (development preview)

VelvetDOS is an experimental **GNU GPLv3-only**, 8086-compatible, real-mode
DOS operating system. **This preview has not been boot-tested in 86Box yet**;
run it only with disposable, writable floppy image copies.

## What's new

Version 0.6.0 extends **FAT12 subdirectories from 1 cluster (16 directory
entries) to up to 8 clusters (128 entries, including `.` and `..`)**. The FAT
root directory remains fixed at 224 entries, as required by the image's BPB.

- Subdirectory reads now follow the FAT12 cluster chain, loading the complete
  directory into a bounded 4 KiB buffer.
- Creating a file or subdirectory in a full subdirectory allocates another
  cluster, zero-initializes and writes it, and links it into the FAT chain.
- File lookup, DOS Find First/Find Next, directory listing, timestamps, attributes,
  and open-handle directory entry offsets work with entries beyond the first
  cluster.
- Metadata flushing writes *every* directory cluster, and `RD` checks and
  frees the entire directory chain when empty.
- A new DOS API-only `DIRGROW.COM` test creates **20 files**, forces a second
  directory cluster, searches them through the DOS DTA, reads the final file,
  deletes all files, and removes the directory.
- The earlier 0.1.0–0.5.0 regression programs are retained.

## Linux build

Requires GNU Make, GNU binutils (`as`, `ld`), Python 3, and optional QEMU.
No 16-bit C compiler or Free Pascal compiler is required.

```sh
make clean test
make run   # only if qemu-system-i386 is installed
```

Output: `build/velvetdos-0.6.0.img` — a 1.44 MB FAT12 floppy image.

## Manual 86Box acceptance test

**Boot a new, writable copy of the image. Do not use an image that already
contains `A:\\GROW`.**

```text
A:\\>VER
A:\\>HELLO
A:\\>EXEDEMO
A:\\>FINDTEST
A:\\>DIRGROW
```

The new regression should print:

```text
DIRGROW.COM: 20 files, FAT directory growth, DTA, cleanup PASS!
```

If it fails, report the exact `DIRGROW.COM failed at: ... AX=XXXX` output.
A failed test may leave the `GROW` directory on disk, so use a **fresh copy**
before retrying. `DIRGROW` automatically removes all its test files and
`GROW` on success.

Separately verify `VLIST`, `READ`, and `PATHS` on fresh writable disk copies.
`PATHS` creates `LAB`/`ONE`; it should not be run twice on the same image.

## DOS interface status

The OS still implements a **small subset** of MS-DOS calls, including `.COM`
and restricted MZ `.EXE` loading, FAT12 file create/read/write/delete/seek,
DOS pathname parsing, `CD`/`MD`/`RD`, attributes and timestamps, DTA management,
Find First/Find Next and basic memory management.

### Known limitations

- **Pre-alpha:** only static FAT12 1.44 MB floppy geometry, no FAT16/32,
  filenames limited to 8.3, no LFN, no hard-disk controller support.
- Maximum eight FAT12 clusters (128 directory entries) in a subdirectory;
  attempting to add a 129th entry fails without growing past the buffer.
- The root directory does not grow. Directory blocks are *not* reclaimed
  while a directory is still present; `RD` releases the whole chain.
- Metadata writes are not atomic or journaled. Abrupt reset, power loss,
  emulated media failure, or write errors can leave a damaged FAT12 image.
- Long/looping/corrupt FAT chains are not fully hardened against malicious
  disk images; keep testing on disposable images.
- DOS file locking/sharing, robust error propagation, full 8086 MZ loading,
  resident device drivers, process environments, batch files, PC game
  hardware quirks, and most `INT 21h` services remain unimplemented.
- The shell is still built into the kernel, not a separate `COMMAND.COM`.
- 386 protected mode, DPMI/GO32v2 and Free Pascal applications are deferred.

**Verification completed here:** kernel and floppy image build, 21 Python
structural tests pass, the previous DOS program binaries are preserved, and
checks confirm the directory buffer does not overlap application memory.
The 0.6.0 runtime path has **not** yet been exercised in an x86 emulator.

## Source layout

- `boot/` — 8086 boot sector
- `kernel/kernel.s` — DOS interrupt handler and FAT12 filesystem
- `programs/dirgrow.s` — new native directory expansion test
- `programs/` — other native regression programs
- `tests/test_image.py` — FAT12 and build integrity tests
- `tools/` — boot image generator and DOS MZ test helper
- `docs/ROADMAP.md` — release goals

## License

VelvetDOS source files are licensed under the **GNU General Public License
version 3 only** (see `COPYING`, SPDX `GPL-3.0-only`). No Microsoft or
FreeDOS proprietary/copy-left incompatible kernel code is included.
