bits 16
org 100h

start:
    push cs
    pop ds
    push cs
    pop es

    ; Allocate a three-page named handle used throughout the lifecycle.
    mov bx, 3
    mov ah, 43h
    int 67h
    test ah, ah
    jnz fail_alloc
    mov [handle], dx

    ; 47/48: save and restore a handle's mapping context.  Keep the
    ; first window unmapped so FFFFh is exercised as legitimate map data.
    xor al, al
    mov bx, 0ffffh
    mov ah, 44h
    int 67h
    test ah, ah
    jnz fail_map
    mov dx, [handle]
    mov ah, 47h
    int 67h
    test ah, ah
    jnz fail_save
    mov ah, 47h
    int 67h
    cmp ah, 8dh                       ; map already saved
    jne fail_save
    mov ah, 45h
    int 67h
    cmp ah, 86h                       ; cannot release a saved handle
    jne fail_save
    mov ah, 48h
    int 67h
    test ah, ah
    jnz fail_restore
    mov ah, 48h
    int 67h
    cmp ah, 8eh                       ; no map remains saved
    jne fail_restore
    call saved_map_owners

    ; 49/4A are explicitly unsupported by this software EMM.
    mov ah, 49h
    int 67h
    cmp ah, 84h
    jne fail_unsupported
    mov ah, 4ah
    int 67h
    cmp ah, 84h
    jne fail_unsupported

    ; 4B-4D: handle count, size, and directory entry array.
    mov ah, 4bh
    int 67h
    test ah, ah
    jnz fail_directory
    cmp bx, 2                         ; OS handle plus ours
    jb fail_directory
    mov dx, [handle]
    mov ah, 4ch
    int 67h
    test ah, ah
    jnz fail_directory
    cmp bx, 3
    jne fail_directory
    push cs
    pop es
    mov di, handle_pages
    mov ah, 4dh
    int 67h
    test ah, ah
    jnz fail_directory
    call find_handle_pages
    jc fail_directory

    push cs
    pop es
    mov di, physical_pages
    mov ax, 5800h
    int 67h
    test ah, ah
    jnz fail_info

    ; 4E: size, get, set, and atomic get/set subfunctions.
    mov ax, 4e03h
    int 67h
    test ah, ah
    jnz fail_full_map
    test al, al
    jz fail_full_map
    push cs
    pop es
    mov di, full_map_saved
    mov ax, 4e00h
    int 67h
    test ah, ah
    jnz fail_full_map
    mov si, full_map_saved
    mov di, full_map_previous
    mov ax, 4e02h
    int 67h
    test ah, ah
    jnz fail_full_map

    ; 4F: size, get and set a one-page partial map.
    mov bx, 1
    mov ax, 4f02h
    int 67h
    test ah, ah
    jnz fail_partial_map
    cmp al, 6
    jne fail_partial_map
    mov ax, [physical_pages]
    mov [partial_request+2], ax
    mov si, partial_request
    mov di, partial_saved
    mov ax, 4f00h
    int 67h
    test ah, ah
    jnz fail_partial_map
    mov si, partial_saved
    mov ax, 4f01h
    int 67h
    test ah, ah
    jnz fail_partial_map

    ; 50: map an array expressed by physical-page number and verify data.
    push cs
    pop es
    mov di, physical_pages
    mov ax, 5800h
    int 67h
    test ah, ah
    jnz fail_map_array
    mov ax, [physical_pages+2]
    mov [map_array+2], ax
    mov dx, [handle]
    mov cx, 1
    mov si, map_array
    mov ax, 5000h
    int 67h
    test ah, ah
    jnz fail_map_array
    mov ax, [physical_pages]
    mov [map_array_segment+2], ax
    mov si, map_array_segment
    mov cx, 1
    mov ax, 5001h
    int 67h
    test ah, ah
    jnz fail_map_array

    ; 51: grow and shrink while preserving the handle identity.
    mov dx, [handle]
    mov bx, 4
    mov ah, 51h
    int 67h
    test ah, ah
    jnz fail_realloc
    mov ah, 4ch
    int 67h
    test ah, ah
    jnz fail_realloc
    cmp bx, 4
    jne fail_realloc
    mov bx, 2
    mov ah, 51h
    int 67h
    test ah, ah
    jnz fail_realloc

    ; 52: only volatile handles are supported.
    xor al, al
    mov ah, 52h
    int 67h
    test ah, ah
    jnz fail_attr
    test al, al
    jnz fail_attr
    mov al, 1
    mov ah, 52h
    int 67h
    cmp ah, 91h
    jne fail_attr
    mov al, 2
    mov ah, 52h
    int 67h
    test ax, ax
    jnz fail_attr

    ; 53/54: set/get a name, locate it, enumerate it, and query capacity.
    mov dx, [handle]
    mov si, handle_name
    mov ax, 5301h
    int 67h
    test ah, ah
    jnz fail_name
    push cs
    pop es
    mov di, name_result
    mov ax, 5300h
    int 67h
    test ah, ah
    jnz fail_name
    mov si, handle_name
    mov di, name_result
    mov cx, 8
    repe cmpsb
    jne fail_name
    mov si, handle_name
    mov ax, 5401h
    int 67h
    test ah, ah
    jnz fail_name
    cmp dx, [handle]
    jne fail_name
    push cs
    pop es
    mov di, name_directory
    mov ax, 5400h
    int 67h
    test ah, ah
    jnz fail_name
    cmp al, 2
    jb fail_name
    mov ax, 5402h
    int 67h
    test ah, ah
    jnz fail_name
    cmp bx, 2
    jb fail_name

    ; Indexed name ownership: compare all eight bytes, reject duplicates,
    ; preserve an unrelated handle, and clear names on free/reallocation.
    mov bx,1
    mov ah,43h
    int 67h
    test ah,ah
    jnz fail_name
    mov [name_handle],dx
    mov si,handle_name
    mov ax,5301h
    int 67h
    cmp ah,0a1h
    jne fail_name
    mov dx,[name_handle]
    mov si,other_name
    mov ax,5301h
    int 67h
    test ah,ah
    jnz fail_name
    mov si,other_name
    mov ax,5401h
    int 67h
    test ah,ah
    jnz fail_name
    cmp dx,[name_handle]
    jne fail_name
    mov ah,45h
    int 67h
    test ah,ah
    jnz fail_name
    mov bx,1
    mov ah,43h
    int 67h
    test ah,ah
    jnz fail_name
    mov [name_handle],dx
    push cs
    pop es
    mov di,name_result
    mov ax,5300h
    int 67h
    test ah,ah
    jnz fail_name
    xor ax,ax
    mov di,name_result
    mov cx,8
    repe scasb
    jne fail_name
    mov dx,[name_handle]
    mov ah,45h
    int 67h
    test ah,ah
    jnz fail_name
    mov si,handle_name
    mov ax,5401h
    int 67h
    test ah,ah
    jnz fail_name
    cmp dx,[handle]
    jne fail_name

    ; 55 performs a far jump even when the mapping list is empty.
    mov word [jump_struct], jump_target
    mov word [jump_struct+2], cs
    mov dx, [handle]
    mov si, jump_struct
    mov ax, 5500h
    int 67h
    jmp fail_alter                    ; successful calls never return here
