; Discardable boot-transaction witness, never part of a normal provider.
; Allocate before EMM backing preparation; verify after activation/cancellation.
; All real-mode move pointers are rebuilt from the current (possibly moved) CS.
boot_owner_entry dd 0
boot_owner_handle dw 0
boot_owner_physical dd 0
boot_owner_move dd 1024
        dw 0
        dd 0
        dw 0
        dd 0
boot_owner_pattern db 1024 dup (0)
boot_owner_result db 1024 dup (0)
boot_owner_step db 0

BootOwnerPrepare proc near
        pushf
        pusha
        push ds
        push es
        push cs
        pop ds
        assume ds:LAST
        mov [boot_owner_step],1
        mov ax,4300h
        int 2fh
        cmp al,80h
        jne BootOwnerFail
        mov ax,4310h
        int 2fh
        mov word ptr [boot_owner_entry],bx
        mov word ptr [boot_owner_entry+2],es
        mov ah,09h
        mov dx,1
        call dword ptr [boot_owner_entry]
        cmp ax,1
        jne BootOwnerFail
        mov [boot_owner_handle],dx
        mov [boot_owner_step],2
        mov ah,0ch
        call dword ptr [boot_owner_entry]
        cmp ax,1
        jne BootOwnerFail
        mov word ptr [boot_owner_physical],bx
        mov word ptr [boot_owner_physical+2],dx
        push cs
        pop es
        mov di,offset boot_owner_pattern
        mov cx,512
        mov ax,0a531h
        cld
BootOwnerFill:
        stosw
        add ax,137
        loop BootOwnerFill
        mov word ptr [boot_owner_move+4],0
        mov word ptr [boot_owner_move+6],offset boot_owner_pattern
        mov word ptr [boot_owner_move+8],cs
        mov ax,[boot_owner_handle]
        mov word ptr [boot_owner_move+10],ax
        mov dword ptr [boot_owner_move+12],0
        mov si,offset boot_owner_move
        mov [boot_owner_step],3
        mov ah,0bh
        call dword ptr [boot_owner_entry]
        cmp ax,1
        jne BootOwnerFail
        pop es
        pop ds
        popa
        popf
        ret
BootOwnerPrepare endp

BootOwnerVerify proc near
        pushf
        pusha
        push ds
        push es
        push cs
        pop ds
        assume ds:LAST
        ; Check the cached pre-prepare entry, not just fresh discovery.
        mov [boot_owner_step],4
        mov dx,[boot_owner_handle]
        mov ah,0eh
        call dword ptr [boot_owner_entry]
        cmp ax,1
        jne BootOwnerFail
        cmp bh,1
        jne BootOwnerFail
        cmp dx,1
        jne BootOwnerFail
        mov [boot_owner_step],5
        mov dx,[boot_owner_handle]
        mov ah,0ch
        call dword ptr [boot_owner_entry]
        cmp ax,1
        jne BootOwnerFail
        cmp bx,word ptr [boot_owner_physical]
        jne BootOwnerFail
        cmp dx,word ptr [boot_owner_physical+2]
        jne BootOwnerFail
        mov dx,[boot_owner_handle]
        mov ah,0dh
        call dword ptr [boot_owner_entry]
        cmp ax,1
        jne BootOwnerFail
        mov ax,[boot_owner_handle]
        mov word ptr [boot_owner_move+4],ax
        mov dword ptr [boot_owner_move+6],0
        mov word ptr [boot_owner_move+10],0
        mov word ptr [boot_owner_move+12],offset boot_owner_result
        mov word ptr [boot_owner_move+14],cs
        mov si,offset boot_owner_move
        mov [boot_owner_step],6
        mov ah,0bh
        call dword ptr [boot_owner_entry]
        cmp ax,1
        jne BootOwnerFail
ifdef EMM_BOOTSTRAP_OWNER_BAD
        xor byte ptr [boot_owner_result+1023],1
endif
        push cs
        pop es
        mov si,offset boot_owner_pattern
        mov di,offset boot_owner_result
        mov cx,512
        mov [boot_owner_step],7
        cld
        repe cmpsw
        jne BootOwnerFail
        mov [boot_owner_step],8
        mov dx,[boot_owner_handle]
        mov ah,0dh
        call dword ptr [boot_owner_entry]
        cmp ax,1
        jne BootOwnerFail
        mov [boot_owner_step],9
        mov dx,[boot_owner_handle]
        mov ah,0ah
        call dword ptr [boot_owner_entry]
        cmp ax,1
        jne BootOwnerFail
        ; Fixed 10-byte record: tag, preserved handle, physical base, size KiB.
        mov al,'X'
        out 0e9h,al
        mov al,'O'
        out 0e9h,al
        mov si,offset boot_owner_handle
        mov cx,6
BootOwnerEmit:
        lodsb
        out 0e9h,al
        loop BootOwnerEmit
        mov al,1
        out 0e9h,al
        xor al,al
        out 0e9h,al
        pop es
        pop ds
        popa
        popf
        ret
BootOwnerVerify endp

BootOwnerFail:
        mov al,'X'
        out 0e9h,al
        mov al,'F'
        out 0e9h,al
        mov al,cs:[boot_owner_step]
        out 0e9h,al
        mov dx,0f4h
        mov ax,11h
        out dx,ax
        cli
BootOwnerHalt:
        hlt
        jmp BootOwnerHalt
        assume ds:DGROUP
