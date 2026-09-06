; Transitional common-core adapter. Reuse the existing 20-byte copy packet;
; copy the caller descriptor, never decode it or fetch a handle record here.
; CF set only when bootstrap still owns services and high transport is absent.
xms_public_move_front proc near
        pushf
        cli
        push bx
        push dx
        push bp
        push es
        mov ax,8
        call xms_remote_owned
        jc move_front_bootstrap
        mov ax,XCP_QUERY
        int 15h
        cmp ax,XCP_REPLY
        jne move_front_failed
        cmp bx,XCP_SIGNATURE
        jne move_front_failed
        cmp cx,XCP_VERSION
        jne move_front_failed
        test dx,XCP_PUBLIC_MOVE
        jz move_front_failed
        mov si,[caller_si]
        cmp si,65536-16
        ja move_front_bad_descriptor
        mov es,[caller_ds]
        mov di,offset protected_copy_packet+4
        mov cx,16
move_front_snapshot:
        mov al,es:[si]
        mov [di],al
        inc si
        inc di
        loop move_front_snapshot
        mov word ptr [protected_copy_packet],4d58h
        mov word ptr [protected_copy_packet+2],4d53h
        push ds
        pop es
        mov si,offset protected_copy_packet
        mov ah,87h
        int 15h
        jc move_front_failed
        mov ax,word ptr [protected_copy_packet]
        mov bx,word ptr [protected_copy_packet+2]
        cmp ax,1
        ja move_front_failed
        jmp short move_front_restore
move_front_bad_descriptor:
        mov bl,ERR_BAD_LENGTH
        xor ax,ax
        jmp short move_front_restore
move_front_failed:
        xor ax,ax
        mov bl,ERR_GENERAL
move_front_restore:
        mov word ptr [protected_copy_packet],4358h ; restore XCPY for old copy adapter
        mov word ptr [protected_copy_packet+2],5950h
        pop es
        pop bp
        pop dx
        or ax,ax
        jz move_front_error
        pop bx                   ; public Move preserves BX on success
        popf
        clc
        ret
move_front_error:
        add sp,2
        popf
        clc
        ret
move_front_bootstrap:
        pop es
        pop bp
        pop dx
        pop bx
        popf
        stc
        ret
xms_public_move_front endp
