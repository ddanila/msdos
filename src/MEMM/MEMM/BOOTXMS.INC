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
IFDEF EMM_AUTHORITATIVE_OWNER_TEST
        include ..\..\INC\XMSCOPYABI.INC
; Deliberately unusable import metadata: status must not dereference/import it.
boot_owner_receipt db 'XAUT'
        dw 3,0ffffh,0ffffh,0,0,0,0,0ffffh
boot_owner_layout dw 6 dup (0) ; segment, permanent end, records, count, boot end, entry
ENDIF

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
IFDEF EMM_AUTHORITATIVE_OWNER_TEST
        mov [boot_owner_step],13
        call BootOwnerLayout
        mov [boot_owner_layout],dx
        mov [boot_owner_layout+2],bx
        mov [boot_owner_layout+4],si
        mov [boot_owner_layout+6],di
        mov [boot_owner_layout+8],cx
        mov ax,word ptr [boot_owner_entry]
        mov [boot_owner_layout+10],ax
ENDIF
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
IFDEF EMM_AUTHORITATIVE_OWNER_TEST
IFNDEF EMM_REJECT_PREPARED
        mov [boot_owner_step],11
        xor ax,ax
        call BootOwnerReceipt
        call BootOwnerReceipt
ENDIF
ENDIF
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
IFDEF EMM_AUTHORITATIVE_OWNER_TEST
IFNDEF EMM_REJECT_PREPARED
        mov [boot_owner_step],12
        mov ax,1
        call BootOwnerReceipt
        call BootOwnerReceipt
ENDIF
ENDIF
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
ifdef EMM_BOOTSTRAP_EXPECT_HMA
        ; DOS-high must retain the same complete cached XMS entry across the
        ; loader callback. A config string alone is not residency evidence.
        mov [boot_owner_step],10
        mov ax,1234h
        mov cx,584dh
        mov si,1
        xor di,di
        int 2fh
        cmp ax,1
        jne BootOwnerFail
        cmp bx,word ptr [boot_owner_entry]
        jne BootOwnerFail
        cmp dx,word ptr [boot_owner_entry+2]
        jne BootOwnerFail
endif
IFDEF EMM_AUTHORITATIVE_OWNER_TEST
        mov [boot_owner_step],14
        call BootOwnerLayout
        cmp dx,[boot_owner_layout]
        jne BootOwnerFail
        cmp bx,[boot_owner_layout+2]
        jne BootOwnerFail
        cmp si,[boot_owner_layout+4]
        jne BootOwnerFail
        cmp di,[boot_owner_layout+6]
        jne BootOwnerFail
        cmp cx,[boot_owner_layout+8]
        jne BootOwnerFail
        mov al,'X'
        out 0e9h,al
        mov al,'L'
        out 0e9h,al
        mov si,offset boot_owner_layout
        mov cx,12
BootOwnerEmitLayout:
        lodsb
        out 0e9h,al
        loop BootOwnerEmitLayout
ENDIF
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

IFDEF EMM_AUTHORITATIVE_OWNER_TEST
BootOwnerLayout proc near
        ; Reject mismatched protocol versions without touching ownership.
        mov ax,XCP_LAYOUT_QUERY
        mov cx,XCP_LAYOUT_SIGNATURE
        mov si,XCP_LAYOUT_VERSION+1
        xor di,di
        int 2fh
        or ax,ax
        jnz BootOwnerFail
        mov ax,XCP_LAYOUT_QUERY
        mov cx,XCP_LAYOUT_SIGNATURE
        mov si,XCP_LAYOUT_VERSION
        xor di,di
        int 2fh
        cmp ax,XCP_LAYOUT_REPLY
        jne BootOwnerFail
        cmp dx,word ptr [boot_owner_entry+2]
        jne BootOwnerFail
        test bx,15
        jnz BootOwnerFail
        or bx,bx
        jz BootOwnerFail
        cmp bx,si
        jae BootOwnerFail
        cmp di,32
        jne BootOwnerFail
        mov ax,di
        imul ax,5              ; shared XMS record width
        add ax,si
        jc BootOwnerFail
        add ax,15
        jc BootOwnerFail
        and ax,0fff0h
        cmp ax,cx
        jne BootOwnerFail
        cmp word ptr [boot_owner_entry],bx
        jae BootOwnerFail
        ret
BootOwnerLayout endp

; AX expected committed state. Read twice around the first cached-entry call:
; receipt alone must not import, and repeated receipt must not reimport.
BootOwnerReceipt proc near
        pusha
        push es
        mov bp,ax
        mov ax,XCP_QUERY
        int 15h
        cmp ax,XCP_REPLY
        jne BootOwnerFail
        cmp bx,XCP_SIGNATURE
        jne BootOwnerFail
        cmp cx,XCP_VERSION
        jne BootOwnerFail
        test dx,XCP_OWNER_RECEIPT
        jz BootOwnerFail
        push cs
        pop es
        mov si,offset boot_owner_receipt
        mov word ptr [si+10],0ffffh
        mov word ptr [si+12],0ffffh
        mov word ptr [si+14],0ffffh
        mov ah,87h
        int 15h
        jc BootOwnerFail
        cmp word ptr [boot_owner_receipt+10],bp
        jne BootOwnerFail
        cmp word ptr [boot_owner_receipt+14],bp
        jne BootOwnerFail
        mov ax,bp
        shl ax,5               ; fixture uses the default 32-handle owner
        cmp word ptr [boot_owner_receipt+12],ax
        jne BootOwnerFail
        cmp word ptr [boot_owner_receipt+6],0ffffh
        jne BootOwnerFail
        cmp word ptr [boot_owner_receipt+8],0ffffh
        jne BootOwnerFail
        cmp word ptr [boot_owner_receipt+18],0ffffh
        jne BootOwnerFail
        pop es
        popa
        ret
BootOwnerReceipt endp
ENDIF

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
