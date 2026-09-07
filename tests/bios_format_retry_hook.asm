; Private QEMU fixture only: fail the first format, overwrite its DMA buffer
; during reset, and check that the next attempt regenerated every descriptor.
bits 16
org 100h
%ifndef BAD_EXPECTATION
%define BAD_EXPECTATION 0
%endif
start:
    mov ax,3513h
    int 21h
    mov [old13],bx
    mov [old13+2],es
    mov dx,hook13
    mov ax,2513h
    int 21h
    mov dx,(resident_end-$$+100h+15)/16
    mov ax,3100h
    int 21h

hook13:
    cmp ah,5
    je format
    cmp ah,0
    jne chain
    cmp byte [cs:phase],1
    jne chain
    pushf
    push ax
    push cx
    push di
    push es
    les di,[cs:buffer]
    mov cx,[cs:count]
    mov al,0a5h
    cld
    rep stosb
%if BAD_EXPECTATION
    mov byte [cs:descriptors],0ffh ; deliberately wrong oracle for track zero
%endif
    mov al,'R'
    out 0e9h,al
    pop es
    pop di
    pop cx
    pop ax
    popf
chain:
    jmp far [cs:old13]

format:
    cmp byte [cs:phase],2
    jae chain
    pushf
    push ax
    push cx
    push si
    push di
    push ds
    push es
    cld
    xor ah,ah
    shl ax,1
    shl ax,1
    mov cx,ax
    push es
    pop ds
    mov si,bx
    push cs
    pop es
    mov di,descriptors
    cmp byte [cs:phase],0
    jne compare
    cmp cx,252
    ja bad
    jcxz bad
    mov [cs:count],cx
    mov [cs:buffer],bx
    mov [cs:buffer+2],ds
    rep movsb
    mov byte [cs:phase],1
    mov al,'F'
    out 0e9h,al
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    popf
    mov ah,20h                 ; controller error: require driver's retry
    push bp
    mov bp,sp
    or word [ss:bp+6],1         ; carry in interrupt frame; preserve caller IF/DF
    pop bp
    iret
compare:
    cmp cx,[cs:count]
    jne bad
    repe cmpsb
    jne bad
    mov al,'P'
    jmp short report
bad:
    mov al,'X'
report:
    out 0e9h,al
    mov byte [cs:phase],2
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    popf
    jmp chain

old13 dd 0
buffer dd 0
count dw 0
phase db 0
descriptors times 252 db 0
resident_end:
