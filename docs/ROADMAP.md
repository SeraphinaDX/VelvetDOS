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
- [ ] 0.7.0 — PSP argument tail, environment, current PSP query, exit code
      (built + offline tests passed; awaiting 86Box verification)
- [ ] 0.8.0+ — Introduce standalone command interpreter, broaden DOS APIs,
      process environment management, AH=4Bh EXEC, documented MZ loading
      and independent third-party DOS application tests
- [ ] Later — FAT error recovery, traditional device drivers, FAT16, 386
      protected mode, DPMI/GO32v2, optional 32-bit Free Pascal and self-hosting

Use disposable images. Preserve a regression for every fixed disk or DOS API
bug, and never claim DOS compatibility based solely on static tests.
