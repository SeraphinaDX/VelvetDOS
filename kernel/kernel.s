/* VelvetDOS 0.11.0 -- experimental 16-bit DOS-compatible kernel.
 * SPDX-License-Identifier: GPL-3.0-only
 * Linked at offset 0, loaded by the boot sector at physical 0x10000.
 * FAT12 root and bounded multi-cluster directories (8.3); one resident shell
 * with a single non-nesting COM or bounded MZ EXE child, no multi-tasking.
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
.equ DIR_SEG,        0x2600
.equ MEM_LIMIT,      0x9000
.equ MEM_MCB,        0x2fff
.equ APP_SEG,        0x3000
.equ CHILD_SEG,      0x5000  /* first available child segment */
.equ CHILD_MCB,      0x4fff
.equ CHILD_PARAS,    0x1100  /* 68 KiB incl. MZ load segment and near-64K SP */
.equ ENV_SEG,        0x2a00  /* resident shell environment */
.equ CHILD_ENV_SEG,  0x2b00  /* bounded 256-byte child environment staging */
.equ ROOT_SECTOR,    83
.equ FAT_SECTOR,     65
.equ ROOT_ENTRIES,   224
.equ MAX_DIR_CLUSTERS, 8 /* DIR_SEG holds eight 512-byte clusters */
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
    cld
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
    mov word ptr [dta_seg], 0
    mov word ptr [dta_off], offset kernel_dta
    call load_tables
    call init_environment
    mov si, offset banner
    call print_z
    /* Boot the DOS command interpreter as a genuine resident .COM process.
     * The former embedded shell remains an emergency recovery prompt. */
    mov word ptr [dir_parent_cluster], 0
    mov si, offset command_filename
    mov di, offset filename
    mov cx, 11
    rep movsb
    call find_file
    jc shell_start_failed
    test byte ptr [file_attributes], 0x10
    jnz shell_start_failed
    call load_com
    jc shell_start_failed
    mov byte ptr [cmdtail_len], 0
    call start_com
shell_start_failed:
    mov si, offset shell_failed_message
    call print_z
shell_loop:
    mov ax, cs
    mov word ptr [dta_seg], ax
    mov word ptr [dta_off], offset kernel_dta
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, offset stack_end
    mov si, offset prompt
    call print_z
    mov si, offset cwd_text
    call print_z
    mov al, '>'
    call putc
    call read_line
    call uppercase_command_token
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
    mov di, offset cmd_status
    call str_eq
    jc do_status
    mov si, offset cmdline
    mov di, offset cmd_reboot
    call str_eq
    jc do_reboot
    /* The prototype shell accepts one directory path after CD/MD/RD. */
    mov si, offset cmdline
    cmp word ptr [si], 0x4443   /* CD */
    jne .L_shell_check_md
    cmp byte ptr [si + 2], ' '
    jne .L_shell_check_md
    add si, 3
    mov ax, cs
    mov es, ax
    call dos_chdir
    jc shell_dir_error
    jmp shell_loop
.L_shell_check_md:
    mov si, offset cmdline
    cmp word ptr [si], 0x444d   /* MD */
    jne .L_shell_check_rd
    cmp byte ptr [si + 2], ' '
    jne .L_shell_check_rd
    add si, 3
    mov ax, cs
    mov es, ax
    call dos_mkdir
    jc shell_dir_error
    jmp shell_loop
.L_shell_check_rd:
    mov si, offset cmdline
    cmp word ptr [si], 0x4452   /* RD */
    jne .L_shell_no_directory_cmd
    cmp byte ptr [si + 2], ' '
    jne .L_shell_no_directory_cmd
    add si, 3
    mov ax, cs
    mov es, ax
    call dos_rmdir
    jc shell_dir_error
    jmp shell_loop
.L_shell_no_directory_cmd:
    /* Strip the executable token, keep the exact case and spacing of its tail. */
    call split_external_command
    mov ax, word ptr [cwd_cluster]
    mov word ptr [dir_parent_cluster], ax
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
    test byte ptr [file_attributes], 0x10
    jnz bad_command
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
    test byte ptr [file_attributes], 0x10
    jnz bad_command
    call load_com
    jc .L_shell_loop_load_error
    call start_exe
    jmp .L_shell_loop_load_error
.L_shell_load_com:
    test byte ptr [file_attributes], 0x10
    jnz bad_command
    call load_com
    jc .L_shell_loop_load_error
    call start_com     /* does not return; app returns through INT 20h/21h */
.L_shell_loop_load_error:
    mov si, offset load_error_message
    call print_z
    jmp shell_loop
shell_dir_error:
    mov si, offset dir_error_message
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

do_status:
    mov si, offset status_message
    call print_z
    mov al, byte ptr [last_exit_code]
    call print_hex_byte
    call newline
    jmp shell_loop

do_dir:
    mov si, offset dir_header
    call print_z
    mov ax, word ptr [cwd_cluster]
    mov word ptr [dir_parent_cluster], ax
    call select_directory
    jc shell_dir_error
    xor di, di
.L_do_dir_next:
    cmp byte ptr es:[di], 0
    je .L_do_dir_done
    cmp byte ptr es:[di], 0xe5
    je .L_do_dir_skip
    mov al, byte ptr es:[di + 11]
    test al, 0x08           /* volume label */
    jnz .L_do_dir_skip
    cmp al, 0x0f
    je .L_do_dir_skip
    cmp byte ptr es:[di], '.'
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
    test byte ptr es:[di + 11], 0x10
    jz .L_do_dir_newline
    mov si, offset dir_marker
    call print_z
.L_do_dir_newline:
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

/* Print a byte in hexadecimal without relying on DOS itself. */
print_hex_byte:
    push ax
    push bx
    mov bl, al
    mov cl, 4
    shr al, cl
    call print_hex_nibble
    mov al, bl
    and al, 0x0f
    call print_hex_nibble
    pop bx
    pop ax
    ret
print_hex_nibble:
    and al, 0x0f
    cmp al, 10
    jb .L_hex_digit
    add al, 'A' - 10
    jmp .L_hex_print
.L_hex_digit:
    add al, '0'
.L_hex_print:
    call putc
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
    cmp bx, 120
    jae .L_read_line_key
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

/* Normalize only the command token: argument strings must retain their case.
 * Keep original spacing after the first whitespace until PSP copy. */
uppercase_command_token:
    push ax
    push si
    mov si, offset cmdline
.L_upper_next:
    mov al, byte ptr [si]
    test al, al
    jz .L_upper_end
    cmp al, ' '
    je .L_upper_end
    cmp al, 'a'
    jb .L_upper_step
    cmp al, 'z'
    ja .L_upper_step
    sub al, 32
    mov byte ptr [si], al
.L_upper_step:
    inc si
    jmp .L_upper_next
.L_upper_end:
    pop si
    pop ax
    ret

/* Extract the original DOS command tail including its leading space.
 * cmdline becomes the ASCIIZ program token used by 8.3 lookup. */
split_external_command:
    push ax
    push cx
    push si
    push di
    mov byte ptr [cmdtail_len], 0
    mov si, offset cmdline
.L_split_seek:
    mov al, byte ptr [si]
    test al, al
    jz .L_split_done
    cmp al, ' '
    je .L_split_copy
    inc si
    jmp .L_split_seek
.L_split_copy:
    mov di, offset cmdtail
    xor cx, cx
.L_split_loop:
    mov al, byte ptr [si]
    test al, al
    jz .L_split_end
    cmp cx, 126
    jae .L_split_end
    mov byte ptr [di], al
    inc di
    inc si
    inc cx
    jmp .L_split_loop
.L_split_end:
    mov byte ptr [cmdtail_len], cl
    mov byte ptr [di], 0
    /* Terminate program token at the first space, not at the tail end. */
    mov si, offset cmdline
.L_split_rewind:
    cmp byte ptr [si], ' '
    je .L_split_nul
    inc si
    jmp .L_split_rewind
.L_split_nul:
    mov byte ptr [si], 0
.L_split_done:
    pop di
    pop si
    pop cx
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
 * Shell commands still omit paths, spaces, switches or argument tails. */
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
    mov cx, ax
    mov cl, 9
    shr ax, cl
    mov bx, word ptr [file_size]
    and bx, 511
    jz .L_load_com_sector_count
    inc ax
.L_load_com_sector_count:
    mov cx, ax
    mov dx, word ptr [file_cluster]
    mov ax, word ptr [exec_load_segment]
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

/* Initial resident COMMAND.COM owns the first block (3000h..4FFEh).
 * The remaining conventional memory starts as an unowned free MCB.
 * Never reinitialize this MCB chain during child EXEC/termination.
 */
reset_mcb:
    push ax
    push cx
    push di
    push es
    mov ax, cs
    mov es, ax
    mov di, offset handles
    mov cx, 64
    xor al, al
    rep stosb
    mov di, offset handle_refs
    mov cx, 4
    rep stosb
    mov word ptr [rw_cached_sector], 0xffff
    mov byte ptr [rw_cache_dirty], 0
    mov ax, MEM_MCB
    mov es, ax
    mov byte ptr es:[0], 'M'
    mov word ptr es:[1], APP_SEG
    mov word ptr es:[3], CHILD_MCB - APP_SEG
    mov ax, CHILD_MCB
    mov es, ax
    mov byte ptr es:[0], 'Z'
    mov word ptr es:[1], 0
    mov word ptr es:[3], MEM_LIMIT - CHILD_SEG
    pop es
    pop di
    pop cx
    pop ax
    ret

/* A basic static DOS 3.x-style environment. All programs see the same
 * read-only variables; AH=4B EXEC and SET remain future work. This memory
 * lives below the DOS application MCB and must not be freed with AH=49. */
init_environment:
    push ax
    push cx
    push si
    push di
    push es
    mov ax, ENV_SEG
    mov es, ax
    xor di, di
    mov si, offset environment_template
    mov cx, environment_end - environment_template
    rep movsb
    pop es
    pop di
    pop si
    pop cx
    pop ax
    ret

/* Establish the single-process PSP for .COM and small MZ .EXE programs.
 * DTA defaults to PSP:80h. Reserved fields are zeroed; no shell PSP yet. */
make_psp:
    push ax
    push bx
    push cx
    push si
    push di
    push es
    mov ax, word ptr [current_psp]
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, 128
    rep stosw
    mov byte ptr es:[0], 0xcd
    mov byte ptr es:[1], 0x20
    /* PSP:2 is the exclusive end of this program's OWN allocation. */
    mov ax, word ptr [current_psp]
    dec ax
    mov es, ax
    mov bx, word ptr es:[3]
    mov ax, word ptr [current_psp]
    add bx, ax
    mov es, ax
    mov word ptr es:[2], bx
    /* Expose terminate, Ctrl-Break and critical-error IVT vectors. */
    xor ax, ax
    mov es, ax
    mov ax, word ptr es:[0x22 * 4]
    mov bx, word ptr es:[0x22 * 4 + 2]
    mov cx, word ptr [current_psp]
    mov es, cx
    mov word ptr es:[0x0a], ax
    mov word ptr es:[0x0c], bx
    xor ax, ax
    mov es, ax
    mov ax, word ptr es:[0x23 * 4]
    mov bx, word ptr es:[0x23 * 4 + 2]
    mov cx, word ptr [current_psp]
    mov es, cx
    mov word ptr es:[0x0e], ax
    mov word ptr es:[0x10], bx
    xor ax, ax
    mov es, ax
    mov ax, word ptr es:[0x24 * 4]
    mov bx, word ptr es:[0x24 * 4 + 2]
    mov cx, word ptr [current_psp]
    mov es, cx
    mov word ptr es:[0x12], ax
    mov word ptr es:[0x14], bx
    /* Conventional PSP parent pointer: zero for primary shell. */
    mov ax, word ptr [psp_parent]
    mov word ptr es:[0x16], ax
    mov ax, word ptr [current_env_seg]
    mov word ptr es:[0x2c], ax
    /* Standard inherited handle table (0..4; 5..19 unused). */
    mov di, 0x18
    mov cx, 20
    mov al, 0xff
    rep stosb
    mov byte ptr es:[0x18], 0
    mov byte ptr es:[0x19], 1
    mov byte ptr es:[0x1a], 2
    mov byte ptr es:[0x1b], 3
    mov byte ptr es:[0x1c], 4
    /* Two 8.3 default FCB slots; no filename-to-FCB translation yet. */
    mov di, 0x5d
    mov al, ' '
    mov cx, 11
    rep stosb
    mov di, 0x6d
    mov cx, 11
    rep stosb
    /* PSP:80h has length, PSP:81h contains bytes, then CR. */
    mov al, byte ptr [cmdtail_len]
    mov byte ptr es:[0x80], al
    xor ch, ch
    mov cl, al
    mov si, offset cmdtail
    mov di, 0x81
    rep movsb
    mov byte ptr es:[di], 13
    mov ax, word ptr [current_psp]
    mov word ptr [dta_seg], ax
    mov word ptr [dta_off], 0x80
    pop es
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

