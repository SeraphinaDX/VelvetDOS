/* VelvetDOS 0.12.0 child-process environment regression.
 * License: GPL-3.0-only. Native 8086 DOS .COM file.
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
    mov ax, word ptr [0x2c]       /* DOS PSP environment segment */
    test ax, ax
    jz .L_fail
    mov es, ax
    xor di, di
.L_next:
    cmp di, 253
    jae .L_fail
    cmp byte ptr es:[di], 0
    je .L_fail
    push di
    mov si, offset expected
.L_compare:
    mov al, byte ptr [si]
    cmp al, byte ptr es:[di]
    jne .L_not_match
    inc si
    inc di
    test al, al
    jne .L_compare
    pop di
    mov dx, offset success
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21
.L_not_match:
    pop di
.L_skip:
    cmp di, 253
    jae .L_fail
    cmp byte ptr es:[di], 0
    je .L_advance
    inc di
    jmp .L_skip
.L_advance:
    inc di
    jmp .L_next
.L_fail:
    mov dx, offset failure
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21
expected: .asciz "BATCHOK=YES"
success:  .ascii "ENVCHK.COM: child inherited BATCHOK=YES PASS!\r\n$"
failure:  .ascii "ENVCHK.COM: child environment FAIL!\r\n$"
