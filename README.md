# VelvetDOS 0.3.0 (development preview)

VelvetDOS is an experimental **GNU GPLv3** 8086 real-mode DOS-compatible operating
system. The 0.3.0 milestone adds **writable FAT12 root-directory files**,
building on 0.2.0's 86Box-tested COM/MZ executable loading, read-only DOS file
handles and preliminary memory management. **It is not a complete MS-DOS
replacement** and should run only against disposable disk images.

## New in 0.3.0

- BIOS-backed FAT12 **file creation, truncation, writing, and deletion** in the
  floppy root directory (`INT 21h AH=3Ch`, `40h`, `41h`).
- Read/write file handles (`AH=3Dh` modes 0, 1, and 2); file close (`3Eh`),
  reads (`3Fh`), and seek (`42h`) share the same 8.3 filename and FAT chain.
- Sector-buffered writes with allocation of additional FAT12 clusters;
  zero-initialize newly allocated sectors rather than copying old disk data.
- Flush file contents after each successful `AH=40h`. Persist both FAT copies
  and the root directory on close or normal program termination.
- `WRITE.COM`, `APPEND.COM`, `RECHECK.COM`, and `DELETE.COM` regression programs,
  along with the previous 0.1/0.2 tests.

**Verification:** assembly and disk image build successfully and the automated
image integrity tests pass. **86Box/runtime execution of the 0.3.0 changes has
not yet been verified.** The prior version (0.2.0) was tested by the project
owner in 86Box.

## Build on Linux

Requires GNU Make, GNU binutils (`as`, `ld`), Python 3. QEMU is optional; you
can use 86Box to boot the image instead.

```sh
make clean test
make run  # if QEMU is installed
```

Output: `build/velvetdos-0.3.0.img` (1.44 MB). Mount/boot **a writable copy**
in 86Box; leave the image unprotected, or BIOS writes will fail.

### Manual regression in 86Box

At `A:\>` enter, in order:

```text
HELLO
EXEDEMO
READ
MEMORY
WRITE
DIR
APPEND
RECHECK
```

`WRITE` creates `DATA.BIN` and tests a 700-byte cross-cluster write/read;
`APPEND` reopens it for read/write, seeks to EOF and adds `XYZ`;
`RECHECK` verifies the complete 703 bytes. The programs print PASS/FAIL.

For a **persistence test**, shut down the emulator after `APPEND`, boot the
*same writable disk image again*, then run `RECHECK`. Run `DELETE` to remove
`DATA.BIN`, then `DIR` to confirm it is gone. Avoid mounting a fresh image or
configuring 86Box to discard writes, or the persistence test will fail.

## DOS API coverage (partial)

| INT 21h | Purpose | Current scope |
|---|---|---|
| AH=3Ch | Create/truncate file | Root 8.3 only, ordinary/archive attributes |
| AH=3Dh | Open file | 4 concurrent handles (5–8), read/write modes |
| AH=3Eh | Close handle | Flush root/FAT metadata |
| AH=3Fh | Read | File data across FAT12 sectors |
| AH=40h | Write | File data plus stdout/stderr console output |
| AH=41h | Delete | Unlink root file and free FAT chain |
| AH=42h | Seek | Absolute/current/EOF; no sparse writes |
| AH=48–4Ah | Memory allocation | Provisional single-process MCB implementation |

## Known limitations and risks

- **Do not use on real storage or valuable floppy images.** FAT copies and root
  directory are written separately and **not transactionally**. Disk failure,
  forced shutdown, or interruption while updating metadata can corrupt the
  FAT12 filesystem. A dedicated 86Box/QEMU *copy* is essential.
- Root directory only; no `CD`, `MD`, `RD`, folder traversal, FAT16/32,
  date/time stamps, LFN, file sharing or locking.
- No sparse files: writing after seeking past EOF returns a seek error.
  Zero-byte `AH=40h` file truncation is not implemented.
- Access modes and error codes are incomplete; no full DOS attributes,
  permission/share semantics, or file handle inheritance. A file cannot be
  deleted/truncated while it is open by another handle.
- The built-in shell still has no batch processing, paths, command-line
  arguments, pipes, redirection, environment blocks, or standalone COMMAND.COM.
- Small one-segment MZ loader only; no TSRs, DOS device drivers, DPMI,
  protected-mode DOS extenders, full EXE relocation/loading or DOS API coverage.
- Bootstraps from a private 64-sector kernel reservation on the FAT12 disk,
  not a standard MS-DOS boot/system-file layout.
- `AH=30h` reports an MS-DOS 6.22 *compatibility target*, not full conformance.
- Remains entirely 16-bit 8086 assembly, **no Pascal or protected-mode code**.

## Files

- `boot/`: 8086 boot sector
- `kernel/kernel.s`: DOS kernel and FAT12 driver
- `programs/`: native DOS compatibility tests
- `tools/mkfloppy.py`: reproducible FAT12 floppy image generator
- `tests/test_image.py`: offline disk structural tests
- `docs/ROADMAP.md`: next milestones

## License

Original VelvetDOS source code is GNU General Public License version 3 only
(`COPYING`, `SPDX-License-Identifier: GPL-3.0-only`). No Microsoft or FreeDOS
code is included; interoperability follows the published DOS/BIOS interfaces.
