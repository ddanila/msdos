; Exercise INT 2Fh/0801h with a caller-owned far BDS after boot packing.
; Detach before returning, then the batch runs the FCB I/O regression.
bits 16
org 100h
start:
    mov ax,0803h
    int 2fh
    mov [cs:root],di
    mov [cs:root+2],ds
    push ds
    pop es
    push cs
    pop ds
    mov cx,26
.walk:
    cmp word [es:di],-1
    je .last
    les di,[es:di]
    loop .walk
    jmp fail
.last:
    mov [last],di
    mov [last+2],es
    mov ax,[es:di]
    mov [saved],ax
    mov ax,[es:di+2]
    mov [saved+2],ax
    push ds
    push es
    pop ds
    push cs
    pop es
    mov si,di
    mov di,descriptor
    mov cx,100
    cld
    rep movsb
    pop ds
    mov byte [descriptor+4],0feh ; a distinct physical identifier
    mov byte [descriptor+5],25  ; public graph only; no new DOS DPB
    mov di,descriptor
    mov ax,0801h
    int 2fh
    push cs
    pop ds
    mov byte [installed],1
    les di,[last]
    cmp word [es:di],descriptor
    jne fail
    mov ax,cs
    cmp [es:di+2],ax
    jne fail
    cmp word [descriptor],-1
    jne fail
    mov ax,0803h
    int 2fh
    mov ax,ds
    push cs
    pop ds
    cmp ax,[root+2]
    jne fail
    cmp di,[root]
    jne fail
    call detach
    mov dx,passed
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
fail:
    push cs
    pop ds
    call detach
    mov dx,failed
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h
detach:
    cmp byte [installed],0
    je .done
    pushf
    cli
    les di,[last]
    mov ax,[saved]
    mov [es:di],ax
    mov ax,[saved+2]
    mov [es:di+2],ax
    mov byte [installed],0
    popf
.done:
    ret
installed db 0
root dd 0
last dd 0
saved dd 0
passed db 'BIOS_EXTERNAL_BDS_PASS',13,10,'$'
failed db 'BIOS_EXTERNAL_BDS_FAIL',13,10,'$'
descriptor times 100 db 0
