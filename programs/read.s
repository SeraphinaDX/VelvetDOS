/* DOS INT 21h open/read/seek/close regression executable.
 * SPDX-License-Identifier: GPL-3.0-only
 */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    mov dx, offset filename
    mov ax, 0x3d00
    int 0x21
    jc failure
    mov bx, ax               /* handle */
    mov dx, offset buffer
    mov cx, 600              /* cross a FAT12 sector boundary */
    mov ah, 0x3f
    int 0x21
    jc failure
    cmp ax, 600
    jne failure
    /* Seek back to the beginning and reread the first 4 letters. */
    xor cx, cx
    xor dx, dx
    mov ax, 0x4200
    int 0x21
    jc failure
    or dx, ax
    jnz failure
    mov dx, offset buffer
    mov cx, 4
    mov ah, 0x3f
    int 0x21
    jc failure
    cmp ax, 4
    jne failure
    cmp word ptr [buffer], 0x4556   /* "VE" little endian */
    jne failure
    cmp word ptr [buffer + 2], 0x564c /* "LV" little endian */
    jne failure
    mov ah, 0x3e
    int 0x21
    jc failure
    mov dx, offset success_message
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21
failure:
    mov dx, offset failure_message
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21
filename: .asciz "README.TXT"
success_message: .ascii "READ.COM: open/read/seek/close PASS!\r\n$"
failure_message: .ascii "READ.COM: FILE API FAIL!\r\n$"
buffer: .space 600
