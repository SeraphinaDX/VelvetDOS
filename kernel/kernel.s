/* VelvetDOS 0.1.0 -- experimental 16-bit DOS-compatible kernel.
 * SPDX-License-Identifier: GPL-3.0-only
 * Linked at offset 0, loaded by the boot sector at physical 0x10000.
 * Read-only FAT12 root directory; one COM application at a time.
 * Not a replacement for full MS-DOS and not ready for real hardware.
 */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.equ ROOT_SEG,       0x2000
.equ FAT_SEG,        0x2200
.equ APP_SEG,        0x3000
.equ ROOT_SECTOR,    83
.equ FAT_SECTOR,     65
.equ ROOT_ENTRIES,   224
.equ ROOT_SECTORS,   14
.equ FAT_SECTORS,    9
.equ DATA_BIAS,     95    /* first data LBA (97) minus first cluster (2) */
_start:
    cli
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, offset stack_end
    sti
    mov byte ptr [boot_drive], dl
    /* Install INT 20h and INT 21h in the real-mode IVT. */
    xor ax, ax
    mov es, ax
    mov word ptr es:[0x20 * 4], offset int20_handler
    mov ax, cs
    mov word ptr es:[0x20 * 4 + 2], ax
    mov word ptr es:[0x21 * 4], offset int21_handler
    mov word ptr es:[0x21 * 4 + 2], ax
    call load_tables
    mov si, offset banner
    call print_z
shell_loop:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, offset stack_end
    mov si, offset prompt
    call print_z
    call read_line
    cmp byte ptr [cmdline], 0
    je shell_loop
    mov si, offset cmdline
    mov di, offset cmd_help
    call str_eq
    jc do_help
    mov si, offset cmdline
    mov di, offset cmd_dir
    call str_eq
    jc do_dir
    mov si, offset cmdline
    mov di, offset cmd_ver
    call str_eq
    jc do_ver
    mov si, offset cmdline
    mov di, offset cmd_cls
    call str_eq
    jc do_cls
    mov si, offset cmdline
    mov di, offset cmd_reboot
    call str_eq
    jc do_reboot
    call prepare_filename
    jc bad_command
    /* 0.1.0 is a COM loader, not an arbitrary binary/.EXE launcher. */
    cmp byte ptr [filename + 8], 'C'
    jne bad_command
    cmp byte ptr [filename + 9], 'O'
    jne bad_command
    cmp byte ptr [filename + 10], 'M'
    jne bad_command
    call find_file
    jc bad_command
    call load_com
    jc .L_shell_loop_load_error
    call start_com     /* does not return; app returns through INT 20h/21h */
.L_shell_loop_load_error:
    mov si, offset load_error_message
    call print_z
    jmp shell_loop
bad_command:
    mov si, offset bad_command_message
    call print_z
    jmp shell_loop

do_help:
    mov si, offset help_text
    call print_z
    jmp shell_loop
do_ver:
    mov si, offset banner
    call print_z
    jmp shell_loop
do_cls:
    mov ax, 0x0003     /* BIOS 80x25 text mode resets screen */
    int 0x10
    jmp shell_loop
do_reboot:
    int 0x19
    jmp shell_loop

do_dir:
    mov si, offset dir_header
    call print_z
    mov ax, ROOT_SEG
    mov es, ax
    xor di, di
    mov cx, ROOT_ENTRIES
.L_do_dir_next:
    cmp byte ptr es:[di], 0
    je .L_do_dir_done
    cmp byte ptr es:[di], 0xe5
    je .L_do_dir_skip
    mov al, byte ptr es:[di + 11]
    test al, 0x18    /* no volume labels/directories for this version */
    jnz .L_do_dir_skip
    cmp al, 0x0f     /* skip long filename entries */
    je .L_do_dir_skip
    push cx
    mov bx, di
    xor si, si
.L_do_dir_name:
    mov al, byte ptr es:[bx + si]
    call putc
    inc si
    cmp si, 8
    jb .L_do_dir_name
    mov al, '.'
    call putc
.L_do_dir_ext:
    mov al, byte ptr es:[bx + si]
    call putc
    inc si
    cmp si, 11
    jb .L_do_dir_ext
    call newline
    pop cx
