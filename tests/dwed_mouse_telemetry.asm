; SPDX-License-Identifier: MIT
; Observe the real driver's function 3 replies without supplying mouse events.
bits 16
org 100h
jmp install
old33: dd 0
telemetry: dw 0,0,0
handler:
 cmp ax,3
 jne chain
 pushf
 call far [cs:old33]
 mov [cs:telemetry],bx
 mov [cs:telemetry+2],cx
 mov [cs:telemetry+4],dx
 iret
chain:
 jmp far [cs:old33]
resident_end:
pointer_data: db 'DWMP'
 dw telemetry,0
filename: db 'C:\MOUSE.PTR',0
install:
 push cs
 pop ds
 mov ax,0
 int 33h
 cmp ax,0ffffh
 jne fail
 mov [pointer_data+6],cs
 mov ax,3533h
 int 21h
 mov [old33],bx
 mov [old33+2],es
 mov dx,filename
 xor cx,cx
 mov ah,3ch
 int 21h
 jc fail
 mov bx,ax
 mov dx,pointer_data
 mov cx,8
 mov ah,40h
 int 21h
 jc fail
 cmp ax,8
 jne fail
 mov ah,3eh
 int 21h
 jc fail
 mov dx,handler
 mov ax,2533h
 int 21h
 mov dx,(resident_end-$$+100h+15)/16
 mov ax,3100h
 int 21h
fail:
 mov ax,4c01h
 int 21h
