# VelvetDOS development roadmap

VelvetDOS is a clean GPLv3-only 8086-compatible DOS implementation.
386 DOS extenders and optional Free Pascal tools are deferred.

- [x] 0.1.0–0.7.0: FAT12, file APIs, COM/MZ, directory APIs, PSP and environment.
- [x] 0.8.0: Standalone COMMAND.COM and basic child EXEC.
- [x] 0.9.0: Bounded MZ child EXEC.
- [x] 0.10.0: Handle inheritance and independent child environment.
- [x] 0.11.0: Owner-based DOS memory management and stack hotfix (86Box tested).
- [ ] 0.12.0: Small batch interpreter, SET/PATH, environment editing (86Box pending).
- [ ] 0.13.0: Program lookup using PATH, DOS command processing refinements,
  better batch constructs and third-party compiled DOS software trials.
- [ ] Later: environment allocation/metadata, more DOS services, robust
  multi-level EXEC, FAT16, traditional device drivers, DPMI/GO32v2 and optional
  32-bit Free Pascal development, ultimately DOS-hosted tools.

Prefer regression fixtures for every real DOS API bug. Offline image integrity
checks do not replace CPU/emulator execution tests. Use disposable floppies.