.L_do_dir_skip:
    add di, 32
    loop .L_do_dir_next
.L_do_dir_done:
    mov ax, cs
    mov es, ax
    jmp shell_loop

/* print ASCIIZ at DS:SI */
print_z:
    push ax
    push si
.L_print_z_repeat:
    lodsb
    test al, al
    jz .L_print_z_done
    call putc
    jmp .L_print_z_repeat
.L_print_z_done:
    pop si
    pop ax
    ret
putc:
    push ax
    push bx
    mov ah, 0x0e
    mov bx, 0x0007
    int 0x10
    pop bx
    pop ax
    ret
newline:
    push ax
    mov al, 13
    call putc
    mov al, 10
    call putc
    pop ax
    ret

/* Read a line and uppercase ASCII; DEL/backspace editing, CR to submit. */
read_line:
    push ax
    push bx
    push di
    xor bx, bx
    mov di, offset cmdline
.L_read_line_key:
    xor ah, ah
    int 0x16
    cmp al, 13
    je .L_read_line_enter
    cmp al, 8
    je .L_read_line_back
    cmp al, 127
    je .L_read_line_back
    cmp al, 32
    jb .L_read_line_key
    cmp al, 126
    ja .L_read_line_key
    cmp bx, 63
    jae .L_read_line_key
    cmp al, 'a'
    jb .L_read_line_store
    cmp al, 'z'
    ja .L_read_line_store
    sub al, 32
.L_read_line_store:
    mov byte ptr [di], al
    inc di
    inc bx
    call putc
    jmp .L_read_line_key
.L_read_line_back:
    test bx, bx
    jz .L_read_line_key
    dec bx
    dec di
    mov al, 8
    call putc
    mov al, ' '
    call putc
    mov al, 8
    call putc
    jmp .L_read_line_key
.L_read_line_enter:
    mov byte ptr [di], 0
    call newline
    pop di
    pop bx
    pop ax
    ret

/* Compare zero-terminated DS:SI and DS:DI, CF=1 if equal. */
str_eq:
    push ax
.L_str_eq_loop:
    mov al, byte ptr [si]
    cmp al, byte ptr [di]
    jne .L_str_eq_unequal
    test al, al
    jz .L_str_eq_equal
    inc si
    inc di
    jmp .L_str_eq_loop
.L_str_eq_equal:
    stc
    jmp .L_str_eq_exit
.L_str_eq_unequal:
    clc
.L_str_eq_exit:
    pop ax
    ret

/* Convert FILENAME[.L_str_eq_EXT] into FAT 8.3 uppercase name.
 * No paths, spaces, switches or command-line arguments in 0.1.0. */
prepare_filename:
    push ax
    push bx
    push cx
    push si
    push di
    mov di, offset filename
    mov cx, 11
    mov al, ' '
    rep stosb
    mov si, offset cmdline
    mov di, offset filename
    xor bx, bx
.L_prepare_filename_base:
    lodsb
    test al, al
    jz .L_prepare_filename_default_ext
    cmp al, '.'
    je .L_prepare_filename_has_ext
    cmp al, ' '
    je .L_prepare_filename_error
    cmp bx, 8
    jae .L_prepare_filename_error
    mov byte ptr [di], al
    inc di
    inc bx
    jmp .L_prepare_filename_base
.L_prepare_filename_default_ext:
    mov byte ptr [filename + 8], 'C'
    mov byte ptr [filename + 9], 'O'
    mov byte ptr [filename + 10], 'M'
    jmp .L_prepare_filename_ok
.L_prepare_filename_has_ext:
    xor bx, bx
    mov di, offset filename + 8
.L_prepare_filename_ext:
    lodsb
    test al, al
    jz .L_prepare_filename_ok
    cmp bx, 3
    jae .L_prepare_filename_error
    cmp al, ' '
    je .L_prepare_filename_error
    cmp al, '.'
    je .L_prepare_filename_error
    mov byte ptr [di], al
    inc di
    inc bx
    jmp .L_prepare_filename_ext
.L_prepare_filename_ok:
    cmp byte ptr [filename], ' '
    je .L_prepare_filename_error
    clc
    jmp .L_prepare_filename_exit
