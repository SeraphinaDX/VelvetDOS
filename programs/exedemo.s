/* Tiny relocatable DOS MZ program assembled as a raw image.
 * tools/mkmz.py adds the MZ header with a relocation for the first word.
 * SPDX-License-Identifier: GPL-3.0-only
 */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
_start:
    .word 0                    /* relocated to EXE load segment */
main:
    mov ax, word ptr cs:[0]
    mov ds, ax
    mov dx, offset message
    mov ah, 0x09
    int 0x21
    mov ax, 0x4c00
    int 0x21
message: .ascii "MZ EXE relocation worked in VelvetDOS!\r\n$"
