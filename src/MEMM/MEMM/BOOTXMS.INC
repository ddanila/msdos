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
IFNDEF EMM_BOOTSTRAP_XMS_HANDLES
EMM_BOOTSTRAP_XMS_HANDLES equ 32
ENDIF
; Deliberately unusable import metadata: status must not dereference/import it.
boot_owner_receipt db 'XAUT'
        dw 3,0ffffh,0ffffh,0,0,0,0,0ffffh
boot_owner_layout dw 6 dup (0) ; segment, permanent end, records, count, boot end, entry
ENDIF
IFDEF EMM_BOOTSTRAP_STAGE_TEST
boot_stage_segment dw 0
        align 16
boot_stage_image db 8192 dup (0) ; explicitly owned LAST scratch, discarded on return
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
IFDEF EMM_BOOTSTRAP_STAGE_TEST
        call BootStagePrepare
ENDIF
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
IFDEF EMM_BOOTSTRAP_STAGE_TEST
IFDEF EMM_REJECT_PREPARED
        mov [boot_owner_step],16
        mov dx,[boot_stage_segment]
        mov ax,XCP_STAGE_RESTORE
        mov cx,XCP_LAYOUT_SIGNATURE
        mov si,XCP_LAYOUT_VERSION
        xor di,di
        int 2fh
        cmp ax,XCP_LAYOUT_REPLY
        jne BootOwnerFail
        mov ax,XCP_STAGE_RESTORE
        int 2fh
        or ax,ax
        jnz BootOwnerFail
        push es
        mov es,[boot_stage_segment]
        xor di,di
        mov cx,8192
        mov al,0f4h
        cld
        rep stosb
        pop es
ENDIF
ENDIF
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
IFDEF EMM_COMMON_XMS_TEST
        mov [boot_owner_step],18
        mov ax,XCP_BOOTSTRAP_FINISH
        mov cx,XCP_LAYOUT_SIGNATURE
        mov si,XCP_LAYOUT_VERSION
        xor di,di
        int 2fh
        cmp ax,XCP_LAYOUT_REPLY
        jne BootOwnerFail
ENDIF
IFDEF EMM_BOOTSTRAP_STAGE_TEST
        ; Both common owners are confirmed before discarding their stage.
        mov dx,[boot_stage_segment]
        mov ax,XCP_STAGE_RESTORE
        mov cx,XCP_LAYOUT_SIGNATURE
        mov si,XCP_LAYOUT_VERSION
        xor di,di
        int 2fh
        or ax,ax
        jnz BootOwnerFail      ; restoring after publication must be refused
        push es
        mov es,[boot_stage_segment]
        xor di,di
        mov cx,8192
        mov al,0f4h
        cld
        rep stosb
        pop es
ENDIF
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
IFDEF EMM_BOOTSTRAP_STAGE_TEST
BootStageRelocated proc near
        pushf
        pusha
        push ds
        push cs
        pop ds
        mov [boot_owner_step],17
        mov ax,offset boot_stage_image
        test ax,15
        jnz BootOwnerFail
        shr ax,4
        mov dx,cs
        add dx,ax
        jc BootOwnerFail
        mov bx,[boot_stage_segment]
        cmp bx,dx
        je BootStageRelocatedDone
        push bx
        push dx
        mov ah,08h
        call dword ptr [boot_owner_entry]
        or ax,ax
        jnz BootOwnerFail
        or dx,dx
        jnz BootOwnerFail
        cmp bl,8eh
        jne BootOwnerFail
        ; Frozen Move must fail before dereferencing an unusable descriptor.
        push ds
        xor ax,ax
        mov ds,ax
        mov si,0ffffh
        mov ah,0bh
        call dword ptr cs:[boot_owner_entry]
        pop ds
        or ax,ax
        jnz BootOwnerFail
        cmp bl,8eh
        jne BootOwnerFail
        pop dx
        pop bx
IFNDEF EMM_BOOTSTRAP_SKIP_RETARGET
        ; A stale expected root must fail without blocking the correct retry.
        inc bx
        mov ax,XCP_STAGE_RETARGET
        mov cx,XCP_LAYOUT_SIGNATURE
        mov si,XCP_LAYOUT_VERSION
        xor di,di
        int 2fh
        or ax,ax
        jnz BootOwnerFail
        dec bx
        mov ax,XCP_STAGE_RETARGET
        int 2fh
        cmp ax,XCP_LAYOUT_REPLY
        jne BootOwnerFail
        mov ax,XCP_STAGE_RETARGET
        int 2fh
        or ax,ax
        jnz BootOwnerFail      ; expected-old token may not be replayed
        mov [boot_stage_segment],dx
ENDIF
BootStageRelocatedDone:
        pop ds
        popa
        popf
        ret
BootStageRelocated endp

BootStagePrepare proc near
        pushf
        pusha
        push ds
        push es
        mov cs:[boot_owner_step],15
        mov cx,cs:[boot_owner_layout+8]
        cmp cx,8192
        ja BootOwnerFail
        mov dx,cs
        mov ax,offset boot_stage_image
        test ax,15
        jnz BootOwnerFail
        shr ax,4
        add dx,ax
        jc BootOwnerFail
        mov cs:[boot_stage_segment],dx
        mov es,dx
        mov ds,cs:[boot_owner_layout]
        xor si,si
        xor di,di
        cld
        rep movsb
        ; A stale copy must not be published, and rejection must permit retry.
        xor byte ptr es:[0],1
        mov ax,XCP_STAGE_BIND
        mov cx,XCP_LAYOUT_SIGNATURE
        mov si,XCP_LAYOUT_VERSION
        xor di,di
        int 2fh
        or ax,ax
        jnz BootOwnerFail
        xor byte ptr es:[0],1
        mov ax,XCP_STAGE_BIND
        int 2fh
        cmp ax,XCP_LAYOUT_REPLY
        jne BootOwnerFail
        mov ax,XCP_STAGE_BIND
        int 2fh
        or ax,ax
        jnz BootOwnerFail      ; no duplicate owner publication
        ; Make stale bootstrap use fail before EMM backing is even allocated.
        mov es,cs:[boot_owner_layout]
        mov di,cs:[boot_owner_layout+2]
        mov cx,cs:[boot_owner_layout+8]
        sub cx,di
        mov al,0f4h
        cld
        rep stosb
        pop es
        pop ds
        popa
        popf
        ret
BootStagePrepare endp
ENDIF

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
        cmp di,EMM_BOOTSTRAP_XMS_HANDLES
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
        or ax,ax
        jz BootReceiptCapacity
        mov ax,EMM_BOOTSTRAP_XMS_HANDLES
BootReceiptCapacity:
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
