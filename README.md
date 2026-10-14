# VelvetDOS 0.9.0 — MZ EXEC compatibility preview

VelvetDOS is an experimental **GNU GPLv3-only**, **8086-compatible**,
real-mode DOS-like operating system. This version extends the separate
`COMMAND.COM` introduced in 0.8.0 so it can launch **bounded DOS MZ `.EXE`**
children as well as `.COM` files. It is **pre-alpha**, not a drop-in replacement
for MS-DOS or FreeDOS. Run it on a disposable floppy image in an emulator.

## What's new

- `INT 21h AH=4B00` now recognizes explicit `.COM` and `.EXE` names.
- Validates the MZ header, declared file length, relocation table, entry
  point, minimum memory, and initial stack against the current fixed child
  allocation. Invalid MZ images return **DOS error 11** without starting a
  child process.
- Relocates MZ fixup words by the child load segment, moves initialized
  EXE code/data past the PSP, initializes `CS:IP`, `SS:SP`, and `DS=ES=PSP`,
  and returns to the resident parent shell when the child exits.
- In `COMMAND.COM`, an unqualified executable name tries `.COM` and then
  `.EXE` **only when the first lookup returns file-not-found**. Explicit
  extensions are respected; there is no `PATH` searching yet.
- `EXECHK.EXE`: new MZ fixture checking relocation, PSP parent, command
  tail, and propagation of exit code `37h`. The existing `EXEDEMO.EXE`
  can now launch directly from `COMMAND.COM`.
- `BADMZ.EXE`: deliberately invalid relocation count to test clean error
  recovery, preserving the shell for further commands.
- Regression suite includes 28 host-side structural checks.

## Build on Linux

Requires GNU Make, binutils (`as`, `ld`) and Python 3. Optional: QEMU.

```sh
make clean test
make run   # if qemu-system-i386 is installed
```

The result is `build/velvetdos-0.9.0.img`, a FAT12 1.44 MB floppy image.
Boot a fresh copy with **86Box** or QEMU. Build scripts do not need Pascal,
a DOS cross-compiler, or an i386-only host.

## 86Box manual regression

At the standalone `VelvetDOS COMMAND.COM 0.9.0` prompt:

```text
A:\>VER
A:\>HELLO
A:\>EXECHK hello MiXeD
A:\>STATUS
A:\>EXEDEMO
A:\>STATUS
A:\>EXEDEMO.EXE
A:\>BADMZ
A:\>HELLO
A:\>EXECCHK
A:\>PSPTEST hello MiXeD 123
A:\>FINDTEST
A:\>VLIST
```

Expected:

- `EXECHK` prints `EXECHK.EXE: MZ, relocation, PSP, tail PASS!`
- The first `STATUS` prints `37` hex (the EXE's success code).
- `EXEDEMO` works from **COMMAND.COM** without entering recovery mode.
- After `EXEDEMO`, `STATUS` prints `00` hex.
- `BADMZ` returns to the prompt with `EXEC failed, DOS error AX=0B`.
- Subsequent `HELLO`, `EXECCHK`, `PSPTEST` and `FINDTEST` still pass.
- For the prior directory/file-writing tests (`PATHS`, `DIRGROW`, `WRITE`,
  `APPEND`, `RECHECK`, `DELETE`), use a separate **writable disposable image**.

This release has been assembled and verified with host-side tests, **not**
run in 86Box in the build environment. The 86Box tests above still need
confirmation before considering 0.9.0 validated.

## Current EXEC subset and restrictions

- `AH=4B00` only: one child at a time, launched from the resident
  `COMMAND.COM`. Nested `EXEC` is intentionally rejected with AX=0008.
- Small real-mode MZ files whose **complete disk file is at most 65,024
  bytes**, with an initialized image that fits within 64 KiB. This does **not**
  yet support large multi-segment images, overlays requiring special loaders,
  DOS extenders, DPMI, or protected mode.
- Execution uses fixed resident shell segment `3000h` and child PSP `5000h`;
  entry relocation base is `5010h`. Full DOS allocator ownership, process
  environment inheritance, file handle inheritance, file sharing, interrupt
  restoration, and true TSR semantics are not implemented.
- Only the bootstrap environment and simple command tails are supported.
  The interpreter has no batch processing, redirection, pipes, `PATH`
  searching, or memory-resident commands beyond its current small built-ins.
- FAT12 metadata updates are not transactional; an interrupted write can
  corrupt the floppy. **Do not use on valuable images or physical disks.**
- The kernel retains its older restricted MZ path in the emergency recovery
  shell. The new child MZ loader is a separate path and has tighter header
  validation, pending 86Box tests.
- Core stays 8086 assembly; **Pascal remains deferred** until later 386
  DOS-extended support.

## Source layout

- `boot/` — FAT12 boot sector
- `kernel/kernel.s` — interrupts, FAT12, loader, PSP and bounded EXEC
- `programs/command.s` — standalone command interpreter
- `programs/exechk.s` — DOS MZ child-execution test
- `tools/mkmz.py`, `tools/mkbadmz.py` — MZ test image generation
- `tests/` — offline regression suite
- `docs/ROADMAP.md` — milestones

## License

Original VelvetDOS source is **GNU GPL version 3 only** (`COPYING`,
`SPDX-License-Identifier: GPL-3.0-only`). No Microsoft or FreeDOS kernel source
is incorporated.
