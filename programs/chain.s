/* Multi-cluster .COM loader regression, GPL-3.0-only.
 * Ends before the data padding. Confirms the loader follows FAT12 chains. */
.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global _start
.org 0x100
_start:
    mov dx, offset message
    mov ah, 0x09
    int 0x21
    mov ax, 0x4c00
    int 0x21
message: .ascii "CHAIN.COM loaded from more than one FAT12 cluster!\r\n$"
.rept 1100
    nop
.endr
