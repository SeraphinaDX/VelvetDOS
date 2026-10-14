/* VelvetDOS 0.3.0 -- delete FAT12 file and verify it is gone. GPLv3. */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    mov dx, offset fname
    mov ah, 0x41
    int 0x21
    jc failure
    mov dx, offset fname
    mov ax, 0x3d00
    int 0x21
    jnc failure
    cmp ax, 2
    jne failure
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
ok:    .ascii "DELETE.COM: delete/not-found PASS!\r\n$"
bad:   .ascii "DELETE.COM: FAIL (run WRITE first).\r\n$"
