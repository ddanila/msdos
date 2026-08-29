bits 16
org 100h

int 63h
mov dx, pass_message
mov ah, 09h
int 21h
mov ax, 4c00h
int 21h

pass_message db 'LOADHIGH_TSR_TRIGGER_PASS',13,10,'$'
