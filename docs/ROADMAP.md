# VelvetDOS roadmap

The 8086 real-mode kernel is the priority; no 386 extender or Pascal build
is required for early releases. All releases remain experimental until proven
in actual PC emulation. GNU GPLv3-only.

- [x] 0.1.0 — bootable FAT12 floppy and COM execution
- [x] 0.2.0 — basic DOS file handles, small MZ binaries, memory allocation
- [x] 0.3.0 — writable FAT12 root files
- [x] 0.4.0 — single-cluster directories and DOS path navigation
- [ ] 0.5.0 — DOS Find First/Next, attributes, timestamps, DTA and free space
      (implemented, awaiting 86Box runtime acceptance)
- [ ] 0.6.0 — multi-cluster directory growth, safer FAT chain and metadata
      updates, root and subdirectory stress tests
- [ ] 0.7.0 — PSP/environment/command arguments, DOS error and attribute
      compatibility, executable command interpreter
- [ ] Later — broader DOS games/app compatibility, proper 386 DPMI/GO32v2,
      optional 32-bit Free Pascal user programs, self-hosting investigation

Never test writable FAT changes on valuable media. Every filesystem bug
requires a regression before merging.
