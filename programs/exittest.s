/* VelvetDOS 0.7.0 DOS process exit code probe. GPL-3.0-only. */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    mov dx, offset message
    mov ah, 9
    int 0x21
    mov ax, 0x4c2a  /* DOS exit status 42 decimal, 2Ah hex */
    int 0x21
message: .ascii "EXITTEST.COM: returning code 2A hex (42 decimal).\r\n$"
