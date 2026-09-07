; Actual installed strategy/interrupt calls; deterministic firmware, no DOS I/O
; while hooks are active. Each hook disables A20 before returning with IRET.
bits 16
org 100h
%include "character-defs.inc"
start:
    push cs
    pop ds
    mov si,vectors
    mov di,old_vectors
    mov cx,5
.save:
    lodsb
    mov ah,35h
    push cx
    push si
    push di
    int 21h
    pop di
    mov [di],bx
    mov [di+2],es
    pop si
    pop cx
    add di,4
    loop .save
    mov si,vectors
    mov di,handlers
    mov cx,5
.install:
    lodsb
    mov ah,25h
    mov dx,[di]
    push cx
    push si
    push di
    int 21h
    pop di
    pop si
    pop cx
    add di,2
    loop .install
    mov si,cases
    mov cx,19
.case:
    push cx
    lodsw
    mov [header],ax
    lodsb
    mov [command],al
    lodsw
    mov [table_entry],ax
    push si
    ; The low-service control may legitimately return with A20 off. Restore
    ; it before inspecting HMA tables, not after entering the tested service.
    mov ax,0e705h
    int 2fh
    push cs
    pop es
    mov di,packet
    xor ax,ax
    mov cx,30
    rep stosb
    mov di,buffer
    mov ax,1
    stosw
    mov ax,0302h
    stosw
    mov ax,0504h
    stosw
    mov byte [packet],30
    mov al,[command]
    mov [packet+2],al
    mov word [packet+14],buffer
    mov [packet+16],cs
    mov word [packet+18],1
    mov byte [activity],0
    mov ax,70h
    mov es,ax
    cmp byte [es:ACTIVE_OFFSET],1
    jne fail
    mov di,[es:DISPATCH_SLOT]
    sub di,DISPATCH_OFFSET
    add di,[table_entry]
    push es
    mov ax,0ffffh
    mov es,ax
    cmp word [es:di+2],EXPECTED_TARGET_SEGMENT
    pop es
    jne fail
    mov byte [es:ALTAH],0
    mov word [es:AUXBUF],0
    mov word [es:DAYCNT],1
    mov byte [es:HAVECMOSCLOCK],1
    mov byte [es:FHAVEK09],0
    mov bx,[header]
    mov ax,[es:bx+6]
    mov [strategy],ax
    mov ax,[es:bx+8]
    mov [driver],ax
    push cs
    pop es
    mov bx,packet
    call far [strategy]
    mov [saved_sp],sp
    mov ax,1111h
    mov bx,2222h
    mov cx,3333h
    mov dx,4444h
    mov si,5555h
    mov di,6666h
    mov bp,7777h
    call far [cs:driver]
    cmp sp,[cs:saved_sp]
    jne fail
    cmp ax,1111h
    jne fail
    cmp bx,2222h
    jne fail
    cmp cx,3333h
    jne fail
    cmp dx,4444h
    jne fail
    cmp si,5555h
    jne fail
    cmp di,6666h
    jne fail
    cmp bp,7777h
    jne fail
    mov ax,ds
    mov bx,cs
    cmp ax,bx
    jne fail
    mov ax,es
    cmp ax,bx
    jne fail
    test byte [packet+4],1 ; every request must complete
    jz fail
    mov al,[command]
    call hexbyte
    mov si,packet+3
    mov cx,2
    call bytes
    mov si,packet+18
    mov cx,2
    call bytes
    mov al,[packet+13]
    call hexbyte
    mov si,buffer
    mov cx,6
    call bytes
    mov al,[activity]
    call hexbyte
    mov al,10
    out 0e9h,al
    pop si
    pop cx
    dec cx
    jz .done
    jmp .case
.done:
    ; The private guest exits here; no application inherits changed firmware.
    mov al,'P'
    out 0e9h,al
    mov al,10h
    out 0f4h,al
    hlt
fail:
    mov al,'F'
    out 0e9h,al
    mov al,11h
    out 0f4h,al
    hlt
bytes:
    lodsb
    call hexbyte
    loop bytes
    ret
hexbyte:
    push ax
    shr al,1
    shr al,1
    shr al,1
    shr al,1
    call nibble
    pop ax
    and al,15
nibble:
    add al,'0'
    cmp al,'9'
    jbe .emit
    add al,7
.emit:
    out 0e9h,al
    ret
hook14:
    or byte [cs:activity],1
    cmp ah,3
    jne .data
    mov ax,2120h ; DSR, data ready and transmit ready
    jmp a20_return
.data:
    mov ax,0053h
    jmp a20_return
hook16:
    or byte [cs:activity],2
    push bp
    mov bp,sp
    and word [ss:bp+6],0ffbfh
    cmp ah,1
    je .empty
    cmp ah,11h
    jne .read
.empty:
    or word [ss:bp+6],40h
.read:
    mov ax,1e4bh
    pop bp
    jmp a20_return
hook17:
    or byte [cs:activity],4
    mov ah,90h ; selected, ready, no error
    jmp a20_return
hook1a:
    or byte [cs:activity],8
    cmp ah,0
    jne a20_return
    xor cx,cx
    mov dx,1234h
    xor al,al
    jmp a20_return
hook29:
    or byte [cs:activity],16
a20_return:
    push ax
    in al,92h
    and al,0fdh
    out 92h,al
    pop ax
    iret
vectors db 14h,16h,17h,1ah,29h
handlers dw hook14,hook16,hook17,hook1a,hook29
old_vectors times 5 dd 0
strategy dw 0,70h
driver dw 0,70h
saved_sp dw 0
command db 0
activity db 0
header dw 0
table_entry dw 0
packet times 30 db 0
buffer times 6 db 0
cases:
%macro REQUEST 2
    dw %1
    db %2
%if %1 = CONHEADER
    dw TABLES_OFFSET+2*(CONTBL-DSKTBL)+2+4*%2
%elif %1 = AUXDEV2
    dw TABLES_OFFSET+2*(AUXTBL-DSKTBL)+2+4*%2
%elif %1 = PRNDEV2
    dw TABLES_OFFSET+2*(PRNTBL-DSKTBL)+2+4*%2
%elif %1 = TIMDEV
    dw TABLES_OFFSET+2*(TIMTBL-DSKTBL)+2+4*%2
%endif
%endmacro
REQUEST CONHEADER,4
REQUEST CONHEADER,5
REQUEST CONHEADER,7
REQUEST CONHEADER,8
REQUEST CONHEADER,9
REQUEST AUXDEV2,4
REQUEST AUXDEV2,5
REQUEST AUXDEV2,7
REQUEST AUXDEV2,8
REQUEST AUXDEV2,9
REQUEST AUXDEV2,10
REQUEST PRNDEV2,8
REQUEST PRNDEV2,9
REQUEST PRNDEV2,10
REQUEST PRNDEV2,16
REQUEST PRNDEV2,19 ; unsupported major category: CMDERR without dereferencing it
REQUEST TIMDEV,4
REQUEST TIMDEV,8
REQUEST TIMDEV,9
