; SPDX-License-Identifier: MIT
; Inject recovery read faults; Caps Lock releases errors or enables corruption.
bits 16
org 100h
jmp install
old21: dd 0
owned: dw 0ffffh
reads: dw 0
active: db 0
handler:
 cmp ah,3dh
 je opening
%if FAULT = 5
 cmp ah,3eh
 jne .not_close
 cmp bx,[cs:owned]
 jne chain
 mov byte [cs:active],0
 jmp chain
.not_close:
%endif
 cmp byte [cs:active],0
 je chain
 cmp bx,[cs:owned]
 jne chain
 push ax
 push es
 mov ax,40h
 mov es,ax
 test byte [es:17h],40h
 pop es
 pop ax
%if FAULT = 5
 ; Corrupt only the returned saved-document bytes after confirmation.
 jz chain
 cmp ah,3fh
 jne chain
 pushf
 call far [cs:old21]
 jc returned_failure
 test ax,ax
 jz success
 push si
 mov si,dx
 xor byte [si],1
 pop si
 jmp success
%else
 jnz chain
%endif
%if FAULT = 4
 cmp ah,3eh
 jne chain
 jmp failed
%else
 cmp ah,3fh
 jne chain
 inc word [cs:reads]
%if FAULT = 1
 jmp failed
%else
 cmp word [cs:reads],1
 jne later_read
 cmp cx,16
 jbe chain
 mov cx,16
 jmp chain
later_read:
%if FAULT = 3
 xor ax,ax
 jmp success
%else
 jmp failed
%endif
%endif
%endif
opening:
 push si
 mov si,dx
%if FAULT = 5
 cmp word [si+3],'SA'
 jne other_open
 cmp word [si+5],'MP'
 jne other_open
 cmp word [si+7],'LE'
 jne other_open
 cmp word [si+9],'.T'
 jne other_open
 cmp word [si+11],'XT'
 jne other_open
 cmp byte [si+13],0
%else
 cmp byte [si+3],'$'
 jne other_open
%if FAULT = 1 || FAULT = 4
 cmp word [si+4],'ER'
%else
 cmp word [si+4],'ED'
%endif
%endif
other_open:
 pop si
 jne chain
 pushf
 call far [cs:old21]
 jc returned_failure
 mov [cs:owned],ax
 mov word [cs:reads],0
 mov byte [cs:active],1
success:
 push bp
 mov bp,sp
 and word [ss:bp+6],0fffeh
 pop bp
 iret
failed:
 mov ax,5
returned_failure:
 push bp
 mov bp,sp
 or word [ss:bp+6],1
 pop bp
 iret
chain:
 jmp far [cs:old21]
resident_end:
install:
 push cs
 pop ds
 mov ax,3521h
 int 21h
 mov [old21],bx
 mov [old21+2],es
 mov dx,handler
 mov ax,2521h
 int 21h
 mov dx,(resident_end-$$+100h+15)/16
 mov ax,3100h
 int 21h