.L_prepare_filename_error:
    stc
.L_prepare_filename_exit:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

/* Search FAT root for 8.3 file, setting file_cluster/file_size.
 * CF=0 found, CF=1 missing. Directories/volume entries excluded. */
find_file:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov ax, ROOT_SEG
    mov es, ax
    xor di, di
    mov cx, ROOT_ENTRIES
.L_find_file_entry:
    cmp byte ptr es:[di], 0
    je .L_find_file_not_found
    cmp byte ptr es:[di], 0xe5
    je .L_find_file_next
    mov al, byte ptr es:[di + 11]
    test al, 0x18
    jnz .L_find_file_next
    cmp al, 0x0f
    je .L_find_file_next
    xor bx, bx
    mov si, offset filename
.L_find_file_cmp:
    mov al, byte ptr [si + bx]
    cmp al, byte ptr es:[di + bx]
    jne .L_find_file_next
    inc bx
    cmp bx, 11
    jb .L_find_file_cmp
    mov ax, word ptr es:[di + 26]
    mov word ptr [file_cluster], ax
    mov ax, word ptr es:[di + 28]
    mov word ptr [file_size], ax
    mov ax, word ptr es:[di + 30]
    mov word ptr [file_size_high], ax
    clc
    jmp .L_find_file_exit
.L_find_file_next:
    add di, 32
    loop .L_find_file_entry
.L_find_file_not_found:
    stc
.L_find_file_exit:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* Load COM into APP_SEG:0100. Reject >65024 bytes and bad/truncated chains. */
load_com:
    push ax
    push bx
    push cx
    push dx
    push es
    mov ax, word ptr [file_size_high]
    test ax, ax
    jnz .L_load_com_failed
    mov ax, word ptr [file_size]
    test ax, ax
    jz .L_load_com_failed
    cmp ax, 65024
    ja .L_load_com_failed
    add ax, 511
    mov cl, 9
    shr ax, cl
    mov cx, ax
    mov dx, word ptr [file_cluster]
    mov ax, APP_SEG
    mov es, ax
    mov bx, 0x0100
    test cx, cx
    jz .L_load_com_loaded
.L_load_com_next:
    cmp dx, 2
    jb .L_load_com_failed
    cmp dx, 2784     /* 1.44 MB floppy, our reserved-sector geometry */
    ja .L_load_com_failed
    mov ax, dx
    add ax, DATA_BIAS
    call read_sector
    jc .L_load_com_failed
    add bx, 512
    dec cx
    jz .L_load_com_loaded
    mov ax, dx
    call fat_next
    mov dx, ax
    cmp dx, 0xff8
    jae .L_load_com_failed
    jmp .L_load_com_next
.L_load_com_loaded:
    clc
    jmp .L_load_com_exit
.L_load_com_failed:
    stc
.L_load_com_exit:
    pop es
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* FAT12 next cluster, AX=cluster, returns AX=next or 0xfff. */
fat_next:
    push bx
    push dx
    push es
    push cx
    mov bx, ax
    mov dx, ax
    shr bx, 1
    add bx, ax
    mov ax, FAT_SEG
    mov es, ax
    mov ax, word ptr es:[bx]
    test dx, 1
    jz .L_fat_next_even
    mov cl, 4
    shr ax, cl
    jmp .L_fat_next_done
.L_fat_next_even:
    and ax, 0x0fff
.L_fat_next_done:
    pop cx
    pop es
    pop dx
    pop bx
    ret

/* Create PSP and execute a real DOS .COM image. Never returns. */
start_com:
    mov ax, APP_SEG
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, 128
    rep stosw
    mov byte ptr es:[0], 0xcd      /* INT 20h instruction */
    mov byte ptr es:[1], 0x20
    mov word ptr es:[2], 0x4000    /* approximate last available paragraph */
    mov byte ptr es:[0x80], 0      /* empty command tail */
    mov byte ptr es:[0x81], 13
    cli
    mov ax, APP_SEG
    mov ds, ax
    mov ss, ax
    mov sp, 0xfffe
    mov word ptr ss:[0xfffe], 0 /* near RET -> PSP:0000 -> INT 20h */
    sti
    mov ax, APP_SEG
    push ax
    mov ax, 0x0100
    push ax
    xor ax, ax
    retf

