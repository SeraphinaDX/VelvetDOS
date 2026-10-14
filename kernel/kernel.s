/* VelvetDOS 0.2.0 -- experimental 16-bit DOS-compatible kernel.
 * SPDX-License-Identifier: GPL-3.0-only
 * Linked at offset 0, loaded by the boot sector at physical 0x10000.
 * Read-only FAT12 root directory; one DOS application at a time.
 * Not a replacement for full MS-DOS and not ready for real hardware.
 */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.equ ROOT_SEG,       0x2000
.equ FAT_SEG,        0x2200
.equ IO_SEG,         0x2400
.equ MEM_LIMIT,      0x9000
.equ MEM_MCB,        0x2fff
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
    /* Recognize explicit .EXE as well as .COM; default remains .COM. */
    cmp byte ptr [filename + 8], 'E'
    jne .L_shell_check_com
    cmp byte ptr [filename + 9], 'X'
    jne bad_command
    cmp byte ptr [filename + 10], 'E'
    jne bad_command
    call find_file
    jc bad_command
    call load_com
    jc .L_shell_loop_load_error
    call start_exe      /* validates MZ header and applies relocations */
    jmp .L_shell_loop_load_error
.L_shell_check_com:
    cmp byte ptr [filename + 8], 'C'
    jne bad_command
    cmp byte ptr [filename + 9], 'O'
    jne bad_command
    cmp byte ptr [filename + 10], 'M'
    jne bad_command
    call find_file
    jnc .L_shell_load_com
    /* DOS searches .COM then .EXE when the command has no suffix. */
    mov si, offset cmdline
.L_shell_find_period:
    lodsb
    test al, al
    jz .L_shell_try_exe
    cmp al, '.'
    je bad_command
    jmp .L_shell_find_period
.L_shell_try_exe:
    mov byte ptr [filename + 8], 'E'
    mov byte ptr [filename + 9], 'X'
    mov byte ptr [filename + 10], 'E'
    call find_file
    jc bad_command
    call load_com
    jc .L_shell_loop_load_error
    call start_exe
    jmp .L_shell_loop_load_error
.L_shell_load_com:
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
 * No paths, spaces, switches or command-line arguments in 0.2.0. */
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

/* MZ loader: bounded one-segment real-mode subset (file <= 65024 bytes).
 * Image from disk is at APP_SEG:0100. Apply relocations IN PLACE while
 * header/table are still available, then slide image over the header.
 * MZ EXEs with larger images/multiple load segments are not supported yet.
 * Returns CF on invalid header, otherwise transfers control and never returns.
 */
start_exe:
    push ds
    mov ax, APP_SEG
    mov es, ax
    cmp word ptr es:[0x100], 0x5a4d
    jne .L_exe_bad
    mov ax, word ptr es:[0x108] /* header paragraphs */
    cmp ax, 2
    jb .L_exe_bad
    cmp ax, 0x0ff0
    ja .L_exe_bad
    mov word ptr cs:[exe_hdrparas], ax
    mov cl, 4
    shl ax, cl
    cmp ax, word ptr cs:[file_size]
    jae .L_exe_bad
    mov word ptr cs:[exe_hdrbytes], ax
    mov bx, word ptr es:[0x118] /* relocation table offset */
    mov cx, word ptr es:[0x106] /* relocation count */
    cmp cx, 512
    ja .L_exe_bad
    mov ax, cx
    shl ax, 1
    shl ax, 1
    add ax, bx
    jc .L_exe_bad
    cmp ax, word ptr cs:[exe_hdrbytes]
    ja .L_exe_bad
    mov ax, word ptr es:[0x10e]
    mov word ptr cs:[exe_ss], ax
    mov ax, word ptr es:[0x110]
    mov word ptr cs:[exe_sp], ax
    mov ax, word ptr es:[0x114]
    mov word ptr cs:[exe_ip], ax
    mov ax, word ptr es:[0x116]
    mov word ptr cs:[exe_cs], ax
    mov word ptr cs:[exe_reloc_remaining], cx
    /* pre-relocate words inside the on-disk image */
