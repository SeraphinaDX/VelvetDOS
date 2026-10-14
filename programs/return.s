/* Demonstrates legacy COM near-RET termination via PSP:0000 and INT 20h.
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
    ret
msg: .ascii "RET worked (via the PSP INT 20h stub).\r\n$"
