/* Basic DOS MCB resize, allocation and release test.
 * SPDX-License-Identifier: GPL-3.0-only
 * Requires a conventional-memory block owned by this process.
 */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    push ds
    pop es                 /* ES = PSP/initial process block */
    mov bx, 0x2000         /* release most initial conventional memory */
    mov ah, 0x4a
    int 0x21
    jc failed
    mov bx, 0x0010         /* request 256 bytes + one MCB */
    mov ah, 0x48
    int 0x21
    jc failed
    mov es, ax             /* AX = allocated segment */
    mov ah, 0x49
    int 0x21
    jc failed
    mov dx, offset ok_message
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21
failed:
    mov dx, offset bad_message
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21
ok_message:  .ascii "MEMORY.COM: MCB resize/alloc/free PASS!\r\n$"
bad_message: .ascii "MEMORY.COM: MCB memory operation FAIL!\r\n$"
