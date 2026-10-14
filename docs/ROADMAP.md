# VelvetDOS development roadmap

VelvetDOS targets 8086-class PCs and MS-DOS compatible 16-bit real-mode
software. Early releases use assembly and host-side tooling; 386 DPMI and
optional 32-bit Free Pascal programs are future work. All code: GPLv3-only.

- [x] 0.1.0 — FAT12 floppy boot and COM execution (86Box verified)
- [x] 0.2.0 — DOS handles, small MZ binaries, memory allocation (86Box verified)
- [x] 0.3.0 — Writable FAT12 files (86Box verified)
- [x] 0.4.0 — Directory navigation and 8.3 DOS path resolution (86Box verified)
- [x] 0.5.0 — Find First/Next, attributes, timestamps, DTA, free space (86Box verified)
- [x] 0.6.0 — Bounded FAT12 directory growth (86Box verified)
- [x] 0.7.0 — PSP argument tail, environment, current PSP query, exit code
      (86Box verified)
- [x] 0.8.0 — Standalone COMMAND.COM, single-child COM EXEC and PSP parent
      (86Box verified)
- [ ] 0.9.0 — Bounded MZ child EXEC, .COM-to-.EXE shell fallback,
      malformed MZ rejection (built + offline tests; awaiting 86Box)
- [ ] 0.10.0+ — More complete executable memory ownership, environment,
      handle inheritance, batch files, third-party DOS application trials
- [ ] Later — FAT error recovery, traditional device drivers, FAT16, 386
      protected mode, DPMI/GO32v2, optional 32-bit Free Pascal and self-hosting

Use disposable images. Preserve a regression for every fixed disk or DOS API
bug, and never claim DOS compatibility based solely on static tests.

## 0.10.0 — Handle ownership (preview)

- Per-process file-handle tables and reference counting across one resident
  shell and one DOS EXEC child.
- Bounded copied child environment, preserving parent's environment.
- `HNDTEST` and `HNDCHILD.COM` parent/child I/O regression.
- **After emulator validation:** consider more complete conventional-memory
  allocation ownership and resize handling, preserving parent MCBs across
  EXEC. Do not introduce Pascal until a 386-class DOS extender works.
