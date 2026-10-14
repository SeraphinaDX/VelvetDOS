/* VelvetDOS 0.9.0 resident DOS command interpreter.
 * SPDX-License-Identifier: GPL-3.0-only
 * This is a real .COM process which uses the documented DOS INT 21h API;
 * the kernel has a recovery prompt if COMMAND.COM exits or is unavailable.
 * Restriction: EXEC supports one bounded .COM or MZ .EXE child at a time.
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
    mov word ptr [exec_parameters+4], ax
    mov dx, offset banner
    call print_dollar
    mov dx, offset dta
    mov ah, 0x1a
    int 0x21
command_loop:
    push cs
    pop ds
    mov dx, offset prefix
    call print_dollar
    mov si, offset cwd
    xor dl, dl
    mov ah, 0x47
    int 0x21
    jc .L_prompt_tail
    mov si, offset cwd
    call print_z
.L_prompt_tail:
    mov dx, offset prompt_end
    call print_dollar
    mov byte ptr [input+1], 0
    mov dx, offset input
    mov ah, 0x0a
    int 0x21
    call parse_line
    cmp byte ptr [token], 0
    je command_loop
    mov si, offset token
    mov di, offset help_command
    call str_equal
    jc do_help
    mov si, offset token
    mov di, offset ver_command
    call str_equal
    jc do_ver
    mov si, offset token
    mov di, offset cls_command
    call str_equal
    jc do_cls
    mov si, offset token
    mov di, offset dir_command
    call str_equal
    jc do_dir
    mov si, offset token
    mov di, offset cd_command
    call str_equal
    jc do_cd
    mov si, offset token
    mov di, offset md_command
    call str_equal
    jc do_md
    mov si, offset token
    mov di, offset rd_command
    call str_equal
    jc do_rd
    mov si, offset token
    mov di, offset status_command
    call str_equal
    jc do_status
    mov si, offset token
    mov di, offset reboot_command
    call str_equal
    jc do_reboot
    mov si, offset token
    mov di, offset exit_command
    call str_equal
    jc do_exit
    jmp run_external

/* Normalize just the program token; preserve the command tail verbatim.
 * After parsing, DS:DX points at an ASCIIZ filename and cmdtail carries
 * its original spaces, DOS length byte and CR terminator. */
parse_line:
    push ax
    push bx
    push cx
    push si
    push di
    mov si, offset input+2
    mov bl, byte ptr [input+1]
    xor bh, bh
    mov byte ptr [si+bx], 0
.L_skip_leading:
    cmp byte ptr [si], ' '
    jne .L_token
    inc si
    jmp .L_skip_leading
.L_token:
    mov di, offset token
    mov cx, 63
.L_token_loop:
    mov al, byte ptr [si]
    cmp al, 0
    je .L_token_end
    cmp al, ' '
    je .L_token_end
    cmp cx, 0
    je .L_token_end
    cmp al, 'a'
    jb .L_store
    cmp al, 'z'
    ja .L_store
    sub al, 32
.L_store:
    mov byte ptr [di], al
    inc si
    inc di
    dec cx
    jmp .L_token_loop
.L_token_end:
    mov byte ptr [di], 0
    mov word ptr [args_pointer], si
    mov di, offset cmdtail+1
    xor cx, cx
.L_tail:
    mov al, byte ptr [si]
    test al, al
    jz .L_tail_end
    cmp cx, 120
    jae .L_tail_end
    mov byte ptr [di], al
    inc di
    inc si
    inc cx
    jmp .L_tail
.L_tail_end:
    mov byte ptr [cmdtail], cl
    mov byte ptr [di], 13
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

run_external:
    /* Explicit .COM/.EXE is respected. Without an extension, try .COM
     * first, then .EXE only if DOS reports file not found (AX=0002). */
    mov byte ptr [implicit_extension], 0
    mov si, offset token
    mov di, offset exec_name
    mov cx, 60
.L_copy_name:
    mov al, byte ptr [si]
    cmp al, 0
    je .L_name_end
    cmp al, '.'
    je .L_explicit_extension
    mov byte ptr [di], al
    inc si
    inc di
    loop .L_copy_name
    jmp .L_bad_name
.L_explicit_extension:
    /* Copy explicit extension without altering case (already uppercase). */
.L_copy_rest:
    mov al, byte ptr [si]
    mov byte ptr [di], al
    inc si
    inc di
    test al, al
    jz .L_launch
    loop .L_copy_rest
    jmp .L_bad_name
.L_name_end:
    mov byte ptr [implicit_extension], 1
    mov word ptr [extension_location], di
    mov byte ptr [di], '.'
    mov byte ptr [di+1], 'C'
    mov byte ptr [di+2], 'O'
    mov byte ptr [di+3], 'M'
    mov byte ptr [di+4], 0
.L_launch:
    mov dx, offset exec_name
    mov bx, offset exec_parameters
    push ds
    pop es
    mov ax, 0x4b00
    int 0x21
    jnc command_loop
    cmp ax, 2
    jne .L_launch_failed
    cmp byte ptr [implicit_extension], 1
    jne .L_launch_failed
    mov di, word ptr [extension_location]
    mov byte ptr [di+1], 'E'
    mov byte ptr [di+2], 'X'
    mov byte ptr [di+3], 'E'
    mov dx, offset exec_name
    mov bx, offset exec_parameters
    push ds
    pop es
    mov ax, 0x4b00
    int 0x21
    jnc command_loop
