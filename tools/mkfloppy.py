#!/usr/bin/env python3
"""Build the VelvetDOS 0.7.0 FAT12 floppy from boot/kernel binaries.

License: GPL-3.0-only. No external Python packages required.
The kernel lives in reserved sectors 1..64. This is a private bootstrap
layout, not an MS-DOS system-file layout. FAT12 itself is standards-based.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import struct

BYTES_PER_SECTOR = 512
SECTORS = 2880
RESERVED = 65
FATS = 2
FAT_SECTORS = 9
ROOT_ENTRIES = 224
ROOT_SECTORS = 14
DATA_START = RESERVED + FATS * FAT_SECTORS + ROOT_SECTORS
CLUSTERS = SECTORS - DATA_START
KERNEL_CAPACITY = (RESERVED - 1) * BYTES_PER_SECTOR


def set_fat12(fat: bytearray, cluster: int, value: int) -> None:
    if not 0 <= value <= 0xFFF:
        raise ValueError("FAT12 cluster must be 12 bits")
    off = cluster + cluster // 2
    if cluster & 1:
        fat[off] = (fat[off] & 0x0F) | ((value & 0xF) << 4)
        fat[off + 1] = (value >> 4) & 0xFF
    else:
        fat[off] = value & 0xFF
        fat[off + 1] = (fat[off + 1] & 0xF0) | ((value >> 8) & 0xF)


def dos_name(name: str) -> bytes:
    parts = name.upper().split(".")
    if len(parts) != 2 or not 1 <= len(parts[0]) <= 8 or not 1 <= len(parts[1]) <= 3:
        raise ValueError(f"not an 8.3 DOS filename: {name}")
    if any(c not in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$~!#%&-{}()@^`'" for p in parts for c in p):
        raise ValueError(f"unsupported DOS filename character: {name}")
    return (parts[0].ljust(8) + parts[1].ljust(3)).encode("ascii")


def create_image(boot: bytes, kernel: bytes, files: list[tuple[str, bytes]]) -> bytes:
    if len(boot) != 512 or boot[510:] != b"\x55\xaa":
        raise ValueError("boot sector must be 512 bytes and end with 55 AA")
    if len(kernel) > KERNEL_CAPACITY:
        raise ValueError(f"kernel too large: {len(kernel)} > {KERNEL_CAPACITY} bytes")
    if struct.unpack_from("<H", boot, 14)[0] != RESERVED:
        raise ValueError("boot sector BPB reserved sector count mismatch")
    if len(files) > ROOT_ENTRIES:
        raise ValueError("too many root entries")
    result = bytearray(SECTORS * BYTES_PER_SECTOR)
    result[:512] = boot
    result[512:512 + len(kernel)] = kernel
    fat = bytearray(FAT_SECTORS * BYTES_PER_SECTOR)
    fat[:3] = b"\xf0\xff\xff"
    root = bytearray(ROOT_SECTORS * BYTES_PER_SECTOR)
    next_cluster = 2
    seen = set()
    for idx, (name, contents) in enumerate(files):
        short = dos_name(name)
        if short in seen:
            raise ValueError(f"duplicate filename: {name}")
        seen.add(short)
        count = (len(contents) + BYTES_PER_SECTOR - 1) // BYTES_PER_SECTOR
        if next_cluster + count > CLUSTERS + 2:
            raise ValueError("out of FAT12 data clusters")
        first = next_cluster if count else 0
        for i in range(count):
            cluster = next_cluster + i
            set_fat12(fat, cluster, cluster + 1 if i + 1 < count else 0xFFF)
            disk_pos = (DATA_START + cluster - 2) * BYTES_PER_SECTOR
            block = contents[i * BYTES_PER_SECTOR:(i + 1) * BYTES_PER_SECTOR]
            result[disk_pos:disk_pos + len(block)] = block
        next_cluster += count
        pos = idx * 32
        root[pos:pos + 11] = short
        root[pos + 11] = 0x20  # archive attribute
        struct.pack_into("<H", root, pos + 26, first)
        struct.pack_into("<I", root, pos + 28, len(contents))
    for fat_idx in range(FATS):
        start = (RESERVED + fat_idx * FAT_SECTORS) * BYTES_PER_SECTOR
        result[start:start + len(fat)] = fat
    start = (RESERVED + FATS * FAT_SECTORS) * BYTES_PER_SECTOR
    result[start:start + len(root)] = root
    return bytes(result)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--boot", type=Path, required=True)
    p.add_argument("--kernel", type=Path, required=True)
    p.add_argument("--file", type=Path, action="append", default=[])
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    files = [(f.name, f.read_bytes()) for f in a.file]
    image = create_image(a.boot.read_bytes(), a.kernel.read_bytes(), files)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_bytes(image)
    print(f"VelvetDOS FAT12 floppy: {a.output} ({len(image)} bytes)")
    print(f"  kernel: {a.kernel.stat().st_size}/{KERNEL_CAPACITY} bytes (reserved sectors)")
    for name, contents in files:
        print(f"  {name}: {len(contents)} bytes")


if __name__ == "__main__":
    main()
