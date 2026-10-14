/* VLIST.COM - an ordinary, separate DOS application that lists files through
 * INT 21h AH=4Eh/4Fh, not internal VelvetDOS shell functions. GPL-3.0-only.
 */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    mov dx, offset heading
    mov ah, 9
    int 0x21
    mov dx, offset dta
    mov ah, 0x1a
    int 0x21
    mov dx, offset pattern
    mov cx, 0x10  /* include directories (but no hidden/system) */
    mov ah, 0x4e
    int 0x21
    jc .L_no_files
.L_each:
    mov si, offset dta + 30
.L_print_name:
    lodsb
    test al, al
    jz .L_next
    mov dl, al
    mov ah, 2
    int 0x21
    jmp .L_print_name
.L_next:
    mov dx, offset newline
    mov ah, 9
    int 0x21
    mov ah, 0x4f
    int 0x21
    jnc .L_each
    cmp ax, 18
    jne .L_error
    mov ax, 0x4c00
    int 0x21
.L_no_files:
    cmp ax, 18
    jne .L_error
    mov dx, offset empty
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21
.L_error:
    mov dx, offset err
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21
heading: .ascii "VLIST.COM - DOS FindFirst/FindNext directory listing\r\n$"
pattern: .asciz "*.*"
newline: .ascii "\r\n$"
empty:   .ascii "No matching entries.\r\n$"
err:     .ascii "Directory search failed.\r\n$"
.align 2
dta:     .space 43
