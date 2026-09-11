; SPDX-License-Identifier: MIT
; One-shot failure at an actual editor-owned DOS save operation.
bits 16
org 100h
jmp install
old21: dd 0
telemetry: dw 0,0,0ffffh ; injected, rename count, owned handle
active: db 0
handler:
 cmp ah,5bh
 je created
 cmp byte [cs:active],0
 je chain
 cmp word [cs:telemetry],0
 jne chain
%if FAULT = 1
 cmp ah,3eh
 jne chain
 cmp bx,[cs:telemetry+4]
 jne chain
%else
 cmp ah,56h
 jne chain
 inc word [cs:telemetry+2]
 cmp word [cs:telemetry+2],2
 jne chain
%endif
 mov word [cs:telemetry],1
 mov ax,5
failed:
 push bp
 mov bp,sp
 or word [ss:bp+6],1
 pop bp
 iret
created:
 pushf
 call far [cs:old21]
 jc failed
 mov [cs:telemetry+4],ax
 mov byte [cs:active],1
 push bp
 mov bp,sp
 and word [ss:bp+6],0fffeh
 pop bp
 iret
chain:
 jmp far [cs:old21]
resident_end:
pointer_data: db 'DWSF'
 dw telemetry,0
filename: db 'C:\SFAULT.PTR',0
install:
 push cs
 pop ds
 mov [pointer_data+6],cs
 mov ax,3521h
 int 21h
 mov [old21],bx
 mov [old21+2],es
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
 mov ax,2521h
 int 21h
 mov dx,(resident_end-$$+100h+15)/16
 mov ax,3100h
 int 21h
fail:
 mov ax,4c01h
 int 21h