.L_launch_failed:
    push ax
    mov dx, offset exec_failed
    call print_dollar
    pop ax
    call print_hex_byte
    mov dx, offset crlf
    call print_dollar
    jmp command_loop
.L_bad_name:
    mov dx, offset bad_command
    call print_dollar
    jmp command_loop

do_help:
    mov dx, offset help_text
    call print_dollar
    jmp command_loop
do_ver:
    mov ax, cs
    mov word ptr [exec_parameters+4], ax
    mov dx, offset banner
    call print_dollar
    jmp command_loop
do_cls:
    mov ax, 3
    int 0x10
    jmp command_loop
do_exit:
    mov ax, 0x4c00
    int 0x21
do_reboot:
    int 0x19
    jmp command_loop
do_status:
    mov ah, 0x4d
    int 0x21
    push ax
    mov dx, offset status_text
    call print_dollar
    pop ax
    call print_hex_byte
    mov dx, offset crlf
    call print_dollar
    jmp command_loop
do_cd:
    mov ah, 0x3b
    jmp .L_dir_op
do_md:
    mov ah, 0x39
    jmp .L_dir_op
do_rd:
    mov ah, 0x3a
.L_dir_op:
    mov dx, word ptr [args_pointer]
    mov si, dx
.L_dir_skip:
    cmp byte ptr [si], ' '
    jne .L_dir_use
    inc dx
    inc si
    jmp .L_dir_skip
.L_dir_use:
    cmp byte ptr [si], 0
    je .L_dir_error
    int 0x21
    jnc command_loop
.L_dir_error:
    mov dx, offset dir_failed
    call print_dollar
    jmp command_loop

do_dir:
    mov dx, offset search_mask
    mov cx, 0x10  /* include subdirectories */
    mov ah, 0x4e
    int 0x21
    jc .L_dir_done
.L_listing:
    mov si, offset dta+30
    cmp byte ptr [si], '.'
    je .L_dir_next
    call print_z
    mov dx, offset crlf
    call print_dollar
.L_dir_next:
    mov ah, 0x4f
    int 0x21
    jnc .L_listing
.L_dir_done:
    jmp command_loop

str_equal:
    push ax
.L_eq:
    mov al, byte ptr [si]
    cmp al, byte ptr [di]
    jne .L_no
    test al, al
    je .L_yes
    inc si
    inc di
    jmp .L_eq
.L_yes:
    stc
    jmp .L_eq_done
.L_no:
    clc
.L_eq_done:
    pop ax
    ret

print_dollar:
    mov ah, 9
    int 0x21
    ret
print_z:
    push ax
    push dx
    push si
.L_print:
    lodsb
    test al, al
    jz .L_end_print
    mov dl, al
    mov ah, 2
    int 0x21
    jmp .L_print
.L_end_print:
    pop si
    pop dx
    pop ax
    ret
print_hex_byte:
    push ax
    push bx
    push cx
    mov bl, al
    mov cl, 4
    shr al, cl
    call nibble
    mov al, bl
    and al, 15
    call nibble
    pop cx
    pop bx
    pop ax
    ret
nibble:
    and al, 15
    cmp al, 10
    jb .L_digit
    add al, 'A'-10
    jmp .L_out
.L_digit:
    add al, '0'
.L_out:
    mov dl, al
    mov ah, 2
    int 0x21
    ret

banner:       .ascii "\r\nVelvetDOS COMMAND.COM 0.9.0 [experimental]\r\n$"
prefix:       .ascii "\r\nA:\\$"
prompt_end:   .ascii ">$"
crlf:         .ascii "\r\n$"
help_text:    .ascii "HELP VER CLS DIR CD MD RD STATUS REBOOT EXIT\r\n"
              .ascii "Run .COM and small MZ .EXE programs. Nested EXEC unavailable.\r\n$"
status_text:  .ascii "Last exit code (hex): $"
dir_failed:   .ascii "Directory operation failed.\r\n$"
exec_failed:  .ascii "EXEC failed, DOS error AX=$"
bad_command:  .ascii "Command too long.\r\n$"
help_command: .asciz "HELP"
ver_command:  .asciz "VER"
cls_command:  .asciz "CLS"
dir_command:  .asciz "DIR"
cd_command:   .asciz "CD"
md_command:   .asciz "MD"
rd_command:   .asciz "RD"
status_command:.asciz "STATUS"
reboot_command:.asciz "REBOOT"
exit_command:.asciz "EXIT"
search_mask:  .asciz "*.*"
.align 2
exec_parameters:
    .word 0                 /* environment: inherited */
    .word cmdtail           /* DOS command tail offset */
    .word 0                 /* command tail segment — set during startup */
    .word 0,0               /* two unused FCB far pointers */
    .word 0,0
cwd:           .space 68
.align 2
args_pointer:  .word 0
cmdtail:       .space 128
exec_name:     .space 68
implicit_extension: .byte 0
.align 2
extension_location: .word 0
token:         .space 64
input:         .byte 124,0
               .space 125
.align 2
dta:           .space 43
