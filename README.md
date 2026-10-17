# VelvetDOS 0.12.0 — Batch files and DOS environment (development preview)

VelvetDOS is a GPLv3-only experimental, independently implemented 8086
real-mode DOS-compatible OS. It is **not** a complete MS-DOS replacement.
Always boot disposable writable FAT12 floppy copies in 86Box or QEMU.

This development release builds on the 0.11.0 memory-ownership and EXEC stack
hotfix. It moves another set of DOS user-facing features into the resident
`COMMAND.COM`, without introducing Pascal or 386 instructions.

## New in 0.12.0

- `COMMAND.COM` can open and execute **one non-nested `.BAT` script** with
  `INT 21h` open/read/close. Both `DEMO` and `DEMO.BAT` work. The shell tries
  `.COM`, then `.EXE`, then `.BAT` for bare filenames.
- Batch lines are read incrementally from disk, accept CRLF or LF line endings,
  and are run through the same interpreter as interactive commands.
- `SET` displays the environment, assigns/replaces `NAME=VALUE` entries,
  and deletes entries with `SET NAME=`. Names are uppercased; values preserve
  their case. Invalid names and oversized edits are rejected without changes.
- `PATH` displays or sets the environment's `PATH` value. **Executable search
  using PATH is not implemented**; only the current directory or an explicit
  pathname is searched for programs.
- `ECHO`, `REM`, and a leading `@` are understood by the basic batch reader.
  For now, command echoing is always disabled; `ECHO ON/OFF` is accepted.
- Environment entries written by `SET` are inherited by EXEC children via the
  0.10.0 copy-on-EXEC child environment mechanism.
- `DEMO.BAT` and `ENVCHK.COM` exercise batch dispatch, SET, PATH, environment
  inheritance, child termination, and deletion of a variable.
- The kernel supports DOS open (`INT 21h AH=3Dh`) **non-inherit bit 7** for
  read-only file handles; `COMMAND.COM` uses it for the currently open `.BAT`
  file. A child therefore doesn't inherit the batch reader's internal handle.
  Normal read-only handles remain inheritable (the `HNDTEST` regression).

## Build on Linux

Requires GNU Make, GNU binutils (`as` and `ld`), and Python 3.

```sh
make clean
make test
make run        # if QEMU is installed; otherwise use 86Box
```

The 1.44 MB image is `build/velvetdos-0.12.0.img`.

## Test this release in 86Box

Boot a fresh floppy image. Type:

```text
VER
HELP
SET
PATH
DEMO
SET
DEMO.BAT
SET BATCHOK=YES
ENVCHK
STATUS
SET BATCHOK=
HNDTEST
MEMOWN
MEMOWN
PSPTEST hello MiXeD 123
EXECHK hello MiXeD
FINDTEST
```

The two important success messages from `DEMO` are:

```text
ENVCHK.COM: child inherited BATCHOK=YES PASS!
PSPTEST.COM: command tail, PSP, DTA, handles, environment PASS!
```

Run `PSPTEST hello MiXeD 123` independently afterward too. The `.BAT` file
stays open during `DEMO`, but its handle must **not** appear in the child PSP;
when typed interactively the same PSP test must also pass.

`DEMO` should return to the prompt at EOF, and `SET` afterward should **not**
contain `BATCHOK`. `ENVCHK` run without first setting `BATCHOK=YES` should
return failure status `01`; with the variable present it should report PASS
and exit `00`. `HNDTEST`, `MEMOWN`, and prior tests should continue passing.
Run the write-intensive `DIRGROW`/`PATHS`/`WRITE` regression on separate
writable copies if needed.

## Deliberate limits

- This is a **small batch interpreter**, not complete COMMAND.COM batch
  compatibility. No `IF`, `GOTO`, `FOR`, `CALL`, `%VAR%` substitution, `%1`
  parameters, redirection, pipes, `AUTOEXEC.BAT`, or nested batch files.
- The shell edits a **fixed 256-byte environment** in place; variables cannot
  exceed 125 bytes including the name. The DOS 3+ program-name trailer
  (count=1 plus ASCIIZ path) is now preserved when SET/PATH rebuild the block;
  insufficient space or malformed metadata rejects the edit. This remains a
  limited environment implementation, not full DOS environment semantics.
- `PATH` can be edited but is not used to locate executables.
- The current `COMMAND.COM` uses single-byte DOS file reads for batch lines:
  correct for small scripts, not yet optimized for large scripts.
- Child processes remain one level deep, DOS file handle count is small,
  and the MZ/COM memory allocation policy is still bounded.
- FAT12 updates are not crash-safe; always use throwaway disk images.

## 0.12.0 environment trailer hotfix

Following 86Box testing, `PSPTEST hello MiXeD 123` failed at **Environment
block** after the batch tests ran. The shell's `SET` implementation omitted
DOS's 16-bit trailing name-count and ASCIIZ program path when rebuilding the
environment variables. This hotfix preserves that metadata and rejects updates
that cannot fit it in the 256-byte buffer. `DEMO.BAT` now runs `PSPTEST` after
changing and removing variables, so the old regression is exercised with the
new environment editor.

The environment hotfix alone was tested: `PSPTEST` succeeded interactively but
failed inside `DEMO.BAT`. The batch file's open handle (slot 5) was inherited
into the child and violated PSPTEST's expectation of a free slot. This follow-up
fix uses the conventional non-inherit flag rather than weakening PSPTEST.

**86Box verification of the combined hotfixes is still required.**

## Verification

Host-side assembler/build and **39 offline tests pass**. Source patch
reproduction is checked separately. The user reported that the previous
hotfix passed standalone PSPTEST but failed when run inside DEMO.BAT.
**This combined fix still requires 86Box runtime verification** before tagging.

## Repository note

At preparation time, GitHub `main` had the 0.11.0 allocator hotfix but several
remaining files (`COMMAND.COM`, `Makefile`, memory child fixture, changelog)
were still at 0.10.0. The 0.12.0 source patch is based on the **actual GitHub
main tree**, and intentionally includes the missing 0.11.0 source updates
as well as 0.12.0 changes.

## License

All original code is GPL-3.0-only (`COPYING`). No Microsoft or FreeDOS kernel
code is bundled.
