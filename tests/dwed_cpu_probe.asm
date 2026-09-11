; SPDX-License-Identifier: MIT
bits 16
org 100h
pushf
pop dx
mov bx,sp
push sp
pop ax
%if EXPECT_8086
sub bx,2
cmp ax,bx
jne fail
%else
cmp ax,bx
jne fail
; 286 real mode cannot set the high FLAGS bits; a 386 can set IOPL/NT.
mov ax,0f000h
push ax
popf
pushf
pop ax
push dx
popf
and ax,0f000h
jnz fail
%endif
mov dx,passed
mov ah,9
int 21h
mov ax,4c00h
int 21h
fail:
push dx
popf
mov dx,failed
mov ah,9
int 21h
mov ax,4c01h
int 21h
passed: db 'CPU MODEL PASS',13,10,'$'
failed: db 'CPU MODEL FAIL',13,10,'$'
