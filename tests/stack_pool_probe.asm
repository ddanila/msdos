; Local DOS only: validate the split pool and nest through the installed timer
; stack handler. Substitute its successor while IRQs are masked, then restore it.
bits 16
org 100h
%include "stack-defs.inc"
%ifndef STACK_COUNT
%define STACK_COUNT 9
%endif
%ifndef STACK_SIZE
%define STACK_SIZE 128
%endif
%define POOL_PARAS ((STACK_COUNT * (8 + STACK_SIZE) + 15) / 16)
%macro shape_step 1
%ifdef STACK_SHAPE_TRACE
    mov byte [cs:stage],%1
%endif
%endmacro
start:
%ifdef EXPECT_DOS_HIGH
    push ds
    mov ax,1203h                  ; executing DOSGROUP, no HMA allocation
    int 2fh
    mov ax,ds
    pop ds
    cmp ax,0ffffh
%if EXPECT_DOS_HIGH
    jne fail
%else
    je fail
%endif
%endif
    shape_step '1'
    mov ah,52h
    int 21h
    mov bp,[es:bx-2]
    mov cx,512
.arena:
    cmp bp,0a000h
    jae fail
    mov es,bp
    mov di,bp
    add di,[es:3]
    jc fail
    inc di
    cmp word [es:1],8
    jne .next
    mov si,bp
    inc si
.mark:
    cmp si,di
    jae .next
    mov es,si
    mov ax,si
    inc ax
    cmp ax,[es:1]
    jne .next
    cmp byte [es:0],'S'
    je .found
    add ax,[es:3]
    jc fail
    cmp ax,si
    jbe fail
    mov si,ax
    jmp .mark
.next:
    mov bp,di
    loop .arena
    jmp fail
.found:
    shape_step '2'
%if EXPECT_UPPER
    cmp word [es:3],38             ; low handler/control only, no low pool
%else
    cmp word [es:3],38+POOL_PARAS
%endif
    jne fail
    mov [cs:code_seg],ax
    mov [cs:handler+2],ax
    mov es,ax
    cmp word [es:2],STACK_COUNT
    jne fail
    cmp word [es:6],STACK_SIZE
    jne fail
    cmp word [es:8],0
    jne fail
    mov ax,[es:10]
    mov [cs:pool_seg],ax
%if EXPECT_UPPER
    cmp ax,0a000h
    jb fail
    sub ax,2
    mov es,ax
    cmp word [es:1],8
    jne fail
    cmp word [es:3],POOL_PARAS+1
    jne fail
    inc ax
    mov es,ax
    cmp byte [es:0],'S'
    jne fail
    cmp word [es:3],POOL_PARAS
    jne fail
    inc ax
    cmp [es:1],ax
    jne fail
%else
    cmp ax,0a000h
    jae fail
    sub ax,[cs:code_seg]
    cmp ax,38
    jne fail
%endif
    pushf
    cli
    shape_step '3'
%ifdef POOL_BAD_BACKLINK
    mov si,negative_ready
    call debug
    mov es,[cs:pool_seg]
    mov word [es:STACK_COUNT*8+STACK_SIZE-2],0ffffh
%endif
    call check_pool
    shape_step '4'
    mov es,[cs:code_seg]
    mov ax,[es:OLD_SLOT]
    mov [cs:successor],ax
    mov ax,[es:OLD_SLOT+2]
    mov [cs:successor+2],ax
    mov word [es:OLD_SLOT],nested
    mov [es:OLD_SLOT+2],cs
    mov [cs:original_sp],sp
    mov [cs:original_ss],ss
    mov ax,1234h
    mov bp,5678h
    mov si,9abch
    mov es,ax
    pushf
    call far [cs:handler]
    shape_step '5'
    cmp ax,1234h
    jne fail
    cmp bp,5678h
    jne fail
    cmp si,9abch
    jne fail
    mov ax,es
    cmp ax,1234h
    jne fail
    cmp sp,[cs:original_sp]
    jne fail
    mov ax,ss
    cmp ax,[cs:original_ss]
    jne fail
    cmp word [cs:depth],0
    jne fail
    cmp word [cs:visits],STACK_COUNT
    jne fail
    call check_pool
    mov es,[cs:code_seg]
    mov ax,[cs:successor]
    mov [es:OLD_SLOT],ax
    mov ax,[cs:successor+2]
    mov [es:OLD_SLOT+2],ax
    popf
    mov si,passed
    call debug
    mov ax,4c00h
    int 21h

nested:
    push ax
    push bx
    mov ax,ss
    cmp ax,[cs:pool_seg]
    jne fail
    inc word [cs:visits]
    mov bx,[cs:depth]
    shl bx,1
    mov ax,sp
    mov [cs:seen+bx],ax
    ; Every deeper interrupt must receive a different, lower stack.
    or bx,bx
    jz .recurse
    cmp ax,[cs:seen+bx-2]
    jae fail
.recurse:
    inc word [cs:depth]
    cmp word [cs:depth],STACK_COUNT
    je .return
    pushf
    call far [cs:handler]
.return:
    dec word [cs:depth]
    pop bx
    pop ax
    iret

check_pool:
    mov es,[cs:pool_seg]
    xor bx,bx
    mov dx,STACK_COUNT*8+STACK_SIZE-2
    mov cx,STACK_COUNT
.entry:
    shape_step 'A'
    cmp byte [es:bx],0
    jne fail
    shape_step 'B'
    cmp [es:bx+6],dx
    jne fail
    mov di,dx
    shape_step 'C'
    cmp [es:di],bx
    jne fail
    add bx,8
    add dx,STACK_SIZE
    loop .entry
    ret

fail:
%ifdef STACK_SHAPE_TRACE
    mov al,[cs:stage]
    out 0e9h,al
    mov ax,[cs:visits]
    call shape_hex
    mov ax,bx
    call shape_hex
    cmp byte [cs:stage],'C'
    jne .no_marker
    mov ax,[es:di]
    call shape_hex
.no_marker:
%endif
    mov si,failed
    call debug
    mov ax,11h
    out 0f4h,ax                    ; terminal failure, never resume altered IRQ state
    cli
    hlt
    jmp fail
%ifdef STACK_SHAPE_TRACE
shape_hex:
    mov cx,4
.digit:
    rol ax,1
    rol ax,1
    rol ax,1
    rol ax,1
    mov dx,ax
    and al,0fh
    add al,'0'
    cmp al,'9'
    jbe .out
    add al,7
.out:
    out 0e9h,al
    mov ax,dx
    loop .digit
    mov al,' '
    out 0e9h,al
    ret
%endif
debug:
    mov al,[cs:si]
    inc si
    or al,al
    jz .done
    out 0e9h,al
    jmp debug
.done:
    ret
handler dw ENTRY_OFFSET,0
successor dd 0
code_seg dw 0
pool_seg dw 0
original_sp dw 0
original_ss dw 0
depth dw 0
visits dw 0
seen times STACK_COUNT dw 0
passed db 'STACK_POOL_NESTED_PASS',13,10,0
failed db 'STACK_POOL_FAIL',13,10,0
negative_ready db 'STACK_POOL_BAD_BACKLINK_READY',13,10,0
%ifdef STACK_SHAPE_TRACE
stage db '0'
%endif
