/* VelvetDOS 0.12.0 resident DOS command interpreter.
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
    cmp word ptr [batch_handle], 0xffff
    je .L_interactive
    call batch_next_line
    jnc .L_dispatch
    jmp command_loop
.L_interactive:
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
.L_dispatch:
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
    mov di, offset hndtest_command
    call str_equal
    jc do_hndtest
    mov si, offset token
    mov di, offset memown_command
    call str_equal
    jc do_memown
    mov si, offset token
    mov di, offset exit_command
    call str_equal
    jc do_exit
    mov si, offset token
    mov di, offset set_command
    call str_equal
    jc do_set
    mov si, offset token
    mov di, offset path_command
    call str_equal
    jc do_path
    mov si, offset token
    mov di, offset echo_command
    call str_equal
    jc do_echo
    mov si, offset token
    mov di, offset rem_command
    call str_equal
    jc command_loop
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
    je .L_skip_char
    cmp byte ptr [si], '@'
    jne .L_token
.L_skip_char:
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
    /* An explicit .BAT is data for the shell, not an EXEC executable. */
    mov si, offset exec_name
.L_bat_scan:
    cmp byte ptr [si], 0
    je .L_bat_check
    inc si
    jmp .L_bat_scan
.L_bat_check:
    mov ax, si
    sub ax, offset exec_name
    cmp ax, 4
    jb .L_launch_exe
    cmp byte ptr [si-4], '.'
    jne .L_launch_exe
    cmp byte ptr [si-3], 'B'
    jne .L_launch_exe
    cmp byte ptr [si-2], 'A'
    jne .L_launch_exe
    cmp byte ptr [si-1], 'T'
    je start_batch
.L_launch_exe:
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
    cmp ax, 2
    jne .L_launch_failed
    /* Neither .COM nor .EXE exists: try .BAT. */
    mov di, word ptr [extension_location]
    mov byte ptr [di+1], 'B'
    mov byte ptr [di+2], 'A'
    mov byte ptr [di+3], 'T'
    jmp start_batch
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

/* Non-nested .BAT interpreter. All commands go through the same dispatcher as
 * interactive input. Handles remain owned by COMMAND.COM across child EXEC.
 * Reads one byte at a time using documented DOS AH=3Fh; no kernel changes. */
start_batch:
    cmp word ptr [batch_handle], 0xffff
    jne .L_batch_nested
    mov dx, offset exec_name
    mov ax, 0x3d80  /* DOS 3+: open read-only, do not inherit in EXEC child */
    int 0x21
    jc .L_batch_error
    mov word ptr [batch_handle], ax
    jmp command_loop
.L_batch_nested:
    mov dx, offset batch_nested_text
    call print_dollar
    jmp command_loop
.L_batch_error:
    mov dx, offset batch_open_error
    call print_dollar
    jmp command_loop

batch_next_line:
    push ax
    push bx
    push cx
    push dx
    push si
    mov si, offset input+2
    xor cx, cx
    mov byte ptr [batch_overflow], 0
.L_batch_char:
    mov bx, word ptr [batch_handle]
    mov dx, offset batch_char
    push cx
    mov cx, 1
    mov ah, 0x3f
    int 0x21
    pop cx
    jc .L_batch_eof
    cmp ax, 1
    jne .L_batch_eof
    mov al, byte ptr [batch_char]
    cmp al, 10
    je .L_batch_ready /* Accept both DOS CRLF and Unix LF scripts. */
    cmp al, 13
    je .L_batch_ready
    cmp cx, 123
    jae .L_batch_too_long
    mov byte ptr [si], al
    inc si
    inc cx
    jmp .L_batch_char
.L_batch_too_long:
    mov byte ptr [batch_overflow], 1
    jmp .L_batch_char
.L_batch_eof:
    mov bx, word ptr [batch_handle]
    mov ah, 0x3e
    int 0x21
    mov word ptr [batch_handle], 0xffff
    cmp cx, 0
    jne .L_batch_ready
    stc
    jmp .L_batch_return
.L_batch_ready:
    cmp byte ptr [batch_overflow], 0
    je .L_batch_line_ok
    mov dx, offset batch_line_long
    call print_dollar
    /* Don't execute a truncated command. */
    cmp word ptr [batch_handle], 0xffff
    je .L_batch_done
    xor cx, cx
    mov si, offset input+2
    mov byte ptr [batch_overflow], 0
    jmp .L_batch_char
