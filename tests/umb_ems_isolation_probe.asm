bits 16
org 100h

; Hold patterned DOS-owned upper memory while EMS repeatedly changes all four
; page-frame mappings.  A shared backing page, stale PTE, or page-pool overlap
; changes the UMB pattern and fails the probe.

start:
    mov ax, 5800h
    int 21h
    mov [saved_strategy], ax
    mov bx, 1
    mov ax, 5803h
    int 21h
    jc umb_failed
    mov bx, 0040h
    mov ax, 5801h
    int 21h
    jc umb_failed

    mov bx, 0100h
    mov ah, 48h
    int 21h
    jc umb_failed
    mov [umb_segment], ax
    mov es, ax
    xor di, di
    mov ax, 0a55ah
    mov cx, 0800h
    rep stosw

    mov ah, 41h
    int 67h
    test ah, ah
    jnz ems_failed
    mov [frame_segment], bx

    mov bx, 4
    mov ah, 43h
    int 67h
    test ah, ah
    jnz ems_failed
    mov [ems_handle], dx

    xor si, si
.remap_round:
    xor cx, cx
.map_slot:
    mov ax, cx
    and al, 3
    mov bx, si
    add bx, cx
    and bx, 3
    mov dx, [ems_handle]
    mov ah, 44h
    int 67h
    test ah, ah
    jnz map_failed

    push es
    mov es, [frame_segment]
    mov di, cx
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    mov ax, si
    xor ax, cx
    xor ax, 05aa5h
    mov [es:di], ax
    pop es

    inc cx
    cmp cx, 4
    jb .map_slot

    call verify_umb
    jc isolation_failed
    inc si
    cmp si, 64
    jb .remap_round

    mov dx, [ems_handle]
    mov ah, 45h
    int 67h
    test ah, ah
    jnz release_failed
    mov es, [umb_segment]
    mov ah, 49h
    int 21h
    jc umb_release_failed
    call restore_strategy

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

verify_umb:
    push ax
    push cx
    push di
    push es
    mov es, [umb_segment]
    xor di, di
    mov ax, 0a55ah
    mov cx, 0800h
    repe scasw
    jne .corrupt
    pop es
    pop di
    pop cx
    pop ax
    clc
    ret
.corrupt:
    pop es
    pop di
    pop cx
    pop ax
    stc
    ret

map_failed:
    mov dx, map_fail
    jmp short cleanup_ems
isolation_failed:
    mov dx, isolation_fail
cleanup_ems:
    push dx
    mov dx, [ems_handle]
    mov ah, 45h
    int 67h
    pop dx
    jmp short cleanup_umb
release_failed:
    mov dx, release_fail
    jmp short cleanup_umb
ems_failed:
    mov dx, ems_fail
cleanup_umb:
    push dx
    mov es, [umb_segment]
    mov ah, 49h
    int 21h
    pop dx
    push dx
    call restore_strategy
    pop dx
    jmp short fail
umb_release_failed:
    mov dx, umb_release_fail
    push dx
    call restore_strategy
    pop dx
    jmp short fail
umb_failed:
    mov dx, umb_fail
    push dx
    call restore_strategy
    pop dx
fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

restore_strategy:
    push ax
    push bx
    mov bx, [saved_strategy]
    mov ax, 5801h
    int 21h
    pop bx
    pop ax
    ret

saved_strategy dw 0
umb_segment   dw 0
frame_segment dw 0
ems_handle    dw 0
pass_message  db 'UMB_EMS_ISOLATION_PASS', 13, 10, '$'
umb_fail      db 'UMB_EMS_UMB_FAIL', 13, 10, '$'
ems_fail      db 'UMB_EMS_ALLOC_FAIL', 13, 10, '$'
map_fail      db 'UMB_EMS_MAP_FAIL', 13, 10, '$'
isolation_fail db 'UMB_EMS_CORRUPTION', 13, 10, '$'
release_fail  db 'UMB_EMS_RELEASE_FAIL', 13, 10, '$'
umb_release_fail db 'UMB_EMS_UMB_RELEASE_FAIL', 13, 10, '$'
