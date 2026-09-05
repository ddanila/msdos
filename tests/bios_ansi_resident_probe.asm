; Exercise a real DEVICEHIGH resident alongside development DOS tables.
bits 16
org 100h
%include "public-layout.inc"
start:
    mov ax,5802h
    int 21h
    jc fail
    mov [old_link],al
    mov ah,52h
    int 21h
    mov ax,[es:bx-2]
    mov [arena_head],ax
    les si,[es:bx+PUB_SYSI_CON]
    mov ax,es
    mov [con_segment],ax
%if EXPECT_HIGH
    cmp ax,0a000h
    jb fail
    mov bx,1
    mov ax,5803h
    int 21h
    jc fail
    mov byte [link_changed],1
    mov ax,[arena_head]
    mov cx,256
.arena:
    mov es,ax
    cmp byte [es:0],'M'
    je .valid
    cmp byte [es:0],'Z'
    jne fail
.valid:
    mov dx,ax
    inc dx
    cmp [con_segment],dx
    jb .next
    add dx,[es:3]
    cmp [con_segment],dx
    jae .next
    cmp word [es:1],8
    jne fail
    jmp .found
.next:
    cmp byte [es:0],'Z'
    je fail
    add ax,[es:3]
    inc ax
    loop .arena
    jmp fail
.found:
    xor bx,bx
    mov bl,[old_link]
    mov ax,5803h
    int 21h
    jc fail
    mov byte [link_changed],0
%else
    cmp ax,0a000h
    jae fail
%endif
    ; CTTY AUX must not bypass the driver under test: explicitly open CON.
    mov dx,con_name
    mov ax,3d02h
    int 21h
    jc fail
    mov bx,ax
    mov ax,440ch
    mov cx,037fh
    mov dx,packet
    int 21h
    jc fail
    cmp byte [packet+6],1
    jne fail
    cmp word [packet+14],80
    jne fail
    mov dx,sequence
    mov cx,sequence_end-sequence
    mov ah,40h
    int 21h
    jc fail
    cmp ax,cx
    jne fail
    mov ah,3eh
    int 21h
    jc fail
    mov bh,0
    mov ah,03h
    int 10h
    cmp dx,0913h
    jne fail
    mov dx,passed
    mov ah,09h
    int 21h
    mov ax,4c00h
    int 21h
fail:
    cmp byte [link_changed],0
    je .print
    xor bx,bx
    mov bl,[old_link]
    mov ax,5803h
    int 21h
.print:
    mov dx,failed
    mov ah,09h
    int 21h
    mov ax,4c01h
    int 21h
old_link db 0
link_changed db 0
arena_head dw 0
con_segment dw 0
con_name db 'CON',0
packet db 0,0
       dw 14,0
       db 0,0
       dw 0,0,0,0,0
sequence db 27,'[2J',27,'[10;20H'
sequence_end:
passed db 'BIOS_ANSI_RESIDENT_PASS',13,10,'$'
failed db 'BIOS_ANSI_RESIDENT_FAIL',13,10,'$'
