# VelvetDOS changelog

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
**86Box execution of this release is still unverified**.

## 0.7.0 — Program compatibility (2026-10-14)

- 0.7.0 adds PSP command tails, environment and initial exit codes.
- User reported the 0.7.0 86Box tests passing and merged/tagged the release.

## Earlier releases

See repository version tags for the 0.1.0–0.6.0 changelogs.
