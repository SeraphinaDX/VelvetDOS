/* VelvetDOS 0.4.0 8086 COM regression for directory APIs and DOS paths.
 * SPDX-License-Identifier: GPL-3.0-only
 * Must run on a freshly copied writable floppy image.
 */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    /* Create nested directories and enter the deepest one. */
    mov word ptr [last_step], offset step_mk_lab
    mov dx, offset first_dir
    mov ah, 0x39
    int 0x21
    jc failure
    mov word ptr [last_step], offset step_mk_one
    mov dx, offset second_dir
    mov ah, 0x39
    int 0x21
    jc failure
    mov word ptr [last_step], offset step_cd_one
    mov dx, offset second_dir
    mov ah, 0x3b
    int 0x21
    jc failure
    /* DOS get-CWD excludes the drive and initial backslash. */
    mov word ptr [last_step], offset step_getcwd
    xor dl, dl
    mov si, offset cwd_buffer
    mov ah, 0x47
    int 0x21
    jc failure
    mov word ptr [last_step], offset step_checkcwd
    push ds
    pop es
    mov si, offset cwd_buffer
    mov di, offset cwd_expected
cwd_compare:
    lodsb
    cmp al, byte ptr es:[di]
    jne failure
    inc di
    test al, al
    jnz cwd_compare
    /* Test create/write inside a directory, then open using an absolute path. */
    mov word ptr [last_step], offset step_create
    mov dx, offset local_file
    xor cx, cx
    mov ah, 0x3c
    int 0x21
    jc failure
    mov word ptr [last_step], offset step_write
    mov bx, ax
    mov dx, offset pattern
    mov cx, 600
    mov ah, 0x40
    int 0x21
    jc failure
    mov word ptr [last_step], offset step_write_count
    mov word ptr [last_step], offset step_read_count
    cmp ax, 600
    jne failure
    mov word ptr [last_step], offset step_close_write
    mov word ptr [last_step], offset step_close_read
    mov ah, 0x3e
    int 0x21
    jc failure
    mov word ptr [last_step], offset step_open_abs
    mov dx, offset absolute_file
    mov ax, 0x3d00
    int 0x21
    jc failure
    mov word ptr [last_step], offset step_read
    mov bx, ax
    mov dx, offset buffer
    mov cx, 600
    mov ah, 0x3f
    int 0x21
    jc failure
    cmp ax, 600
    jne failure
    mov word ptr [last_step], offset step_compare
    push ds
    pop es
    mov si, offset pattern
    mov di, offset buffer
    mov cx, 600
    repe cmpsb
    jne failure
    mov ah, 0x3e
    int 0x21
    jc failure
    /* A directory containing a file must not be removable. */
    mov word ptr [last_step], offset step_cd_root
    mov dx, offset root_dir
    mov ah, 0x3b
    int 0x21
    jc failure
    mov word ptr [last_step], offset step_notempty
    mov dx, offset one_dir
    mov ah, 0x3a
    int 0x21
    jnc failure
    mov word ptr [last_step], offset step_delete
    mov dx, offset child_file
    mov ah, 0x41
    int 0x21
    jc failure
    mov word ptr [last_step], offset step_rm_one
    mov dx, offset one_dir
    mov ah, 0x3a
    int 0x21
    jc failure
    mov word ptr [last_step], offset step_rm_lab
    mov dx, offset first_dir
    mov ah, 0x3a
    int 0x21
    jc failure
    /* Entering removed directory must fail. */
    mov word ptr [last_step], offset step_cd_removed
    mov dx, offset first_dir
    mov ah, 0x3b
    int 0x21
    jnc failure
    mov dx, offset ok
    mov ah, 0x09
    int 0x21
    mov ax, 0x4c00
    int 0x21
failure:
    push ax                       /* preserve DOS error/result in AX */
    mov dx, offset bad
    mov ah, 0x09
    int 0x21
    mov dx, word ptr [last_step]
    mov ah, 0x09
    int 0x21
    mov dx, offset errprefix
    mov ah, 0x09
    int 0x21
    pop ax
    call print_hex_ax
    mov dx, offset newline
    mov ah, 0x09
    int 0x21
    /* Return to root even when the test stops midway. */
    mov dx, offset root_dir
    mov ah, 0x3b
    int 0x21
    mov ax, 0x4c01
    int 0x21

/* Print the hexadecimal DOS AX value (8086, DOS AH=02h). */
print_hex_ax:
    push ax
    push bx
    push cx
    push dx
    mov bx, ax
    mov cx, 4
.L_next_nibble:
    rol bx, 1
    rol bx, 1
    rol bx, 1
    rol bx, 1
    mov dl, bl
    and dl, 0x0f
    cmp dl, 9
    jbe .L_digit
    add dl, 'A' - 10
    jmp .L_print
.L_digit:
    add dl, '0'
.L_print:
    mov ah, 0x02
    int 0x21
    loop .L_next_nibble
    pop dx
    pop cx
    pop bx
    pop ax
    ret
first_dir:     .asciz "LAB"
second_dir:    .asciz "LAB\\ONE"
root_dir:      .asciz "\\"
one_dir:       .asciz "LAB\\ONE"
child_file:    .asciz "LAB\\ONE\\TEST.DAT"
local_file:    .asciz "TEST.DAT"
absolute_file: .asciz "A:\\LAB\\ONE\\TEST.DAT"
cwd_expected:  .asciz "LAB\\ONE"
ok:            .ascii "PATHS.COM: directories, paths, file I/O PASS!\r\n$"
bad:           .ascii "PATHS.COM failed at: $"
errprefix:     .ascii "  AX=$"
newline:       .ascii "\r\n$"
last_step:     .word step_mk_lab
step_mk_lab:   .ascii "MD LAB$"
step_mk_one:   .ascii "MD LAB\\ONE$"
step_cd_one:   .ascii "CD LAB\\ONE$"
step_getcwd:   .ascii "INT 21h/47h getcwd$"
step_checkcwd: .ascii "Compare CWD to LAB\\ONE$"
step_create:   .ascii "Create TEST.DAT in CWD$"
step_write:    .ascii "Write 600 bytes$"
step_write_count: .ascii "Verify 600 bytes written$"
step_close_write: .ascii "Close new TEST.DAT$"
step_open_abs: .ascii "Open A:\\LAB\\ONE\\TEST.DAT$"
step_read:     .ascii "Read 600 bytes$"
step_read_count: .ascii "Verify 600 bytes read$"
step_compare:  .ascii "Compare file data$"
step_close_read: .ascii "Close TEST.DAT after reading$"
step_cd_root:  .ascii "CD root directory$"
step_notempty: .ascii "Reject RD of nonempty LAB\\ONE$"
step_delete:   .ascii "Delete LAB\\ONE\\TEST.DAT$"
step_rm_one:   .ascii "RD LAB\\ONE$"
step_rm_lab:   .ascii "RD LAB$"
step_cd_removed: .ascii "Reject CD of deleted LAB$"
pattern:       .fill 512, 1, 0x4d
               .fill 88, 1, 0x4e
buffer:        .space 600
cwd_buffer:    .space 128