/* Resolve an ASCIIZ DOS 8.3 path at ES:SI.
 * dir_parent_cluster = directory holding final name (0 is FAT root).
 * filename = final 11-byte name, path_directory_only=1 for a path
 * resolving directly to a directory (root, ".", or "..").
 * A maximum of eight nested directory levels is supported in 0.4.0.
 * dir_path_stack holds the cluster at each traversed level.
 */
filename_from_es_si:
    push ax
    push bx
    push cx
    push dx
    push di
    mov byte ptr [path_directory_only], 0
    mov al, byte ptr [cwd_depth]
    mov byte ptr [path_depth], al
    mov cx, 8
    mov di, offset cwd_stack
    mov bx, offset path_stack
.L_path_copy_stack:
    mov ax, word ptr [di]
    mov word ptr [bx], ax
    add di, 2
    add bx, 2
    loop .L_path_copy_stack
    mov ax, word ptr [cwd_cluster]
    mov word ptr [dir_parent_cluster], ax
    cmp byte ptr es:[si + 1], ':'
    jne .L_path_absolute
    mov al, byte ptr es:[si]
    and al, 0xdf
    cmp al, 'A'
    jne .L_path_fail
    add si, 2
.L_path_absolute:
    mov al, byte ptr es:[si]
    cmp al, 0x5c  /* ASCII backslash; GAS char-literal form misassembles */
    je .L_path_root
    cmp al, '/'
    jne .L_path_component
.L_path_root:
    mov word ptr [dir_parent_cluster], 0
    mov byte ptr [path_depth], 0
    inc si
.L_path_component:
    cmp byte ptr es:[si], 0
    jne .L_path_dot
    mov byte ptr [path_directory_only], 1
    clc
    jmp .L_path_exit
.L_path_dot:
    cmp byte ptr es:[si], '.'
    jne .L_path_normal
    mov al, byte ptr es:[si + 1]
    cmp al, 0
    je .L_path_dot_one_end
    cmp al, 0x5c  /* ASCII backslash; GAS char-literal form misassembles */
    je .L_path_dot_one_sep
    cmp al, '/'
    je .L_path_dot_one_sep
    cmp al, '.'
    jne .L_path_normal
    mov al, byte ptr es:[si + 2]
    cmp al, 0
    je .L_path_dot_two_end
    cmp al, 0x5c  /* ASCII backslash; GAS char-literal form misassembles */
    je .L_path_dot_two_sep
    cmp al, '/'
    jne .L_path_normal
.L_path_dot_two_sep:
    add si, 3
    jmp .L_path_pop_parent
.L_path_dot_two_end:
    add si, 2
    jmp .L_path_pop_parent
.L_path_dot_one_sep:
    add si, 2
    jmp .L_path_component
.L_path_dot_one_end:
    inc si
    jmp .L_path_component
.L_path_pop_parent:
    cmp byte ptr [path_depth], 0
    je .L_path_component
    dec byte ptr [path_depth]
    mov bl, byte ptr [path_depth]
    xor bh, bh
    shl bx, 1
    cmp bx, 0
    jne .L_path_parent_nonroot
    mov word ptr [dir_parent_cluster], 0
    jmp .L_path_component
.L_path_parent_nonroot:
    mov ax, word ptr [path_stack + bx - 2]
    mov word ptr [dir_parent_cluster], ax
    jmp .L_path_component
.L_path_normal:
    /* Decode a single 8.3 component in the kernel data segment. */
    push es
    push cs
    pop es
    mov di, offset filename
    mov cx, 11
    mov al, ' '
    rep stosb
    pop es
    xor bx, bx
    xor dx, dx           /* DL=extension length, DH=in extension */
.L_path_char:
    mov al, byte ptr es:[si]
    test al, al
    jz .L_path_final
    cmp al, 0x5c  /* ASCII backslash; GAS char-literal form misassembles */
    je .L_path_descend
    cmp al, '/'
    je .L_path_descend
    cmp al, '.'
    jne .L_path_char_plain
    test dh, dh
    jnz .L_path_fail
    mov dh, 1
    inc si
    jmp .L_path_char
.L_path_char_plain:
    cmp al, ' '
    jbe .L_path_fail
    cmp al, ':'
    je .L_path_fail
    cmp al, 'a'
    jb .L_path_case_done
    cmp al, 'z'
    ja .L_path_case_done
    sub al, 32
.L_path_case_done:
    test dh, dh
    jnz .L_path_extension
    cmp bx, 8
    jae .L_path_fail
    mov byte ptr [filename + bx], al
    inc bx
    inc si
    jmp .L_path_char
.L_path_extension:
    cmp dl, 3
    jae .L_path_fail
    push bx
    xor bh, bh
    mov bl, dl
    mov byte ptr [filename + bx + 8], al
    pop bx
    inc dl
    inc si
    jmp .L_path_char
.L_path_descend:
    cmp byte ptr [filename], ' '
    je .L_path_fail
    /* Every nonterminal component must name a real subdirectory. */
    call find_directory
    jc .L_path_fail
    cmp byte ptr [path_depth], 8
    jae .L_path_fail
    mov bl, byte ptr [path_depth]
    xor bh, bh
    shl bx, 1
    mov ax, word ptr [file_cluster]
    mov word ptr [path_stack + bx], ax
    mov word ptr [dir_parent_cluster], ax
    inc byte ptr [path_depth]
    inc si
    jmp .L_path_component
.L_path_final:
    cmp byte ptr [filename], ' '
    je .L_path_fail
    clc
    jmp .L_path_exit
.L_path_fail:
    stc
.L_path_exit:
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* Load the entire selected directory into a contiguous buffer.
 * ES:0000 = first 32-byte entry, CX = count of available entries.
 * Root stays in ROOT_SEG; subdirectories span up to eight FAT12 clusters
 * loaded consecutively into DIR_SEG (4 KiB). Larger chains are rejected,
 * not silently truncated. Preserve AX/BX/DX/SI/DI; return CF on error.
 * A whole-directory buffer keeps DOS entry offsets stable for open handles.
 */
select_directory:
    push ax
    push bx
    push dx
    push si
    mov word ptr [dir_cluster_count], 0
    mov word ptr [dir_last_cluster], 0
    mov ax, word ptr [dir_parent_cluster]
    test ax, ax
    jnz .L_sd_subdir
    mov ax, ROOT_SEG
    mov es, ax
    mov cx, ROOT_ENTRIES
    clc
    jmp .L_sd_exit
.L_sd_subdir:
    mov dx, ax
    mov ax, DIR_SEG
    mov es, ax
    xor bx, bx
.L_sd_load:
    cmp dx, 2
    jb .L_sd_error
    cmp dx, 2784
    ja .L_sd_error
    mov word ptr [dir_last_cluster], dx
    mov ax, dx
    add ax, DATA_BIAS
    call read_sector
    jc .L_sd_error
    add bx, 512
    inc word ptr [dir_cluster_count]
    mov ax, dx
    call fat_next
    cmp ax, 0x0ff8
    jae .L_sd_loaded
    cmp word ptr [dir_cluster_count], MAX_DIR_CLUSTERS
    jae .L_sd_error
    mov dx, ax
    jmp .L_sd_load
.L_sd_loaded:
    mov cx, word ptr [dir_cluster_count]
    shl cx, 1
    shl cx, 1
    shl cx, 1
    shl cx, 1                 /* 16 directory entries per sector */
    clc
    jmp .L_sd_exit
.L_sd_error:
    stc
.L_sd_exit:
    pop si
    pop dx
    pop bx
    pop ax
    ret

/* Commit all sectors in the selected directory (not merely cluster #1).
 * ES:BX points at DIR_SEG, which must contain the selected directory data.
 * Preserve all general registers except flags; limit traversal to 8 links. */
flush_directory:
    push ax
    push bx
    push cx
    push dx
    push es
    mov dx, word ptr [dir_parent_cluster]
    test dx, dx
    jnz .L_fd_subdir
    mov byte ptr [fs_dirty], 1
    clc
    jmp .L_fd_done
.L_fd_subdir:
    mov ax, DIR_SEG
    mov es, ax
    xor bx, bx
    mov cx, MAX_DIR_CLUSTERS
.L_fd_loop:
    cmp dx, 2
    jb .L_fd_error
    cmp dx, 2784
    ja .L_fd_error
    mov ax, dx
    add ax, DATA_BIAS
    call write_sector
    jc .L_fd_error
    add bx, 512
    mov ax, dx
    call fat_next
    cmp ax, 0x0ff8
    jae .L_fd_ok
    mov dx, ax
    loop .L_fd_loop
.L_fd_error:
    stc
    jmp .L_fd_done
.L_fd_ok:
    clc
.L_fd_done:
    pop es
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* Lookup any matching file or directory; reject volume/LFN entries. */
find_file:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    call select_directory
    jc .L_find_file_not_found
    xor di, di
.L_find_file_entry:
    cmp byte ptr es:[di], 0
    je .L_find_file_not_found
    cmp byte ptr es:[di], 0xe5
    je .L_find_file_next
    mov al, byte ptr es:[di + 11]
    test al, 0x08
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
    mov word ptr [file_dir_offset], di
    mov al, byte ptr es:[di + 11]
    mov byte ptr [file_attributes], al
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

find_directory:
    call find_file
    jc .L_fdir_leave
    test byte ptr [file_attributes], 0x10
    jnz .L_fdir_leave
    stc
.L_fdir_leave:
    ret

/* BX=per-process handle (5..8); validate the PSP JFT before accessing the
 * shared kernel file record. Inherited handles share their file position.
 * Preserve AX and ES; BX becomes a pointer to the kernel record. */
locate_handle:
    cmp bx, 5
    jb .L_lh_err
    cmp bx, 8
    ja .L_lh_err
    push ax
    push es
    mov ax, word ptr [current_psp]
    mov es, ax
    cmp byte ptr es:[bx + 0x18], bl
    jne .L_lh_inactive
    pop es
    pop ax
    sub bx, 5
    push ax
    mov ax, 16
    mul bx
    mov bx, ax
    add bx, offset handles
    pop ax
    cmp byte ptr [bx], 1
    jne .L_lh_err
    clc
    ret
.L_lh_inactive:
    pop es
    pop ax
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

/* AH=4B reserves an actual free 68-KiB process MCB before loading.
 * Returns AX=new PSP, CF clear; CF set for no suitable block. The
 * original shell and any allocations made by the shell remain untouched.
 * Split off a trailing free MCB when there is enough room for its header.
 * Uses the same first-fit policy as AH=48h, with bounded traversal. */
reserve_exec_block:
    push bx
    push cx
    push dx
    push es
    mov dx, MEM_MCB
.L_reserve_scan:
    mov es, dx
    mov al, byte ptr es:[0]
    cmp al, 'M'
    je .L_reserve_type_ok
    cmp al, 'Z'
    jne .L_reserve_fail