.L_batch_line_ok:
    mov byte ptr [input+1], cl
    mov byte ptr [si], 0
    clc
    jmp .L_batch_return
.L_batch_done:
    stc
.L_batch_return:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

/* SET NAME=VALUE, SET NAME= (delete), and SET (list).
 * Writes a bounded 256-byte copy of the resident environment, preserving the
 * existing data if the replacement would overflow. Variable names are upper-
 * cased; values retain their case. No %VAR% expansion in this release. */
do_set:
    mov si, word ptr [args_pointer]
    call skip_spaces
    cmp byte ptr [si], 0
    je show_env
    mov di, offset set_entry
    mov cx, 31
.L_set_name:
    mov al, byte ptr [si]
    cmp al, '='
    je .L_set_name_done
    cmp al, 'a'
    jb .L_set_upper_done
    cmp al, 'z'
    ja .L_set_upper_done
    sub al, 32
.L_set_upper_done:
    cmp al, 'A'
    jb .L_set_digit
    cmp al, 'Z'
    jbe .L_set_name_ok
.L_set_digit:
    cmp al, '0'
    jb .L_set_underscore
    cmp al, '9'
    jbe .L_set_name_ok
.L_set_underscore:
    cmp al, '_'
    jne .L_set_invalid
.L_set_name_ok:
    test cx, cx
    jz .L_set_invalid
    mov byte ptr [di], al
    inc si
    inc di
    dec cx
    jmp .L_set_name
.L_set_name_done:
    cmp di, offset set_entry
    je .L_set_invalid
    mov byte ptr [di], '='
    inc si
    inc di
    call copy_set_value
    jc .L_set_invalid
    call commit_environment
    jc .L_set_full
    jmp command_loop
.L_set_invalid:
    mov dx, offset set_syntax_text
    call print_dollar
    jmp command_loop
.L_set_full:
    mov dx, offset set_full_text
    call print_dollar
    jmp command_loop

do_path:
    mov si, word ptr [args_pointer]
    call skip_spaces
    cmp byte ptr [si], 0
    je show_path
    mov byte ptr [set_entry], 'P'
    mov byte ptr [set_entry+1], 'A'
    mov byte ptr [set_entry+2], 'T'
    mov byte ptr [set_entry+3], 'H'
    mov byte ptr [set_entry+4], '='
    mov di, offset set_entry+5
    call copy_set_value
    jc .L_path_error
    call commit_environment
    jc .L_path_error
    jmp command_loop
.L_path_error:
    mov dx, offset set_full_text
    call print_dollar
    jmp command_loop

/* SI points to ASCIIZ value; append through NUL, limited to 125 bytes total. */
copy_set_value:
.L_csv_next:
    cmp di, offset set_entry+125
    jae .L_csv_overflow
    mov al, byte ptr [si]
    mov byte ptr [di], al
    inc di
    inc si
    test al, al
    jne .L_csv_next
    clc
    ret
.L_csv_overflow:
    stc
    ret

skip_spaces:
    cmp byte ptr [si], ' '
    jne .L_ss_done
    inc si
    jmp skip_spaces
.L_ss_done:
    ret

/* Compare the NAME= prefix of set_entry and ES:SI. Flags CF=1 on match.
 * Does not alter ES, SI, or DI in the caller. */
match_env_name:
    push ax
    push bx
    push di
    push si
    mov di, offset set_entry
.L_match_next:
    mov al, byte ptr [di]
    cmp al, '='
    je .L_match_equal
    cmp al, byte ptr es:[si]
    jne .L_match_no
    inc di
    inc si
    jmp .L_match_next
.L_match_equal:
    cmp byte ptr es:[si], '='
    jne .L_match_no
    stc
    jmp .L_match_end
.L_match_no:
    clc
.L_match_end:
    pop si
    pop di
    pop bx
    pop ax
    ret

/* Store a NUL-terminated string DS:SI into env_work.
 * DI points at next free byte; reserve >=1 byte for final extra NUL. */
append_env_string:
.L_append_env_loop:
    cmp di, offset env_work+254
    jae .L_append_env_fail
    mov al, byte ptr [si]
    mov byte ptr [di], al
    inc di
    inc si
    test al, al
    jnz .L_append_env_loop
    clc
    ret