.L_exe_reloc_loop:
    test cx, cx
    jz .L_exe_reloc_done
    mov ax, word ptr es:[bx + 2 + 0x100]
    cmp ax, 0x0fff       /* only offsets within 64KiB */
    ja .L_exe_bad
    mov dx, ax
    mov cl, 4
    shl ax, cl
    add ax, word ptr es:[bx + 0x100]
    jc .L_exe_bad
    inc ax
    cmp ax, word ptr cs:[file_size]
    jae .L_exe_bad
    /* ensure relocation word is inside image and not header */
    dec ax
    mov si, word ptr cs:[file_size]
    sub si, word ptr cs:[exe_hdrbytes]
    inc ax
    cmp ax, si
    jae .L_exe_bad
    /* use a separate segment to access relocation target */
    mov ax, APP_SEG + 0x10
    add ax, word ptr cs:[exe_hdrparas]
    add ax, dx
    mov ds, ax
    mov si, word ptr es:[bx + 0x100]
    add word ptr [si], APP_SEG + 0x10
    mov ax, APP_SEG
    mov ds, ax
    add bx, 4
    dec word ptr cs:[exe_reloc_remaining]
    /* CX used as shift count; preserve explicit reloc counter below. */
    mov cx, word ptr cs:[exe_reloc_remaining]
    jmp .L_exe_reloc_loop
.L_exe_reloc_done:
    /* Copy code+data downward into conventional MZ load segment. */
    mov ax, APP_SEG + 0x10
    mov es, ax
    add ax, word ptr cs:[exe_hdrparas]
    mov ds, ax
    xor si, si
    xor di, di
    mov cx, word ptr cs:[file_size]
    sub cx, word ptr cs:[exe_hdrbytes]
    rep movsb
    pop ds
    mov ax, cs
    mov es, ax
    call reset_mcb
    call make_psp
    /* entry CS and SS are relative to EXE load segment */
    mov ax, APP_SEG + 0x10
    add word ptr [exe_cs], ax
    add word ptr [exe_ss], ax
    cli
    mov ax, word ptr [exe_ss]
    mov ss, ax
    mov sp, word ptr [exe_sp]
    sti
    mov ax, APP_SEG
    mov ds, ax
    mov es, ax
    xor ax, ax
    push word ptr cs:[exe_cs]
    push word ptr cs:[exe_ip]
    retf
.L_exe_bad:
    pop ds
    stc
    ret

/* Exactly one MCB covering the current process until AH=4Ah shrinks it.
 * Implementing allocation/free is staged separately from the EXE loader.
 */
reset_mcb:
    push ax
    push cx
    push di
    push es
    mov ax, cs
    mov es, ax
    mov di, offset handles
    mov cx, 48
    xor al, al
    rep stosb
    mov ax, MEM_MCB
    mov es, ax
    mov byte ptr es:[0], 'Z'
    mov word ptr es:[1], APP_SEG
    mov word ptr es:[3], MEM_LIMIT - APP_SEG
    pop es
    pop di
    pop cx
    pop ax
    ret

make_psp:
    push ax
    push cx
    push di
    push es
    mov ax, APP_SEG
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, 128
    rep stosw
    mov byte ptr es:[0], 0xcd
    mov byte ptr es:[1], 0x20
    mov word ptr es:[2], MEM_LIMIT
    mov byte ptr es:[0x80], 0
    mov byte ptr es:[0x81], 13
    pop es
    pop di
    pop cx
    pop ax
    ret

/* Normalize one root-directory 8.3 path supplied as ASCIIZ in ES:SI.
 * Uppercases ASCII and optionally accepts A: or A:\ prefix.
 * No subdirectories (intentional, reported as file not found).
 */
filename_from_es_si:
    push ax
    push bx
    push cx
    push dx
    push di
    mov di, offset filename
    mov cx, 11
    mov al, ' '
    push es
    push cs
    pop es
    rep stosb
    pop es
    xor bx, bx
    cmp byte ptr es:[si + 1], ':'
    jne .L_fn_base
    mov al, byte ptr es:[si]
    and al, 0xdf
    cmp al, 'A'
    jne .L_fn_err
    add si, 2
    cmp byte ptr es:[si], '\'
    je .L_fn_skip_slash
    cmp byte ptr es:[si], '/'
    jne .L_fn_base
