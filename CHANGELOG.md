# VelvetDOS changelog

## 0.6.0 (development preview; awaiting 86Box acceptance)

- Make FAT12 subdirectories grow from one to eight clusters, up to 128 entries
  per directory including `.` and `..`. FAT12 root remains fixed at 224 slots.
- Load the entire bounded directory FAT chain into a 4 KiB cache; reject chains
  exceeding eight clusters rather than silently ignoring later entries.
- Allocate, zero, and persist additional directory sectors on demand, linking
  them through the normal FAT12 allocator.
- Flush all sectors of a modified subdirectory and preserve logical directory
  entry offsets in DOS file handles and directory searches.
- Scan all directory clusters before `RD`; free a multi-cluster directory's
  FAT chain only when all its directory entries are empty/deleted.
- Include `DIRGROW.COM`: DOS API-only test for 20 file creations, enumerating
  more than 16 directory slots, reopening the 20th file, deletion, and cleanup.
- Retain 0.5.0 DTA/Find First/Find Next and all earlier runtime tests.
- Add three structural integrity regressions; 21 offline tests pass.
- **Warning:** no crash-consistency/journaling; write operations must use only
  disposable floppy images. 86Box test of this version still outstanding.

## 0.5.0 (86Box validated by project owner)

- DOS DTA pointer management (`INT 21h AH=1Ah/2Fh`), Find First/Next
  (`AH=4Eh/4Fh`), 8.3 wildcards, file attributes (`AH=43h`), FAT timestamps
  (`AH=57h`), and free-space reporting (`AH=36h`).
- Native DOS `FINDTEST.COM` and `VLIST.COM` utilities.

## Earlier versions

See Git history for 0.4.0 path support and directory creation, 0.3.0 file
writes, 0.2.0 DOS handles/MZ loading, and 0.1.0 bootable floppy foundation.
