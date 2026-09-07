; Controlled INT 24h formatter calls, not a real-media/redirector test.
; Intercept only AH=59h during our call to supply the wrong-volume record.
; Run under COMMAND /P /F with stdout redirected and stderr on serial.
bits 16
org 100h

start:
    push cs
    pop ds
    mov ax,3521h
    int 21h
    mov [old21],bx
    mov [old21+2],es
    mov dx,extended_error
    mov ax,2521h
    int 21h
    les bx,[34h]
    mov ax,[es:bx]
    mov [saved_handles],ax
    cmp ah,[es:bx+2]
    je failure
    mov es,[16h]
    cmp byte [es:SHELL_HIGH_ACTIVE],EXPECT_ACTIVE
    jne failure
%if EXPECT_ACTIVE
    mov ax,es
    dec ax
    mov es,ax
    cmp word [es:3],EXPECT_LOW_PARAGRAPHS
    jne failure
%endif
%ifdef LOW_MESSAGE_REPLY
    call check_disk_reply
%endif
%ifdef BAD_SERIAL_OFFSET
    mov es,[16h]
    mov bx,BAD_SERIAL_OFFSET
%ifdef PIPE_BINDING
    add bx,[es:PIPE_BINDING]
    sub bx,LOW_PIPE_TEXT
    mov ax,0ffffh
    mov es,ax
%endif
    mov [mutation_off],bx
    mov [mutation_seg],es
    mov ax,[es:bx]
    mov [saved_offset],ax
    sub word [es:bx],2
    mov byte [patched],1
%endif
.request:
    mov byte [active],1
    mov ax,[critical_args]       ; Fail allowed; block read, then device write
    mov di,15                    ; wrong disk
    mov bp,cs
    mov si,device
    mov cx,05a5ah
    mov dx,0a55ah
    mov bx,01234h
    mov es,bx                    ; deliberately not COMMAND's owner
    mov [saved_sp],sp
    push ax
    mov ax,ss
    mov [saved_ss],ax
    pop ax
    int 24h
    mov byte [cs:active],0
    cmp al,3
    jne failure
    cmp sp,[cs:saved_sp]
    jne failure
    mov ax,ss
    cmp ax,[cs:saved_ss]
    jne failure
    mov ax,ds
    mov bx,cs
    cmp ax,bx
    jne failure
    mov ax,es
    cmp ax,01234h
    jne failure
    cmp si,device
    jne failure
    cmp cx,05a5ah
    jne failure
    mov ax,[expected_queries]
    cmp [queries],ax
    jne failure
    cmp word [guard_before],0a55ah
    jne failure
    cmp word [guard_after],05aa5h
    jne failure
    les bx,[34h]
    mov ax,[es:bx]
    cmp ax,[saved_handles]
    jne failure
    cmp word [queries],1
    jne .done
    mov word [expected_queries],2
    mov word [error_code],31     ; general failure
    mov word [critical_args],0900h
    mov word [device+4],8000h    ; character device
    jmp .request
.done:
    call restore
    mov dx,passed
    mov ah,09h
    int 21h
    mov ax,4c00h
    int 21h
failure:
    push cs
    pop ds
    call restore
    mov dx,failed
    mov ah,09h
    int 21h
    mov ax,4c01h
    int 21h

%ifdef LOW_MESSAGE_REPLY
check_disk_reply:
    mov ax,122eh
    mov dl,8
    int 2fh
    mov [disk_reader],di
    mov [disk_reader+2],es
    mov ax,122eh
    xor dx,dx
    int 2fh
    mov ax,es
    cmp ax,1                    ; COMMAND's disk-backed class sentinel
    jne failure
    mov ax,83
    call far [disk_reader]
    jc failure
    mov ax,es
    cmp ax,[16h]                ; public reply must remain in low parent
    jne failure
    cmp di,LOW_MESSAGE_REPLY
    jne failure
    cmp byte [es:di],14
    jne failure
    mov ah,30h                  ; low caller may issue DOS calls before use
    int 21h
    mov di,LOW_MESSAGE_REPLY+1
    mov si,expected_reply
    mov cx,14
    cld
    repe cmpsb
    jne failure
    ret
disk_reader dd 0
expected_reply db 'Fail on INT 24'
%endif

restore:
%ifdef BAD_SERIAL_OFFSET
    cmp byte [patched],0
    je .vector
    les bx,[mutation_off]
    mov ax,[saved_offset]
    mov [es:bx],ax
.vector:
%endif
    push ds
    lds dx,[old21]
    mov ax,2521h
    int 21h
    pop ds
    ret

extended_error:
    cmp byte [cs:active],0
    je .chain
    cmp ah,59h
    jne .chain
    inc word [cs:queries]
    mov ax,[cs:error_code]       ; controlled extended error and record
    mov bx,0803h
    mov ch,2
    push cs
    pop es
    mov di,volume
    iret
.chain:
    jmp far [cs:old21]

old21 dd 0
saved_sp dw 0
saved_ss dw 0
saved_handles dw 0
saved_offset dw 0
mutation_off dw 0
mutation_seg dw 0
patched db 0
queries dw 0
expected_queries dw 1
error_code dw 34                 ; extended wrong-disk error: 19 + 15
critical_args dw 0801h
active db 0
device dd -1
    dw 0                         ; block device attributes
    dw 0,0                       ; unused strategy/interrupt offsets
    db 'FIXTURE '
guard_before dw 0a55ah
volume db 'STATEVOL123',0
    dd 01234abcdh
guard_after dw 05aa5h
passed db 'COMMAND_FORMATTER_STATE_PASS',13,10,'$'
failed db 'COMMAND_FORMATTER_STATE_FAIL',13,10,'$'