.L_reserve_type_ok:
    cmp word ptr es:[1], 0
    jne .L_reserve_next
    mov ax, word ptr es:[3]
    cmp ax, CHILD_PARAS
    jb .L_reserve_next
    /* Original free header is at DX; allocation data begins at DX+1. */
    mov cx, CHILD_PARAS
    sub ax, cx
    cmp ax, 1
    jbe .L_reserve_whole
    /* A new free MCB is located immediately after the child allocation. */
    dec ax
    mov bx, ax                /* remainder after the new header */
    mov ax, dx
    add ax, CHILD_PARAS + 1
    /* ES is already saved on entry; another PUSH here corrupts RET. */
    mov es, ax
    mov word ptr es:[1], 0
    mov word ptr es:[3], bx
    mov ax, dx
    mov es, ax
    mov bl, byte ptr es:[0]
    push es
    mov ax, dx
    add ax, CHILD_PARAS + 1
    mov es, ax
    mov byte ptr es:[0], bl
    pop es
    mov byte ptr es:[0], 'M'
    mov word ptr es:[3], CHILD_PARAS
.L_reserve_whole:
    mov ax, dx
    inc ax
    mov word ptr es:[1], ax  /* DOS owner of process block = own PSP */
    clc
    jmp .L_reserve_done
.L_reserve_next:
    cmp byte ptr es:[0], 'Z'
    je .L_reserve_fail
    mov ax, word ptr es:[3]
    inc ax
    add dx, ax
    cmp dx, MEM_LIMIT
    jb .L_reserve_scan
.L_reserve_fail:
    stc
.L_reserve_done:
    pop es
    pop dx
    pop cx
    pop bx
    ret

/* Free all blocks owned by AX and coalesce the adjacent unowned blocks.
 * Ownership, not a guessed block address, determines what is released.
 * Called on normal child termination and on failed image preparation. */
release_process_blocks:
    push ax
    push bx
    push dx
    push es
    mov bx, ax
    mov dx, MEM_MCB
.L_release_scan:
    mov es, dx
    mov al, byte ptr es:[0]
    cmp al, 'M'
    je .L_release_valid
    cmp al, 'Z'
    jne .L_release_finish
.L_release_valid:
    cmp word ptr es:[1], bx
    jne .L_release_next
    mov word ptr es:[1], 0
.L_release_next:
    cmp byte ptr es:[0], 'Z'
    je .L_release_finish
    mov ax, word ptr es:[3]
    inc ax
    add dx, ax
    cmp dx, MEM_LIMIT
    jb .L_release_scan
.L_release_finish:
    call merge_free_mcbs
    pop es
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

/* Copy parent's four file JFT slots to child and increase reference counts.
 * Std handles 0..4 are initialized by make_psp. An inherited close does not
 * invalidate the parent's copy of the same DOS file handle. */
inherit_child_handles:
    push ax
    push bx
    push si
    push ds
    push es
    mov ax, APP_SEG
    mov ds, ax
    mov ax, word ptr cs:[exec_load_segment]
    mov es, ax
    mov bx, 5
.L_ich_next:
    mov al, byte ptr [bx + 0x18]
    cmp al, 0xff
    je .L_ich_skip
    mov byte ptr es:[bx + 0x18], al
    mov si, bx
    sub si, 5
    inc byte ptr cs:[handle_refs + si]
.L_ich_skip:
    inc bx
    cmp bx, 9
    jb .L_ich_next
    pop es
    pop ds
    pop si
    pop bx
    pop ax
    ret

/* Copy at most 256 bytes of the requested parent environment into an
 * independent child staging segment. Reject unterminated environments to
 * avoid silently changing the child's variable strings. */
copy_child_environment:
    push ax
    push bx
    push cx
    push si
    push di
    push ds
    push es
    mov ax, word ptr [exec_env_source]
    test ax, ax
    jnz .L_ce_source
    mov ax, APP_SEG
    mov es, ax
    mov ax, word ptr es:[0x2c]
.L_ce_source:
    test ax, ax
    jz .L_ce_fail
    mov ds, ax
    mov ax, CHILD_ENV_SEG
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 256
    rep movsb
    xor si, si
    mov cx, 255
.L_ce_scan:
    cmp byte ptr es:[si], 0
    jne .L_ce_next
    cmp byte ptr es:[si + 1], 0
    je .L_ce_ok
.L_ce_next:
    inc si
    loop .L_ce_scan
.L_ce_fail:
    stc
    jmp .L_ce_done
.L_ce_ok:
    clc
.L_ce_done:
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

/* Software INT 20h process exit. App stack is discarded. */
int20_handler:
    mov byte ptr cs:[last_exit_code], 0
process_exit:
    cli
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, offset stack_end
    sti
    call close_all_handles
    cmp byte ptr [exec_active], 0
    je .L_exit_to_recovery_shell
    /* Restore parent without altering any parent-owned memory blocks.
     * Release only the exiting child's PSP and AH=48h allocations. */
    mov ax, word ptr [current_psp]
    call release_process_blocks
    mov word ptr [current_psp], APP_SEG
    mov word ptr [exec_load_segment], APP_SEG
    mov word ptr [psp_parent], 0
    mov word ptr [current_env_seg], ENV_SEG
    mov byte ptr [exec_active], 0
    mov ax, word ptr [exec_parent_dta_seg]
    mov word ptr [dta_seg], ax
    mov ax, word ptr [exec_parent_dta_off]
    mov word ptr [dta_off], ax
    mov ax, word ptr [exec_parent_ss]
    mov bx, word ptr [exec_parent_sp]
    cli
    mov ss, ax
    mov sp, bx
    mov bp, bx
    xor ax, ax
    jmp .L_int21_handler_return
.L_exit_to_recovery_shell:
    jmp shell_loop

/* Minimal, deliberate subset of MS-DOS INT 21h. Unimplemented AH -> CF, AX=1.
 * Saves user DS, ES, BX, CX, DX, SI, DI, BP. Return AX stays live.
 * Stack offsets at BP: DI=2 SI=4 DX=6 CX=8 BX=10 ES=12 DS=14 FLAGS=20.
 */
int21_handler:
    cmp ah, 0x4c
    jne .L_int21_not_exit
    mov byte ptr cs:[last_exit_code], al
    jmp process_exit
.L_int21_not_exit:
    push ds
    push es
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov bp, sp
    cld  /* kernel string instructions require forward direction; IRET restores caller FLAGS */
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
    cmp ah, 0x1a
    je .L_dos_set_dta
    cmp ah, 0x2f
    je .L_dos_get_dta
    cmp ah, 0x36
    je .L_dos_diskfree
    cmp ah, 0x43
    je .L_dos_attributes
    cmp ah, 0x4e
    je .L_dos_findfirst
    cmp ah, 0x4f
    je .L_dos_findnext
    cmp ah, 0x57
    je .L_dos_timestamp
    cmp ah, 0x39
    je .L_dos_mkdir
    cmp ah, 0x3a
    je .L_dos_rmdir
    cmp ah, 0x3b
    je .L_dos_chdir
    cmp ah, 0x47
    je .L_dos_getcwd
    cmp ah, 0x3c
    je .L_dos_create
    cmp ah, 0x3d
    je .L_dos_open
    cmp ah, 0x3e
    je .L_dos_close
    cmp ah, 0x3f
    je .L_dos_read
    cmp ah, 0x41
    je .L_dos_delete
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
    cmp ah, 0x4b
    je .L_dos_exec
    cmp ah, 0x4d
    je .L_int21_handler_return_code
    cmp ah, 0x51
    je .L_dos_get_psp
    cmp ah, 0x62
    je .L_dos_get_psp
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
/* Directory syscall wrappers: DS:DX input, DS:SI output for AH=47h. */
.L_dos_mkdir:
    mov ax, word ptr ss:[bp + 14]
    mov es, ax
    mov si, word ptr ss:[bp + 6]
    call dos_mkdir
    jc .L_set_error
    xor ax, ax
    jmp .L_int21_handler_return
.L_dos_rmdir:
    mov ax, word ptr ss:[bp + 14]
    mov es, ax
    mov si, word ptr ss:[bp + 6]
    call dos_rmdir
    jc .L_set_error
    xor ax, ax
    jmp .L_int21_handler_return
.L_dos_chdir:
    mov ax, word ptr ss:[bp + 14]
    mov es, ax
    mov si, word ptr ss:[bp + 6]
    call dos_chdir
    jc .L_set_error
    xor ax, ax
    jmp .L_int21_handler_return
.L_dos_getcwd:
    mov al, byte ptr ss:[bp + 6] /* DL drive number: 0=current, 1=A: */
    cmp al, 1
    ja .L_getcwd_bad
    /* DOS callers typically allocate a 64-byte buffer for AH=47h. */
    mov si, offset cwd_text
    mov cx, 64
.L_getcwd_length:
    cmp byte ptr [si], 0
    je .L_getcwd_length_ok
    inc si
    loop .L_getcwd_length
    mov ax, 3
    jmp .L_set_error
.L_getcwd_length_ok:
    mov ax, word ptr ss:[bp + 14]
    mov es, ax
    mov di, word ptr ss:[bp + 4]
    mov si, offset cwd_text
.L_getcwd_copy:
    mov al, byte ptr [si]
    mov byte ptr es:[di], al
    inc di
    inc si
    test al, al
    jnz .L_getcwd_copy
    xor ax, ax
    jmp .L_int21_handler_return
.L_getcwd_bad:
    mov ax, 15
    jmp .L_set_error

/* DOS disk transfer area and disk geometry. DTA belongs to the user process,
 * defaults to PSP:0080 and is restored for each shell application. */
.L_dos_set_dta:
    mov ax, word ptr ss:[bp + 14]
    mov word ptr [dta_seg], ax
    mov ax, word ptr ss:[bp + 6]
    mov word ptr [dta_off], ax
    xor ax, ax
    jmp .L_int21_handler_return
.L_dos_get_dta:
    mov ax, word ptr [dta_seg]
    mov word ptr ss:[bp + 12], ax      /* saved ES returned to caller */
    mov ax, word ptr [dta_off]
    mov word ptr ss:[bp + 10], ax      /* saved BX returned to caller */
    xor ax, ax
    jmp .L_int21_handler_return
.L_dos_diskfree:
    mov al, byte ptr ss:[bp + 6]     /* DL: 0=default, 1=A: */
    cmp al, 1
    ja .L_dos_diskfree_bad
    mov si, 2
    xor di, di
.L_dos_diskfree_loop:
    mov ax, si
    call fat_next
    test ax, ax
    jnz .L_dos_diskfree_used
    inc di
.L_dos_diskfree_used:
    inc si
    cmp si, 2784
    jbe .L_dos_diskfree_loop
    mov word ptr ss:[bp + 10], di    /* BX free clusters */
    mov word ptr ss:[bp + 8], 512   /* CX bytes per sector */
    mov word ptr ss:[bp + 6], 2783  /* DX total clusters */
    mov ax, 1                       /* sectors per cluster */
    jmp .L_int21_handler_return
.L_dos_diskfree_bad:
    mov ax, 0xffff                  /* invalid drive */
    jmp .L_int21_handler_return

/* DOS file attributes, AH=43h AL=00 get (CX), AL=01 set (CX).
 * Only ordinary file attributes may be changed; directories are read-only
 * to this API. The raw FAT entry is the authoritative source. */
.L_dos_attributes:
    mov byte ptr [attr_mode], al
    cmp al, 1
    ja .L_find_bad_function
    mov ax, word ptr ss:[bp + 14]
    mov es, ax
    mov si, word ptr ss:[bp + 6]
    call filename_from_es_si
    jc .L_open_not_found
    cmp byte ptr [path_directory_only], 0
    jne .L_open_not_found
    call find_file
    jc .L_open_not_found
    cmp byte ptr [attr_mode], 0
    jne .L_dos_attr_set
    xor cx, cx
    mov cl, byte ptr [file_attributes]
    mov word ptr ss:[bp + 8], cx
    xor ax, ax
    jmp .L_int21_handler_return
