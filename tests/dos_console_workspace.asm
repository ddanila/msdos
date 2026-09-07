bits 16
org 100h
; Exercise the complete overlapping workspace and the handle-read cursor.
; Optional DATE_FLAG_OFFSET comes from the image's matched map, never a fixed
; release offset. It forces the idle clock-refresh branch before a new line.
    push cs
    pop ds
    push cs
    pop es
    cld
    mov dx,input_name
    mov ax,3d00h
    int 21h
    jc failed
    mov bx,ax
    xor cx,cx
    mov ah,46h
    int 21h
    jc failed
    mov ah,3eh
    int 21h
    jc failed
    mov dx,line
    mov byte [stage],'L'
    mov ah,0ah
    int 21h
    mov byte [stage],'N'
    cmp byte [line+1],254
    jne failed
    cmp byte [line+256],13
    jne failed
    cmp word [guard_before],0a55ah
    jne failed
    cmp word [guard_after],05aa5h
    jne failed
    mov si,line+2
    mov cx,254
.long:
    lodsb
    cmp al,'x'
    jne failed
    loop .long
    mov byte [stage],'C'
    mov dx,con_name
    mov ax,3d00h
    int 21h
    jc failed
    mov byte [stage],'D'
    mov bx,ax
    xor cx,cx
    mov ah,46h
    int 21h
    jc failed
    mov byte [stage],'E'
    mov ah,3eh
    int 21h
    jc failed
    mov dx,ready
    mov ah,9
    int 21h
    mov dx,chunk
    mov cx,2
    call read_console
    cmp ax,2
    jne failed
    mov dx,chunk+2
    mov cx,2
    call read_console
    cmp ax,2
    jne failed
    mov dx,chunk+4
    mov cx,2
    call read_console
    cmp ax,1
    jne failed
    mov si,chunk
    mov di,expected
    mov cx,5
    repe cmpsb
    jne failed
    mov dx,editing
    mov ah,9
    int 21h
    mov dx,chunk
    mov cx,8
    call read_console
    cmp ax,4
    jne failed
    mov si,chunk
    mov di,expected_edit
    mov cx,4
    repe cmpsb
    jne failed
    mov si,passed
    call debug
    mov ax,10h
    out 0f4h,ax
    cli
    hlt
failed:
    ; Failure record: stage, line length, AX, five output bytes, DS and ES.
    push ax
    mov al,[cs:stage]
    out 0e9h,al
    mov al,[cs:line+1]
    out 0e9h,al
    pop ax
    out 0e9h,al
    mov al,ah
    out 0e9h,al
    mov si,chunk
    mov cx,5
.dump:
    cs lodsb
    out 0e9h,al
    loop .dump
    mov ax,ds
    out 0e9h,al
    mov al,ah
    out 0e9h,al
    mov ax,es
    out 0e9h,al
    mov al,ah
    out 0e9h,al
    mov si,failure
    call debug
    mov ax,11h
    out 0f4h,ax
    cli
    hlt
read_console:
%ifdef DATE_FLAG_OFFSET
    push ax
    push bx
    push es
    mov ah,34h
    int 21h                       ; ES addresses the retained low DOS data
    mov word [es:DATE_FLAG_OFFSET],0ffffh
    pop es
    pop bx
    pop ax
%endif
    xor bx,bx
    mov ah,3fh
    int 21h
    jc failed
    ret
debug:
    cs lodsb
    test al,al
    jz .end
    out 0e9h,al
    jmp debug
.end:
    ret
input_name db 'LINE.TXT',0
stage db 'O'
con_name db 'CON',0
ready db 13,10,'CONSOLE_CHUNKS_READY',13,10,'$'
editing db 13,10,'CONSOLE_EDIT_READY',13,10,'$'
expected db 'abc',13,10
expected_edit db 'xz',13,10
chunk times 8 db 0
guard_before dw 0a55ah
line db 255,0
    times 255 db 0
guard_after dw 05aa5h
passed db 'CONSOLE_WORKSPACE_PASS',0
failure db 'CONSOLE_WORKSPACE_FAIL',0
