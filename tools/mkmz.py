#!/usr/bin/env python3
"""Wrap a raw 16-bit code image in a minimal relocatable DOS MZ header.

Our example has one relocatable word at image offset 0. Entry is image offset 2.
This is a development/test helper, NOT a general-purpose DOS EXE linker.
SPDX-License-Identifier: GPL-3.0-only
"""
import argparse
from pathlib import Path
import struct


def wrap(raw: bytes) -> bytes:
    if len(raw) > 65024 - 32:
        raise ValueError("MZ demo too large for current one-segment loader")
    length = 32 + len(raw)
    hdr = bytearray(32)
    struct.pack_into('<14H', hdr, 0,
        0x5A4D, length % 512, (length + 511) // 512,
        1, 2, 0, 0xffff, 0, 0xfffe, 0, 2, 0, 0x1c, 0)
    struct.pack_into('<2H', hdr, 28, 0, 0)  # word at image offset 0000:0000
    return bytes(hdr) + raw

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('input', type=Path)
    ap.add_argument('output', type=Path)
    ns = ap.parse_args()
    ns.output.write_bytes(wrap(ns.input.read_bytes()))