.L_dos_attr_set:
    test byte ptr [file_attributes], 0x10
    jnz .L_open_denied
    mov ax, word ptr ss:[bp + 8]
    test ax, 0xffd8                /* only R/H/S/A flags */
    jnz .L_open_denied
    call root_is_open
    jc .L_open_denied
    call select_directory
    jc .L_write_failure
    mov di, word ptr [file_dir_offset]
    mov ax, word ptr ss:[bp + 8]
    mov byte ptr es:[di + 11], al
    call flush_directory
    jc .L_write_failure
    call flush_metadata
    jc .L_write_failure
    xor ax, ax
    jmp .L_int21_handler_return

/* DOS timestamp, AH=57h AL=0 get CX(time)/DX(date), AL=1 set.
 * Reads/writes FAT directory fields, independent of the file's data. */
.L_dos_timestamp:
    mov byte ptr [attr_mode], al
    cmp al, 1
    ja .L_find_bad_function
    mov bx, word ptr ss:[bp + 10]
    call locate_handle
    jc .L_invalid_handle
    cmp byte ptr [attr_mode], 1
    jne .L_dos_timestamp_fetch
    cmp byte ptr [bx + 1], 0
    je .L_open_denied
.L_dos_timestamp_fetch:
    mov ax, word ptr [dir_parent_cluster]
    mov word ptr [saved_parent_cluster], ax
    mov ax, word ptr [bx + 14]
    mov word ptr [dir_parent_cluster], ax
    mov di, word ptr [bx + 12]
    call select_directory
    jc .L_dos_timestamp_ioerr
    cmp byte ptr [attr_mode], 1
    je .L_dos_timestamp_put
    mov ax, word ptr es:[di + 22]
    mov word ptr ss:[bp + 8], ax
    mov ax, word ptr es:[di + 24]
    mov word ptr ss:[bp + 6], ax
    jmp .L_dos_timestamp_done
.L_dos_timestamp_put:
    mov ax, word ptr ss:[bp + 8]
    mov word ptr es:[di + 22], ax
    mov ax, word ptr ss:[bp + 6]
    mov word ptr es:[di + 24], ax
    call flush_directory
    jc .L_dos_timestamp_ioerr
    call flush_metadata
    jc .L_dos_timestamp_ioerr
.L_dos_timestamp_done:
    mov ax, word ptr [saved_parent_cluster]
    mov word ptr [dir_parent_cluster], ax
    xor ax, ax
    jmp .L_int21_handler_return
.L_dos_timestamp_ioerr:
    mov ax, word ptr [saved_parent_cluster]
    mov word ptr [dir_parent_cluster], ax
    jmp .L_write_failure

/* Search state is stored inside the caller-selected DTA, so separate DTAs
 * can maintain separate iterators. DTA bytes 0..17 are VelvetDOS private;
 * bytes 21..42 match standard DOS FindFirst result layout. */
.L_dos_findfirst:
    mov ax, word ptr ss:[bp + 14]
    mov es, ax
    mov si, word ptr ss:[bp + 6]
    call filename_from_es_si
    jc .L_find_path_error
    cmp byte ptr [path_directory_only], 0
    jne .L_find_path_error
    /* Expand a star into '?' wildcards within each 8.3 name field. */
    xor bx, bx
.L_find_expand_loop:
    cmp byte ptr [filename + bx], '*'
    jne .L_find_expand_next
    mov di, bx
    mov dx, 8
    cmp bx, 8
    jae .L_find_expand_extension
    /* DOS treats an unqualified NAME* as matching every extension. */
    cmp word ptr [filename + 8], 0x2020
    jne .L_find_expand_fill
    cmp byte ptr [filename + 10], ' '
    jne .L_find_expand_fill
    mov byte ptr [filename + 8], '?'
    mov byte ptr [filename + 9], '?'
    mov byte ptr [filename + 10], '?'
    jmp .L_find_expand_fill
.L_find_expand_extension:
    mov dx, 11
.L_find_expand_fill:
    mov byte ptr [filename + di], '?'
    inc di
    cmp di, dx
    jb .L_find_expand_fill
    mov bx, di
    jmp .L_find_expand_test
.L_find_expand_next:
    inc bx
.L_find_expand_test:
    cmp bx, 11
    jb .L_find_expand_loop
    mov ax, word ptr [dta_seg]
    mov es, ax
    mov di, word ptr [dta_off]
    mov si, offset filename
    mov cx, 11
    rep movsb
    mov bx, word ptr [dta_off]
    mov ax, word ptr ss:[bp + 8]
    mov byte ptr es:[bx + 11], al
    mov ax, word ptr [dir_parent_cluster]
    mov word ptr es:[bx + 12], ax
    mov word ptr es:[bx + 14], 0
    mov word ptr es:[bx + 16], 0x4456 /* 'VD' */
    call dta_findnext
    jc .L_set_error
    xor ax, ax
    jmp .L_int21_handler_return
.L_dos_findnext:
    call dta_findnext
    jc .L_set_error
    xor ax, ax
    jmp .L_int21_handler_return
.L_find_path_error:
    mov ax, 3
    jmp .L_set_error
.L_find_bad_function:
    mov ax, 1
    jmp .L_set_error

/* FAT12 8.3 file APIs (four handles: 5..8).
 * 3Ch create/truncate, 3Dh open R/W, 3Eh close, 3Fh read, 40h write,
 * 41h delete, 42h seek. Directory paths supported, but no file sharing or locking yet.
 * Handle layout: used(0), mode(1), cluster(2), pos(4,6), size(8,10),
 * root offset(12), padding(14); length 16 bytes.
 */
.L_dos_open:
    mov byte ptr [open_mode], al
    and al, 3
    cmp al, 3
    je .L_open_denied
    mov ax, word ptr ss:[bp + 14]
    mov es, ax
    mov si, word ptr ss:[bp + 6]
    call filename_from_es_si
    jc .L_open_not_found
    cmp byte ptr [path_directory_only], 0
    jne .L_open_not_found
    call find_file
    jc .L_open_not_found
    test byte ptr [file_attributes], 0x10
    jnz .L_open_denied
    test byte ptr [file_attributes], 1
    jz .L_open_get_slot
    cmp byte ptr [open_mode], 0
    jne .L_open_denied
.L_open_get_slot:
    call find_handle_slot
    jc .L_open_no_slots
    mov al, byte ptr [open_mode]
    and al, 3
    mov byte ptr [si + 1], al
    call fill_handle
    mov ax, dx
    jmp .L_int21_handler_return
.L_open_denied:
    mov ax, 5
    jmp .L_set_error
.L_open_no_slots:
    mov ax, 4
    jmp .L_set_error
.L_open_not_found:
    mov ax, 2
    jmp .L_set_error
/* DOS 3Ch creates or truncates an 8.3 file in a supported directory. CX=attributes.
 * Existing read-only files are protected. A new file is empty and has
 * first cluster 0 until the first successful allocation.
 */
.L_dos_create:
    mov ax, word ptr ss:[bp + 8]
    test ax, 0xffdf  /* allow ordinary or archive attributes only */
    jnz .L_open_denied
    mov ax, word ptr ss:[bp + 14]
    mov es, ax
    mov si, word ptr ss:[bp + 6]
    call filename_from_es_si
    jc .L_open_denied
    cmp byte ptr [path_directory_only], 0
    jne .L_open_denied
    call find_handle_slot
    jc .L_open_no_slots
    mov word ptr [new_handle], si
    mov word ptr [new_handle_number], dx
    call find_file
    jc .L_create_new
    test byte ptr [file_attributes], 0x10
    jnz .L_open_denied
    test byte ptr [file_attributes], 1
    jnz .L_open_denied
    /* Safeguard against truncating a file opened by another handle. */
    call root_is_open
    jc .L_open_denied
    call free_file_chain
    jc .L_write_failure
    jmp .L_create_initialize
.L_create_new:
    call find_free_root
    jc .L_create_full
.L_create_initialize:
    call select_directory
    jc .L_write_failure
    mov di, word ptr [file_dir_offset]
    push di
    mov cx, 16
    xor ax, ax
    rep stosw
    pop di
    mov si, offset filename
    mov cx, 11
.L_create_copy_name:
    mov al, byte ptr [si]
    mov byte ptr es:[di], al
    inc si
    inc di
    loop .L_create_copy_name
    mov ax, word ptr ss:[bp + 8]
    or al, 0x20 /* archive */
    mov byte ptr es:[di], al
    mov word ptr [file_cluster], 0
    mov word ptr [file_size], 0
    mov word ptr [file_size_high], 0
    mov si, word ptr [new_handle]
    mov dx, word ptr [new_handle_number]
    mov byte ptr [si + 1], 2 /* read/write */
    call fill_handle
    call flush_directory
    jc .L_write_failure
    call flush_metadata
    jc .L_write_failure
    mov ax, dx
    jmp .L_int21_handler_return
.L_create_full:
    mov ax, 4 /* root directory full */
    jmp .L_set_error
.L_dos_close:
    mov bx, word ptr ss:[bp + 10]
    call release_handle
    jc .L_invalid_handle
    call flush_metadata
    jc .L_write_failure
    xor ax, ax
    jmp .L_int21_handler_return
.L_dos_read:
    mov bx, word ptr ss:[bp + 10]
    call locate_handle
    jc .L_invalid_handle
    cmp byte ptr [bx + 1], 1 /* write-only */
    je .L_open_denied
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
/* DOS AH=41h removes an 8.3 file and releases its FAT12 chain. */
.L_dos_delete:
    mov ax, word ptr ss:[bp + 14]
    mov es, ax
    mov si, word ptr ss:[bp + 6]
    call filename_from_es_si
    jc .L_open_not_found
    cmp byte ptr [path_directory_only], 0
    jne .L_open_not_found
    call find_file
    jc .L_open_not_found
    test byte ptr [file_attributes], 0x10
    jnz .L_open_denied
    test byte ptr [file_attributes], 1
    jnz .L_open_denied
    call root_is_open
    jc .L_open_denied
    call free_file_chain
    jc .L_write_failure
    call select_directory
    jc .L_write_failure
    mov di, word ptr [file_dir_offset]
    mov byte ptr es:[di], 0xe5
    call flush_directory
    jc .L_write_failure
    call flush_metadata
    jc .L_write_failure
    xor ax, ax
    jmp .L_int21_handler_return
/* DOS AH=40h write to file. No sparse seeks yet: a write when current
 * position > EOF fails rather than exposing uninitialized clusters.
 */
.L_dos_write:
    mov bx, word ptr ss:[bp + 10]
    call locate_handle
    jc .L_invalid_handle
    cmp byte ptr [bx + 1], 0
    je .L_open_denied
    mov word ptr [rw_handle], bx
    mov ax, word ptr ss:[bp + 14]
    mov word ptr [rw_dstseg], ax
    mov ax, word ptr ss:[bp + 6]
    mov word ptr [rw_dstoff], ax
    mov ax, word ptr ss:[bp + 8]
    mov word ptr [rw_remaining], ax
    mov word ptr [rw_read], 0
    mov word ptr [rw_cached_sector], 0xffff
    mov byte ptr [write_errno], 0
.L_write_next:
    cmp word ptr [rw_remaining], 0
    je .L_write_finish
    mov bx, word ptr [rw_handle]
    /* only allow writing at/before logical EOF */
    mov ax, word ptr [bx + 6]
    cmp ax, word ptr [bx + 10]
    ja .L_write_bad_seek
    jb .L_write_copy
    mov ax, word ptr [bx + 4]
    cmp ax, word ptr [bx + 8]
    ja .L_write_bad_seek
.L_write_copy:
    push es
    mov ax, word ptr [rw_dstseg]
    mov es, ax
    mov si, word ptr [rw_dstoff]
    mov al, byte ptr es:[si]
    pop es
    call write_file_byte
    jc .L_write_partial_or_error
    inc word ptr [rw_dstoff]
    inc word ptr [rw_read]
    dec word ptr [rw_remaining]
    add word ptr [bx + 4], 1
    adc word ptr [bx + 6], 0
    /* grow logical EOF if the new position passed it */
    mov ax, word ptr [bx + 6]
    cmp ax, word ptr [bx + 10]
    jb .L_write_next
    ja .L_write_grow
    mov ax, word ptr [bx + 4]
    cmp ax, word ptr [bx + 8]
    jbe .L_write_next
