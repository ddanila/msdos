; Only PREPARE runs in the original bootstrap image. Later administration
; runs in SYSINIT-owned code, separate from the moving allocator stage.
bootstrap_admin proc far
        cmp ax,XCP_ADMIN_PREPARE
        je admin_prepare
        cmp ax,XCP_BOOTSTRAP_FINISH
        jne admin_stage_call
        call bootstrap_admin_finish
        retf
admin_stage_call:
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        call bootstrap_admin_stage
else
        xor ax,ax
endif
        retf
admin_prepare:
        mov ax,[handle_limit]
        imul ax,HANDLE_SIZE
        add ax,offset handles+15
        and ax,0fff0h
        cmp bx,ax
        jb admin_prepare_bad
        mov cx,ax
        shr ax,4
        mov bx,ds
        add bx,ax
        jc admin_prepare_bad
        cmp dx,bx
        jb admin_prepare_bad
        add ax,dx
        jc admin_prepare_bad
        cmp ax,0a000h
        ja admin_prepare_bad
        mov es,dx
        xor si,si
        xor di,di
        cld
        rep movsb
        mov word ptr [admin_entry+2],dx
        mov [admin_state],1
        mov ax,XCP_LAYOUT_REPLY
        retf
admin_prepare_bad:
        xor ax,ax
        retf
bootstrap_admin endp

; Public XMS must enter the actual low front, never this copied code image.
admin_xms_call proc near
        push bp
        sub sp,4
        mov bp,sp
        mov word ptr ss:[bp],offset xms_control
        push ds
        pop word ptr ss:[bp+2]
        call dword ptr ss:[bp]
        add sp,4
        pop bp
        ret
admin_xms_call endp
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        include XMSADMINSTAGE.INC
endif
        include XMSBOOTFINISH.INC
