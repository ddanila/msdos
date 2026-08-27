bits 16
org 100h

int 60h
int 61h
mov dx, pass_message
mov ah, 09h
int 21h
mov dx, 0f4h
mov ax, 10h
out dx, ax
mov ax, 4c00h
int 21h

pass_message db 'INT21_TSR_TRIGGER_PASS', 13, 10, '$'