.L_write_grow:
    mov ax, word ptr [bx + 4]
    mov word ptr [bx + 8], ax
    mov ax, word ptr [bx + 6]
    mov word ptr [bx + 10], ax
    jmp .L_write_next
.L_write_bad_seek:
    mov byte ptr [write_errno], 1
.L_write_partial_or_error:
    /* A full disk returns a short successful write (AX < CX) if
     * anything was written; otherwise AX=0, CF clear. */
    cmp byte ptr [write_errno], 39
    jne .L_write_failed
    jmp .L_write_finish
.L_write_failed:
    mov al, byte ptr [write_errno]
    xor ah, ah
    push ax
    call flush_write_cache
    pop ax
    jmp .L_set_error
.L_write_finish:
    call flush_write_cache
    jc .L_write_failure
    mov bx, word ptr [rw_handle]
    call update_root_handle
    /* Deliberately defer FAT/root sync until close (or normal exit).
     * Data sectors are persisted on every successful AH=40h call. */
    mov ax, word ptr [rw_read]
    jmp .L_int21_handler_return
.L_write_failure:
    mov ax, 29 /* write fault */
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

/* Validate, relocate, and compact a bounded MZ child image.
 * Input: loaded DOS file at exec_load_segment:0100h.
 * Output: code/data at exec_load_segment+10h:0000, relocated EXE entry in
 * exe_ip/exe_cs and stack in exe_sp/exe_ss. CF=1 on malformed input.
 * Does NOT alter the resident parent's PSP, stack, MCB, or DTA.
 * Restriction: entire file <=65024 bytes; one <=64K initialized image;
 * stack and declared minimum memory fit the 68-KiB child allocation.
 */
prepare_child_exe:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    mov ax, word ptr [exec_load_segment]
    mov es, ax
    cmp word ptr es:[0x100], 0x5a4d
    jne .L_child_mz_bad
    cmp word ptr [file_size_high], 0
    jne .L_child_mz_bad
    mov ax, word ptr [file_size]
    cmp ax, 34
    jb .L_child_mz_bad
    /* Check exact MZ page-byte count (overlays beyond MZ are allowed). */
    mov ax, word ptr es:[0x104]
    test ax, ax
    jz .L_child_mz_bad
    cmp ax, 127
    ja .L_child_mz_bad
    dec ax
    mov cl, 9
    shl ax, cl
    mov bx, word ptr es:[0x102]
    cmp bx, 512
    ja .L_child_mz_bad
    test bx, bx
    jnz .L_child_mz_last
    mov bx, 512
.L_child_mz_last:
    add ax, bx
    jc .L_child_mz_bad
    cmp ax, word ptr [file_size]
    ja .L_child_mz_bad
    mov word ptr [exe_image_total], ax
    mov ax, word ptr es:[0x108]
    cmp ax, 2
    jb .L_child_mz_bad
    cmp ax, 0x0ff0
    ja .L_child_mz_bad
    mov word ptr [exe_hdrparas], ax
    mov cl, 4
    shl ax, cl
    cmp ax, word ptr [exe_image_total]
    jae .L_child_mz_bad
    mov word ptr [exe_hdrbytes], ax
    mov dx, word ptr [exe_image_total]
    sub dx, ax
    mov word ptr [exe_image_bytes], dx
    /* MZ image + minimum extra allocation must fit child MCB. */
    mov ax, dx
    add ax, 15
    jc .L_child_mz_bad
    mov cl, 4
    shr ax, cl
    add ax, word ptr es:[0x10a]
    jc .L_child_mz_bad
    cmp ax, CHILD_PARAS - 0x10
    ja .L_child_mz_bad
    mov ax, word ptr es:[0x116] /* relative CS */
    mov word ptr [exe_cs], ax
    cmp ax, CHILD_PARAS - 0x10
    jae .L_child_mz_bad
    mov dx, ax
    mov cl, 4
    shl ax, cl
    jc .L_child_mz_bad
    add ax, word ptr es:[0x114] /* IP */
    jc .L_child_mz_bad
    cmp ax, word ptr [exe_image_bytes]
    jae .L_child_mz_bad
    mov ax, word ptr es:[0x114]
    mov word ptr [exe_ip], ax
    mov ax, word ptr es:[0x10e] /* relative SS */
    cmp ax, CHILD_PARAS - 0x10
    jae .L_child_mz_bad
    mov word ptr [exe_ss], ax
    mov bx, word ptr es:[0x110] /* SP */
    mov word ptr [exe_sp], bx
    mov cl, 4
    shr bx, cl
    add bx, ax
    jc .L_child_mz_bad
    cmp bx, CHILD_PARAS - 0x10
    jae .L_child_mz_bad
    /* Relocation table must be entirely within MZ header. */
    mov bx, word ptr es:[0x118] /* relocation offset */
    cmp bx, 0x001c
    jb .L_child_mz_bad
    mov cx, word ptr es:[0x106] /* count */
    cmp cx, 512
    ja .L_child_mz_bad
    mov ax, cx
    shl ax, 1
    shl ax, 1
    add ax, bx
    jc .L_child_mz_bad
    cmp ax, word ptr [exe_hdrbytes]
    ja .L_child_mz_bad
    add bx, 0x100
    jc .L_child_mz_bad
    mov word ptr [exe_reloc_remaining], cx
.L_child_mz_reloc:
    cmp word ptr [exe_reloc_remaining], 0
    je .L_child_mz_copy
    /* Relocation entries are 16-bit offset, then relative segment. */
    mov si, word ptr es:[bx]
    mov dx, word ptr es:[bx+2]
    mov ax, dx
    mov cl, 4
    shl ax, cl
    jc .L_child_mz_bad
    add ax, si
    jc .L_child_mz_bad
    inc ax
    jc .L_child_mz_bad
    cmp ax, word ptr [exe_image_bytes]
    jae .L_child_mz_bad
    mov ax, word ptr [exec_load_segment]
    add ax, 0x10
    add ax, word ptr [exe_hdrparas]
    add ax, dx
    mov ds, ax
    mov ax, word ptr cs:[exec_load_segment]
    add ax, 0x10
    add word ptr [si], ax
    push cs
    pop ds
    add bx, 4
    dec word ptr [exe_reloc_remaining]
    jmp .L_child_mz_reloc
.L_child_mz_copy:
    /* Source lies above destination, so a forward copy is overlap-safe. */
    mov ax, word ptr [exec_load_segment]
    add ax, 0x10
    mov es, ax
    add ax, word ptr [exe_hdrparas]
    mov ds, ax
    xor si, si
    xor di, di
    mov cx, word ptr cs:[exe_image_bytes]
    rep movsb
    mov ax, word ptr cs:[exec_load_segment]
    add ax, 0x10
    add word ptr cs:[exe_cs], ax
    add word ptr cs:[exe_ss], ax
    clc
    jmp .L_child_mz_done
.L_child_mz_bad:
    stc
.L_child_mz_done:
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* DOS EXEC (AH=4B00) — one suspended parent plus a .COM or small MZ .EXE child.
 * DS:DX is an 8.3 DOS path; ES:BX points to the DOS EXEC parameter block.
 * Only the command tail pointer at offsets +2/+4 is read, and a zero
 * environment segment inherits the fixed bootstrap environment. Errors
 * return through the parent INT 21h frame, success resumes after child exit.
 * Nested EXEC remains unsupported; bounded dynamic child MCB allocation.
 */
.L_dos_exec:
    cmp al, 0
    jne .L_exec_bad_function
    cmp byte ptr [exec_active], 0
    jne .L_exec_no_memory
    /* Interpret the filename from the calling process's DS:DX. */
    mov ax, word ptr ss:[bp + 14]
    mov es, ax
    mov si, word ptr ss:[bp + 6]
    call filename_from_es_si
    jc .L_exec_not_found
    cmp byte ptr [path_directory_only], 0
    jne .L_exec_not_found
    /* Explicit .COM and .EXE supported. Keep the selected format until
     * after the command tail is copied from the parent process. */
    mov byte ptr [exec_exe_mode], 0
    cmp byte ptr [filename + 8], 'C'
    jne .L_exec_check_exe
    cmp byte ptr [filename + 9], 'O'
    jne .L_exec_bad_format
    cmp byte ptr [filename + 10], 'M'
    jne .L_exec_bad_format
    jmp .L_exec_format_ok
.L_exec_check_exe:
    cmp byte ptr [filename + 8], 'E'
    jne .L_exec_bad_format
    cmp byte ptr [filename + 9], 'X'
    jne .L_exec_bad_format
    cmp byte ptr [filename + 10], 'E'
    jne .L_exec_bad_format
    mov byte ptr [exec_exe_mode], 1
.L_exec_format_ok:
    call find_file
    jc .L_exec_not_found
    test byte ptr [file_attributes], 0x10
    jnz .L_exec_bad_format
    /* The user's DOS command tail is length-prefixed, not ASCIIZ. */
    mov ax, word ptr ss:[bp + 12]
    mov es, ax
    mov bx, word ptr ss:[bp + 10]
    mov ax, word ptr es:[bx]
    mov word ptr [exec_env_source], ax
    mov di, word ptr es:[bx + 2]
    mov ax, word ptr es:[bx + 4]
    test ax, ax
    jz .L_exec_bad_function
    mov es, ax
    mov cl, byte ptr es:[di]
    cmp cl, 126
    ja .L_exec_bad_function
    xor ch, ch
    mov byte ptr [cmdtail_len], cl
    mov si, offset cmdtail
    push cx
.L_exec_tail_copy:
    test cx, cx
    jz .L_exec_tail_end
    mov al, byte ptr es:[di + 1]
    mov byte ptr [si], al
    inc si
    inc di
    dec cx
    jmp .L_exec_tail_copy
.L_exec_tail_end:
    mov byte ptr [si], 0
    pop cx
    /* Reserve a free DOS MCB before the loader touches child memory.
     * Parent AH=48h allocations can force the child above 5000h. */
    call reserve_exec_block
    jc .L_exec_no_memory
    mov word ptr [exec_load_segment], ax
    call load_com
    jc .L_exec_load_failed
    /* .EXE and .COM share the bounded floppy-file staging loader; for
     * MZ, validate and apply relocation records before touching parent
     * process state. A malformed EXE must leave COMMAND.COM running. */
    cmp byte ptr [exec_exe_mode], 0
    je .L_exec_image_ready
    call prepare_child_exe
    jc .L_exec_load_failed
.L_exec_image_ready:
    call copy_child_environment
    jc .L_exec_bad_environment
    mov ax, word ptr [dta_seg]
    mov word ptr [exec_parent_dta_seg], ax
    mov ax, word ptr [dta_off]
    mov word ptr [exec_parent_dta_off], ax
    mov ax, ss
    mov word ptr [exec_parent_ss], ax
    mov word ptr [exec_parent_sp], bp
    /* MCB chain was updated by reserve_exec_block. No parent block
     * may be truncated or overwritten at this stage. */
    mov ax, word ptr [exec_load_segment]
    mov word ptr [current_psp], ax
    mov word ptr [psp_parent], APP_SEG
    mov word ptr [current_env_seg], CHILD_ENV_SEG
    mov byte ptr [exec_active], 1
    call make_psp
    call inherit_child_handles
    cli
    mov ax, word ptr [exec_load_segment]
    mov ds, ax
    mov es, ax
    cmp byte ptr cs:[exec_exe_mode], 0
    jne .L_exec_run_exe
    mov ss, ax
    mov sp, 0xfffe
    mov word ptr ss:[0xfffe], 0
    sti
    push ax
    mov ax, 0x0100
    push ax
    xor ax, ax
    retf
.L_exec_run_exe:
    /* EXE entry CS:IP and SS:SP are relative to its load segment,
     * CHILD_SEG+10h. DS and ES initially identify the child's PSP. */
    mov ax, word ptr cs:[exe_ss]
    mov ss, ax
    mov sp, word ptr cs:[exe_sp]
    mov ax, word ptr cs:[exec_load_segment]
    mov ds, ax
    mov es, ax
    sti
    xor ax, ax
    jmp far ptr cs:[exe_ip]
