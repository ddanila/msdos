; Operational bootstrap transaction for the paired SYSINIT loader.
; LAST owns the staged allocator until both live service owners accept it.
; Ordinary non-paired loading retains the standalone path.
        include ../../INC/XMSCOPYABI.INC
bootstrap_entry dd 0
bootstrap_stage dw 0
        align 16
bootstrap_image db 8192 dup (0)

BootstrapPrepare proc near
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push ds
        push es
        les bx,cs:[prepare_request]
        cmp byte ptr es:[bx],24
        jb BootstrapPrepareSkip
        cmp word ptr es:[bx+BP_MAGIC_OFF],BP_MAGIC
        jne BootstrapPrepareSkip
        cmp word ptr es:[bx+BP_VERSION_OFF],BP_VERSION
        jne BootstrapPrepareSkip
        mov ax,4310h
        int 2fh
        mov word ptr cs:[bootstrap_entry],bx
        mov word ptr cs:[bootstrap_entry+2],es
        mov ax,XCP_LAYOUT_QUERY
        mov cx,XCP_LAYOUT_SIGNATURE
        mov si,XCP_LAYOUT_VERSION
        xor di,di
        int 2fh
        cmp ax,XCP_LAYOUT_REPLY
        jne BootstrapPrepareBad
        cmp dx,word ptr cs:[bootstrap_entry+2]
        jne BootstrapPrepareBad
        test bx,15
        jnz BootstrapPrepareBad
        or bx,bx
        jz BootstrapPrepareBad
        cmp bx,si
        jae BootstrapPrepareBad
        cmp di,1
        jb BootstrapPrepareBad
        cmp di,128
        ja BootstrapPrepareBad
        mov ax,di
        imul ax,5
        add ax,si
        jc BootstrapPrepareBad
        add ax,15
        jc BootstrapPrepareBad
        and ax,0fff0h
        cmp ax,cx
        jne BootstrapPrepareBad
        cmp cx,8192
        ja BootstrapPrepareBad
        mov ds,dx
        mov dx,cs
        mov ax,offset bootstrap_image
        shr ax,4
        add dx,ax
        jc BootstrapPrepareBad
        mov es,dx
        xor si,si
        xor di,di
        cld
        rep movsb
        mov ax,XCP_STAGE_BIND
        mov cx,XCP_LAYOUT_SIGNATURE
        mov si,XCP_LAYOUT_VERSION
        xor di,di
        int 2fh
        cmp ax,XCP_LAYOUT_REPLY
        jne BootstrapPrepareBad
        mov cs:[bootstrap_stage],dx
BootstrapPrepareSkip:
        clc
        jmp short BootstrapPrepareReturn
BootstrapPrepareBad:
        stc
BootstrapPrepareReturn:
        pop es
        pop ds
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret
BootstrapPrepare endp

BootstrapRelocated proc near
        pushf
        pusha
        push ds
        push cs
        pop ds
        mov bx,[bootstrap_stage]
        or bx,bx
        jz BootstrapRelocatedDone
        mov dx,cs
        mov ax,offset bootstrap_image
        shr ax,4
        add dx,ax
        jc BootstrapFatal
        cmp bx,dx
        je BootstrapRelocatedDone
        mov ax,XCP_STAGE_RETARGET
        mov cx,XCP_LAYOUT_SIGNATURE
        mov si,XCP_LAYOUT_VERSION
        xor di,di
        int 2fh
        cmp ax,XCP_LAYOUT_REPLY
        jne BootstrapFatal
        mov [bootstrap_stage],dx
BootstrapRelocatedDone:
        pop ds
        popa
        popf
        ret
BootstrapRelocated endp

BootstrapFinish proc near
        pushf
        pusha
        push ds
        push es
        push cs
        pop ds
        cmp [bootstrap_stage],0
        je BootstrapFinishDone
        cmp [provider_state],PROVIDER_ACTIVE
        jne BootstrapRestore
        ; A public query imports once or retrieves the existing receipt. It
        ; never allocates a test handle or changes the user's resource demand.
        mov bp,3
BootstrapFinishRetry:
        mov ah,08h
        call dword ptr [bootstrap_entry]
        mov ax,XCP_BOOTSTRAP_FINISH
        mov cx,XCP_LAYOUT_SIGNATURE
        mov si,XCP_LAYOUT_VERSION
        xor di,di
        int 2fh
        cmp ax,XCP_LAYOUT_REPLY
        je BootstrapFinished
        dec bp
        jnz BootstrapFinishRetry
        ; An ambiguous publication cannot return to a discarded old owner.
        jmp short BootstrapFatal
BootstrapRestore:
        mov dx,[bootstrap_stage]
        mov ax,XCP_STAGE_RESTORE
        mov cx,XCP_LAYOUT_SIGNATURE
        mov si,XCP_LAYOUT_VERSION
        xor di,di
        int 2fh
        cmp ax,XCP_LAYOUT_REPLY
        jne BootstrapFatal
BootstrapFinished:
        mov [bootstrap_stage],0
BootstrapFinishDone:
        pop es
        pop ds
        popa
        popf
        ret
BootstrapFinish endp

BootstrapFatal:
        ; Ownership cannot safely be unwound. Report through firmware without
        ; issuing another DOS/XMS request or releasing this live stage.
        push cs
        pop ds
        mov si,offset BootstrapFatalMessage
BootstrapFatalPrint:
        lodsb
        or al,al
        jz BootstrapFatalStop
        mov ah,0eh
        mov bx,7
        int 10h
        jmp short BootstrapFatalPrint
BootstrapFatalStop:
        cli
        hlt
        jmp short BootstrapFatalStop
BootstrapFatalMessage db 13,10,'EMM386: unsafe bootstrap ownership state. Reboot required.',13,10,0
