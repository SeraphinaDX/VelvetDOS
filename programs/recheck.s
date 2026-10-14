/* VelvetDOS 0.3.0 -- verify persistence after emulator reboot. GPLv3. */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    mov dx, offset fname
    mov ax, 0x3d00
    int 0x21
    jc failure
    mov bx, ax
    mov dx, offset buffer
    mov cx, 703
    mov ah, 0x3f
    int 0x21
    jc failure
    cmp ax, 703
    jne failure
    push ds
    pop es
    mov di, offset buffer
    mov cx, 512
    mov al, 'A'
    repe scasb
    jne failure
    mov cx, 188
    mov al, 'B'
    repe scasb
    jne failure
    cmp byte ptr [di], 'X'
    jne failure
    cmp byte ptr [di + 1], 'Y'
    jne failure
    cmp byte ptr [di + 2], 'Z'
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
fname:  .asciz "DATA.BIN"
ok:     .ascii "RECHECK.COM: persisted file verify PASS!\r\n$"
bad:    .ascii "RECHECK.COM: FAIL (run WRITE, APPEND first).\r\n$"
buffer: .space 703
