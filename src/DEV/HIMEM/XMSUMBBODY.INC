; The selected bootstrap image owns both code and records. ES:SI remains the
; external registration packet; DS selects this image's canonical UMB table.
bootstrap_umb_service proc far
        cmp ax,10h
        je boot_umb_allocate
        cmp ax,11h
        je boot_umb_release
        cmp ax,12h
        je boot_umb_register
        cmp ax,13h
        je boot_umb_unregister
        xor ax,ax
        mov bl,ERR_GENERAL
        retf
boot_umb_allocate:
        call xms_umb_request
        retf
boot_umb_release:
        call xms_umb_release
        retf
boot_umb_register:
        HIMEM_UMB_REGISTER boot_umb_return
        jmp short boot_umb_return
boot_umb_unregister:
        HIMEM_UMB_UNREGISTER boot_umb_return
boot_umb_return:
        retf
bootstrap_umb_service endp
        include XMSUMB.INC