.L_fn_skip_slash:
    inc si
.L_fn_base:
    mov al, byte ptr es:[si]
    inc si
    cmp al, 0
    je .L_fn_finish
    cmp al, '.'
    je .L_fn_ext
    cmp al, ' '
    jbe .L_fn_err
    cmp al, '\'
    je .L_fn_err
    cmp al, '/'
    je .L_fn_err
    cmp bx, 8
    jae .L_fn_err
    cmp al, 'a'
    jb .L_fn_store_base
    cmp al, 'z'
    ja .L_fn_store_base
    sub al, 32
.L_fn_store_base:
    mov byte ptr [filename + bx], al
    inc bx
    jmp .L_fn_base
.L_fn_ext:
    xor bx, bx
.L_fn_ext_loop:
    mov al, byte ptr es:[si]
    inc si
    test al, al
    jz .L_fn_finish
    cmp al, ' '
    jbe .L_fn_err
    cmp al, '.'
    je .L_fn_err
    cmp al, '\'
    je .L_fn_err
    cmp al, '/'
    je .L_fn_err
    cmp bx, 3
    jae .L_fn_err
    cmp al, 'a'
    jb .L_fn_store_ext
    cmp al, 'z'
    ja .L_fn_store_ext
    sub al, 32
.L_fn_store_ext:
    mov byte ptr [filename + bx + 8], al
    inc bx
    jmp .L_fn_ext_loop
.L_fn_finish:
    cmp byte ptr [filename], ' '
    je .L_fn_err
    clc
    jmp .L_fn_leave
.L_fn_err:
    stc
.L_fn_leave:
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* BX=handle id (5..8), return BX=handle table address or CF=1. */
locate_handle:
    cmp bx, 5
    jb .L_lh_err
    cmp bx, 8
    ja .L_lh_err
    sub bx, 5
    push ax
    mov ax, 12
    mul bx
    mov bx, ax
    add bx, offset handles
    pop ax
    cmp byte ptr [bx], 1
    jne .L_lh_err
    clc
    ret
.L_lh_err:
    stc
    ret

/* Read a byte from current handle position via cached 512-byte sector.
 * BX = handle entry, AL returned, CF=1 on corrupt FAT/BIOS failure.
 * Position update is owned by caller.
 */
read_file_byte:
    push bx
    push cx
    push dx
    push si
    push es
    mov ax, word ptr [bx + 6]
    mov cl, 7
    shl ax, cl
    mov dx, word ptr [bx + 4]
    mov cl, 9
    shr dx, cl
    or ax, dx            /* absolute sector ordinal within file */
    cmp ax, word ptr [rw_cached_sector]
    je .L_rfb_ready
    mov word ptr [rw_cached_sector], ax
    mov si, ax
    mov dx, word ptr [bx + 2]
.L_rfb_chain:
    cmp dx, 2
    jb .L_rfb_err
    cmp dx, 2784
    ja .L_rfb_err
    test si, si
    jz .L_rfb_sector
    mov ax, dx
    call fat_next
    mov dx, ax
    cmp dx, 0xff8
    jae .L_rfb_err
    dec si
    jmp .L_rfb_chain
.L_rfb_sector:
    mov ax, IO_SEG
    mov es, ax
    xor bx, bx
    mov ax, dx
    add ax, DATA_BIAS
    call read_sector
    jc .L_rfb_err
.L_rfb_ready:
    mov ax, IO_SEG
    mov es, ax
    mov bx, word ptr [rw_handle]
    mov si, word ptr [bx + 4]
    and si, 511
    mov al, byte ptr es:[si]
    clc
    jmp .L_rfb_exit
.L_rfb_err:
    mov word ptr [rw_cached_sector], 0xffff
    stc
.L_rfb_exit:
    pop es
    pop si
    pop dx
    pop cx
    pop bx
    ret

