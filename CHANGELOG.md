# VelvetDOS changelog

## 0.10.0 — DOS handle inheritance and bounded process environment (2026-10-14)

- Add four per-process PSP JFT file-handle slots and reference-counted kernel
  file records. Preserve shell handles when a child exits or closes one.
- Stage an independent 256-byte environment for a DOS EXEC child and point
  the child's PSP:002Ch to the copy. Support a nonzero environment pointer in
  the EXEC parameter block within this bounded prototype.
- Add `HNDCHILD.COM` and `COMMAND.COM`'s `HNDTEST` built-in to exercise an
  inherited read/close and verify the parent can continue reading.
- Expand the offline test suite from 28 to 29 host-side tests.
- Retain 8086 compatibility and defer full dynamic MCB ownership and DOS
  handle duplication to later milestones.

**Validation:** Offline assembly, FAT12 image creation, and structural tests
passed. Runtime behavior in 86Box is not yet verified.


## 0.9.0 — Bounded MZ child EXEC (2026-10-14)

- Extend resident COMMAND.COM EXEC beyond `.COM` to limited relocatable DOS
  `.EXE` programs, with MZ header/relocation/stack validation and DOS error 11
  on malformed executables. Keep one child at a time and 8086 compatibility.
- Add default `.COM` then `.EXE` fallback for extensionless program commands.
- Add `EXECHK.EXE` checking MZ relocation, PSP, argument tail and returned exit
  code, plus intentionally malformed `BADMZ.EXE` to test clean rejection.
- Include 28 host-side tests and retain old regression programs.
- Continue deferring Pascal and 386 protected-mode execution.

**Validation:** GNU assembly, 1.44 MB floppy creation and host-side tests pass.
**86Box execution of 0.9.0 has not yet been checked.**


## 0.8.0 — Standalone shell and first DOS EXEC (2026-10-14)

- Boot a genuine separately built `COMMAND.COM` as the resident shell, with
  the existing kernel command prompt retained as a recovery environment.
- Implement a limited `INT 21h AH=4B00` that loads and executes one child
  `.COM` process while keeping the shell intact; restore the parent interrupt
  frame, DTA, and PSP/memory allocation after child termination.
- Populate the child's PSP parent field, expose a per-process PSP through
  `AH=51h/62h`, and retain process return codes through `AH=4Dh`.
- Add common DOS shell commands through public `INT 21h` interfaces, rather
  than directly using private filesystem routines.
- Add `EXECCHK.COM` to check that nested EXEC fails safely. Adapt `PSPTEST`
  to validate its parent PSP in the new process structure.
- Expand offline regression coverage from 23 to 25 tests, retaining all
  previous boot image, FAT12, directory, file and command-tail fixtures.
- Remain completely 8086/real-mode; MZ child EXEC, resident TSR semantics,
  batch processing and arbitrary executable memory allocation remain future
  work. No Pascal code has been added.

**Validation:** host assembly/image build and 25 structural tests pass;
**86Box execution of 0.8.0 has passed (reported by the project owner)**.

## 0.7.0 — Program compatibility (2026-10-14)

- 0.7.0 adds PSP command tails, environment and initial exit codes.
- User reported the 0.7.0 86Box tests passing and merged/tagged the release.

## Earlier releases

See repository version tags for the 0.1.0–0.6.0 changelogs.
