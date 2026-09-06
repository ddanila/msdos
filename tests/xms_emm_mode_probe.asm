; Repository-only control ABI. Keep one locked XMS owner across EMM modes.
bits 16
org 100h

start:
    push cs
    pop ds
    ; Signed repository query: assert actual residency, not just CONFIG text.
    mov ax, 580eh
    mov cx, 4d55h
    mov si, 2142h
    mov di, 0a55ah
    int 21h
    jc failed
    cmp ax, EXPECT_HMA
    jne failed
    mov ax, 3567h
    int 21h
    mov di, 20
    mov si, signature
    mov cx, signature_end-signature
    cld
    repe cmpsb
    jne failed
    mov ax, [es:18]
    mov [control], ax
    mov [control+2], es
    mov ax, 4300h
    int 2fh
    cmp al, 80h
    jne failed
    mov ax, 4310h
    int 2fh
    mov [xms], bx
    mov [xms+2], es
    mov dx, 1
    mov ah, 09h
    call far [xms]
    cmp ax, 1
    jne failed
    mov [handle], dx
    mov ah, 0ch
    call far [xms]
    cmp ax, 1
    jne failed
    mov [physical], bx
    mov [physical+2], dx
%ifdef WRONG_ADDRESS
    inc word [physical]
%endif
    ; Fill the allocation through the public move API, not a physical write.
    mov ax, cs
    mov [move_source+2], ax
    mov ax, [handle]
    mov [move_dst_handle], ax
    call move_block
%ifdef WRONG_DATA
    xor byte [sent], 1
%endif

    ; ON -> OFF -> idle AUTO -> ON. The XMS owner spans every transition.
    mov byte [step], 0
.next:
    xor bx, bx
    mov bl, [step]
    mov al, [modes+bx]
    mov ah, 1
    call far [control]
    jc failed
    call check_mode
    mov dx, [handle]
    mov ah, 0ch
    call far [xms]
    cmp ax, 1
    jne failed
    cmp bx, [physical]
    jne failed
    cmp dx, [physical+2]
    jne failed
    mov dx, [handle]
    mov ah, 0dh
    call far [xms]
    cmp ax, 1
    jne failed
    mov ax, [handle]
    mov [move_src_handle], ax
    mov word [move_source], 0
    mov word [move_source+2], 0
    mov word [move_dst_handle], 0
    mov word [move_dest], received
    mov ax, cs
    mov [move_dest+2], ax
    mov word [received], 0
    call move_block
    mov si, sent
    mov di, received
    push cs
    pop es
    mov cx, 16
    cld
    repe cmpsb
    jne failed
    ; XMS services must not leave explicit OFF or idle AUTO active.
    call check_mode
    inc byte [step]
    cmp byte [step], 4
    jb .next
    mov dx, [handle]
    mov ah, 0dh
    call far [xms]
    cmp ax, 1
    jne failed
    mov dx, [handle]
    mov ah, 0ah
    call far [xms]
    cmp ax, 1
    jne failed
    mov dx, passed
    mov ah, 09h
    int 21h
    mov ax, 10h
    jmp exit_guest

move_block:
    ; The public descriptor is a real-mode far pointer, not a code-relative
    ; offset or a protected selector. Keep its segment distinct from CS and
    ; its offset nonzero so a future high backend must translate both parts.
    push cs
    pop ds
    mov ax, cs
    add ax, DESCRIPTOR_ADDRESS >> 4
    mov es, ax
    mov di, DESCRIPTOR_ADDRESS & 15
    mov si, move_request
    mov cx, 8
    cld
    rep movsw
%ifdef WRONG_DESCRIPTOR
    ; Only the external copy is invalid; using the original would falsely pass.
    or byte [es:DESCRIPTOR_ADDRESS & 15], 1
%endif
    mov si, DESCRIPTOR_ADDRESS & 15
    push es
    pop ds
    mov ah, 0bh
    call far [cs:xms]
    push ds
    pop dx
    push cs
    pop ds
    cmp ax, 1
    jne failed
    mov ax, cs
    add ax, DESCRIPTOR_ADDRESS >> 4
    cmp dx, ax
    jne failed
    cmp si, DESCRIPTOR_ADDRESS & 15
    jne failed
    ret

check_mode:
    xor ax, ax
    call far [control]
    xor bx, bx
    mov bl, [step]
    cmp ah, [statuses+bx]
    jne failed
    ret

failed:
    ; Disposable guest: never continue a suite with an uncertain live owner.
    mov dx, failure
    mov ah, 09h
    int 21h
    mov ax, 11h
exit_guest:
    mov dx, 0f4h
    out dx, ax
    cli
    hlt

control dd 0
xms dd 0
handle dw 0
physical dd 0
step db 0
modes db 0,1,2,0
statuses db 0,1,3,0
move_request:
    dd 16
move_src_handle dw 0
move_source dw sent,0
move_dst_handle dw 0
move_dest dd 0
sent db 'XMS OWNER INTACT'
received times 16 db 0
signature db 'MICROSOFT EXPANDED MEMORY MANAGER 386'
signature_end:
passed db 'XMS_EMM_MODE_PASS',13,10,'$'
failure db 'XMS_EMM_MODE_FAIL',13,10,'$'
align 16
    times 7 db 0
descriptor_storage times 16 db 0
DESCRIPTOR_ADDRESS equ descriptor_storage - $$ + 100h
