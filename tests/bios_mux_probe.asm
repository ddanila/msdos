; Public AH=08h operations; temporary external BDS is unlinked before exit.
bits 16
org 100h
    cld
    mov ax,70h
    mov es,ax
    cmp byte [es:BIOS_ACTIVE],EXPECT_ACTIVE
    jne fail
%ifdef COLD_START
    mov byte [cs:stage],'P'
    ; Released bytes can already belong to another owner at program entry.
    ; Check the release boundary and high binding, not their old poison fill.
    mov bx,[es:BIOS_END]
    mov cl,4
    shl bx,cl
    cmp bx,COLD_START
    ja fail
    cmp word [es:HIGH_ENTRY+2],0ffffh
    jne fail
%endif
    mov byte [cs:stage],'Q'
    mov ax,0800h
    int 2fh
    cmp al,0ffh
    jne fail
    mov ax,08f8h
    int 2fh
    cmp ax,08f8h
    jne fail
    mov ax,08ffh
    int 2fh
    cmp ax,08ffh
    jne fail
    mov ax,0803h
    int 2fh
    mov [cs:root],di
    mov [cs:root+2],ds
    mov cx,26
    mov si,saved_flags
.walk:
    mov [cs:si],di
    mov [cs:si+2],ds
    mov ax,[di+35]          ; MSBDS.INC: BDS_TYPE.FLAGS
    mov [cs:si+4],ax
    mov al,[di+4]
    mov [cs:si+6],al
    add si,8
    cmp word [di],0ffffh
    je .last
    lds di,[di]
    loop .walk
    jmp fail
.last:
    mov [cs:saved_end],si
    mov [cs:last],di
    mov [cs:last+2],ds
    mov ax,[di+2]
    mov [cs:last_segment],ax
    push cs
    pop ds
    mov byte [cs:stage],'I'
    mov di,record
    mov ax,0801h
    int 2fh
    les bx,[cs:last]
    cmp word [es:bx],record
    jne fail
    mov ax,cs
    cmp [es:bx+2],ax
    jne fail
    cmp word [cs:record],0ffffh
    jne fail
    ; Restore the existing graph, including its unused terminal segment.
    pushf
    cli
    mov word [es:bx],0ffffh
    mov ax,[cs:last_segment]
    mov [es:bx+2],ax
    popf
    mov ax,0803h
    int 2fh
    cmp di,[cs:root]
    jne fail
    mov ax,ds
    cmp ax,[cs:root+2]
    jne fail
    push cs
    pop ds
    ; A second insertion exercises shared-physical-drive flag propagation.
    ; Restore every changed record before another DOS request can use it.
    mov byte [stage],'M'
    mov al,[saved_flags+6]
    mov [record+4],al
    mov word [record+35],20h
    pushf
    cli
    mov di,record
    mov ax,0801h
    int 2fh
    les bx,[cs:last]
    cmp word [es:bx],record
    jne fail
    mov ax,cs
    cmp [es:bx+2],ax
    jne fail
    mov si,saved_flags
    mov dx,10h
.verify_flags:
    les bx,[cs:si]
    mov ax,[cs:si+4]
    mov cl,[cs:si+6]
    cmp cl,[cs:record+4]
    jne .unmatched
    or ax,10h
    test ax,2
    jz .unmatched
    or dx,2
.unmatched:
    cmp [es:bx+35],ax
    jne fail
    mov ax,[cs:si+4]
    mov [es:bx+35],ax
    add si,8
    cmp si,[cs:saved_end]
    jb .verify_flags
    cmp [cs:record+35],dx
    jne fail
    cmp word [cs:record],0ffffh
    jne fail
    les bx,[cs:last]
    mov word [es:bx],0ffffh
    mov ax,[cs:last_segment]
    mov [es:bx+2],ax
    popf
    push cs
    pop ds
    push cs
    pop es
    mov byte [cs:stage],'D'
    mov bx,packet
    mov ax,0802h
    int 2fh
    cmp word [packet+3],8103h
    jne fail
    mov word [packet+3],0
    mov ax,0804h             ; legacy non-reserved aliases dispatch requests
    int 2fh
    cmp word [packet+3],8103h
    jne fail
%ifdef COLD_START
    mov byte [cs:stage],'A'
    ; Find distinct low/high words without modifying either memory owner.
    mov ax,0ffffh
    mov es,ax
    xor ax,ax
    mov ds,ax
    mov si,10h
.find_alias:
    mov bx,si
    sub bx,10h
    mov ax,[bx]
    cmp ax,[es:si]
    jne .found
    add si,2
    cmp si,110h
    jb .find_alias
    jmp fail
.found:
    mov [cs:alias_low],ax
    mov ax,[es:si]
    mov [cs:alias_high],ax
    mov [cs:alias_offset],si
    in al,92h
    and al,0fdh
    out 92h,al
    call check_alias_off
    mov byte [cs:stage],'C'
    mov ax,4300h             ; unrelated discovery must chain without recursion
    int 2fh
    cmp al,80h
    jne fail
    call check_alias_off
    mov byte [cs:stage],'H'
    mov ax,0803h
    int 2fh
    cmp di,[cs:root]
    jne fail
    mov ax,ds
    cmp ax,[cs:root+2]
    jne fail
    mov ax,0ffffh
    mov es,ax
    mov si,[cs:alias_offset]
    mov ax,[cs:alias_high]
    cmp ax,[es:si]
    jne fail
%endif
    push cs
    pop ds
    mov si,passed
.print:
    lodsb
    or al,al
    jz .done
    out 0e9h,al
    jmp .print
.done:
    mov ax,10h
    out 0f4h,ax
    jmp $
check_alias_off:
    mov ax,0ffffh
    mov es,ax
    mov si,[cs:alias_offset]
    mov ax,[cs:alias_low]
    cmp ax,[es:si]
    jne fail
    ret
fail:
    mov al,[cs:stage]
    out 0e9h,al
    mov al,'F'
    out 0e9h,al
    mov ax,11h
    out 0f4h,ax
    jmp $
root dd 0
stage db 'S'
last dd 0
last_segment dw 0
saved_end dw 0
saved_flags times 26*8 db 0
alias_offset dw 0
alias_low dw 0
alias_high dw 0
record:
    dw 0ffffh,0
    db 0feh,0feh
    times 94 db 0
packet:
    db 32,0,0ffh
    times 29 db 0
passed db 'BIOS_MUX_PASS',13,10,0