/* Locate a valid allocated MCB by its data segment (BX).
 * Returns ES=MCB segment, CF clear; rejects interior/fictitious addresses.
 */
locate_mcb:
    push ax
    push dx
    mov dx, MEM_MCB
.L_locate_mcb_next:
    mov es, dx
    mov ax, dx
    inc ax
    cmp ax, bx
    je .L_locate_mcb_found
    cmp byte ptr es:[0], 'M'
    jne .L_locate_mcb_bad
    mov ax, word ptr es:[3]
    inc ax
    add dx, ax
    cmp dx, MEM_LIMIT
    jb .L_locate_mcb_next
.L_locate_mcb_bad:
    stc
    jmp .L_locate_mcb_out
.L_locate_mcb_found:
    clc
.L_locate_mcb_out:
    pop dx
    pop ax
    ret

/* Coalesce adjacent free MCBs; preserves all general-purpose registers.
 * Every MCB chain must terminate with type 'Z'. */
merge_free_mcbs:
    push ax
    push bx
    push dx
    push si
    push es
    mov dx, MEM_MCB
.L_merge_loop:
    mov es, dx
    cmp byte ptr es:[0], 'M'
    jne .L_merge_done
    mov bx, word ptr es:[3]
    inc bx
    add bx, dx
    cmp bx, MEM_LIMIT
    jae .L_merge_done
    cmp word ptr es:[1], 0
    jne .L_merge_next
    mov ax, bx
    mov es, ax
    cmp word ptr es:[1], 0
    jne .L_merge_next
    mov si, word ptr es:[3]
    inc si
    mov al, byte ptr es:[0]
    mov es, dx
    add word ptr es:[3], si
    mov byte ptr es:[0], al
    jmp .L_merge_loop
.L_merge_next:
    mov dx, bx
    jmp .L_merge_loop
.L_merge_done:
    pop es
    pop si
    pop dx
    pop bx
    pop ax
    ret

/* Create PSP and execute a real DOS .COM image. Never returns. */
start_com:
    call reset_mcb
    call make_psp
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
    cmp ah, 0x3d
    je .L_dos_open
    cmp ah, 0x3e
    je .L_dos_close
    cmp ah, 0x3f
    je .L_dos_read
    cmp ah, 0x42
    je .L_dos_seek
    cmp ah, 0x48
    je .L_dos_alloc
    cmp ah, 0x49
    je .L_dos_free
    cmp ah, 0x4a
    je .L_dos_resize
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
/* DOS file handle operations. Read-only FAT12 root directory for now.
 * Maximum four file handles (5..8). Standard console handles are separate.
 * AH=3Dh DS:DX ASCIIZ  -> AX handle; AL must be 0 (read-only)
 * AH=3Eh BX           -> close
 * AH=3Fh BX/CX/DS:DX -> AX bytes read, zero at EOF
 * AH=42h AL/BX/CX:DX  -> DX:AX new byte offset.
 * Errors: 2=file not found, 4=too many handles, 5=access denied,
 * 6=invalid handle, 1=invalid seek, 30=read failure.
 */
.L_dos_open:
    test al, 3
    jnz .L_open_denied
    mov ax, word ptr ss:[bp + 14]  /* caller DS */
    mov es, ax
    mov si, word ptr ss:[bp + 6]   /* caller DX */
    call filename_from_es_si
    jc .L_open_not_found
    call find_file
    jc .L_open_not_found
    mov si, offset handles
    mov dx, 5
.L_open_slot:
    cmp byte ptr [si], 0
    je .L_open_found
    add si, 12
    inc dx
    cmp dx, 9
    jb .L_open_slot
    mov ax, 4
    jmp .L_set_error
.L_open_found:
    mov byte ptr [si], 1
    mov ax, word ptr [file_cluster]
    mov word ptr [si + 2], ax
    mov word ptr [si + 4], 0
    mov word ptr [si + 6], 0
    mov ax, word ptr [file_size]
    mov word ptr [si + 8], ax
    mov ax, word ptr [file_size_high]
    mov word ptr [si + 10], ax
    mov ax, dx
    jmp .L_int21_handler_return
