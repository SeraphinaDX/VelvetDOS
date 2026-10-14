# VelvetDOS 0.10.0 — DOS handle inheritance (development preview)

VelvetDOS is an experimental **GNU GPLv3-only, 8086 real-mode** operating
system. It provides a limited DOS kernel, FAT12 filesystem and standalone
`COMMAND.COM`. This is **not yet a replacement for MS-DOS**. Test on a spare,
writable floppy image in 86Box or QEMU, not physical or valuable storage.

## Changes in 0.10.0

- Add an elementary per-process PSP Job File Table (JFT) for DOS handles 5–8.
- Add reference counts for the existing four shared file records. A child
  inherits the parent's open file handles (and shared file positions). If the
  child closes one, the underlying file remains open for the parent.
- Close just the exiting process's open handle references instead of closing
  every kernel file record when `INT 21h AH=4Ch` returns from a child.
- Copy at most 256 bytes of an inherited or explicitly supplied environment
  segment into a distinct child buffer at `2B00h`; the child's PSP:002Ch
  points to its own copy. Invalid/unterminated environments are rejected with
  DOS error 10. The shell environment remains at `2A00h`.
- Add `HNDCHILD.COM` and the new `HNDTEST` built-in command. The shell opens
  `README.TXT`, runs the child, the child reads and closes its inherited handle,
  and the parent reads the next byte after the child exits.
- Retain the 0.9.0 COM/MZ loader and previous regression programs.

## Build on Linux

Requires GNU Make, GNU binutils (`as`, `ld`) and Python 3. No Pascal compiler
is required. The kernel and programs remain 8086-compatible.

```sh
make clean test
make run     # requires qemu-system-i386; 86Box can load the .img directly
```

The image is `build/velvetdos-0.10.0.img` (1.44 MB FAT12).

## Required 86Box tests

Boot a **fresh, writable copy** of the image. From the standalone prompt:

```text
A:\>VER
A:\>HNDTEST
A:\>HNDTEST
A:\>HELLO
A:\>PSPTEST hello MiXeD 123
A:\>EXECHK hello MiXeD
A:\>STATUS
A:\>EXECCHK
A:\>FINDTEST
A:\>VLIST
```

The new test should print, in this order:

```text
HNDCHILD: inherited read, close, and environment PASS!
HNDTEST: parent handle preserved across child close PASS!
```

Repeat `HNDTEST` to detect leaked handles. After `EXECHK`, `STATUS` should
still show `37` hex. `EXECCHK` should continue to report nested EXEC rejected.
Use a *different* disposable writable image for tests that modify FAT12,
such as `PATHS`, `DIRGROW`, `WRITE`, `APPEND`, `RECHECK`, and `DELETE`.

## Important limitations

- File handles 5–8 only, using the original four global file records. Open
  handles are inherited for the single supported shell -> child transition.
  General DOS `DUP` (`AH=45h`) and `FORCEDUP` (`AH=46h`) are not implemented;
  standard console handles 0–4 are not redirected or duplicated.
- Environment buffers are a bounded, fixed 256-byte proof of concept,
  **not** DOS-allocated, mutable, arbitrarily sized environment blocks.
  Child-specific bytes are staged in a reserved kernel-managed segment.
- The child PSP always uses `5000h`; no nested EXEC, full parent allocator
  preservation, TSR support, multisegment large MZ images, DPMI, or DOS
  extenders. Dynamic process MCB ownership remains a subsequent milestone.
- Limited FAT12 filesystem and DOS API coverage. File writes and directory
  metadata remain nontransactional; interruption may corrupt the filesystem.
  Use disposable emulator images only.
- Compiler remains Linux-hosted. Pascal is deferred pending later 386-class
  DOS-extended execution support.

**Verification:** The GNU assembler, image generator, and host-side structural
regression tests pass. **The new 0.10.0 runtime behavior has not been tested in
86Box here**. This release must remain a preview until its emulator tests pass.

## License

Original VelvetDOS code is **GNU GPLv3 only** (`COPYING`,
`SPDX-License-Identifier: GPL-3.0-only`). No Microsoft or FreeDOS kernel code
is included.
