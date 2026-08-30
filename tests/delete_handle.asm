bits 16
org 100h

mov dx, filename
mov ah, 41h
int 21h
mov ax, 4c00h
jnc exit
mov al, 1
exit:
int 21h

filename db 'B:\HANDLE.TXT', 0