.L_open_denied:
    mov ax, 5
    jmp .L_set_error
.L_open_not_found:
    mov ax, 2
    jmp .L_set_error
.L_dos_close:
    mov bx, word ptr ss:[bp + 10]
    call locate_handle
    jc .L_invalid_handle
    mov byte ptr [bx], 0
    xor ax, ax
    jmp .L_int21_handler_return
.L_dos_read:
    mov bx, word ptr ss:[bp + 10]
    call locate_handle
    jc .L_invalid_handle
    mov word ptr [rw_handle], bx
    mov ax, word ptr ss:[bp + 14]
    mov word ptr [rw_dstseg], ax
    mov ax, word ptr ss:[bp + 6]
    mov word ptr [rw_dstoff], ax
    mov ax, word ptr ss:[bp + 8]
    mov word ptr [rw_remaining], ax
    mov word ptr [rw_read], 0
    mov word ptr [rw_cached_sector], 0xffff
.L_read_next:
    cmp word ptr [rw_remaining], 0
    je .L_read_done
    mov bx, word ptr [rw_handle]
    /* EOF if position >= length, unsigned 32-bit compare. */
    mov ax, word ptr [bx + 6]
    cmp ax, word ptr [bx + 10]
    ja .L_read_done
    jb .L_read_get_byte
    mov ax, word ptr [bx + 4]
    cmp ax, word ptr [bx + 8]
    jae .L_read_done
.L_read_get_byte:
    call read_file_byte
    jc .L_read_disk_error
    push es
    mov dx, word ptr [rw_dstseg]
    mov es, dx
    mov di, word ptr [rw_dstoff]
    mov byte ptr es:[di], al
    pop es
    inc word ptr [rw_dstoff]
    inc word ptr [rw_read]
    dec word ptr [rw_remaining]
    add word ptr [bx + 4], 1
    adc word ptr [bx + 6], 0
    jmp .L_read_next
.L_read_done:
    mov ax, word ptr [rw_read]
    jmp .L_int21_handler_return
.L_read_disk_error:
    mov ax, 30
    jmp .L_set_error
.L_dos_seek:
    mov byte ptr [rw_mode], al
    mov bx, word ptr ss:[bp + 10]
    call locate_handle
    jc .L_invalid_handle
    cmp byte ptr [rw_mode], 2
    ja .L_seek_bad
    mov ax, word ptr ss:[bp + 6] /* DX = offset low */
    mov dx, word ptr ss:[bp + 8] /* CX = offset high */
    cmp byte ptr [rw_mode], 0
    je .L_seek_set
    cmp byte ptr [rw_mode], 1
    jne .L_seek_from_end
    add ax, word ptr [bx + 4]
    adc dx, word ptr [bx + 6]
    jc .L_seek_bad
    jmp .L_seek_set
.L_seek_from_end:
    add ax, word ptr [bx + 8]
    adc dx, word ptr [bx + 10]
    jc .L_seek_bad
.L_seek_set:
    test dx, 0x8000    /* disallow negative signed positions */
    jnz .L_seek_bad
    mov word ptr [bx + 4], ax
    mov word ptr [bx + 6], dx
    mov word ptr ss:[bp + 6], dx /* returned DX high word */
    jmp .L_int21_handler_return
.L_seek_bad:
    mov ax, 1
    jmp .L_set_error
.L_invalid_handle:
    mov ax, 6
.L_set_error:
    or word ptr ss:[bp + 20], 1
    jmp .L_int21_handler_return

/* Conventional memory MCB API. This prototype owns one MCB chain
 * in low memory and resets it between shell applications. No TSRs yet.
 * AH=48h: allocate BX paragraphs, AX=segment, failure BX=largest block.
 * AH=49h: release block at ES, AX=9 for invalid block.
 * AH=4Ah: resize ES to BX paragraphs, failure BX=maximum possible.
 */
.L_dos_alloc:
    mov ax, word ptr ss:[bp + 10]
    mov word ptr [mcb_req], ax
    mov word ptr [mcb_largest], 0
    test ax, ax
    jz .L_mem_no_space
    mov dx, MEM_MCB
