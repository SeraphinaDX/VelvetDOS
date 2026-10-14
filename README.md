# VelvetDOS 0.7.0 — Program compatibility preview

VelvetDOS is an experimental **8086 real-mode DOS-compatible operating system**
under GNU **GPLv3-only**. This release builds on the 0.6.0 source that was
validated in 86Box by the project owner. It adds a real DOS-style PSP command
tail and a minimal process environment so native DOS programs can inspect
arguments and startup information.

> **Development preview:** Builds and offline tests pass, but **0.7.0 has not
> yet been boot-tested in 86Box**. Use disposable disk images, not real data.

## Added in 0.7.0

- The internal shell accepts arguments after a `.COM` or small MZ `.EXE` name.
  The executable name is normalized to uppercase for FAT12 lookup, while the
  tail's original case and whitespace are preserved.
- A DOS-compatible command tail is passed in the PSP at offset `80h`: one
  length byte, the tail starting at `81h`, then a carriage return (`0Dh`).
  `INT 21h AH=2Fh` still reports the default DTA at `PSP:0080h`.
- The PSP now has pointers to the startup interrupt vectors, a placeholder
  parent segment (`0`), a conventional default handle table, and two blank
  default FCB name fields. DOS handle inheritance is not yet implemented.
- `PSP:002Ch` points to a read-only bootstrap environment below the program
  allocation area. It contains `PATH=A:\`, `PROMPT=$P$G` and an extended
  program-name string. `SET` / per-process mutable environments remain future work.
- `INT 21h AH=51h` and `62h` return the current PSP segment in `BX`.
- `INT 21h AH=4Ch` records the application's `AL` exit code; `INT 20h` and
  `AH=00h` record zero. `AH=4Dh` has a minimal one-shot return-code query,
  but no parent process or nested EXEC handling yet.
- `STATUS`, a temporary VelvetDOS shell diagnostic, displays the last exit
  status in hexadecimal.
- New public-API DOS test programs: `PSPTEST.COM` and `EXITTEST.COM`.

No Free Pascal, DPMI, or protected-mode code has been added.

## Build from source on Linux

Requires GNU Make, GNU binutils (`as`, `ld`, `objdump` for one regression), and
Python 3. QEMU is optional.

```sh
make clean test
make run                  # if QEMU is installed
```

The 1.44 MB image is `build/velvetdos-0.7.0.img`. Copy this image before
using it as a writable floppy in **86Box**.

## 86Box acceptance testing

Boot **a fresh writable image** and enter these commands exactly (the mixed
case matters for verifying the command tail):

```text
A:\>VER
A:\>PSPTEST hello MiXeD 123
A:\>STATUS
A:\>EXITTEST
A:\>STATUS
A:\>HELLO
A:\>EXEDEMO
A:\>FINDTEST
A:\>VLIST
```

Expected messages:

```text
PSPTEST.COM: command tail, PSP, DTA, handles, environment PASS!
Last program exit code (hex): 00
EXITTEST.COM: returning code 2A hex (42 decimal).
Last program exit code (hex): 2A
```

`PSPTEST` will print `PSPTEST.COM failed at: <stage>` if an API check fails.
When `STATUS` is invoked after that failure, the expected hexadecimal code is
`01`. Test `DIRGROW`, `PATHS` and `WRITE/APPEND/RECHECK/DELETE` on separate
fresh writable images because they manipulate on-disk files and directories.

## Important limitations

- This is **not a full MS-DOS-compatible environment**: no standalone
  `COMMAND.COM`, batch processing, `AH=4Bh` EXEC, process nesting, environment
  mutation, conventional handle inheritance, shell variable expansion,
  pipelines, redirection or quoting rules. PSP vectors are copied but no
  full termination/break handler mechanism is implemented.
- The shell accepts a single 8.3 command token and a raw argument tail. It
  does not understand quoted executable paths or search `PATH` for programs.
  The command-line input limit is **120 characters** total.
- `AH=4Dh` reflects the last terminated program, not a real parent's child
  process status. The `STATUS` shell command is non-standard and diagnostic.
- Subdirectories are limited to 8 FAT12 clusters; FAT12 writes are not
  crash-safe. Only 1.44 MB floppy geometry and limited `.COM`/MZ loading.
- Kernel and C library DOS API coverage remains incomplete; hardware-specific
  games and 32-bit DOS extenders are unsupported.

## Project layout and license

- `boot/` — 8086 bootloader
- `kernel/` — real-mode kernel, DOS INT 21h handler and FAT12 driver
- `programs/` — standalone DOS API regression programs
- `tools/` — host-side FAT12 image generator and minimal MZ fixture creator
- `tests/` — offline integrity and static compatibility regression checks
- `docs/ROADMAP.md` — milestone roadmap

All original VelvetDOS source code is **GNU GPL version 3 only** (`COPYING`,
SPDX `GPL-3.0-only`). No Microsoft or FreeDOS kernel code was copied.
