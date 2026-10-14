# VelvetDOS 0.4.0 (development preview)

VelvetDOS is an experimental 8086-compatible, real-mode DOS operating system,
licensed under **GNU GPL version 3 only**. It aims to execute unmodified DOS
applications. It is **not yet a complete MS-DOS implementation**.

Version 0.4.0 extends the FAT12 filesystem from root-only operation to **nested
8.3 directories**, including DOS path parsing, directory navigation, and file
operations within those directories. It builds on the 0.3.0 release that was
merged and tagged by the project owner; 0.3.0 runtime test results were not
separately reported here.

## Corrected 0.4.0 test build

- Fix GNU assembler backslash parsing: four path comparisons must use `0x5C`,
  not `'\'`, which was assembled as `0x27` (apostrophe). Previously
  `LAB\ONE` could become a *single invalid FAT directory entry*.
- Keep the stage-by-stage `PATHS.COM` diagnostic: a failure now reports the
  exact operation and AX return code.
- Add a compiled-opcode regression check for all four separators.
- Use a fresh writable floppy image. Discard older test images with malformed
  directory names rather than attempting to repair them using VelvetDOS.

## New in 0.4.0

- `INT 21h AH=39h`: create a subdirectory.
- `INT 21h AH=3Ah`: remove an **empty** subdirectory.
- `INT 21h AH=3Bh`: set the current directory.
- `INT 21h AH=47h`: return the current directory (DOS path without drive/initial slash).
- DOS 8.3 paths in file create, open, and delete APIs. Relative paths,
  `A:`, `A:\`, `.`, `..`, backslashes, and forward slashes are supported.
- Directory-aware handles: file metadata is synchronized to the correct
  directory entry, not always the root.
- Built-in shell adds `CD`, `MD`, `RD`, and a directory-aware `DIR`, with
  current-directory display in the `A:\` prompt.
- New `PATHS.COM` executable tests directory syscalls, nested paths,
  CWD reporting, 600-byte file write/read, nonempty-directory rejection,
  cleanup, and failure to enter a removed directory.

**Compatibility scope:** Each non-root directory occupies exactly **one FAT12
cluster (512 bytes)**. Its two dot entries leave **14 usable entries**.
Directories may be nested up to **8 levels**; AH=47h rejects directory strings
that do not fit in its traditional 64-byte buffer. Existing externally-created
multi-cluster directories can be browsed only within their first cluster;
their removal is refused if the FAT chain extends further.

**Verification:** The source assembles using the GNU assembler's 8086 mode,
the 1.44 MB FAT12 image builds, and 16 offline integrity/structural tests pass.
The new directory code has **not yet been executed in 86Box**. Mark the release
as a preview until the runtime tests below pass.

## Build on Linux

Requires GNU Make, GNU binutils (`as`, `ld`), and Python 3. QEMU is optional,
or use 86Box with an IBM PC-compatible floppy controller.

```sh
make clean test
make run  # requires qemu-system-i386
```

Image: `build/velvetdos-0.4.0.img` (1.44 MB). **Boot a disposable, writable
copy**. Do not test experimental FAT writes on a valuable image or physical
storage.

## Test in 86Box

### New automatic test

At the `A:\>` prompt on a **fresh writable image**, run:

```text
PATHS
```

Expected result:

```text
PATHS.COM: directories, paths, file I/O PASS!
```

`PATHS` creates `LAB` then `ONE` inside it, changes directory, checks DOS `AH=47h`, writes a
600-byte file, reopens it with `A:\LAB\ONE\TEST.DAT`, verifies the bytes,
checks that a nonempty directory cannot be removed, deletes the file, and
removes both directories. Running it twice should succeed if the first run
completed successfully.

### Shell smoke test

```text
MD DEMO
CD DEMO
DIR
CD ..
RD DEMO
DIR
```

The prompt should change between `A:\>` and `A:\DEMO>`. In this version,
program execution searches the **current directory only**; there is no `PATH`
search yet, so run `PATHS`, `WRITE`, etc. while at the root.

### Regression tests from 0.3.0

```text
HELLO
EXEDEMO
READ
MEMORY
WRITE
APPEND
RECHECK
DELETE
```

For persistence testing, restart 86Box using the **same writable image** and
re-run `RECHECK` **before** `DELETE`.

## Implemented DOS API slice

| INT 21h | Feature | Present scope |
| --- | --- | --- |
| 39h | Create directory | 8.3, one cluster per directory |
| 3Ah | Remove directory | Empty, single-cluster, not CWD/ancestor |
| 3Bh | Change directory | Relative/absolute, max depth 8 |
| 47h | Get current directory | Current A: drive |
| 3Ch / 3Dh | Create / open files | 8.3 files inside supported directories |
| 3Eh | Close | Flush directory/FAT metadata |
| 3Fh / 40h | Read / write | Data over FAT12 cluster chains |
| 41h / 42h | Delete / seek | Basic DOS file semantics |
| 48h–4Ah | Conventional memory | Preliminary single-process MCB manager |

## Known limitations

- **Not safe for valuable disk images or real disks.** FAT copies, file data,
  and directory metadata are not updated transactionally; interruptions or
  BIOS write failures can corrupt the filesystem or leak clusters.
- Non-root directories are fixed at 16 entries (two reserved for `.`/`..`).
  No directory growth, no long filenames, wildcard searches, or multiple drives.
- `CD`, `MD`, `RD` accept one unquoted path argument; `DIR` lists the current
  directory only. The shell does not accept command arguments, execute batches,
  implement pipes/redirection, search `PATH`, or provide a separate COMMAND.COM.
- File handles remain limited to four (5–8), and sharing/locking, proper
  attributes, timestamps, access/error codes, and directory inheritance are
  incomplete. Read-only and program execution are not yet broadly tested with
  external DOS binaries.
- Executables are limited to the current small `.COM` and MZ `.EXE` loader;
  no full DOS driver model, EMS, XMS, DPMI, TSRs, or 386 protected mode.
- The boot sector uses a *private 64-sector kernel reservation*, not the
  conventional DOS system-file boot layout.
- `AH=30h` returns 6.22 as a compatibility target, **not** a conformance claim.
- 16-bit 8086 assembly throughout; no Pascal or protected-mode code.

## Repository contents

- `boot/`: 8086 boot sector.
- `kernel/kernel.s`: real-mode kernel, DOS calls, FAT12 driver.
- `programs/`: `.COM` / test `.EXE` assembly fixtures.
- `tools/`: floppy image and MZ fixture builders.
- `tests/`: offline floppy image regression tests.
- `docs/ROADMAP.md`: development direction.

## License

VelvetDOS source is licensed under **GNU GPLv3-only**, see `COPYING` and source
`SPDX-License-Identifier: GPL-3.0-only`. No MS-DOS or FreeDOS code is included.
