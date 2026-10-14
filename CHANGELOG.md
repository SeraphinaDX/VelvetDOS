# Changelog

## 0.3.0 (development preview; awaiting 86Box validation)

- Introduce FAT12 root-directory file creation/truncation (`INT 21h AH=3Ch`),
  deletion (`41h`), and writable file handles (`3Dh`/`40h`).
- Add FAT12 allocator/free-chain routines, mirroring FAT changes to both FATs.
- Buffer data sectors, write them using BIOS `INT 13h AH=03h`, and update
  directory entry size and starting cluster on close and normal program exit.
- Add WRITE/APPEND/RECHECK/DELETE 8086 `.COM` compatibility test programs.
- Preserve prior 0.1.x/0.2.x COM, MZ/EXE, memory, and read tests.
- Structural image tests; 86Box testing is still required before release.

## 0.2.0 (validated in 86Box by project owner)

- Bounded MZ/EXE loading and relocations.
- DOS file open/read/seek/close APIs on read-only FAT12 root.
- Preliminary DOS MCB allocation/free/resize APIs.
- EXEDEMO, READ and MEMORY regression fixtures.

## 0.1.0

- Bootable 8086 FAT12 floppy and prototype DOS-compatible kernel.
- Built-in command loop, COM loader, basic DOS interrupts.
