/* MZ relocation, PSP inheritance and command tail regression.
 * This is genuine DOS real-mode EXE code assembled under GNU binutils.
 * mkmz.py adds one relocation record for image word zero.
 * SPDX-License-Identifier: GPL-3.0-only
 */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
_start:
    .word 0                   /* relocated by VelvetDOS to MZ load segment */
main:
    /* Initial DS/ES must point at PSP, whereas CS points at image. */
    mov ax, ds
    mov bx, es
    cmp ax, bx
    jne fail
    cmp word ptr ds:[0x16], 0x3000 /* parent COMMAND.COM PSP */
    jne fail
    cmp byte ptr ds:[0x80], 12   /* tail: ' hello MiXeD' */
    jne fail
    cmp byte ptr ds:[0x81], ' '
    jne fail
    cmp byte ptr ds:[0x82], 'h'
    jne fail
    cmp byte ptr ds:[0x88], 'M'
    jne fail
    cmp byte ptr ds:[0x89], 'i'
    jne fail
    cmp byte ptr ds:[0x8a], 'X'
    jne fail
    mov ax, cs
    mov ds, ax
    cmp word ptr [0], ax
    jne fail
    mov dx, offset passed
    mov ah, 9
    int 0x21
    mov ax, 0x4c37             /* success exit code for STATUS */
    int 0x21
fail:
    push cs
    pop ds
    mov dx, offset failed
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21
passed: .ascii "EXECHK.EXE: MZ, relocation, PSP, tail PASS!\r\n$"
failed: .ascii "EXECHK.EXE: MZ EXEC FAIL!\r\n$"
