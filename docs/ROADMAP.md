# VelvetDOS roadmap

8086 real-mode compatibility remains the priority. No Free Pascal or DPMI
required for early releases. Experimental until verified under 86Box.
License: GNU GPLv3-only.

- [x] 0.1.0 — FAT12 floppy boot and COM execution
- [x] 0.2.0 — DOS handles, small MZ binaries, memory allocation
- [x] 0.3.0 — writable FAT12 files
- [x] 0.4.0 — directories and 8.3 DOS path resolution
- [x] 0.5.0 — Find First/Next, attributes, timestamps, DTA and free space
- [ ] 0.6.0 — bounded multi-cluster directory growth, DOS regression (built,
      awaiting 86Box test and tag)
- [ ] 0.7.0 — PSP/environment and arguments, executable command interpreter,
      broader DOS errors/attributes, and genuine third-party DOS binaries
- [ ] Later — FAT chain error recovery, extended memory, 386 DPMI/GO32v2,
      optional 32-bit Free Pascal applications and self-hosted builds

Use disposable disk images. Every filesystem bug gets a regression.
