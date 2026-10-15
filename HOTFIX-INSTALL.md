# VelvetDOS 0.11.0 EXEC stack hotfix

Fixes a mismatched PUSH ES in the MCB split path of `reserve_exec_block`, which
corrupts the return address after the first successful child-program allocation.

**Option A:** From your *unmodified* VelvetDOS 0.11.0 checkout run:

    git apply /path/to/VelvetDOS-0.11.0-EXEC-stack-hotfix.patch
    make clean test

**Option B:** Overlay the `kernel/`, `tests/` and `docs/` folders from this ZIP
onto the source checkout, then `make clean test`.

Test a fresh writable copy of the corrected image in 86Box. First run built-in
`VER`, `HELP`, `DIR`; then `HELLO`, `HELLO` again, `MEMOWN` twice, `EXECHK hello MiXeD`,
`HNDTEST` and `FINDTEST`. This patch has not been run inside 86Box here.

GNU GPLv3-only; code is still 8086-compatible.
