/* VelvetDOS 0.6.0 multi-cluster FAT12 directory regression.
 * GPL-3.0-only. Use on a disposable writable FAT12 floppy image.
 * The first 14 files fill cluster 1 (alongside . and ..); files 15..20
 * require the kernel to allocate and use a second directory cluster.
 */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    mov word ptr [step], offset st_mkdir
    mov dx, offset dirname
    mov ah, 0x39
    int 0x21
    jc failed
    mov word ptr [counter], 0
.L_create_loop:
    call set_filename
    mov word ptr [step], offset st_create
    mov dx, offset filename
    xor cx, cx
    mov ah, 0x3c
    int 0x21
    jc failed
    mov word ptr [handle], ax
    mov ax, word ptr [counter]
    mov byte ptr [value], al
    mov word ptr [step], offset st_write
    mov bx, word ptr [handle]
    mov dx, offset value
    mov cx, 1
    mov ah, 0x40
    int 0x21
    jc failed
    cmp ax, 1
    jne failed
    mov word ptr [step], offset st_close
    mov bx, word ptr [handle]
    mov ah, 0x3e
    int 0x21
    jc failed
    inc word ptr [counter]
    cmp word ptr [counter], 20
    jb .L_create_loop

    /* Enumerate all twenty files in the new directory via DOS DTA. */
    mov word ptr [step], offset st_find
    mov dx, offset dta
    mov ah, 0x1a
    int 0x21
    mov dx, offset pattern
    xor cx, cx
    mov ah, 0x4e
    int 0x21
    jc failed
    mov word ptr [found], 1
.L_find_loop:
    mov word ptr [step], offset st_findnext
    mov ah, 0x4f
    int 0x21
    jc .L_find_end
    inc word ptr [found]
    cmp word ptr [found], 20
    jbe .L_find_loop
    jmp failed            /* duplicate entries or broken enumeration */
.L_find_end:
    cmp ax, 18            /* DOS: no more files */
    jne failed
    cmp word ptr [found], 20
    jne failed

    /* Reopen the last file using an absolute path: it is in cluster 2. */
    mov word ptr [counter], 19
    call set_filename
    mov word ptr [step], offset st_reopen
    mov dx, offset filename
    mov ax, 0x3d00
    int 0x21
    jc failed
    mov word ptr [handle], ax
    mov word ptr [step], offset st_read
    mov bx, ax
    mov dx, offset value
    mov cx, 1
    mov ah, 0x3f
    int 0x21
    jc failed
    cmp ax, 1
    jne failed
    cmp byte ptr [value], 19
    jne failed
    mov word ptr [step], offset st_close
    mov bx, word ptr [handle]
    mov ah, 0x3e
    int 0x21
    jc failed

    /* Deleting 20 entries must preserve the directory FAT chain and RD
     * must free both clusters, rather than rejecting a grown directory. */
    mov word ptr [counter], 0
.L_delete_loop:
    call set_filename
    mov word ptr [step], offset st_delete
    mov dx, offset filename
    mov ah, 0x41
    int 0x21
    jc failed
    inc word ptr [counter]
    cmp word ptr [counter], 20
    jb .L_delete_loop
    mov word ptr [step], offset st_rmdir
    mov dx, offset dirname
    mov ah, 0x3a
    int 0x21
    jc failed

    mov dx, offset msg_ok
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21

/* Update the only two digits of A:\\GROW\\Fnn.TST. */
set_filename:
    push ax
    push bx
    xor ax, ax
    mov ax, word ptr [counter]
    mov bl, 10
    div bl
    add al, '0'
    add ah, '0'
    mov byte ptr [tens], al
    mov byte ptr [ones], ah
    pop bx
    pop ax
    ret

failed:
    push ax
    mov dx, offset msg_fail
    mov ah, 9
    int 0x21
    mov dx, word ptr [step]
    mov ah, 9
    int 0x21
    pop ax
    push ax
    mov dx, offset msg_ax
    mov ah, 9
    int 0x21
    pop ax
    call hex_ax
    mov dx, offset eol
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
.L_hex_digit:
    rol bx, 1
    rol bx, 1
    rol bx, 1
    rol bx, 1
    mov dl, bl
    and dl, 15
    cmp dl, 9
    jbe .L_hex_numeric
    add dl, 'A' - 10
    jmp .L_hex_out
.L_hex_numeric:
    add dl, '0'
.L_hex_out:
    mov ah, 2
    int 0x21
    loop .L_hex_digit
    pop dx
    pop cx
    pop bx
    pop ax
    ret

dirname: .asciz "A:\\GROW"
filename: .ascii "A:\\GROW\\F"
tens: .byte '0'
ones: .byte '0'
          .asciz ".TST"
pattern: .asciz "A:\\GROW\\*.TST"
msg_ok: .ascii "DIRGROW.COM: 20 files, FAT directory growth, DTA, cleanup PASS!\r\n$"
msg_fail: .ascii "DIRGROW.COM failed at: $"
msg_ax: .ascii " AX=$"
eol: .ascii "\r\n$"
st_mkdir: .ascii "MD GROW $"
st_create: .ascii "Create file $"
st_write: .ascii "Write file $"
st_close: .ascii "Close file $"
st_find: .ascii "FindFirst $"
st_findnext: .ascii "FindNext/count $"
st_reopen: .ascii "Open last file $"
st_read: .ascii "Read last file $"
st_delete: .ascii "Delete file $"
st_rmdir: .ascii "RD grown directory $"
.align 2
step: .word st_mkdir
counter: .word 0
found: .word 0
handle: .word 0
value: .byte 0
dta: .space 43
