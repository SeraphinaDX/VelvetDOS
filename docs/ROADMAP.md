# VelvetDOS compatibility roadmap

## 0.1.0 — minimal real-mode foundation

Bootable 1.44 MB FAT12 disk, source-built kernel, command loop, read-only root
file access, basic INT 21h and COM launching. Includes test programs.

## 0.2.0 — early DOS runtime (in progress)

Deliver initial read-only file handles (open/read/seek/close), a bounded small
MZ `.EXE` loader, and provisional MCB allocate/free/resize. Improve these into
fully DOS-compatible behaviors incrementally. Still **to do**: general MZ
loaders, PSP/environment/exit semantics, DTA and find-first/find-next,
FAT12/FAT16 directories and writable files, richer DOS error handling.

Do not mark this milestone complete until the new demos pass in 86Box.

## 0.3.0 — everyday DOS shell

Implement DOS-compatible COMMAND.COM execution (internal/external commands,
command tails, batch files, PATH, redirection/pipes, environment variables),
writeable FAT with consistency checks, subdirectories and timestamps.

## 0.4.0 — drivers and resident applications

DOS device chains, request packets, CONFIG.SYS-style installation, TSRs,
interrupt chaining, appropriate critical-error handling, and printer/serial IO.

## 0.5.0 — larger DOS software and games

XMS, EMS, upper-memory support, DPMI cooperation and DOS extenders, plus
hardware/BIOS behavior regression testing under 86Box and QEMU.

## 1.0.0 — measured compatibility target

Publish a reproducible compatibility suite and verified application/game
matrix, with clearly documented unsupported and hardware-dependent cases.

No version implies automatic compatibility with every program: DOS behavior
includes undocumented interfaces and hardware/software interaction quirks.
