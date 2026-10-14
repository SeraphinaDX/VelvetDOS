# VelvetDOS changelog

## 0.4.0 test hotfix — path separators

- Correct four GNU assembler backslash checks (`0x5C` instead of a malformed
  character literal that encoded as `0x27`). This prevented nested paths and
  permitted a literal backslash to be written into 8.3 FAT directory entries.
- Retain `PATHS.COM` stage diagnostics from the separate diagnostic build.
- Add regression test checking assembled path-parser opcodes.
- 86Box runtime confirmation still pending.

## 0.4.0 (development preview — awaiting 86Box runtime validation)

- Implement `INT 21h` directory APIs 39h/3Ah/3Bh/47h.
- Parse DOS A: paths (absolute/relative, `.`, `..`, multi-component 8.3 names).
- Introduce first-class single-cluster FAT12 subdirectories, parent pointers
  and a per-handle containing-directory reference.
- Make create/open/delete/update file operations work in subdirectories.
- Add shell `CD`, `MD`, `RD`, directory-aware `DIR`, and CWD prompt.
- Reject non-empty directory removal, active/ancestor CWD deletion, and
  removal of pre-existing multi-cluster directories.
- Add `PATHS.COM` on-device compatibility regression test.
- Maintain 8086 instruction compatibility and GPLv3-only licensing.
- 15 offline tests pass; interactive runtime behavior not yet verified.

## 0.3.0 (merged and tagged; 86Box results not separately reported)

- FAT12 root file create/truncate (`AH=3Ch`), write (`40h`), and delete (`41h`).
- Add FAT12 cluster allocation, free chains, and metadata persistence.
- Add `WRITE.COM`, `APPEND.COM`, `RECHECK.COM`, and `DELETE.COM`.

## 0.2.0 (merged, tagged, tested in 86Box)

- Basic MZ `.EXE` relocations, DOS file read/seek handles and preliminary
  conventional-memory allocation.

## 0.1.0 (tested in 86Box)

- Boot sector, real-mode kernel, shell, FAT12 root reader and `.COM` loader.
