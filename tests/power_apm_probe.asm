bits 16
org 100h

mov ax, 0e7ffh
int 2fh
cmp bx, 1
jne fail
cmp cx, 1
jne fail
cmp dx, 1
jb fail

mov bl, 0
mov ax, 0e801h
int 2fh
cmp ax, 0e8ffh
jne fail
mov bl, 1
mov ax, 0e801h
int 2fh
cmp ax, 0e8ffh
jne fail
int 28h

mov ax, 0e7ffh
int 2fh
cmp dx, 2
jb fail
cmp si, 1
jb fail
cmp di, 1
jb fail
mov dx, pass_message
jmp short print
fail:
mov dx, fail_message
print:
mov ah, 9
int 21h
mov ax, 4c00h
int 21h

pass_message db 'POWER_APM_PASS',13,10,'$'
fail_message db 'POWER_APM_FAIL',13,10,'$'