.L_mem_alloc_scan:
    mov es, dx
    mov al, byte ptr es:[0]
    cmp al, 'M'
    je .L_mem_alloc_type_ok
    cmp al, 'Z'
    jne .L_mem_no_space
.L_mem_alloc_type_ok:
    cmp word ptr es:[1], 0
    jne .L_mem_alloc_next
    mov ax, word ptr es:[3]
    cmp ax, word ptr [mcb_largest]
    jbe .L_mem_alloc_test
    mov word ptr [mcb_largest], ax
.L_mem_alloc_test:
    cmp ax, word ptr [mcb_req]
    jae .L_mem_alloc_fit
.L_mem_alloc_next:
    cmp byte ptr es:[0], 'Z'
    je .L_mem_no_space
    mov ax, word ptr es:[3]
    inc ax
    add dx, ax
    cmp dx, MEM_LIMIT
    jb .L_mem_alloc_scan
    jmp .L_mem_no_space
.L_mem_alloc_fit:
    /* Split if >1 paragraph remains; one is needed for the new MCB. */
    mov ax, word ptr es:[3]
    sub ax, word ptr [mcb_req]
    cmp ax, 1
    jbe .L_mem_alloc_whole
    dec ax
    mov word ptr [mcb_temp_size], ax
    mov al, byte ptr es:[0]
    mov byte ptr [mcb_temp_type], al
    mov ax, dx
    inc ax
    add ax, word ptr [mcb_req]
    push es
    mov es, ax
    mov al, byte ptr [mcb_temp_type]
    mov byte ptr es:[0], al
    mov word ptr es:[1], 0
    mov ax, word ptr [mcb_temp_size]
    mov word ptr es:[3], ax
    pop es
    mov byte ptr es:[0], 'M'
    mov ax, word ptr [mcb_req]
    mov word ptr es:[3], ax
.L_mem_alloc_whole:
    mov word ptr es:[1], APP_SEG
    mov ax, dx
    inc ax
    jmp .L_int21_handler_return
.L_mem_no_space:
    mov ax, word ptr [mcb_largest]
    mov word ptr ss:[bp + 10], ax
    mov ax, 8
    jmp .L_set_error
.L_dos_free:
    mov bx, word ptr ss:[bp + 12] /* caller ES */
    cmp bx, APP_SEG
    je .L_mem_invalid
    call locate_mcb
    jc .L_mem_invalid
    cmp word ptr es:[1], APP_SEG
    jne .L_mem_invalid
    mov word ptr es:[1], 0
    call merge_free_mcbs
    xor ax, ax
    jmp .L_int21_handler_return
.L_dos_resize:
    mov bx, word ptr ss:[bp + 12] /* caller ES */
    call locate_mcb
    jc .L_mem_invalid
    cmp word ptr es:[1], APP_SEG
    jne .L_mem_invalid
    mov ax, word ptr ss:[bp + 10]
    mov word ptr [mcb_req], ax
    mov ax, word ptr es:[3]
    mov word ptr [mcb_largest], ax
    cmp ax, word ptr [mcb_req]
    je .L_mem_resize_ok
    ja .L_mem_resize_shrink
    /* Growing requires an immediately adjacent free MCB. */
    cmp byte ptr es:[0], 'M'
    jne .L_mem_resize_fail
    mov ax, word ptr es:[3]
    add ax, bx
    mov dx, ax           /* BX is DATA segment; next MCB is BX + size */
    push es
    mov es, dx
    cmp word ptr es:[1], 0
    jne .L_mem_grow_no
    mov ax, word ptr es:[3]
    inc ax
    add ax, word ptr [mcb_largest]
    mov word ptr [mcb_largest], ax
    mov al, byte ptr es:[0]
    mov byte ptr [mcb_temp_type], al
    pop es
    mov ax, word ptr [mcb_largest]
    cmp ax, word ptr [mcb_req]
    jb .L_mem_resize_fail
    sub ax, word ptr [mcb_req]
    cmp ax, 1
    jbe .L_mem_grow_all
    /* New trailing free segment with remaining paragraphs. */
    dec ax
    mov word ptr [mcb_temp_size], ax
    mov ax, bx
    add ax, word ptr [mcb_req]
    push es
    mov es, ax
    mov al, byte ptr [mcb_temp_type]
    mov byte ptr es:[0], al
    mov word ptr es:[1], 0
    mov ax, word ptr [mcb_temp_size]
    mov word ptr es:[3], ax
    pop es
    mov byte ptr es:[0], 'M'
    mov ax, word ptr [mcb_req]
    mov word ptr es:[3], ax
    jmp .L_mem_resize_ok
