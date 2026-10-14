/* VelvetDOS 0.1.0 -- FAT12 floppy bootstrap, GNU GPLv3.
 * Standard 1.44 MB BPB. 64 reserved sectors after the boot sector hold
 * the real-mode stage-2 kernel. The FAT filesystem remains conventional.
 */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
_start:
    jmp boot_entry
    nop
    .ascii "VELVET  "          /* OEM */
    .word 512                /* bytes / sector */
    .byte 1                  /* sectors / cluster */
    .word 65                 /* reserved sectors incl. this boot sector */
    .byte 2                  /* number of FATs */
    .word 224                /* root entries */
    .word 2880               /* total sectors */
    .byte 0xf0               /* floppy media */
    .word 9                  /* sectors per FAT */
    .word 18                 /* sectors per track */
    .word 2                  /* heads */
    .long 0                  /* hidden sectors */
    .long 0                  /* total sectors, large form */
    .byte 0                  /* drive number */
    .byte 0                  /* reserved */
    .byte 0x29               /* extended boot signature */
    .long 0x20261014         /* volume ID */
    .ascii "VELVETDOS  "     /* 11-byte volume label */
    .ascii "FAT12   "        /* filesystem hint */
boot_entry:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    sti
    mov byte ptr [boot_drive], dl
    mov ax, 0x1000
    mov es, ax
    xor bx, bx
    mov si, 1
    mov di, 64
.load:
    mov ax, si
    call read_sector
    jc disk_error
    add bx, 512
    inc si
    dec di
    jnz .load
    mov dl, byte ptr [boot_drive]
    mov ax, 0x1000
    push ax
    xor ax, ax
    push ax
    retf

disk_error:
    mov si, offset errstr
.error_char:
    lodsb
    test al, al
    jz .halt
    mov ah, 0x0e
    mov bx, 0x0007
    int 0x10
    jmp .error_char
.halt:
    cli
    hlt
    jmp .halt

/* AX=LBA (0..2879), ES:BX=buffer. CF indicates BIOS error. */
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
boot_drive: .byte 0
errstr: .asciz "\r\nVelvetDOS: disk read failed.\r\n"
.org 510
.word 0xaa55
