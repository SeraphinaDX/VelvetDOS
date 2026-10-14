# VelvetDOS compatibility roadmap

VelvetDOS targets compatibility with genuine real-mode MS-DOS programs on
8086-class IBM PC compatible machines. GNU GPLv3-only. Pascal, if introduced,
will be reserved for future 386 protected-mode DOS-extended applications.

- **0.1.0** — boot, FAT12, basic `.COM` loading (86Box tested).
- **0.2.0** — small MZ `.EXE`, basic DOS file APIs and memory (86Box tested).
- **0.3.0** — writable FAT12 root directory (merged and tagged).
- **0.4.0 preview** — FAT12 8.3 directories, paths, `CD`/`MD`/`RD`, directory
  API regression program; **needs 86Box validation**.
- **0.5.0 candidate** — directory chain growth, FAT timestamp support, DOS
  find-first/find-next (`AH=4Eh/4Fh`), attributes and robust error reporting.
- **Longer term** — environment/argument passing, batch files, shell, device
  drivers, broader MZ loading, TSR support, EMS/XMS, then optional 386 DPMI.

The goal is compatibility, not merely a DOS-looking prompt. No release claims
100% compatibility until real applications and hardware have been tested.
