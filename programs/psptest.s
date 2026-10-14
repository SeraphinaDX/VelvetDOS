/* VelvetDOS 0.7.0 public DOS API and PSP contract regression.
 * SPDX-License-Identifier: GPL-3.0-only
 * Run as: PSPTEST hello MiXeD 123
 * Tests exact mixed-case command tail, DTA, handles, environment and PSP queries.
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
    mov word ptr [stage], offset msg_psp
    mov ah, 0x62
    int 0x21
    jc failed
    mov ax, cs
    cmp bx, ax
    jne failed
    mov ah, 0x51
    int 0x21
    jc failed
    mov ax, cs
    cmp bx, ax
    jne failed
    cmp word ptr [0], 0x20cd  /* INT 20h */
    jne failed
    cmp word ptr [2], 0x9000 /* exclusive segment of allocation */
    jne failed
    cmp word ptr [0x16], 0x3000
    jne failed

    mov word ptr [stage], offset msg_dta
    mov ah, 0x2f
    int 0x21
    mov ax, cs
    mov dx, es
    cmp dx, ax
    jne failed
    cmp bx, 0x80
    jne failed

    mov word ptr [stage], offset msg_tail
    mov si, offset wanted_tail
    mov di, 0x81
    mov cx, wanted_end - wanted_tail
    cmp byte ptr [0x80], cl
    jne failed
compare_tail:
    mov al, byte ptr [si]
    cmp al, byte ptr [di]
    jne failed
    inc si
    inc di
    loop compare_tail
    cmp byte ptr [di], 13
    jne failed

    mov word ptr [stage], offset msg_handles
    cmp byte ptr [0x18], 0
    jne failed
    cmp byte ptr [0x19], 1
    jne failed
    cmp byte ptr [0x1a], 2
    jne failed
    cmp byte ptr [0x1b], 3
    jne failed
    cmp byte ptr [0x1c], 4
    jne failed
    cmp byte ptr [0x1d], 0xff
    jne failed

    mov word ptr [stage], offset msg_environment
    mov ax, word ptr [0x2c]
    test ax, ax
    jz failed
    mov dx, cs
    cmp ax, dx
    je failed
    mov es, ax
    mov si, offset wanted_env
    xor di, di
    mov cx, wanted_env_end - wanted_env
compare_env:
    mov al, byte ptr [si]
    cmp al, byte ptr es:[di]
    jne failed
    inc si
    inc di
    loop compare_env

passed:
    mov dx, offset msg_ok
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21
failed:
    mov dx, offset msg_bad
    mov ah, 9
    int 0x21
    mov dx, [stage]
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21
stage: .word 0
wanted_tail: .ascii " hello MiXeD 123"
wanted_end:
wanted_env: .ascii "PATH=A:\\"
            .byte 0
            .ascii "PROMPT=$P$G"
            .byte 0, 0
            .word 1
            .asciz "A:\\VELVETDOS"
wanted_env_end:
msg_psp: .asciz "PSP query / header$"
msg_dta: .asciz "Default DTA$"
msg_tail: .asciz "PSP command tail$"
msg_handles: .asciz "Standard handles$"
msg_environment: .asciz "Environment block$"
msg_bad: .ascii "PSPTEST.COM failed at: $"
msg_ok: .ascii "PSPTEST.COM: command tail, PSP, DTA, handles, environment PASS!\r\n$"