.L_append_env_fail:
    stc
    ret

/* ES points to old env during scan; copy old strings through DS:temp_env.
 * Moves one original string into env_work with strict bounds. */
append_old_env:
    push ds
    push es
    pop ds
    /* DS=old environment; ES=old environment; use CS override on destination */
.L_old_copy:
    cmp si, 255
    jae .L_old_fail
    cmp di, offset env_work+254
    jae .L_old_fail
    mov al, byte ptr [si]
    mov byte ptr cs:[di], al
    inc si
    inc di
    test al, al
    jne .L_old_copy
    pop ds
    clc
    ret
.L_old_fail:
    pop ds
    stc
    ret

/* On input set_entry NAME=VALUE\0, update ENV_SEG safely.
 * ES is source environment; CS is the destination work buffer. */
commit_environment:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov ax, word ptr [0x2c]
    mov es, ax
    mov di, offset env_work
    mov si, offset set_entry
    /* When updating PATH, place it first (HNDCHILD expects PATH first). */
    cmp word ptr [set_entry], 0x4150  /* PA */
    jne .L_commit_old
    cmp word ptr [set_entry+2], 0x4854 /* TH */
    jne .L_commit_old
    cmp byte ptr [set_entry+4], '='
    jne .L_commit_old
    cmp byte ptr [set_entry+5], 0
    je .L_commit_old
    call append_env_string
    jc .L_commit_fail
    mov byte ptr [set_inserted], 1
    jmp .L_commit_scan
.L_commit_old:
    mov byte ptr [set_inserted], 0
.L_commit_scan:
    xor si, si
.L_commit_scan_next:
    cmp si, 254
    jae .L_commit_fail
    cmp byte ptr es:[si], 0
    je .L_commit_append_new
    call match_env_name
    jc .L_commit_skip
    call append_old_env
    jc .L_commit_fail
    jmp .L_commit_scan_next
.L_commit_skip:
    cmp si, 255
    jae .L_commit_fail
    mov al, byte ptr es:[si]
    inc si
    test al, al
    jne .L_commit_skip
    jmp .L_commit_scan_next
.L_commit_append_new:
    /* SI points to the extra NUL after the last NAME=VALUE string.
     * The standard DOS environment trailer (count + program path) follows.
     * Keep its offset before SI is reused to append the new variable. */
    mov word ptr [old_env_trailer], si
    cmp byte ptr [set_inserted], 1
    je .L_commit_finalize
    mov si, offset set_entry
    /* Do not add NAME= when the value is empty: SET NAME= deletes. */
.L_commit_find_eq:
    cmp byte ptr [si], '='
    je .L_commit_has_eq
    inc si
    jmp .L_commit_find_eq
.L_commit_has_eq:
    cmp byte ptr [si+1], 0
    je .L_commit_finalize
    mov si, offset set_entry
    call append_env_string
    jc .L_commit_fail
.L_commit_finalize:
    cmp di, offset env_work+255
    jae .L_commit_fail
    mov byte ptr [di], 0       /* second NUL ending environment variables */
    inc di
    /* Preserve the conventional DOS 3+ trailer, not just NAME=VALUE strings.
     * VelvetDOS currently supports one ASCIIZ program-name string. The old
     * environment remains untouched if the rebuilt block is too large. */
    mov si, word ptr [old_env_trailer]
    inc si                    /* old trailer follows old double-NUL */
    cmp si, 254               /* need a complete 16-bit count */
    ja .L_commit_fail
    cmp word ptr es:[si], 1
    jne .L_commit_fail
    cmp di, offset env_work+254
    ja .L_commit_fail
    mov word ptr [di], 1
    add di, 2
    add si, 2
.L_commit_tail_name:
    cmp si, 256               /* old name must terminate inside 256 bytes */
    jae .L_commit_fail
    cmp di, offset env_work+256
    jae .L_commit_fail
    mov al, byte ptr es:[si]
    mov byte ptr [di], al
    inc si
    inc di
    test al, al
    jne .L_commit_tail_name
    /* Zero unused environment space; avoids leaking stale variable contents. */
    mov bx, di
.L_commit_zero:
    cmp bx, offset env_work+256
    jae .L_commit_copy
    mov byte ptr [bx], 0
    inc bx
    jmp .L_commit_zero
