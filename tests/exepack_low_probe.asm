; Synthetic MZ/EXEPACK stream: a literal record followed (backwards) by a
; zero run at the image base. The old decoder underflows its segment while
; reading that record below 64 KiB with A20 enabled. No external app needed.
bits 16
org 0
header:
    dw 'MZ', (file_end-header) % 512, (file_end-header+511)/512, 0, 2
    dw 100h, 100h, 40h, 100h, 0, 12h, 5, 1ch, 0
    times 32-($-header) db 0
image_start:
    db 0                    ; value, count, final run record
    dw 16
    db 0b1h
literal:
    push cs
    pop ds
    mov ax,cs
    cmp ax,1000h
    jae fail_payload
    cmp word [0],0
    jne fail_payload
    cmp word [14],0
    jne fail_payload
    mov dx,16+(pass_message-literal)
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
fail_payload:
    mov ax,4c01h
    int 21h
pass_message db 'EXEPACK_LOW_PASS',13,10,'$'
    times 64-($-literal) db 90h
    dw 64
    db 0b2h
    times 80-($-image_start) db 0ffh
stub:
    dw 10h,0,0,stub_end-stub,0,0,5,1,4252h
entry:
%ifdef NEAR_MISS
    push es                 ; same semantics/length, unsupported signature
    pop ax
%else
    mov ax,es
%endif
    db 05h,10h,00h             ; ADD AX,10h (EXEPACK encoding)
    push cs
    pop ds
    mov [4],ax
    add ax,[12]
    mov es,ax
    mov cx,[6]
    db 8bh,0f9h               ; MOV DI,CX
    dec di
    db 8bh,0f7h               ; MOV SI,DI
    std
    rep movsb
    mov dx,[14]
    push ax
    mov ax,38h
    push ax
    retf
    mov bx,es
    mov ax,ds
    db 2bh,0c2h               ; SUB AX,DX
    mov ds,ax
    mov es,ax
    mov di,15
    mov cx,16
    mov al,0ffh
    repe scasb
    inc di
    db 8bh,0f7h               ; MOV SI,DI
    db 8bh,0c3h               ; MOV AX,BX
    db 2bh,0c2h               ; SUB AX,DX
    mov es,ax
    mov di,15
record:
    mov cl,4
    db 8bh,0c6h               ; MOV AX,SI
    not ax
    shr ax,cl
    jz destination
    mov dx,ds
    db 2bh,0d0h               ; SUB DX,AX              ; BUG: can wrap below segment zero
    mov ds,dx
    or si,byte -16
 destination:
    db 8bh,0c7h               ; MOV AX,DI
    not ax
    shr ax,cl
    jz decode
    mov dx,es
    db 2bh,0d0h               ; SUB DX,AX              ; same bug for the output pointer
    mov es,dx
    or di,byte -16
 decode:
    lodsb
    db 8ah,0d0h               ; MOV DL,AL
    dec si
    lodsw
    db 8bh,0c8h               ; MOV CX,AX
    inc si
    db 8ah,0c2h               ; MOV AL,DL
    and al,0feh
    cmp al,0b0h
    jne copy_literal
    lodsb
    rep stosb
    jmp short next_record
    nop
 copy_literal:
    cmp al,0b2h
    jne short corrupt
    rep movsb
 next_record:
    db 8ah,0c2h               ; MOV AL,DL
    test al,1
    jz record
    ; The decoder leaves execution here; our fixture has no relocations.
    cld
    push cs
    pop ds
    mov ax,[4]
    push ax
    mov ax,10h
    push ax
    retf
    times 0efh-($-entry) db 90h
corrupt:
    cld
    push cs
    pop ds
    mov dx,error_message-stub
    mov ah,9
    int 21h
    mov ax,4c02h
    int 21h
error_message db 'EXEPACK_CORRUPT',13,10,'$'
stub_end:
file_end:
