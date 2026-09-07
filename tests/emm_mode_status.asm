; Public CPU state only; usable unchanged on retail DOS and this repository.
bits 16
org 100h
    push cs
    pop ds
    smsw ax
    and al,1
    add al,'0'
    mov [value],al
    mov dx,message
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
message db 'CPU_PE='
value db '0',13,10,'$'