jump_target:
    test ah, ah
    jnz fail_alter
    mov word [jump_struct], jump_target_segment
    mov dx, [handle]
    mov si, jump_struct
    mov ax, 5501h
    int 67h
    jmp fail_alter
jump_target_segment:
    test ah, ah
    jnz fail_alter

    ; 56/02 reports stack space; 56/00 calls and restores a physical map.
    mov ax, 5602h
    int 67h
    test ah, ah
    jnz fail_alter
    test bx, bx
    jz fail_alter
    mov word [call_struct], call_target
    mov word [call_struct+2], cs
    mov byte [call_struct+4], 1
    mov word [call_struct+5], map_array
    mov word [call_struct+7], cs
    mov byte [call_struct+9], 1
    mov word [call_struct+10], map_array
    mov word [call_struct+12], cs
    mov dx, [handle]
    mov si, call_struct
    mov ax, 5600h
    int 67h
    test ah, ah
    jnz fail_alter
    cmp byte [call_seen], 1
    jne fail_alter
    mov byte [call_seen], 0
    mov word [call_struct], call_target
    mov word [call_struct+5], map_array_segment
    mov word [call_struct+10], map_array_segment
    mov dx, [handle]
    mov si, call_struct
    mov ax, 5601h
    int 67h
    test ah, ah
    jnz fail_alter
    cmp byte [call_seen], 1
    jne fail_alter

    ; 57: conventional -> EMS -> conventional move, then byte comparison.
    mov ax, cs
    mov [move_to_ems+9], ax
    mov [move_from_ems+16], ax
    mov ax, [handle]
    mov [move_to_ems+12], ax
    mov [move_from_ems+5], ax
    mov si, move_to_ems
    mov ax, 5700h
    int 67h
    test ah, ah
    jnz fail_move
    mov si, move_from_ems
    mov ax, 5700h
    int 67h
    test ah, ah
    jnz fail_move
    mov si, move_source
    mov di, move_result
    mov cx, 16
    repe cmpsb
    jne fail_move
    mov ax, cs
    mov [exchange_desc+9], ax
    mov [exchange_desc+16], ax
    mov si, exchange_desc
    mov ax, 5701h
    int 67h
    test ah, ah
    jnz fail_move
    cmp byte [exchange_left], 'R'
    jne fail_move
    cmp byte [exchange_right], 'L'
    jne fail_move

    ; 58: both mappable-address array forms.
    mov ax, 5801h
    int 67h
    test ah, ah
    jnz fail_info
    mov bx, cx
    push cs
    pop es
    mov di, physical_pages
    mov ax, 5800h
    int 67h
    test ah, ah
    jnz fail_info
    cmp cx, bx
    jne fail_info

    ; 59: hardware-info structure and raw-page availability.
    push cs
    pop es
    mov di, hardware_info
    mov ax, 5900h
    int 67h
    test ah, ah
    jnz fail_info
    cmp word [hardware_info], 400h
    jne fail_info
    mov ax, 5901h
    int 67h
    test ah, ah
    jnz fail_info
    test dx, dx
    jz fail_info

    ; 5A accepts a zero-page raw handle; it remains a normal releasable handle.
    xor bx, bx
    mov ah, 5ah
    int 67h
    test ah, ah
    jnz fail_raw
    mov [raw_handle], dx
    mov ah, 45h
    int 67h
    test ah, ah
    jnz fail_raw

    ; 5B: save-area sizing plus an allocate/deallocate register-set cycle.
    mov ax, 5b02h
    int 67h
    test ah, ah
    jnz fail_altreg
    test dx, dx
    jz fail_altreg
    mov ax, 5b03h
    int 67h
    test ah, ah
    jnz fail_altreg
    mov [alt_set], bl
    mov ax, 5b04h
    int 67h
    test ah, ah
    jnz fail_altreg
    xor bl, bl
    xor di, di
    xor ax, ax
    mov es, ax
    mov ax, 5b01h
    int 67h
    test ah, ah
    jnz fail_altreg
    mov ax, 5b00h
    int 67h
    test ah, ah
    jnz fail_altreg
    test bl, bl
    jnz fail_altreg
    mov al, 5