/* Software INT 20h process exit. App stack is discarded. */
int20_handler:
process_exit:
    cli
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, offset stack_end
    sti
    jmp shell_loop

/* Minimal, deliberate subset of MS-DOS INT 21h. Unimplemented AH -> CF, AX=1.
 * Saves user DS, ES, BX, CX, DX, SI, DI, BP. Return AX stays live.
 * Stack offsets at BP: DI=2 SI=4 DX=6 CX=8 BX=10 ES=12 DS=14 FLAGS=20.
 */
int21_handler:
    cmp ah, 0x4c
    je process_exit
    push ds
    push es
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov bp, sp
    mov bx, cs
    mov ds, bx
    and word ptr ss:[bp + 20], 0xfffe /* clear carry */
    cmp ah, 0x09
    je .L_int21_handler_print_dollar
    cmp ah, 0x02
    je .L_int21_handler_write_char
    cmp ah, 0x01
    je .L_int21_handler_read_echo
    cmp ah, 0x08
    je .L_int21_handler_read_noecho
    cmp ah, 0x07
    je .L_int21_handler_read_noecho
    cmp ah, 0x0a
    je .L_int21_handler_buffered_input
    cmp ah, 0x19
    je .L_int21_handler_default_drive
    cmp ah, 0x30
    je .L_int21_handler_version
    cmp ah, 0x40
    je .L_int21_handler_write_handle
    cmp ah, 0x4d
    je .L_int21_handler_return_code
    cmp ah, 0x00
    je .L_int21_handler_exit_now
    mov ax, 1
    or word ptr ss:[bp + 20], 1
    jmp .L_int21_handler_return
.L_int21_handler_print_dollar:
    mov ax, word ptr ss:[bp + 14]
    mov es, ax
    mov si, word ptr ss:[bp + 6]
.L_int21_handler_p_loop:
    mov al, byte ptr es:[si]
    cmp al, '$'
    je .L_int21_handler_p_end
    call putc
    inc si
    jmp .L_int21_handler_p_loop
.L_int21_handler_p_end:
    mov al, '$'
    jmp .L_int21_handler_return
.L_int21_handler_write_char:
    mov al, byte ptr ss:[bp + 6] /* low byte = DL */
    call putc
    jmp .L_int21_handler_return
.L_int21_handler_read_echo:
    xor ah, ah
    int 0x16
    push ax
    call putc
    pop ax
    xor ah, ah
    jmp .L_int21_handler_return
.L_int21_handler_read_noecho:
    xor ah, ah
    int 0x16
    xor ah, ah
    jmp .L_int21_handler_return
.L_int21_handler_buffered_input:
    mov ax, word ptr ss:[bp + 14]
    mov es, ax
    mov di, word ptr ss:[bp + 6]
    mov cl, byte ptr es:[di]    /* max buffer incl. CR */
    xor ch, ch
    xor bx, bx
    test cx, cx
    jz .L_int21_handler_bi_done
.L_int21_handler_bi_loop:
    xor ah, ah
    int 0x16
    cmp al, 13
    je .L_int21_handler_bi_cr
    cmp al, 8
    je .L_int21_handler_bi_back
    cmp al, 32
    jb .L_int21_handler_bi_loop
    mov dx, cx
    dec dx
    cmp bx, dx
    jae .L_int21_handler_bi_loop
    mov byte ptr es:[di + bx + 2], al
    inc bx
    call putc
    jmp .L_int21_handler_bi_loop
.L_int21_handler_bi_back:
    test bx, bx
    jz .L_int21_handler_bi_loop
    dec bx
    mov al, 8
    call putc
    mov al, ' '
    call putc
    mov al, 8
    call putc
    jmp .L_int21_handler_bi_loop
.L_int21_handler_bi_cr:
    mov byte ptr es:[di + bx + 2], 13
    call newline
.L_int21_handler_bi_done:
    mov byte ptr es:[di + 1], bl
    jmp .L_int21_handler_return
.L_int21_handler_default_drive:
    xor ax, ax
    jmp .L_int21_handler_return
