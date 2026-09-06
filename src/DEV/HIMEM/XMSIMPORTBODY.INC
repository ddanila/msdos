; Executes in the original or staged bootstrap image, with DS selecting the
; permanent front. The caller, never this body, retires its storage on return.
bootstrap_remote_owned proc far
        pushf
        cli
        push es
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp [bootstrap_frozen],0
        jne auth_failed
endif
        mov [owner_operation],ax
        mov [owner_bx],bx
        mov [owner_total],dx
        mov ax,XCP_QUERY
ifdef HIMEM_COMMON_XMS_TEST
        call xms_common_query
        cmp word ptr [xms_bound_entry+2],0
        je auth_unavailable
else
        int 15h
endif
        cmp ax,XCP_REPLY
        jne auth_unavailable
        cmp bx,XCP_SIGNATURE
        jne auth_unavailable
        cmp cx,XCP_VERSION
        jne auth_unavailable
        and dx,XCP_REQUIRED OR XCP_OWNER_ACTIVE
        cmp dx,XCP_REQUIRED OR XCP_OWNER_ACTIVE
        jne auth_unavailable
        push ds
        pop es
        cmp [owner_query_active],0
        jne short auth_send
        mov ax,[handle_limit]
        mov [owner_limit],ax
        mov ax,[extended_kb]
        mov [owner_pool],ax
        ; No local mutation is allowed after attempting ownership publication,
        ; including an ambiguous transport failure after the high commit.
        mov [owner_query_active],1
auth_send:
        mov word ptr [owner_packet],4158h ; XAUT
        mov word ptr [owner_packet+2],5455h
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp word ptr [bootstrap_stage_entry+2],0
        je auth_packet_ready
        ; The transport header and live records must share the staged segment.
        ; Keep using it after ambiguous failures until a successful response.
        mov es,word ptr [bootstrap_stage_entry+2]
        mov si,offset owner_packet
        mov di,si
        mov cx,20
        cld
        rep movsb
auth_packet_ready:
endif
        mov si,offset owner_packet
        mov ah,87h
ifdef HIMEM_COMMON_XMS_TEST
        call xms_common_send
else
        int 15h
endif
        jc short auth_failed
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        mov ax,es:[owner_largest]
        mov bx,es:[owner_bx]
        mov dx,es:[owner_total]
        mov [owner_largest],ax
        mov [owner_bx],bx
        mov [owner_total],dx
        ; UMB ownership may still be local: the finish gate releases the stage.
        push ds
        pop es
endif
        mov [owner_query_active],2 ; confirmed reply; retire only after returning low
        mov ax,[owner_largest]
        mov bx,[owner_bx]
        mov dx,[owner_total]
auth_return:
        pop es
        popf
        clc
        retf
auth_unavailable:
        cmp [owner_query_active],0
        jne short auth_failed
        mov bx,[owner_bx]
        mov dx,[owner_total]
        pop es
        popf
        stc
        retf
auth_failed:
        xor ax,ax
        xor dx,dx
        mov bl,ERR_GENERAL
        jmp short auth_return
bootstrap_remote_owned endp
