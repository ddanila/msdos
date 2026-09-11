; SPDX-License-Identifier: MIT
; Terminate QEMU immediately after a selected successful DOS operation.
bits 16
org 100h
jmp install
old21: dd 0
journal_handle: dw 0ffffh
rename_count: dw 0
active: db 0
handler:
 cmp ah,5bh
 je create_new
 cmp byte [cs:active],0
 je chain
 cmp ah,56h
 je renamed
%if STAGE = 0
 cmp ah,3eh
 jne chain
 cmp bx,[cs:journal_handle]
 jne chain
 pushf
 call far [cs:old21]
 jc returned_failure
 jmp cut
%elif STAGE = 4
 cmp ah,41h
 jne chain
 push si
 mov si,dx
 cmp byte [si+3],'$'
 jne other_delete
 cmp word [si+4],'EB'
other_delete:
 pop si
 jne chain
 pushf
 call far [cs:old21]
 jc returned_failure
 jmp cut
%else
 jmp chain
%endif
renamed:
 pushf
 call far [cs:old21]
 jc returned_failure
 inc word [cs:rename_count]
%if STAGE >= 1 && STAGE <= 3
 cmp word [cs:rename_count],STAGE
 je cut
%endif
 jmp returned_success
create_new:
 push si
 mov si,dx
 cmp byte [si+3],'$'
 jne other_create
 cmp word [si+4],'ED'
 je payload
 cmp word [si+4],'ER'
 jne other_create
 pop si
 pushf
 call far [cs:old21]
 jc returned_failure
 mov [cs:journal_handle],ax
 jmp returned_success
payload:
 pop si
 pushf
 call far [cs:old21]
 jc returned_failure
 mov byte [cs:active],1
 jmp returned_success
other_create:
 pop si
chain:
 jmp far [cs:old21]
returned_failure:
 push bp
 mov bp,sp
 or word [ss:bp+6],1
 pop bp
 iret
returned_success:
 push bp
 mov bp,sp
 and word [ss:bp+6],0fffeh
 pop bp
 iret
cut:
 mov dx,0f4h
 mov ax,20h
 out dx,ax
 hlt
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