.dma_subfunction:
    mov ah, 5bh
    int 67h
    cmp ah, 9eh
    jne fail_altreg
    inc al
    cmp al, 9
    jb .dma_subfunction

    ; 5C warm-boot preparation.
    mov ah, 5ch
    int 67h
    test ah, ah
    jnz fail_warm
    ; 5D access-key lifecycle: disable, observe denial, re-enable, release.
    xor bx, bx
    xor cx, cx
    mov ax, 5d00h
    int 67h
    test ah, ah
    jnz fail_os
    mov [os_key_low], bx
    mov [os_key_high], cx
    mov ax, 5d01h
    int 67h
    test ah, ah
    jnz fail_os
    mov ax, 5901h
    int 67h
    cmp ah, 0a4h
    jne fail_os
    mov bx, [os_key_low]
    mov cx, [os_key_high]
    mov ax, 5d00h
    int 67h
    test ah, ah
    jnz fail_os
    mov ax, 5901h
    int 67h
    test ah, ah
    jnz fail_os
    mov bx, [os_key_low]
    mov cx, [os_key_high]
    mov ax, 5d02h
    int 67h
    test ah, ah
    jne fail_os

    mov dx, [handle]
    mov ah, 45h
    int 67h
    test ah, ah
    jnz fail_release
    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

; Two live saved contexts must retain independent slot contents. Restoring
; one releases only that handle's save slot, not the other owner's snapshot.
saved_map_owners:
    mov ah,41h
    int 67h
    test ah,ah
    jnz fail_save
    mov es,bx
    mov bx,1
    mov ah,43h
    int 67h
    test ah,ah
    jnz fail_save
    mov [saved_owner],dx
    mov dx,[handle]
    xor bx,bx
    mov ax,4400h
    int 67h
    test ah,ah
    jnz fail_save
    mov word [es:0],1234h
    mov ah,47h
    int 67h
    test ah,ah
    jnz fail_save
    mov dx,[saved_owner]
    xor bx,bx
    mov ax,4400h
    int 67h
    test ah,ah
    jnz fail_save
    mov word [es:0],5678h
    mov ah,47h
    int 67h
    test ah,ah
    jnz fail_save
    mov dx,[handle]
    mov ah,48h
    int 67h
    test ah,ah
    jnz fail_restore
    cmp word [es:0],1234h
    jne fail_restore
    mov dx,[saved_owner]
    mov ah,48h
    int 67h
    test ah,ah
    jnz fail_restore
    cmp word [es:0],5678h
    jne fail_restore
    mov bx,0ffffh
    mov ax,4400h
    int 67h
    test ah,ah
    jnz fail_restore
    mov dx,[saved_owner]
    mov ah,45h
    int 67h
    test ah,ah
    jnz fail_release
    push cs
    pop es
    ret

find_handle_pages:
    push ax
    push bx
    push cx
    push di
    mov cx, bx
    mov di, handle_pages
.loop:
    mov ax, [handle]
    cmp [di], ax
    jne .next
    cmp word [di+2], 3
    jne .bad
    clc
    jmp .done