.L_exec_bad_environment:
    mov ax, word ptr [exec_load_segment]
    call release_process_blocks
    mov word ptr [exec_load_segment], APP_SEG
    mov ax, 10 /* invalid environment */
    jmp .L_set_error
.L_exec_load_failed:
    mov ax, word ptr [exec_load_segment]
    call release_process_blocks
    mov word ptr [exec_load_segment], APP_SEG
    mov ax, 11 /* invalid EXE format / incomplete load */
    jmp .L_set_error
.L_exec_not_found:
    mov ax, 2
    jmp .L_set_error
.L_exec_bad_function:
    mov ax, 1
    jmp .L_set_error
.L_exec_bad_format:
    mov ax, 11
    jmp .L_set_error
.L_exec_no_memory:
    mov ax, 8
    jmp .L_set_error

/* Conventional memory MCB API. A persistent, owned MCB chain is maintained
 * while a single EXEC child is running. No TSRs yet.
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
    mov ax, word ptr [current_psp]
    mov word ptr es:[1], ax
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
    cmp bx, word ptr [current_psp]
    je .L_mem_invalid
    call locate_mcb
    jc .L_mem_invalid
    mov ax, word ptr [current_psp]
    cmp word ptr es:[1], ax
    jne .L_mem_invalid
    mov word ptr es:[1], 0
    call merge_free_mcbs
    xor ax, ax
    jmp .L_int21_handler_return
.L_dos_resize:
    mov bx, word ptr ss:[bp + 12] /* caller ES */
    call locate_mcb
    jc .L_mem_invalid
    mov ax, word ptr [current_psp]
    cmp word ptr es:[1], ax
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
    /* Keep PSP:0002 synchronized with a successful resize of the
     * process's own initial block. Other AH=4Ah blocks leave it alone. */
    mov bx, word ptr ss:[bp + 12]
    cmp bx, word ptr [current_psp]
    jne .L_mem_resize_return
    mov ax, word ptr es:[3]
    add ax, bx
    push es
    mov es, bx
    mov word ptr es:[2], ax
    pop es
.L_mem_resize_return:
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
    mov al, byte ptr [last_exit_code]
    mov byte ptr [last_exit_code], 0  /* consumed as in DOS parent process */
    jmp .L_int21_handler_return
.L_dos_get_psp:
    mov ax, word ptr [current_psp]
    mov word ptr ss:[bp + 10], ax  /* return PSP segment in BX */
    xor ax, ax
    jmp .L_int21_handler_return
.L_int21_handler_write_handle:
    mov bx, word ptr ss:[bp + 10]
    cmp bx, 1
    je .L_int21_handler_wh_ok
    cmp bx, 2
    je .L_int21_handler_wh_ok
    cmp bx, 5
    jae .L_dos_write
    jmp .L_int21_handler_not_supported
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
    mov byte ptr [last_exit_code], 0
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

/* Read saved DTA search parameters, scan FAT directory, publish DOS result.
 * Return CF=1, AX=18 when exhausted; AX=1 for an invalid DTA.
 * Never relies on a kernel-global iterator: per-DTA next index is persisted. */
dta_findnext:
    mov ax, word ptr [dta_seg]
    mov es, ax
    mov bx, word ptr [dta_off]
    cmp word ptr es:[bx + 16], 0x4456
    jne .L_dn_bad
    push si
    push di
    push cx
    push dx
    mov si, bx
    mov di, offset search_pattern
    mov cx, 11
.L_dn_copy_pattern:
    mov al, byte ptr es:[si]
    mov byte ptr [di], al
    inc si
    inc di
    loop .L_dn_copy_pattern
    mov al, byte ptr es:[bx + 11]
    mov byte ptr [search_attr], al
    mov ax, word ptr es:[bx + 12]
    mov word ptr [dir_parent_cluster], ax
    mov ax, word ptr es:[bx + 14]
    mov word ptr [search_index], ax
    call select_directory
    jc .L_dn_disk_error
.L_dn_scan:
    mov ax, word ptr [search_index]
    cmp ax, cx
    jae .L_dn_not_found
    mov di, ax
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1                    /* directory index * 32 */
    inc word ptr [search_index]
    cmp byte ptr es:[di], 0
    je .L_dn_not_found
    cmp byte ptr es:[di], 0xe5
    je .L_dn_scan
    mov al, byte ptr es:[di + 11]
    cmp al, 0x0f                 /* long filename record */
    je .L_dn_scan
    test al, 0x08                /* volume labels unsupported */
    jnz .L_dn_scan
    test al, 0x02
    jz .L_dn_check_system
    test byte ptr [search_attr], 0x02
    jz .L_dn_scan
.L_dn_check_system:
    test al, 0x04
    jz .L_dn_check_directory
    test byte ptr [search_attr], 0x04
    jz .L_dn_scan
.L_dn_check_directory:
    test al, 0x10
    jz .L_dn_check_name
    test byte ptr [search_attr], 0x10
    jz .L_dn_scan
.L_dn_check_name:
    xor si, si
.L_dn_match:
    mov al, byte ptr [search_pattern + si]
    cmp al, '?'
    je .L_dn_match_next
    mov bx, di
    add bx, si
    cmp al, byte ptr es:[bx]
    jne .L_dn_scan
.L_dn_match_next:
    inc si
    cmp si, 11
    jb .L_dn_match
    /* Found: copy 32-byte raw FAT entry before reusing ES for DTA. */
    mov si, di
    mov bx, offset search_entry
    mov dx, 32
.L_dn_copy_entry:
    mov al, byte ptr es:[si]
    mov byte ptr [bx], al
    inc bx
    inc si
    dec dx
    jnz .L_dn_copy_entry
    mov ax, word ptr [dta_seg]
    mov es, ax
    mov bx, word ptr [dta_off]
    mov ax, word ptr [search_index]
    mov word ptr es:[bx + 14], ax
    mov al, byte ptr [search_entry + 11]
    mov byte ptr es:[bx + 21], al
    mov ax, word ptr [search_entry + 22]
    mov word ptr es:[bx + 22], ax
    mov ax, word ptr [search_entry + 24]
    mov word ptr es:[bx + 24], ax
    mov ax, word ptr [search_entry + 28]
    mov word ptr es:[bx + 26], ax
    mov ax, word ptr [search_entry + 30]
    mov word ptr es:[bx + 28], ax
    /* Format NAME.EXT as a zero-terminated 13-byte DOS string. */
    mov di, bx
    add di, 30
    xor si, si
.L_dn_name:
    cmp si, 8
    jae .L_dn_ext
    mov al, byte ptr [search_entry + si]
    cmp al, ' '
    je .L_dn_name_skip
    mov byte ptr es:[di], al
    inc di
.L_dn_name_skip:
    inc si
    jmp .L_dn_name
.L_dn_ext:
    cmp byte ptr [search_entry + 8], ' '
    je .L_dn_name_done
    mov byte ptr es:[di], '.'
    inc di
.L_dn_ext_loop:
    cmp si, 11
    jae .L_dn_name_done
    mov al, byte ptr [search_entry + si]
    cmp al, ' '
    je .L_dn_ext_skip
    mov byte ptr es:[di], al
    inc di
.L_dn_ext_skip:
    inc si
    jmp .L_dn_ext_loop
.L_dn_name_done:
    mov byte ptr es:[di], 0
    clc
    jmp .L_dn_exit
.L_dn_disk_error:
    mov ax, 30
    stc
    jmp .L_dn_exit
.L_dn_not_found:
    mov ax, 18                    /* DOS: no more files */
    stc
.L_dn_exit:
    pop dx
    pop cx
    pop di
    pop si
    ret
.L_dn_bad:
    mov ax, 1
    stc
    ret

/* Directory operations share the path resolver and 8.3 FAT12 entries.
 * Subdirectories can grow to eight clusters (128 entries including dots).
 * AX returns a DOS error on CF=1, otherwise CF=0.
 */
dos_mkdir:
    call filename_from_es_si
    jc .L_mkdir_bad_path
    cmp byte ptr [path_directory_only], 0
    jne .L_mkdir_bad_path
    call find_file
    jnc .L_mkdir_exists
    call find_free_root
    jc .L_mkdir_disk_full
    call allocate_cluster
    jc .L_mkdir_disk_full
    mov word ptr [new_dir_cluster], ax
    /* Persist the cluster allocation before publishing a directory entry. */
    call flush_metadata
    jc .L_mkdir_write_fault
    /* Write a zero-initialized directory cluster with the mandatory dots. */
    push es
    mov ax, DIR_SEG
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, 256
    rep stosw
    mov byte ptr es:[0], '.'
    mov byte ptr es:[32], '.'
    mov byte ptr es:[33], '.'
    mov di, 1
    mov cx, 10
    mov al, ' '
    rep stosb
    mov di, 34
    mov cx, 9
    rep stosb
    mov byte ptr es:[11], 0x10
    mov byte ptr es:[32 + 11], 0x10
    mov ax, word ptr [new_dir_cluster]
    mov word ptr es:[26], ax
    mov ax, word ptr [dir_parent_cluster]
    mov word ptr es:[32 + 26], ax
    mov ax, word ptr [new_dir_cluster]
    add ax, DATA_BIAS
    xor bx, bx
    call write_sector
    pop es
    jc .L_mkdir_write_fault
    /* Re-select containing directory (DIR_SEG may have been overwritten). */
    call select_directory
    jc .L_mkdir_write_fault
    mov di, word ptr [file_dir_offset]
    push di
    xor ax, ax
    mov cx, 16
    rep stosw
    pop di
    mov si, offset filename
    mov cx, 11
.L_mkdir_copy_name:
    mov al, byte ptr [si]
    mov byte ptr es:[di], al
    inc di
    inc si
    loop .L_mkdir_copy_name
    mov byte ptr es:[di], 0x10
    mov ax, word ptr [new_dir_cluster]
    mov word ptr es:[di + 15], ax /* di now entry+11, FAT first cluster +26 */
    call flush_directory
    jc .L_mkdir_write_fault
    call flush_metadata
    jc .L_mkdir_write_fault
    clc
    ret
.L_mkdir_exists:
    mov ax, 5
    stc
    ret
.L_mkdir_disk_full:
    mov ax, 39
    stc
    ret
.L_mkdir_bad_path:
    mov ax, 3
    stc
    ret
.L_mkdir_write_fault:
    mov ax, 29
    stc
    ret

dos_rmdir:
    call filename_from_es_si
    jc .L_rmdir_bad
    cmp byte ptr [path_directory_only], 0
    jne .L_rmdir_bad
    call find_directory
    jc .L_rmdir_bad
    mov ax, word ptr [file_cluster]
    mov word ptr [new_dir_cluster], ax
    /* The emptiness scan below checks ALL clusters, and free_file_chain
     * releases the entire chain once it has no live directory entries. */
    mov ax, word ptr [new_dir_cluster]
    /* Never remove the cwd or any ancestor of it. */
    mov cl, byte ptr [cwd_depth]
    xor ch, ch
    mov si, offset cwd_stack
.L_rmdir_ancestor:
    jcxz .L_rmdir_check_empty
    cmp word ptr [si], ax
    je .L_rmdir_access
    add si, 2
    loop .L_rmdir_ancestor
.L_rmdir_check_empty:
    mov ax, word ptr [dir_parent_cluster]
    mov word ptr [saved_parent_cluster], ax
    mov ax, word ptr [new_dir_cluster]
    mov word ptr [dir_parent_cluster], ax
    call select_directory
    jc .L_rmdir_disk_error
    xor di, di
.L_rmdir_scan:
    cmp byte ptr es:[di], 0
    je .L_rmdir_is_empty
    cmp byte ptr es:[di], 0xe5
    je .L_rmdir_next
    /* Only the first two standard DOS dot entries may be skipped. */
    cmp di, 32
    ja .L_rmdir_not_empty
    cmp byte ptr es:[di], '.'
    jne .L_rmdir_not_empty
