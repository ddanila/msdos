; Read the installed repository BIOS's selected capability and retained end.
; Offsets come from a hash-matched build map, never from a vendor BIOS.
bits 16
org 100h
    mov ax,70h
    mov es,ax
    xor ax,ax
    mov al,[es:FHAVE96]
    mov [selection],ax
    mov ax,[es:PERMANENT_END]
    mov [selection+2],ax
    mov dx,label
    mov ah,9
    int 21h
    mov ax,[selection]
    call hexword
    mov dl,':'
    mov ah,2
    int 21h
    mov ax,[selection+2]
    call hexword
    mov dx,newline
    mov ah,9
    int 21h
    cmp word [selection],0
    je .not_selected
    mov ax,70h
    mov es,ax
    mov si,helper_bytes
    mov di,HELPER_START
    mov cx,HELPER_COUNT
    cld
    repe cmpsb
    jne .bad
    mov dx,helpers_ok
    jmp short .report
.not_selected:
    mov dx,helpers_na
.report:
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
.bad:
    mov dx,helpers_bad
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h
hexword:
    mov bx,ax
    mov si,4
.digit:
    mov cl,4
    rol bx,cl
    mov dl,bl
    and dl,15
    add dl,'0'
    cmp dl,'9'
    jbe .print
    add dl,7
.print:
    mov ah,2
    int 21h
    dec si
    jnz .digit
    ret
selection dw 0,0
label db 'BIOS_LAYOUT=','$'
newline db 13,10,'$'
helpers_ok db 'BIOS_HELPERS=OK',13,10,'$'
helpers_bad db 'BIOS_HELPERS=BAD',13,10,'$'
helpers_na db 'BIOS_HELPERS=NOT_SELECTED',13,10,'$'
helper_bytes incbin 'media-helpers.bin'
