/* Sample native DOS .COM program using INT 21h AH=09 and AH=4Ch.
 * SPDX-License-Identifier: GPL-3.0-only */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    mov dx, offset msg
    mov ah, 0x09
    int 0x21
    mov ax, 0x4c00
    int 0x21
msg: .ascii "Hello from a native 16-bit DOS .COM program!\r\n$"
