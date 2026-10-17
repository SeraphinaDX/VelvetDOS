# VelvetDOS changelog

## 0.12.0 batch-handle inheritance hotfix (awaiting 86Box)

- Respect DOS open-mode bit 7 in `INT 21h AH=3Dh`: mark files non-inheritable.
- Have `COMMAND.COM` open `.BAT` files with `AX=3D80h`, keeping internal batch
  file handles out of child PSP tables.
- Preserve default inherited file-handle behavior for `HNDTEST`.
- Add offline checks that `DEMO.BAT` runs the original, unchanged `PSPTEST`
  and that the compiled `COMMAND.COM` requests no inheritance.


## 0.12.0 environment-trailer hotfix (unverified in 86Box)

- Preserve DOS environment trailing program-name metadata across `SET`/`PATH`.
- Reject environment updates that would truncate the trailer.
- Run `PSPTEST hello MiXeD 123` from `DEMO.BAT` after changing variables.
- Add an offline structural regression to guard the trailer copy path.

## 0.12.0 — Batch and environment handling (2026-10-15, development preview)

- Standalone COMMAND.COM can run simple `.BAT` scripts via DOS open/read/close.
  Bare command resolution is `.COM`, `.EXE`, then `.BAT`.
- Implement `SET NAME=VALUE`, `SET NAME=`, `SET` listing, and `PATH` query/edit.
  Environment edits use a bounded scratch copy and reject overflow.
- Basic `ECHO`, `REM`, and leading `@` handling for batch files.
- Add `DEMO.BAT` and 8086 `ENVCHK.COM` child environment regression.
- Retain 0.11.0 owned DOS MCBs and the 0.11.0 allocator stack hotfix.
- All 37 offline image and contract tests pass. New behavior awaits 86Box.

## 0.11.0 — Process memory ownership (86Box verified by project owner)

- Preserve parent-owned MCB allocations across EXEC and child process exit.
- First-fit allocation of a bounded 68-KiB child block, dynamic child PSP.
- Automatic cleanup of child-owned memory and coalescing of free blocks.
- Parent/child memory ownership regression `MEMOWN` and `MEMCHILD.COM`.
- Hotfix: remove excess `PUSH ES` in successful child MCB split path to
  avoid corrupting the return address; 86Box-tested.

## 0.10.0 and earlier

See Git tags for earlier 86Box-tested DOS compatibility milestones.
