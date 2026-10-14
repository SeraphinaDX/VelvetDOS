# VelvetDOS changelog

## 0.5.0 (development preview; pending 86Box validation)

- Add DOS DTA pointer management: `INT 21h AH=1Ah/2Fh`.
- Add DOS FAT12 Find First / Find Next (`AH=4Eh/4Fh`) with 8.3 wildcards,
  searchable path components, DOS DTA record fields, filtering for hidden,
  system and directory attributes, and independent per-DTA search indices.
- Add ordinary FAT file attributes get/set (`AH=43h`) and persisted FAT
  last-write date/time get/set for writable handles (`AH=57h`).
- Add FAT12 free-space report for drive A: (`AH=36h`).
- Add native DOS `.COM` regression `FINDTEST` and a user-facing directory
  listing utility `VLIST` built using the public DOS API.
- Preserve the 0.4.0 directory path backslash regression and existing file
  I/O tests; add binary/image integrity tests for the new programs.
- Still 8086-compatible assembly, not Pascal, C, or DPMI.
- Subdirectory expansion deferred until FAT chain traversal/metadata update
  hardening; current 16-slot subdirectories remain unchanged.

## Earlier versions

See Git history for 0.4.0 path handling and directories, 0.3.0 FAT12 writes,
0.2.0 DOS handles and MZ loading, and 0.1.0 bootable DOS foundation.
