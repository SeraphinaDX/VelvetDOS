/* VelvetDOS 0.8.0 nested EXEC rejection/PSP regression.
 * SPDX-License-Identifier: GPL-3.0-only
 * The initial COMMAND.COM may launch one child; nested EXEC must fail
 * harmlessly rather than overwriting the resident parent's memory. */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    push cs
    pop ds
    mov ax, cs
    mov es, ax
    mov word ptr [params+4], ax
    mov dx, offset nested_name
    mov bx, offset params
    mov ax, 0x4b00
    int 0x21
    jnc failure
    cmp ax, 8
    jne failure
    mov ah, 0x62
    int 0x21
    mov ax, cs
    cmp bx, ax
    jne failure
    cmp word ptr [0x16], 0x3000
    jne failure
    mov dx, offset success_text
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21
failure:
    mov dx, offset fail_text
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21
params:
    .word 0
    .word empty_tail
    .word 0
    .word 0,0,0,0
empty_tail: .byte 0,13
nested_name: .asciz "HELLO.COM"
success_text: .ascii "EXECCHK.COM: nested EXEC rejected, child PSP PASS!\r\n$"
fail_text: .ascii "EXECCHK.COM: nested EXEC/PSP FAIL!\r\n$"