.L_mem_grow_all:
    mov al, byte ptr [mcb_temp_type]
    mov byte ptr es:[0], al
    mov ax, word ptr [mcb_largest]
    mov word ptr es:[3], ax
    jmp .L_mem_resize_ok
.L_mem_grow_no:
    pop es
    jmp .L_mem_resize_fail
.L_mem_resize_shrink:
    /* Leave one paragraph for the new MCB if possible. */
    mov ax, word ptr es:[3]
    sub ax, word ptr [mcb_req]
    cmp ax, 1
    jbe .L_mem_resize_ok
    dec ax
    mov word ptr [mcb_temp_size], ax
    mov al, byte ptr es:[0]
    mov byte ptr [mcb_temp_type], al
    mov ax, bx
    add ax, word ptr [mcb_req]
    push es
    mov es, ax
    mov al, byte ptr [mcb_temp_type]
    mov byte ptr es:[0], al
    mov word ptr es:[1], 0
    mov ax, word ptr [mcb_temp_size]
    mov word ptr es:[3], ax
    pop es
    mov byte ptr es:[0], 'M'
    mov ax, word ptr [mcb_req]
    mov word ptr es:[3], ax
    call merge_free_mcbs
.L_mem_resize_ok:
    xor ax, ax
    jmp .L_int21_handler_return
.L_mem_resize_fail:
    mov ax, word ptr [mcb_largest]
    mov word ptr ss:[bp + 10], ax
    mov ax, 8
    jmp .L_set_error
.L_mem_invalid:
    mov ax, 9
    jmp .L_set_error

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
mcb_req:           .word 0
mcb_largest:       .word 0
mcb_temp_size:     .word 0
mcb_temp_type:     .byte 0
.align 2
rw_handle:         .word 0
rw_dstseg:         .word 0
rw_dstoff:         .word 0
rw_remaining:      .word 0
rw_read:           .word 0
rw_cached_sector:  .word 0xffff
rw_mode:           .byte 0
.align 2
handles:           .space 48  /* 4 x 12-byte read-only handle records */
exe_hdrparas:      .word 0
exe_hdrbytes:       .word 0
exe_reloc_remaining:.word 0
exe_cs:            .word 0
exe_ip:            .word 0
exe_ss:            .word 0
exe_sp:            .word 0
boot_drive:         .byte 0
file_cluster:       .word 0
file_size:          .word 0
file_size_high:     .word 0
filename:           .space 11
cmdline:            .space 64
banner:             .asciz "\r\nVelvetDOS 0.2.0  [pre-alpha]\r\nGNU GPLv3 | Type HELP for commands.\r\n"
prompt:             .asciz "\r\nA:\\>"
cmd_help:           .asciz "HELP"
cmd_dir:            .asciz "DIR"
cmd_ver:            .asciz "VER"
cmd_cls:            .asciz "CLS"
cmd_reboot:         .asciz "REBOOT"
help_text:          .asciz "Commands: HELP, DIR, VER, CLS, REBOOT\r\nRun root .COM or small MZ .EXE programs by name.\r\nOnly read-only FAT12 and a subset of INT 21h work.\r\n"
dir_header:         .asciz "Root directory:\r\n"
bad_command_message:.asciz "Bad command or file name.\r\n"
load_error_message: .asciz "Unable to load DOS program (format, size or disk error).\r\n"
disk_error_message: .asciz "FATAL: Cannot read floppy disk.\r\n"
.align 2
stack_start: .space 2048
stack_end:
