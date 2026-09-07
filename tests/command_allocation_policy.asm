; Emit the public allocation strategy and UMB-link state as two little-endian
; words. The test compares these bytes across successful and failed placement.
bits 16
org 100h
    mov ax,5800h
    int 21h
    jc fail
    mov [policy],ax
    mov ax,5802h
    int 21h
    jc fail
    xor ah,ah
    mov [policy+2],ax
    mov bx,1
    mov dx,policy
    mov cx,4
    mov ah,40h
    int 21h
    jc fail
    cmp ax,4
    jne fail
    mov ax,4c00h
    int 21h
fail:
    mov ax,4c01h
    int 21h
policy dw 0,0
