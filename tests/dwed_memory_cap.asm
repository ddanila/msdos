; SPDX-License-Identifier: MIT
; Test-only TSR: leave LIMIT_KIB in the free block following this COM image.
bits 16
cpu 8086
org 100h
%ifndef LIMIT_KIB
%error LIMIT_KIB required
%endif
    mov ax,cs
    dec ax
    mov es,ax
    mov dx,[es:3]
    sub dx,LIMIT_KIB*64+1 ; one MCB separates retained and free blocks
    jc failed
    cmp dx,(resident_end-$$+100h+15)/16
    jb failed
    mov ax,3100h
    int 21h
failed:
    mov ax,4c01h
    int 21h
resident_end:
