/* VelvetDOS v0.5 DOS-compatible .COM regression. GPL-3.0-only.
 * Calls DOS APIs only; does not use any VelvetDOS-private kernel interface.
 * Run on a disposable writable 86Box floppy image.
 */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    mov word ptr [stage], offset msg_dta
    mov dx, offset dta_a
    mov ah, 0x1a
    int 0x21
    jc failed
    mov ah, 0x2f
    int 0x21
    mov ax, ds
    mov cx, es
    cmp ax, cx
    jne failed
    cmp bx, offset dta_a
    jne failed

    mov word ptr [stage], offset msg_find
    mov dx, offset find_com
    xor cx, cx
    mov ah, 0x4e
    int 0x21
    jc failed
    cmp byte ptr [dta_a + 21], 0x20 /* archive file */
    jne failed
    /* Opening a second search on a different DTA must not destroy the first. */
    mov word ptr [stage], offset msg_parallel
    mov dx, offset dta_b
    mov ah, 0x1a
    int 0x21
    mov dx, offset find_exe
    xor cx, cx
    mov ah, 0x4e
    int 0x21
    jc failed
    mov dx, offset dta_a
    mov ah, 0x1a
    int 0x21
    mov ah, 0x4f
    int 0x21
    jc failed
    cmp byte ptr [dta_a + 30], 0
    je failed

    mov word ptr [stage], offset msg_nomatch
    mov dx, offset find_none
    xor cx, cx
    mov ah, 0x4e
    int 0x21
    jnc failed
    cmp ax, 18
    jne failed

    mov word ptr [stage], offset msg_space
    xor dl, dl
    mov ah, 0x36
    int 0x21
    cmp ax, 1
    jne failed
    cmp cx, 512
    jne failed
    cmp dx, 2783
    jne failed
    cmp bx, 0
    je failed
    mov dl, 2                    /* invalid drive B: on floppy-only kernel */
    mov ah, 0x36
    int 0x21
    cmp ax, 0xffff
    jne failed

    mov word ptr [stage], offset msg_create
    mov dx, offset test_file
    xor cx, cx
    mov ah, 0x3c
    int 0x21
    jc failed
    mov word ptr [test_handle], ax

    mov word ptr [stage], offset msg_date
    mov bx, word ptr [test_handle]
    mov cx, 0x6b0f              /* DOS time: 13:24:30 */
    mov dx, 0x5d4e              /* DOS date: 2026-10-14 */
    mov ax, 0x5701
    int 0x21
    jc failed
    mov ax, 0x5700
    int 0x21
    jc failed
    cmp cx, 0x6b0f
    jne failed
    cmp dx, 0x5d4e
    jne failed
    mov ah, 0x3e
    int 0x21
    jc failed

    mov word ptr [stage], offset msg_attr
    mov dx, offset test_file
    mov cx, 0x02                 /* hidden flag */
    mov ax, 0x4301
    int 0x21
    jc failed
    mov dx, offset test_file
    mov ax, 0x4300
    int 0x21
    jc failed
    cmp cx, 2
    jne failed

    mov word ptr [stage], offset msg_hidden
    mov dx, offset find_tst
    xor cx, cx
    mov ah, 0x4e
    int 0x21
    jnc failed                 /* hidden files must be excluded */
    cmp ax, 18
    jne failed
    mov dx, offset find_tst
    mov cx, 2
    mov ah, 0x4e
    int 0x21
    jc failed
    cmp byte ptr [dta_a + 21], 2
    jne failed
    mov si, offset expected_name
    mov di, offset dta_a + 30
    mov cx, 11
compare_name:
    mov al, byte ptr [si]
    cmp al, byte ptr [di]
    jne failed
    inc si
    inc di
    loop compare_name

    mov word ptr [stage], offset msg_persist
    mov dx, offset test_file
    mov ax, 0x3d00
    int 0x21
    jc failed
    mov bx, ax
    mov ax, 0x5700
    int 0x21
    jc failed
    cmp cx, 0x6b0f
    jne failed
    cmp dx, 0x5d4e
    jne failed
    mov ah, 0x3e
    int 0x21
    jc failed

    mov word ptr [stage], offset msg_cleanup
    mov dx, offset test_file
    mov cx, 0x20
    mov ax, 0x4301
    int 0x21
    jc failed
    mov dx, offset test_file
    mov ah, 0x41
    int 0x21
    jc failed

    mov dx, offset msg_ok
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21
failed:
    push ax
    mov dx, offset msg_fail
    mov ah, 9
    int 0x21
    mov dx, word ptr [stage]
    mov ah, 9
    int 0x21
    pop ax
    call hex_ax
    mov dx, offset newline
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21
hex_ax:
    push ax
    push bx
    push cx
    push dx
    mov bx, ax
    mov cx, 4
.L_hex_loop:
    rol bx, 1
    rol bx, 1
    rol bx, 1
    rol bx, 1
    mov dl, bl
    and dl, 0x0f
    cmp dl, 10
    jb .L_hex_num
    add dl, 'A' - 10
    jmp .L_hex_put
.L_hex_num:
    add dl, '0'
.L_hex_put:
    mov ah, 2
    int 0x21
    loop .L_hex_loop
    pop dx
    pop cx
    pop bx
    pop ax
    ret

stage:       .word 0
test_handle: .word 0
find_com:     .asciz "*.COM"
find_exe:     .asciz "*.EXE"
find_none:    .asciz "NOFILE.XYZ"
find_tst:     .asciz "*.TST"
test_file:    .asciz "ATTR05.TST"
expected_name:.asciz "ATTR05.TST"
msg_dta:      .ascii "set/get DTA $"
msg_find:     .ascii "FindFirst *.COM $"
msg_parallel: .ascii "two independent DTA searches $"
msg_nomatch:  .ascii "FindFirst no match $"
msg_space:    .ascii "disk free space $"
msg_create:   .ascii "create ATTR05.TST $"
msg_date:     .ascii "set/read timestamp $"
msg_attr:     .ascii "set/read file attributes $"
msg_hidden:   .ascii "hidden wildcard filter $"
msg_persist:  .ascii "timestamp persists after close $"
msg_cleanup:  .ascii "remove test file $"
msg_fail:     .ascii "FINDTEST.COM FAIL at: $"
msg_ok:       .ascii "FINDTEST.COM: all DOS API checks PASS!\r\n$"
newline:      .ascii "\r\n$"
.align 2
dta_a:        .space 43
dta_b:        .space 43
