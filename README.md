# VelvetDOS 0.8.0 — Standalone COMMAND.COM preview

VelvetDOS is an experimental **GNU GPLv3-only, 8086 real-mode DOS-compatible
operating system**, currently using GNU `as` and `ld` for assembly. Version
0.8.0 introduces a genuine, separately assembled **`COMMAND.COM`** and an
initial synchronous DOS `EXEC` service (`INT 21h AH=4B00`). This is still
**pre-alpha**, not a general replacement for MS-DOS or FreeDOS.

The project has no Pascal or 386 protected-mode dependencies. The core is
still 8086-compatible; 386/DPMI and 32-bit Free Pascal are later milestones.

## What's new in 0.8.0

- `COMMAND.COM` is a separately linked real-mode `.COM` program on the FAT12
  floppy. The kernel finds and launches it during boot instead of displaying
  the old built-in shell by default.
- The built-in kernel shell remains an emergency fallback if `COMMAND.COM`
  cannot be loaded or if it exits with `EXIT`.
- The command interpreter uses DOS interrupts to handle `HELP`, `VER`, `CLS`,
  `DIR`, `CD`, `MD`, `RD`, `STATUS`, `REBOOT`, and `EXIT`.
- `INT 21h AH=4B00` loads **one** external `.COM` child synchronously in a
  separate segment. The parent `COMMAND.COM` remains resident and resumes
  when the child calls `INT 20h` or `INT 21h AH=4Ch`.
- Child PSP has a conventional parent pointer, PSP, environment pointer,
  command-line arguments, and its own default DTA. The parent's DTA,
  interrupt frame, and conventional-memory allocation boundary are restored
  when the child exits. `AH=4Dh` returns the child exit code.
- `EXECCHK.COM` tests rejection of nested `EXEC` and child PSP reporting.
  Earlier regression binaries are retained.

**Current supported EXEC subset:** `AH=4B, AL=00`, `.COM` file with an explicit
8.3 extension, caller's environment selected using parameter block word zero,
command-tail pointer at `ES:BX+2/+4`. This is not yet general DOS process
management; it supports a single resident `COMMAND.COM` and a single child.

## Build

Requires `make`, GNU `as`/`ld` from binutils, and Python 3. QEMU is optional.
86Box can boot the `.img` directly.

```sh
make clean test
make run         # requires qemu-system-i386
```

The image is `build/velvetdos-0.8.0.img` (1.44 MB, FAT12). It contains both
`KERNEL` in reserved sectors and normal filesystem files including
`COMMAND.COM`, `HELLO.COM`, and all the regression binaries.

## Test in 86Box

Boot a **fresh, writable copy** of the image and confirm the interpreter
prints `VelvetDOS COMMAND.COM 0.8.0` before the `A:\>` prompt.

```text
VER
DIR
HELLO
HELLO.COM
PSPTEST hello MiXeD 123
STATUS
EXITTEST
STATUS
EXECCHK
STATUS
FINDTEST
VLIST
MEMORY
```

Expected highlights:

- `HELLO` and `HELLO.COM` each print the existing 16-bit message and **return
  to the `COMMAND.COM` prompt**; multiple launches should work consecutively.
- `PSPTEST hello MiXeD 123` reports PASS, including verifying that its PSP
  parent points to resident COMMAND.COM at segment `3000h`.
- `EXITTEST` reports a return value of `2A` hex; subsequent `STATUS` prints
  `2A` (the value is consumed when queried).
- `EXECCHK` prints `nested EXEC rejected, child PSP PASS!`. A following
  `STATUS` prints `00`.
- `FINDTEST`, `VLIST`, and `MEMORY` should continue working through DOS EXEC.

For destructive directory/file regressions use another fresh writable floppy:

```text
PATHS
DIRGROW
WRITE
APPEND
RECHECK
```

For the previously supported restricted **MZ `.EXE` test**, type `EXIT` to
leave the standalone interpreter for the recovery kernel shell, then run
`EXEDEMO` there. Running MZ children from `COMMAND.COM` is **not** supported
by the first `EXEC` implementation.

## Known limits and cautions

- **Do not use on valuable disks or real hardware.** FAT metadata writes are
  not transactional and can corrupt an interrupted disk image.
- Only **one** child `.COM` process at once. Nested `EXEC` fails with DOS error
  8. MZ `.EXE` child EXEC, shell PATH searching, batch files, pipes,
  redirection, shell environment editing, TSRs, file handle inheritance,
  and full DOS executable memory/ownership semantics are not implemented.
- Parent segment is fixed at `3000h`, child at `5000h`. This is a staging
  solution, not a production DOS memory allocator. Some programs that expect
  a full conventional-memory allocation or inherited open files can fail.
- The new COMMAND.COM handles only one argument string for `CD`/`MD`/`RD`,
  and only single-part 8.3 program names (no wildcard executable lookup).
- The old emergency shell remains part of the kernel in this version and
  still supports the restricted MZ loader. It has not been removed yet.
- Structural tests check boot image layout, generated binaries and source
  contracts. They **do not substitute for 86Box runtime tests**. Runtime
  execution of 0.8.0 has not been verified here.

## Directory structure

- `boot/` — real-mode FAT12 floppy boot sector
- `kernel/kernel.s` — DOS interrupts, filesystem, PSP, and first EXEC path
- `programs/command.s` — standalone `COMMAND.COM` shell
- `programs/execchk.s` — nested EXEC regression
- `programs/*.s` — other DOS regression programs
- `tools/` — floppy image and minimal MZ format build tools
- `tests/` — host-side image integrity tests
- `docs/ROADMAP.md` — roadmap

## Licensing

All original VelvetDOS source files are licensed under **GNU GPL version 3
only**, identified by `SPDX-License-Identifier: GPL-3.0-only` in their headers.
See `COPYING`. No Microsoft/FreeDOS source code is included.