.L_commit_copy:
    mov ax, word ptr [0x2c]
    mov es, ax
    xor di, di
    mov si, offset env_work
    mov cx, 256
    rep movsb
    clc
    jmp .L_commit_return
.L_commit_fail:
    stc
.L_commit_return:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

show_env:
    mov ax, word ptr [0x2c]
    mov es, ax
    xor si, si
.L_show_next:
    cmp si, 254
    jae command_loop
    cmp byte ptr es:[si], 0
    je command_loop
    push ds
    mov ax, es
    mov ds, ax
    call print_z
    pop ds
    mov dx, offset crlf
    call print_dollar
.L_show_skip:
    cmp byte ptr es:[si], 0
    je .L_show_advance
    inc si
    jmp .L_show_skip
.L_show_advance:
    inc si
    jmp .L_show_next

show_path:
    mov byte ptr [set_entry], 'P'
    mov byte ptr [set_entry+1], 'A'
    mov byte ptr [set_entry+2], 'T'
    mov byte ptr [set_entry+3], 'H'
    mov byte ptr [set_entry+4], '='
    mov byte ptr [set_entry+5], 0
    mov ax, word ptr [0x2c]
    mov es, ax
    xor si, si
.L_show_path_loop:
    cmp si, 254
    jae command_loop
    cmp byte ptr es:[si], 0
    je command_loop
    call match_env_name
    jnc .L_show_path_skip
    push ds
    mov ax, es
    mov ds, ax
    call print_z
    pop ds
    mov dx, offset crlf
    call print_dollar
    jmp command_loop
.L_show_path_skip:
    cmp byte ptr es:[si], 0
    je .L_show_path_advance
    inc si
    jmp .L_show_path_skip
.L_show_path_advance:
    inc si
    jmp .L_show_path_loop

do_echo:
    mov si, word ptr [args_pointer]
    call skip_spaces
    cmp byte ptr [si], 0
    je .L_echo_empty
    /* ECHO OFF/ON are accepted; batch output isn't echoed by default. */
    push si
    mov di, offset echo_off_word
    call str_equal
    pop si
    jc command_loop
    push si
    mov di, offset echo_on_word
    call str_equal
    pop si
    jc command_loop
    call print_z
.L_echo_empty:
    mov dx, offset crlf
    call print_dollar
    jmp command_loop

/* Validate shell/child JFT sharing. The child consumes one byte and closes
 * its own handle 5. COMMAND.COM must retain its own handle and see the next
 * byte ('E'). Exercises AH=3D, 4B, 3F, 3E across process boundaries. */
do_hndtest:
    mov dx, offset readme_name
    mov ax, 0x3d00
    int 0x21
    jc .L_hnd_fail
    mov word ptr [hndtest_handle], ax
    mov ax, cs
    mov word ptr [exec_parameters+4], ax
    mov dx, offset child_name
    mov bx, offset exec_parameters
    push ds
    pop es
    mov ax, 0x4b00
    int 0x21
    jc .L_hnd_cleanup_fail
    mov ah, 0x4d
    int 0x21
    test al, al
    jnz .L_hnd_cleanup_fail
    /* The child overwrote its own PATH marker; ours must still be 'P'. */
    mov bx, word ptr [0x2c]
    mov es, bx
    cmp byte ptr es:[0], 'P'
    jne .L_hnd_cleanup_fail
    mov bx, word ptr [hndtest_handle]
    mov dx, offset hndtest_byte
    mov cx, 1
    mov ah, 0x3f
    int 0x21
    jc .L_hnd_cleanup_fail
    cmp ax, 1
    jne .L_hnd_cleanup_fail
    cmp byte ptr [hndtest_byte], 'E'
    jne .L_hnd_cleanup_fail
    mov bx, word ptr [hndtest_handle]
    mov ah, 0x3e
    int 0x21
    jc .L_hnd_fail
    mov dx, offset hndtest_ok
    call print_dollar
    jmp command_loop
.L_hnd_cleanup_fail:
    mov bx, word ptr [hndtest_handle]
    mov ah, 0x3e
    int 0x21
.L_hnd_fail:
    mov dx, offset hndtest_bad
    call print_dollar
    jmp command_loop