.L_int21_handler_version:
    mov ax, 0x1606  /* MS-DOS 6.22 version encoding; compatibility target */
    xor bx, bx
    jmp .L_int21_handler_return
.L_int21_handler_return_code:
    xor ax, ax
    jmp .L_int21_handler_return
.L_int21_handler_write_handle:
    mov bx, word ptr ss:[bp + 10]
    cmp bx, 1
    je .L_int21_handler_wh_ok
    cmp bx, 2
    jne .L_int21_handler_not_supported
.L_int21_handler_wh_ok:
    mov ax, word ptr ss:[bp + 14]
    mov es, ax
    mov si, word ptr ss:[bp + 6]
    mov cx, word ptr ss:[bp + 8]
.L_int21_handler_wh_loop:
    test cx, cx
    jz .L_int21_handler_wh_done
    mov al, byte ptr es:[si]
    call putc
    inc si
    dec cx
    jmp .L_int21_handler_wh_loop
.L_int21_handler_wh_done:
    mov ax, word ptr ss:[bp + 8]
    jmp .L_int21_handler_return
.L_int21_handler_not_supported:
    mov ax, 6 /* invalid handle */
    or word ptr ss:[bp + 20], 1
    jmp .L_int21_handler_return
.L_int21_handler_exit_now:
    jmp process_exit
.L_int21_handler_return:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop es
    pop ds
    iret

/* Preload FAT #1 and root directory into memory (disk is read-only). */
load_tables:
    mov ax, FAT_SEG
    mov es, ax
    xor bx, bx
    mov si, FAT_SECTOR
    mov cx, FAT_SECTORS
.L_load_tables_fat_loop:
    push cx
    mov ax, si
    call read_sector
    jc fatal_disk_with_cx
    add bx, 512
    inc si
    pop cx
    loop .L_load_tables_fat_loop
    mov ax, ROOT_SEG
    mov es, ax
    xor bx, bx
    mov si, ROOT_SECTOR
    mov cx, ROOT_SECTORS
.L_load_tables_root_loop:
    push cx
    mov ax, si
    call read_sector
    jc fatal_disk_with_cx
    add bx, 512
    inc si
    pop cx
    loop .L_load_tables_root_loop
    mov ax, cs
    mov es, ax
    ret
fatal_disk_with_cx:
    pop cx
    mov ax, cs
    mov es, ax
    mov si, offset disk_error_message
    call print_z
.L_fatal_disk_with_cx_hang:
    cli
    hlt
    jmp .L_fatal_disk_with_cx_hang

/* AX=LBA, ES:BX=destination, CF on failure. CHS for 1.44MB floppy. */
read_sector:
    push ax
    push bx
    push cx
    push dx
    push si
    xor dx, dx
    mov cx, 18
    div cx
    mov cx, dx
    inc cl
    xor dx, dx
    mov si, 2
    div si
    mov ch, al
    mov dh, dl
    mov dl, byte ptr [boot_drive]
    mov ax, 0x0201
    int 0x13
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* Runtime state and messages. */
boot_drive:         .byte 0
file_cluster:       .word 0
file_size:          .word 0
file_size_high:     .word 0
filename:           .space 11
cmdline:            .space 64
banner:             .asciz "\r\nVelvetDOS 0.1.0  [experimental]\r\nGNU GPLv3 | Type HELP for commands.\r\n"
prompt:             .asciz "\r\nA:\\>"
cmd_help:           .asciz "HELP"
cmd_dir:            .asciz "DIR"
cmd_ver:            .asciz "VER"
cmd_cls:            .asciz "CLS"
cmd_reboot:         .asciz "REBOOT"
help_text:          .asciz "Commands: HELP, DIR, VER, CLS, REBOOT\r\nRun a root-directory .COM program by name (e.g. HELLO).\r\nOnly root-directory, read-only files and a subset of INT 21h work.\r\n"
dir_header:         .asciz "Root directory:\r\n"
bad_command_message:.asciz "Bad command or file name.\r\n"
load_error_message: .asciz "Unable to load COM file (size, FAT chain or disk error).\r\n"
disk_error_message: .asciz "FATAL: Cannot read floppy disk.\r\n"
.align 2
stack_start: .space 2048
stack_end:
