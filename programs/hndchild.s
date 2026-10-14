/* VelvetDOS 0.10.0 inherited JFT / independent environment test.
 * SPDX-License-Identifier: GPL-3.0-only
 * COMMAND.COM opens README.TXT as handle 5, then EXECs this child.
 * The child reads 'V', closes its inherited handle, and tests that
 * its own PSP no longer grants access to that handle. */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    push cs
    pop ds
    cmp byte ptr [0x1d], 5
    jne failure
    cmp word ptr [0x16], 0x3000
    jne failure
    mov ax, word ptr [0x2c]
    cmp ax, 0x2b00
    jne failure
    mov es, ax
    cmp word ptr es:[0], 0x4150 /* 'PA' */
    jne failure
    cmp byte ptr es:[2], 'T'
    jne failure
    cmp byte ptr es:[3], 'H'
    jne failure
    /* Mutate ONLY the child's independent environment copy. */
    mov byte ptr es:[0], 'X'
    mov bx, 5
    mov dx, offset read_byte
    mov cx, 1
    mov ah, 0x3f
    int 0x21
    jc failure
    cmp ax, 1
    jne failure
    cmp byte ptr [read_byte], 'V'
    jne failure
    mov bx, 5
    mov ah, 0x3e
    int 0x21
    jc failure
    cmp byte ptr [0x1d], 0xff
    jne failure
    mov bx, 5
    mov dx, offset read_byte
    mov cx, 1
    mov ah, 0x3f
    int 0x21
    jnc failure
    cmp ax, 6
    jne failure
    mov dx, offset success
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21
failure:
    mov dx, offset failed
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21
read_byte: .byte 0
success: .ascii "HNDCHILD: inherited read, close, and environment PASS!\r\n$"
failed: .ascii "HNDCHILD: inherited handle/environment FAIL!\r\n$"