/* Parent memory ownership / dynamic child placement regression.
 * The first free block is at 5000h. A parent allocation consumes it;
 * MEMCHILD.COM must execute above it, must not free the parent's block,
 * and any child allocations must be reclaimed by normal termination. */
do_memown:
    mov bx, 0x40
    mov ah, 0x48
    int 0x21
    jc .L_memown_fail
    mov word ptr [memown_segment], ax
    cmp ax, 0x5000
    jne .L_memown_cleanup_fail
    mov es, ax
    mov word ptr es:[0], 0x4556   /* 'VE' */
    mov word ptr es:[2], 0x564c   /* 'LV' */
    mov ax, cs
    mov word ptr [exec_parameters+4], ax
    mov dx, offset memchild_name
    mov bx, offset exec_parameters
    push ds
    pop es
    mov ax, 0x4b00
    int 0x21
    jc .L_memown_cleanup_fail
    mov ah, 0x4d
    int 0x21
    test al, al
    jnz .L_memown_cleanup_fail
    mov ax, word ptr [memown_segment]
    mov es, ax
    cmp word ptr es:[0], 0x4556
    jne .L_memown_cleanup_fail
    cmp word ptr es:[2], 0x564c
    jne .L_memown_cleanup_fail
    mov ah, 0x49
    int 0x21
    jc .L_memown_fail
    mov word ptr [memown_segment], 0
    /* A large allocation can succeed only if child-owned blocks
     * were freed and coalesced and the original parent block was freed. */
    mov bx, 0x3fff
    mov ah, 0x48
    int 0x21
    jc .L_memown_fail
    mov es, ax
    mov ah, 0x49
    int 0x21
    jc .L_memown_fail
    mov dx, offset memown_ok
    call print_dollar
    jmp command_loop
.L_memown_cleanup_fail:
    mov ax, word ptr [memown_segment]
    test ax, ax
    jz .L_memown_fail
    mov es, ax
    mov ah, 0x49
    int 0x21
    mov word ptr [memown_segment], 0
.L_memown_fail:
    mov dx, offset memown_bad
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

banner:       .ascii "\r\nVelvetDOS COMMAND.COM 0.12.0 [experimental]\r\n$"
prefix:       .ascii "\r\nA:\\$"
prompt_end:   .ascii ">$"
crlf:         .ascii "\r\n$"
help_text:    .ascii "HELP VER CLS DIR CD MD RD SET PATH ECHO REM STATUS HNDTEST MEMOWN REBOOT EXIT\r\n"
              .ascii "Run .COM, .EXE and simple .BAT files. Nested batch/EXEC unavailable.\r\n$"
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
hndtest_command:.asciz "HNDTEST"
memown_command:.asciz "MEMOWN"
set_command: .asciz "SET"
path_command:.asciz "PATH"
echo_command:.asciz "ECHO"
rem_command: .asciz "REM"
echo_off_word:.asciz "OFF"
echo_on_word: .asciz "ON"
set_syntax_text:.ascii "SET syntax: SET NAME=VALUE (names: letters, digits, underscore).\r\n$"
set_full_text: .ascii "Environment full (256-byte limit), value too long or invalid.\r\n$"
batch_nested_text:.ascii "Nested batch files not supported.\r\n$"
batch_open_error: .ascii "Batch file not found or cannot open.\r\n$"
batch_line_long: .ascii "Batch line too long (maximum 123 characters); skipped.\r\n$"
memchild_name: .asciz "MEMCHILD.COM"
memown_ok: .ascii "MEMOWN: parent MCB preserved, child MCBs reclaimed PASS!\r\n$"
memown_bad: .ascii "MEMOWN: process memory ownership FAIL!\r\n$"
memown_segment: .word 0
readme_name: .asciz "README.TXT"
child_name: .asciz "HNDCHILD.COM"
hndtest_ok: .ascii "HNDTEST: parent handle preserved across child close PASS!\r\n$"
hndtest_bad: .ascii "HNDTEST: inherited handle regression FAIL!\r\n$"
hndtest_handle: .word 0
hndtest_byte: .byte 0
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
.align 2
batch_handle: .word 0xffff
batch_overflow: .byte 0
batch_char: .byte 0
set_inserted: .byte 0
.align 2
old_env_trailer: .word 0  /* offset after old variable double-NUL */
set_entry: .space 126
env_work: .space 256
