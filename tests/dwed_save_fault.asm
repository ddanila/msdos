; SPDX-License-Identifier: MIT
; Fail actual editor-owned DOS saves; Caps Lock releases persistent faults.
bits 16
org 100h
jmp install
old21: dd 0
telemetry: dw 0,0,0ffffh,0,0 ; injected, renames, owned handle, creates, failures
journal_handle: dw 0ffffh
active: db 0
released: db 0
handler:
 cmp ah,5bh
 je created
 cmp byte [cs:active],0
 je chain
%if FAULT <= 2
 cmp word [cs:telemetry],0
 jne chain
%else
 push ax
 push es
 mov ax,40h
 mov es,ax
 test byte [es:17h],40h
 pop es
 pop ax
 jz fault_active
 mov byte [cs:active],0
 mov byte [cs:released],1
 jmp chain
fault_active:
%endif
%if FAULT = 1 || FAULT = 3 || FAULT = 6
 cmp ah,3eh
 jne chain
%if FAULT = 6
 cmp bx,[cs:journal_handle]
%else
 cmp bx,[cs:telemetry+4]
%endif
 jne chain
%elif FAULT = 2 || FAULT = 4
 cmp ah,56h
 jne chain
 inc word [cs:telemetry+2]
%if FAULT = 2
 cmp word [cs:telemetry+2],2
 jne chain
%else
 cmp word [cs:telemetry+2],3
 jb chain
%endif
%else
 cmp ah,41h
 jne chain
 push si
 mov si,dx
 cmp byte [si+3],'$'
 jne delete_other
 cmp word [si+4],'EB'
delete_other:
 pop si
 jne chain
%endif
 mov word [cs:telemetry],1
 inc word [cs:telemetry+8]
 mov ax,5
failed:
 push bp
 mov bp,sp
 or word [ss:bp+6],1
 pop bp
 iret
created:
 ; Only the payload create arms these faults; recovery records are separate.
 push si
 mov si,dx
 cmp byte [si+3],'$'
 jne created_other
 cmp word [si+4],'ER'
 je created_journal
 cmp word [si+4],'ED'
created_other:
 pop si
 jne chain
 pushf
 call far [cs:old21]
 jc failed
 mov [cs:telemetry+4],ax
 inc word [cs:telemetry+6]
 cmp byte [cs:released],0
 jne created_done
 mov byte [cs:active],1
created_done:
 push bp
 mov bp,sp
 and word [ss:bp+6],0fffeh
 pop bp
 iret
created_journal:
 pop si
 pushf
 call far [cs:old21]
 jc failed
 mov [cs:journal_handle],ax
 jmp created_done
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
