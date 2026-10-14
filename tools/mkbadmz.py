#!/usr/bin/env python3
"""Create a deliberately malformed MZ fixture for safe EXEC rejection.

The invalid relocation count extends well beyond the header and must be
rejected with DOS error 11 *before* any child process is activated.
SPDX-License-Identifier: GPL-3.0-only
"""
import sys
import struct
from pathlib import Path


def main(source: str, target: str) -> None:
    data = bytearray(Path(source).read_bytes())
    if data[:2] != b'MZ' or len(data) < 32:
        raise ValueError('input must be a minimal MZ executable')
    struct.pack_into('<H', data, 6, 513)
    Path(target).write_bytes(data)


if __name__ == '__main__':
    main(*sys.argv[1:])