.next:
    add di, 4
    loop .loop
.bad:
    stc
.done:
    pop di
    pop cx
    pop bx
    pop ax
    ret

call_target:
    mov byte [cs:call_seen], 1
    retf

fail_alloc:       mov dx, msg_alloc
                  jmp fail
fail_map:         mov dx, msg_map
                  jmp fail
fail_save:        mov dx, msg_save
                  jmp fail
fail_restore:     mov dx, msg_restore
                  jmp fail
fail_unsupported: mov dx, msg_unsupported
                  jmp fail
fail_directory:   mov dx, msg_directory
                  jmp fail
fail_full_map:    mov dx, msg_full_map
                  jmp fail
fail_partial_map: mov dx, msg_partial_map
                  jmp fail
fail_map_array:   mov dx, msg_map_array
                  jmp fail
fail_realloc:     mov dx, msg_realloc
                  jmp fail
fail_attr:        mov dx, msg_attr
                  jmp fail
fail_name:        mov dx, msg_name
                  jmp fail
fail_alter:       mov dx, msg_alter
                  jmp fail
fail_move:        mov dx, msg_move
                  jmp fail
fail_info:        mov dx, msg_info
                  jmp fail
fail_raw:         mov dx, msg_raw
                  jmp fail
fail_altreg:      mov dx, msg_altreg
                  jmp fail
fail_warm:        mov dx, msg_warm
                  jmp fail
fail_os:          mov dx, msg_os
                  jmp fail
fail_release:     mov dx, msg_release
fail:
    push cs
    pop ds
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

handle dw 0
raw_handle dw 0
alt_set db 0
call_seen db 0
os_key_low dw 0
os_key_high dw 0
handle_name db 'PARITY40'
other_name db 'PARITY41'
name_handle dw 0
saved_owner dw 0
name_result times 8 db 0
name_directory times 256 db 0
handle_pages times 256 db 0
physical_pages times 256 db 0
map_array dw 0, 0
map_array_segment dw 0, 0
full_map_saved times 260 db 0
full_map_previous times 260 db 0
partial_request dw 1, 0
partial_saved times 8 db 0
hardware_info times 16 db 0
jump_struct:
    dd 0
    db 0
    dd 0
call_struct:
    dd 0
    db 0
    dd 0
    db 0
    dd 0
    times 4 dw 0
move_source db 'EMS40-MOVE-CHECK'
move_result times 16 db 0
exchange_left db 'LEFT'
exchange_right db 'RGHT'
exchange_desc:
    dd 4
    db 0
    dw 0
    dw exchange_left
    dw 0
    db 0
    dw 0
    dw exchange_right
    dw 0

; region length; source/destination descriptors are type, handle, offset,
; and conventional segment or EMS logical page.
move_to_ems:
    dd 16
    db 0
    dw 0
    dw move_source
    dw 0
    db 1
    dw 0
    dw 0
    dw 0
move_from_ems:
    dd 16
    db 1
    dw 0
    dw 0
    dw 0
    db 0
    dw 0
    dw move_result
    dw 0

pass_message db 'EMS40_EXTENDED_PASS',13,10,'$'
msg_alloc db 'EMS40_ALLOC_FAIL',13,10,'$'
msg_map db 'EMS40_MAP_FAIL',13,10,'$'
msg_save db 'EMS40_SAVE_FAIL',13,10,'$'
msg_restore db 'EMS40_RESTORE_FAIL',13,10,'$'
msg_unsupported db 'EMS40_UNSUPPORTED_STATUS_FAIL',13,10,'$'
msg_directory db 'EMS40_DIRECTORY_FAIL',13,10,'$'
msg_full_map db 'EMS40_FULL_MAP_FAIL',13,10,'$'
msg_partial_map db 'EMS40_PARTIAL_MAP_FAIL',13,10,'$'
msg_map_array db 'EMS40_MAP_ARRAY_FAIL',13,10,'$'
msg_realloc db 'EMS40_REALLOC_FAIL',13,10,'$'
msg_attr db 'EMS40_ATTRIBUTE_FAIL',13,10,'$'
msg_name db 'EMS40_NAME_FAIL',13,10,'$'
msg_alter db 'EMS40_ALTER_CALL_FAIL',13,10,'$'
msg_move db 'EMS40_MOVE_FAIL',13,10,'$'
msg_info db 'EMS40_INFO_FAIL',13,10,'$'
msg_raw db 'EMS40_RAW_FAIL',13,10,'$'
msg_altreg db 'EMS40_ALTREG_FAIL',13,10,'$'
msg_warm db 'EMS40_WARM_FAIL',13,10,'$'
msg_os db 'EMS40_OS_DISABLE_FAIL',13,10,'$'
msg_release db 'EMS40_RELEASE_FAIL',13,10,'$'
