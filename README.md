# VelvetDOS 0.5.0 — DOS filesystem API preview

VelvetDOS is an experimental **GPLv3-only**, **8086 real-mode** DOS-compatible
operating system. It is **not a full replacement for MS-DOS**; use only on
**disposable, writable** FAT12 floppy disk images. The kernel remains assembly
only. There is no Free Pascal or 386 protected-mode code yet.

## What's new in 0.5.0

- `INT 21h AH=1Ah / 2Fh`: set/get Disk Transfer Area (DTA), defaulting to the
  running program's PSP:0080. A program can maintain independent searches with
  different DTA buffers.
- `AH=4Eh / 4Fh`: DOS-style Find First / Find Next, 8.3 wildcards `*` and `?`,
  directory-relative or absolute paths, per-DTA search state, DTA result layout
  (attribute/time/date/size/name). Hidden, system, and directory entries are
  excluded unless requested in `CX`. Volume labels/LFN are not supported.
- `AH=43h AL=0/1`: get or set ordinary file attributes. Set supports read-only,
  hidden, system, and archive bits; directories are not mutable by this call.
- `AH=57h AL=0/1`: get/set FAT modification date/time for an open file handle;
  setting requires a write-capable handle.
- `AH=36h`: free-space report for `A:`/default drive (1 sector/cluster,
  512 bytes/sector, 2783 FAT12 clusters); invalid drive returns `AX=FFFFh`.
- `VLIST.COM`: native DOS directory listing using only `AH=4Eh/4Fh`, not
  VelvetDOS shell internals.
- `FINDTEST.COM`: separately assembled native DOS API regression for DTA,
  Find First/Next, wildcards, hidden file filtering, attributes, timestamps,
  disk free space and a cleanup sequence.

## Build

Requires GNU Make, GNU binutils (`as`, `ld`) and Python 3. QEMU or 86Box is
required for **runtime** verification.

```sh
make clean test
make run                     # optional QEMU
```

Boot `build/velvetdos-0.5.0.img` in 86Box as a **writable floppy**. Prefer a
fresh copy when running a test that modifies the disk.

## 86Box acceptance checks

Start with a **fresh image**, then run:

```dos
A:\>VLIST
A:\>FINDTEST
A:\>HELLO
A:\>EXEDEMO
A:\>READ
A:\>MEMORY
```

- `VLIST` should list `HELLO.COM`, `EXEDEMO.EXE`, `VLIST.COM`, and other
  boot-disk entries. Its listing is obtained through DOS APIs.
- `FINDTEST` should print `FINDTEST.COM: all DOS API checks PASS!`.
  If it fails, it prints the API step and AX result; report that output.
- After `FINDTEST`, `ATTR05.TST` should **not** remain on the disk.

For writable FAT12 regression, run `WRITE`, `APPEND`, `RECHECK`, then on
**the same writable image after restarting 86Box** run `RECHECK` again. Use
`DELETE` to clean up. Run `PATHS` separately on a **fresh image**: it creates
and removes `LAB\ONE` and reports pass/fail by stage.

## API compatibility details and limits

| INT 21h | Scope in 0.5.0 |
|:--|:--|
| AH=1Ah / 2Fh | Set/get DTA address |
| AH=4Eh / 4Fh | Root or 1-cluster subdir Find First/Next; 8.3 `*` / `?` wildcards; DTA result at offsets 21..42 |
| AH=43h | File attributes get/set; limited flags; deny updates to open files |
| AH=57h | FAT file modification time/date read/set for open file handles |
| AH=36h | FAT12 floppy total/free cluster count, current / A: drive |
| AH=39h / 3Ah / 3Bh / 47h | Make/remove/change/get directory (from 0.4.0) |
| AH=3Ch..42h | Basic file creation, open, read/write, close, delete, seek (from 0.3.0) |
| AH=48h..4Ah | Preliminary single-program DOS conventional memory model (from 0.2.0) |

**Limitations:** FAT12 only; only drive A:; directory entries remain limited to
16 per subdirectory (including `.` and `..`), and 224 at root. FAT directory
growth and long filenames are **not** implemented. DOS sharing/locking,
interrupt-driven TSRs, full PSP command lines and environment blocks, batch
files, device drivers, DPMI, FAT16/32, and complete MZ/COM compatibility are
future work. The wildcard implementation targets conventional 8.3 DOS
patterns and does not reproduce all undocumented DOS search quirks. FAT
metadata writes are not crash-safe or transactional. New files may have zero
modification dates until the application sets them. Do not use this code on
important disks or hardware.

**Verification status:** offline assembly, image-integrity tests, and build
regression pass. **0.5.0 execution in QEMU/86Box is not verified here**;
please report the `FINDTEST` result before treating this version as final.
The 0.4.0 kernel and prior tests were verified by the maintainer in 86Box.

## License

Copyright (C) 2026 VelvetDOS contributors. Original VelvetDOS source is
**GNU GPL version 3 only**, `SPDX-License-Identifier: GPL-3.0-only`.
No Microsoft proprietary source or FreeDOS source has been incorporated.
