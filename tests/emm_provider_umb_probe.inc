; Exercise allocator metadata only; never access the offered UMB addresses.
; Real registered ranges are used when available. Otherwise a temporary
; two-range registration tests the same peer/public owner in OFF/cancel modes.
check_umb_owner:
    mov ax,4310h
    int 2fh
    mov [umb_entry],bx
    mov [umb_entry+2],es
    mov es,[himem_segment]
    mov si,UMB_GUARD_OFFSET
    mov di,umb_guard
    mov cx,48
.save:
    mov al,[es:si]
    mov [di],al
    inc si
    inc di
    loop .save
    call umb_largest
    or dx,dx
    jnz .have_ranges
    mov ax,0e701h
    mov si,umb_registration
    int 2fh
    cmp ax,1
    jne umb_failed
    mov byte [umb_synthetic],1
    call umb_largest
.have_ranges:
    cmp dx,2
    jb umb_failed
    mov [umb_before],dx
    mov dx,1
    mov ah,10h
    call far [umb_entry]
    cmp ax,1
    jne umb_failed
    mov [umb_first],bx
    mov dx,1
    mov ah,10h
    call far [umb_entry]
    cmp ax,1
    jne umb_failed
    mov [umb_second],bx
    mov ax,0e702h              ; live allocations must prevent peer rollback
    int 2fh
    or ax,ax
    jnz umb_failed
    cmp bl,2
    jne umb_failed
    mov dx,[umb_first]
    mov ah,11h
    call far [umb_entry]
    cmp ax,1
    jne umb_failed
    mov dx,[umb_second]
    mov ah,11h
    call far [umb_entry]
    cmp ax,1
    jne umb_failed
    mov dx,[umb_second]        ; duplicate/interior release must be rejected
    mov ah,11h
    call far [umb_entry]
    or ax,ax
    jnz umb_failed
    cmp bl,0b2h
    jne umb_failed
    call umb_largest
    cmp dx,[umb_before]
    jne umb_failed
    mov es,[himem_segment]
    mov si,UMB_GUARD_OFFSET
    mov di,umb_guard
    mov cx,48
.check:
    mov al,[es:si]
    cmp al,[di]
    jne umb_overrun
    inc si
    inc di
    loop .check
    cmp byte [umb_synthetic],0
    je .done
    mov ax,0e702h
    int 2fh
    cmp ax,1
    jne umb_failed
    call umb_largest
    or dx,dx
    jnz umb_failed
.done:
    mov dx,0e9h
    mov al,'U'
    out dx,al
    mov al,'C'
    out dx,al
    mov al,[umb_synthetic]
    out dx,al
    ret
umb_largest:
    mov dx,0ffffh
    mov ah,10h
    call far [umb_entry]
    or ax,ax
    jnz umb_failed
    cmp bl,0b0h
    je .done
    cmp bl,0b1h
    jne umb_failed
.done:
    ret
umb_overrun:
    mov al,'W'
    jmp short umb_error
umb_failed:
    mov al,'F'
umb_error:
    mov dx,0e9h
    out dx,al
    jmp failed
himem_segment dw 0
umb_entry dd 0
umb_first dw 0
umb_second dw 0
umb_before dw 0
umb_synthetic db 0
umb_registration dw 1,2,0a000h,10h,0b000h,20h
umb_guard times 48 db 0
