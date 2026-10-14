/* VelvetDOS 0.3.0 -- FAT12 root create/write/close/reopen/read test.
 * GNU GPLv3; runs as a real 8086 DOS .COM program. */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    mov dx, offset fname
    xor cx, cx
    mov ah, 0x3c
    int 0x21
    jc failure
    mov bx, ax
    mov dx, offset pattern
    mov cx, 700
    mov ah, 0x40
    int 0x21
    jc failure
    cmp ax, 700
    jne failure
    mov ah, 0x3e
    int 0x21
    jc failure
    mov dx, offset fname
    mov ax, 0x3d00
    int 0x21
    jc failure
    mov bx, ax
    mov dx, offset buffer
    mov cx, 700
    mov ah, 0x3f
    int 0x21
    jc failure
    cmp ax, 700
    jne failure
    push ds
    pop es
    mov si, offset pattern
    mov di, offset buffer
    mov cx, 700
    repe cmpsb
    jne failure
    mov dx, offset buffer
    mov cx, 1
    mov ah, 0x3f
    int 0x21
    jc failure
    test ax, ax
    jnz failure
    mov ah, 0x3e
    int 0x21
    jc failure
    mov dx, offset ok
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21
failure:
    mov dx, offset bad
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21
fname:   .asciz "DATA.BIN"
ok:      .ascii "WRITE.COM: 700 bytes, cross-cluster verify PASS!\r\n$"
bad:     .ascii "WRITE.COM: FAT12 write/read FAIL!\r\n$"
pattern: .fill 512,1,65
         .fill 188,1,66
buffer:  .space 700
