# VelvetDOS compatibility roadmap

## 0.1.0 — bootable foundation (86Box-validated)

Native FAT12 floppy boot, console, COM loader and basic INT 21h subset.

## 0.2.0 — initial DOS runtime (86Box-validated)

Small MZ executables with relocations, root file read/open/seek/close,
preliminary conventional-memory MCB allocation.

## 0.3.0 — writable FAT12 files (development preview)

Support file creation, sequential and random overwrite, append, delete,
FAT cluster allocation/release, and matching DOS file APIs. Provide a
703-byte persistent cross-cluster regression through 86Box.

**Outstanding:** 86Box regression, error-handling hardening, power-loss
resilience and full DOS compatibility.

## 0.4.0 — DOS directories and everyday utility compatibility

Subdirectories/CD/MD/RD, DOS find-first/find-next, directory enumeration,
DTA, timestamps, more complete file attributes, 8.3 paths, command-line
tails, PSP and environment block support; begin independently compiled apps.

## 0.5.0 — command interpreter and system integration

Standalone COMMAND.COM, batch files, PATH, redirection, pipes, file sharing,
optional CONFIG.SYS-style drivers and DOS system-call improvements.

## Later — real-mode compatibility, protected-mode extensions

DOS device chains, TSRs, EMS/XMS/UMB, then 386 DPMI/DOS extender support.
Only consider Free Pascal tools for 386 extended-mode programs after DPMI is
verified. Track known games and applications in a reproducible 86Box/QEMU test
matrix. Self-hosting is a long-term goal, not a 0.x promise.
