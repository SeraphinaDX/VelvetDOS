/* VelvetDOS 0.11.0: child allocation/ownership regression.
 * Parent shell owns block 5000h; child must be loaded above it. If the
 * child can free/resize the parent's block or allocations leak on exit,
 * MEMOWN in COMMAND.COM reports a failure.
 * SPDX-License-Identifier: GPL-3.0-only
 */
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
    cmp ax, 0x5000
    jbe failed
    mov ax, 0x5000
    mov es, ax
    mov ah, 0x49
    int 0x21
    jnc failed
    cmp ax, 9
    jne failed
    mov bx, 0x20
    mov ah, 0x4a
    int 0x21
    jnc failed
    cmp ax, 9
    jne failed
    mov bx, 0x20
    mov ah, 0x48
    int 0x21
    jc failed
    /* Intentionally leak an owned allocation. Process exit must reclaim. */
    mov es, ax
    mov word ptr es:[0], 0x4f4b
    /* Resize our own separate block and leave that allocation too. */
    mov bx, 0x30
    mov ah, 0x4a
    int 0x21
    jc failed
    mov dx, offset success
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21
failed:
    mov dx, offset failure
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21
success: .ascii "MEMCHILD: dynamic child MCB / ownership PASS!\r\n$"
failure: .ascii "MEMCHILD: DOS MCB ownership FAIL!\r\n$"