.L_rmdir_next:
    add di, 32
    loop .L_rmdir_scan
.L_rmdir_is_empty:
    mov ax, word ptr [saved_parent_cluster]
    mov word ptr [dir_parent_cluster], ax
    mov ax, word ptr [new_dir_cluster]
    mov word ptr [file_cluster], ax
    call free_file_chain
    jc .L_rmdir_disk_error
    call select_directory
    jc .L_rmdir_disk_error
    mov di, word ptr [file_dir_offset]
    mov byte ptr es:[di], 0xe5
    call flush_directory
    jc .L_rmdir_disk_error
    call flush_metadata
    jc .L_rmdir_disk_error
    clc
    ret
.L_rmdir_not_empty:
    mov ax, word ptr [saved_parent_cluster]
    mov word ptr [dir_parent_cluster], ax
    mov ax, 5
    stc
    ret
.L_rmdir_disk_error:
    mov ax, word ptr [saved_parent_cluster]
    mov word ptr [dir_parent_cluster], ax
    mov ax, 29
    stc
    ret
.L_rmdir_bad:
    mov ax, 3
    stc
    ret
.L_rmdir_access:
    mov ax, 5
    stc
    ret

dos_chdir:
    call filename_from_es_si
    jc .L_chdir_bad
    cmp byte ptr [path_directory_only], 0
    jne .L_chdir_commit
    call find_directory
    jc .L_chdir_bad
    cmp byte ptr [path_depth], 8
    jae .L_chdir_bad
    mov bl, byte ptr [path_depth]
    xor bh, bh
    shl bx, 1
    mov ax, word ptr [file_cluster]
    mov word ptr [path_stack + bx], ax
    mov word ptr [dir_parent_cluster], ax
    inc byte ptr [path_depth]
.L_chdir_commit:
    mov al, byte ptr [path_depth]
    mov byte ptr [cwd_depth], al
    mov ax, word ptr [dir_parent_cluster]
    mov word ptr [cwd_cluster], ax
    mov cx, 8
    mov si, offset path_stack
    mov di, offset cwd_stack
.L_chdir_copy:
    mov ax, word ptr [si]
    mov word ptr [di], ax
    add si, 2
    add di, 2
    loop .L_chdir_copy
    call rebuild_cwd
    clc
    ret
.L_chdir_bad:
    mov ax, 3
    stc
    ret

/* Reconstruct relative DOS CWD from cluster ancestry for AH=47h and shell.
 * Output is empty for root; otherwise NAME\\CHILD (no leading slash).
 * Names are found in each parent directory by the child's cluster number.
 */
rebuild_cwd:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    xor bx, bx                   /* depth index */
    mov di, offset cwd_text
.L_cwd_next_level:
    cmp bl, byte ptr [cwd_depth]
    jae .L_cwd_done
    test bx, bx
    jz .L_cwd_parent_root
    mov si, bx
    shl si, 1
    mov ax, word ptr [cwd_stack + si - 2]
    jmp .L_cwd_select
.L_cwd_parent_root:
    xor ax, ax
.L_cwd_select:
    mov word ptr [dir_parent_cluster], ax
    call select_directory
    jc .L_cwd_done
    mov si, bx
    shl si, 1
    mov dx, word ptr [cwd_stack + si]
    xor si, si
.L_cwd_find:
    cmp byte ptr es:[si], 0
    je .L_cwd_done
    cmp byte ptr es:[si], 0xe5
    je .L_cwd_skip
    test byte ptr es:[si + 11], 0x10
    jz .L_cwd_skip
    cmp byte ptr es:[si], '.'
    je .L_cwd_skip
    cmp word ptr es:[si + 26], dx
    je .L_cwd_found
.L_cwd_skip:
    add si, 32
    loop .L_cwd_find
    jmp .L_cwd_done
.L_cwd_found:
    test bx, bx
    jz .L_cwd_no_separator
    mov byte ptr [di], '\\'
    inc di
.L_cwd_no_separator:
    xor ax, ax
.L_cwd_base:
    cmp al, 8
    jae .L_cwd_extension
    push bx
    mov bx, ax
    mov dl, byte ptr es:[si + bx]
    pop bx
    cmp dl, ' '
    je .L_cwd_base_next
    mov byte ptr [di], dl
    inc di
.L_cwd_base_next:
    inc al
    jmp .L_cwd_base
.L_cwd_extension:
    cmp byte ptr es:[si + 8], ' '
    je .L_cwd_level_done
    mov byte ptr [di], '.'
    inc di
    mov ax, 8
.L_cwd_ext:
    push bx
    mov bx, ax
    mov dl, byte ptr es:[si + bx]
    pop bx
    cmp dl, ' '
    je .L_cwd_ext_next
    mov byte ptr [di], dl
    inc di
.L_cwd_ext_next:
    inc ax
    cmp ax, 11
    jb .L_cwd_ext
.L_cwd_level_done:
    inc bx
    jmp .L_cwd_next_level
.L_cwd_done:
    mov byte ptr [di], 0
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* Find first unused DOS handle. Returns SI=record and DX=5..8, CF clear;
 * all other registers preserved. */
find_handle_slot:
    mov si, offset handles
    mov dx, 5
.L_fhs_loop:
    cmp byte ptr [si], 0
    je .L_fhs_found
    add si, 16
    inc dx
    cmp dx, 9
    jb .L_fhs_loop
    stc
    ret
.L_fhs_found:
    clc
    ret

/* Fill a handle after mode has been assigned and find_file called.
 * SI=record; preserves AX, DX. */
fill_handle:
    mov byte ptr [si], 1
    mov ax, word ptr [file_cluster]
    mov word ptr [si + 2], ax
    mov word ptr [si + 4], 0
    mov word ptr [si + 6], 0
    mov ax, word ptr [file_size]
    mov word ptr [si + 8], ax
    mov ax, word ptr [file_size_high]
    mov word ptr [si + 10], ax
    mov ax, word ptr [file_dir_offset]
    mov word ptr [si + 12], ax
    mov ax, word ptr [dir_parent_cluster]
    mov word ptr [si + 14], ax
    /* Expose a new handle only in its owner's PSP; refcount starts at 1. */
    push bx
    push dx
    push es
    mov bx, dx
    sub bx, 5
    mov byte ptr [handle_refs + bx], 1
    mov ax, word ptr [current_psp]
    mov es, ax
    mov byte ptr es:[bx + 0x1d], dl
    pop es
    pop dx
    pop bx
    ret

/* Find an unused 32-byte slot, growing a full subdirectory by one
 * FAT12 cluster (up to MAX_DIR_CLUSTERS) when necessary. Root is fixed.
 * Always zero and write the new directory sector BEFORE publishing the FAT
 * chain link. On failure, this pre-alpha filesystem can leak a cluster;
 * it does not offer atomic metadata transactions.
 * file_dir_offset is a BYTE offset in the contiguous directory buffer.
 */
find_free_root:
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    call select_directory
    jc .L_ffr_failed
    xor di, di
.L_ffr_loop:
    cmp byte ptr es:[di], 0
    je .L_ffr_found
    cmp byte ptr es:[di], 0xe5
    je .L_ffr_found
    add di, 32
    loop .L_ffr_loop
    cmp word ptr [dir_parent_cluster], 0
    je .L_ffr_failed  /* FAT12 root cannot grow */
    mov ax, word ptr [dir_cluster_count]
    cmp ax, MAX_DIR_CLUSTERS
    jae .L_ffr_failed
    mov bx, ax
    mov cl, 9
    shl bx, cl          /* offset of new 512-byte sector in DIR_SEG */
    mov word ptr [new_dir_offset], bx
    call allocate_cluster
    jc .L_ffr_failed
    mov word ptr [new_dir_cluster], ax
    /* Clear the new directory sector; it begins with an end marker. */
    mov di, bx
    xor ax, ax
    mov cx, 256
    rep stosw
    mov ax, word ptr [new_dir_cluster]
    add ax, DATA_BIAS
    call write_sector
    jc .L_ffr_failed
    /* Link only after the empty sector was written. */
    mov ax, word ptr [dir_last_cluster]
    mov dx, word ptr [new_dir_cluster]
    call fat_set
    call flush_metadata
    jc .L_ffr_failed
    mov di, word ptr [new_dir_offset]
.L_ffr_found:
    mov word ptr [file_dir_offset], di
    clc
    jmp .L_ffr_exit
.L_ffr_failed:
    stc
.L_ffr_exit:
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* Reject truncate/delete when the target directory slot is still open. */
root_is_open:
    push ax
    push bx
    push cx
    mov bx, offset handles
    mov cx, 4
    mov ax, word ptr [file_dir_offset]
.L_rio_loop:
    cmp byte ptr [bx], 0
    je .L_rio_next
    cmp word ptr [bx + 12], ax
    jne .L_rio_next
    mov ax, word ptr [dir_parent_cluster]
    cmp word ptr [bx + 14], ax
    je .L_rio_busy
    mov ax, word ptr [file_dir_offset]
.L_rio_next:
    add bx, 16
    loop .L_rio_loop
    clc
    jmp .L_rio_exit
.L_rio_busy:
    stc
.L_rio_exit:
    pop cx
    pop bx
    pop ax
    ret

/* Assign 12-bit FAT entry. AX=cluster, DX=value (0..0xfff).
 * Preserves registers, does not flush FAT to disk. */
fat_set:
    push ax
    push bx
    push cx
    push dx
    push es
    mov bx, ax
    shr bx, 1
    add bx, ax
    mov cx, FAT_SEG
    mov es, cx
    test ax, 1
    jnz .L_fset_odd
    mov ax, word ptr es:[bx]
    and ax, 0xf000
    and dx, 0x0fff
    or ax, dx
    mov word ptr es:[bx], ax
    jmp .L_fset_done
.L_fset_odd:
    mov ax, word ptr es:[bx]
    and ax, 0x000f
    and dx, 0x0fff
    mov cl, 4
    shl dx, cl
    or ax, dx
    mov word ptr es:[bx], ax
.L_fset_done:
    mov byte ptr [fs_dirty], 1
    pop es
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* Return AX=allocated free cluster, CF=0; full disk => CF=1.
 * No clustering hints or free-space cache in this first implementation. */
allocate_cluster:
    push bx
    push dx
    mov bx, 2
.L_ac_loop:
    mov ax, bx
    call fat_next
    test ax, ax
    je .L_ac_found
    inc bx
    cmp bx, 2784
    jbe .L_ac_loop
    stc
    jmp .L_ac_done
.L_ac_found:
    mov ax, bx
    mov dx, 0x0fff
    call fat_set
    mov ax, bx
    clc
.L_ac_done:
    pop dx
    pop bx
    ret

/* Free an existing file's FAT chain. Called for truncate/delete.
 * Guards against bad cluster values and loops (maximum 2783 hops). */
free_file_chain:
    push ax
    push bx
    push cx
    push dx
    mov bx, word ptr [file_cluster]
    mov cx, 2783
    cmp bx, 0
    je .L_ffc_done
.L_ffc_next:
    cmp bx, 2
    jb .L_ffc_bad
    cmp bx, 2784
    ja .L_ffc_bad
    mov ax, bx
    call fat_next
    mov word ptr [free_next], ax
    mov ax, bx
    xor dx, dx
    call fat_set
    mov bx, word ptr [free_next]
    cmp bx, 0x0ff8
    jae .L_ffc_done
    loop .L_ffc_next
.L_ffc_bad:
    stc
    jmp .L_ffc_exit
.L_ffc_done:
    clc
.L_ffc_exit:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* Mirror in-memory FAT to both FAT copies and root directory to disk.
 * Metadata changes are deferred until close or process exit. Failure
 * does not clear fs_dirty; this is NOT yet a transactional filesystem. */
flush_metadata:
    push ax
    push bx
    push cx
    push dx
    push si
    push es
    cmp byte ptr [fs_dirty], 0
    je .L_fmd_ok
    mov ax, FAT_SEG
    mov es, ax
    xor bx, bx
    mov si, 65
    mov cx, 9
