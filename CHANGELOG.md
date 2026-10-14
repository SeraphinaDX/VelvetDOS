# VelvetDOS changelog

## 0.7.0 — Program compatibility preview (2026-10-14)

- Accept command-line arguments for built-in shell execution of DOS `.COM`
  and restricted `.EXE` programs; uppercase only the executable token.
- Fill the 128-byte PSP command-tail area with length, verbatim arguments and
  DOS carriage-return terminator.
- Populate PSP environment segment pointer, standard handle placeholders,
  blank FCB name slots, and copied INT 22h/23h/24h vectors.
- Provide a fixed read-only DOS environment at segment 2A00h, outside the
  application memory allocation range.
- Add `INT 21h AH=51h/62h` current-PSP queries and preliminary return code
  tracking via AH=4Ch/4Dh; add `STATUS` shell debug command.
- Add `PSPTEST.COM` and `EXITTEST.COM` regression fixtures. Preserve earlier
  boot, FAT12, executable, directory and find-first test programs.
- Expand offline tests to 23. Tests are **not** proof of 86Box runtime
  behavior; complete the documented acceptance test before tagging.

## Earlier releases

See the repository's tagged changelogs for 0.1.0–0.6.0 history.
