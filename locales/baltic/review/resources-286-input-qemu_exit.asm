bits 16
org 100h

mov dx, 0f4h
mov ax, 10h
out dx, ax
mov ax, 4c00h
int 21h