.L_fmd_fat1:
    push cx
    mov ax, si
    call write_sector
    pop cx
    jc .L_fmd_fail
    add bx, 512
    inc si
    loop .L_fmd_fat1
    xor bx, bx
    mov si, 74
    mov cx, 9
.L_fmd_fat2:
    push cx
    mov ax, si
    call write_sector
    pop cx
    jc .L_fmd_fail
    add bx, 512
    inc si
    loop .L_fmd_fat2
    mov ax, ROOT_SEG
    mov es, ax
    xor bx, bx
    mov si, ROOT_SECTOR
    mov cx, ROOT_SECTORS
.L_fmd_root:
    push cx
    mov ax, si
    call write_sector
    pop cx
    jc .L_fmd_fail
    add bx, 512
    inc si
    loop .L_fmd_root
    mov byte ptr [fs_dirty], 0
.L_fmd_ok:
    clc
    jmp .L_fmd_exit
.L_fmd_fail:
    stc
.L_fmd_exit:
    pop es
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* Update a handle's containing directory entry; not only FAT root. */
update_root_handle:
    push ax
    push cx
    push di
    push es
    cmp byte ptr [bx], 0
    je .L_urh_done
    cmp byte ptr [bx + 1], 0
    je .L_urh_done
    mov ax, word ptr [dir_parent_cluster]
    push ax
    mov ax, word ptr [bx + 14]
    mov word ptr [dir_parent_cluster], ax
    call select_directory
    jc .L_urh_restore
    mov di, word ptr [bx + 12]
    mov ax, word ptr [bx + 2]
    mov word ptr es:[di + 26], ax
    mov ax, word ptr [bx + 8]
    mov word ptr es:[di + 28], ax
    mov ax, word ptr [bx + 10]
    mov word ptr es:[di + 30], ax
    call flush_directory
.L_urh_restore:
    pop ax
    mov word ptr [dir_parent_cluster], ax
.L_urh_done:
    pop es
    pop di
    pop cx
    pop ax
    ret

/* Release one JFT handle from current PSP. BX=5..8, CF=1 if invalid.
 * The underlying file record is closed only after its last reference goes.
 * Preserves general registers except flags, allowing process-exit cleanup. */
release_handle:
    push ax
    push bx
    push cx
    push di
    push es
    call locate_handle
    jc .L_rh_invalid
    /* Locate JFT slot by reverse-mapping the shared record pointer. */
    mov di, bx
    sub di, offset handles
    mov cl, 4
    shr di, cl
    mov ax, word ptr [current_psp]
    mov es, ax
    mov byte ptr es:[di + 0x1d], 0xff
    cmp byte ptr [handle_refs + di], 0
    je .L_rh_invalid
    dec byte ptr [handle_refs + di]
    jnz .L_rh_ok
    call update_root_handle
    mov byte ptr [bx], 0
.L_rh_ok:
    clc
    jmp .L_rh_done
.L_rh_invalid:
    stc
.L_rh_done:
    pop es
    pop di
    pop cx
    pop bx
    pop ax
    ret

/* Called at process exit: release ONLY this PSP's JFT references. The
 * resident COMMAND.COM's file records survive termination of a child. */
close_all_handles:
    push ax
    push bx
    push cx
    mov bx, 5
    mov cx, 4
.L_cah_loop:
    call release_handle
    inc bx
    loop .L_cah_loop
    call flush_metadata
    jnc .L_cah_ok
    mov si, offset sync_error_message
    call print_z
.L_cah_ok:
    pop cx
    pop bx
    pop ax
    ret

/* Persist buffered file content from IO_SEG to its allocated cluster. */
flush_write_cache:
    push ax
    push bx
    push cx
    push dx
    push es
    cmp byte ptr [rw_cache_dirty], 0
    je .L_fwc_ok
    mov ax, IO_SEG
    mov es, ax
    xor bx, bx
    mov ax, word ptr [rw_cached_cluster]
    add ax, DATA_BIAS
    call write_sector
    jc .L_fwc_fail
    mov byte ptr [rw_cache_dirty], 0
.L_fwc_ok:
    clc
    jmp .L_fwc_exit
.L_fwc_fail:
    stc
.L_fwc_exit:
    pop es
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* Append/overwrite one byte in file, returning CF on failure.
 * Pos+size changes are performed by the AH=40h caller. Newly allocated
 * clusters are zero-filled to avoid writing stale disk data.
 */
write_file_byte:
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov byte ptr [rw_saved_byte], al
    mov ax, word ptr [bx + 6]
    mov cl, 7
    shl ax, cl
    mov dx, word ptr [bx + 4]
    mov cl, 9
    shr dx, cl
    or ax, dx
    mov word ptr [rw_saved_ordinal], ax
    cmp ax, word ptr [rw_cached_sector]
    jne .L_wfb_new_sector
    cmp bx, word ptr [rw_cached_handle]
    je .L_wfb_copy
.L_wfb_new_sector:
    call flush_write_cache
    jc .L_wfb_io_err
    mov word ptr [rw_cached_sector], 0xffff
    mov byte ptr [rw_new_cluster], 0
    mov si, word ptr [rw_saved_ordinal]
    mov dx, word ptr [bx + 2]
    test dx, dx
    jnz .L_wfb_follow
    test si, si
    jnz .L_wfb_io_err
    call allocate_cluster
    jc .L_wfb_full
    mov word ptr [bx + 2], ax
    mov dx, ax
    mov byte ptr [rw_new_cluster], 1
.L_wfb_follow:
    test si, si
    jz .L_wfb_found
    cmp dx, 2
    jb .L_wfb_io_err
    cmp dx, 2784
    ja .L_wfb_io_err
    mov ax, dx
    call fat_next
    cmp ax, 0xff8
    jb .L_wfb_existing_next
    mov word ptr [rw_prev_cluster], dx
    call allocate_cluster
    jc .L_wfb_full
    mov word ptr [rw_alloc_new], ax
    mov dx, ax
    mov ax, word ptr [rw_prev_cluster]
    call fat_set
    mov dx, word ptr [rw_alloc_new]
    mov byte ptr [rw_new_cluster], 1
    jmp .L_wfb_advance
.L_wfb_existing_next:
    mov dx, ax
.L_wfb_advance:
    dec si
    jmp .L_wfb_follow
.L_wfb_found:
    cmp dx, 2
    jb .L_wfb_io_err
    cmp dx, 2784
    ja .L_wfb_io_err
    mov word ptr [rw_cached_cluster], dx
    mov ax, IO_SEG
    mov es, ax
    cmp byte ptr [rw_new_cluster], 0
    jne .L_wfb_zero
    xor bx, bx
    mov ax, dx
    add ax, DATA_BIAS
    call read_sector
    jc .L_wfb_io_err
    jmp .L_wfb_ready
.L_wfb_zero:
    xor di, di
    xor ax, ax
    mov cx, 256
    rep stosw
.L_wfb_ready:
    mov ax, word ptr [rw_saved_ordinal]
    mov word ptr [rw_cached_sector], ax
    mov ax, word ptr [rw_handle]
    mov word ptr [rw_cached_handle], ax
.L_wfb_copy:
    mov ax, IO_SEG
    mov es, ax
    mov bx, word ptr [rw_handle]
    mov si, word ptr [bx + 4]
    and si, 511
    mov al, byte ptr [rw_saved_byte]
    mov byte ptr es:[si], al
    mov byte ptr [rw_cache_dirty], 1
    clc
    jmp .L_wfb_exit
.L_wfb_full:
    mov byte ptr [write_errno], 39
    stc
    jmp .L_wfb_exit
.L_wfb_io_err:
    mov byte ptr [write_errno], 29
    stc
.L_wfb_exit:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

/* AX=LBA, ES:BX=512-byte source; CF indicates BIOS write failure. */
write_sector:
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
    mov ax, 0x0301
    int 0x13
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* Preload FAT #1 and root directory into memory. */
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

/* DOS DTA search buffer and per-process pointer. */
.align 2
dta_seg:          .word 0
dta_off:          .word 0
kernel_dta:       .space 43
search_pattern:   .space 11
search_attr:      .byte 0
.align 2
search_index:     .word 0
search_entry:     .space 32
attr_mode:        .byte 0

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
handles:           .space 64  /* 4 x 16-byte read/write handle records */
handle_refs:       .space 4   /* references across shell + child JFTs */
open_mode:         .byte 0
file_attributes:   .byte 0
fs_dirty:          .byte 0
rw_cache_dirty:    .byte 0
rw_new_cluster:    .byte 0
write_errno:       .byte 0
.align 2
file_dir_offset:   .word 0
new_handle:        .word 0
new_handle_number: .word 0
rw_cached_handle:  .word 0
rw_cached_cluster: .word 0
rw_saved_ordinal:  .word 0
rw_saved_byte:     .byte 0
.align 2
rw_prev_cluster:   .word 0
rw_alloc_new:      .word 0
free_next:         .word 0
sync_error_message: .asciz "WARNING: disk metadata sync failed.\r\n"
.align 2
exe_hdrparas:      .word 0
exe_hdrbytes:       .word 0
exe_image_total:    .word 0
exe_image_bytes:    .word 0
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
.align 2
dir_parent_cluster: .word 0
dir_cluster_count: .word 0
dir_last_cluster:  .word 0
new_dir_offset:    .word 0
cwd_cluster:        .word 0
cwd_depth:          .byte 0
path_depth:         .byte 0
path_directory_only:.byte 0
.align 2
cwd_stack:          .space 16
path_stack:         .space 16
cwd_text:           .space 128
new_dir_cluster:    .word 0
saved_parent_cluster:.word 0

/* A minimal non-reentrant EXEC context; kernel shell is a recovery fallback. */
current_psp:        .word APP_SEG
psp_parent:         .word 0
current_env_seg:    .word ENV_SEG
exec_env_source:    .word 0
exec_load_segment:  .word APP_SEG
exec_active:        .byte 0
exec_exe_mode:      .byte 0
.align 2
exec_parent_ss:     .word 0
exec_parent_sp:     .word 0
exec_parent_dta_seg:.word 0
exec_parent_dta_off:.word 0
command_filename:   .ascii "COMMAND COM"
shell_failed_message:.asciz "Standalone COMMAND.COM unavailable; recovery shell active.\r\n"

cmdline:            .space 128
cmdtail:            .space 128
cmdtail_len:        .byte 0
last_exit_code:     .byte 0
/* DOS environment strings are NUL-separated and double-NUL terminated.
 * The trailing count=1 and ASCIIZ path are conventional DOS 3+ metadata. */
environment_template:
    .asciz "PATH=A:\\"
    .asciz "PROMPT=$P$G"
    .byte 0
    .word 1
    .asciz "A:\\VELVETDOS"
environment_end:
banner:             .asciz "\r\nVelvetDOS 0.11.0  [pre-alpha]\r\nGNU GPLv3 | Type HELP for commands.\r\n"
prompt:             .asciz "\r\nA:\\"
cmd_help:           .asciz "HELP"
cmd_dir:            .asciz "DIR"
cmd_ver:            .asciz "VER"
cmd_cls:            .asciz "CLS"
cmd_status:         .asciz "STATUS"
cmd_reboot:         .asciz "REBOOT"
help_text:          .asciz "Commands: HELP, DIR, CD, MD, RD, VER, CLS, STATUS, REBOOT\r\nRun .COM or small MZ .EXE programs with command-line arguments.\r\nPSP command tail, environment and limited DOS file API.\r\n"
status_message:     .asciz "Last program exit code (hex): "
dir_header:         .asciz "Directory:\r\n"
dir_marker:         .asciz "  <DIR>"
dir_error_message:  .asciz "Directory operation failed.\r\n"
bad_command_message:.asciz "Bad command or file name.\r\n"
load_error_message: .asciz "Unable to load DOS program (format, size or disk error).\r\n"
disk_error_message: .asciz "FATAL: Cannot read floppy disk.\r\n"
.align 2
stack_start: .space 2048
stack_end:
