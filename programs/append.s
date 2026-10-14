/* VelvetDOS 0.3.0 -- append after reopening file, seek/read/verify. GPLv3. */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    mov dx, offset fname
    mov ax, 0x3d02
    int 0x21
    jc failure
    mov bx, ax
    mov ax, 0x4202
    xor cx, cx
    xor dx, dx
    int 0x21
    jc failure
    cmp ax, 700
    jne failure
    test dx, dx
    jnz failure
    mov dx, offset tail
    mov cx, 3
    mov ah, 0x40
    int 0x21
    jc failure
    cmp ax, 3
    jne failure
    mov ah, 0x3e
    int 0x21
    jc failure
    mov dx, offset fname
    mov ax, 0x3d00
    int 0x21
    jc failure
    mov bx, ax
    mov ax, 0x4200
    xor cx, cx
    mov dx, 700
    int 0x21
    jc failure
    mov dx, offset buffer
    mov cx, 3
    mov ah, 0x3f
    int 0x21
    jc failure
    cmp ax, 3
    jne failure
    cmp word ptr [buffer], 0x5958 /* XY */
    jne failure
    cmp byte ptr [buffer + 2], 'Z'
    jne failure
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
fname: .asciz "DATA.BIN"
tail:  .ascii "XYZ"
ok:    .ascii "APPEND.COM: seek/append/readback PASS!\r\n$"
bad:   .ascii "APPEND.COM: FAIL (run WRITE first).\r\n$"
buffer:.space 3
