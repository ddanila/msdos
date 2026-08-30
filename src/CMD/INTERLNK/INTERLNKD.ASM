; INTERLNK block-device client for the serial INTERSVR transport.

CODE SEGMENT PUBLIC
        ORG     0
        ASSUME  CS:CODE,DS:NOTHING,ES:NOTHING,SS:NOTHING

device_header:
        dd      0ffffffffh
        dw      0800h
        dw      strategy
        dw      interrupt
unit_count      db      0
        db      7 dup(0)

request_ptr     dd 0
connected       db 0
com_port        dw 03f8h
com_number      db 1
com_explicit    db 0
sector_number   dd 0
bpb_pointers    dw 5 dup(0)
remote_bpbs     db 125 dup(0)
boot_sector     db 512 dup(0)
current_unit    db 0
drive_limit     db 5
installed_units db 0

strategy PROC FAR
        mov     word ptr cs:request_ptr,bx
        mov     word ptr cs:request_ptr+2,es
        ret
strategy ENDP

interrupt PROC FAR
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        lds     bx,cs:request_ptr
        mov     al,[bx+2]
        cmp     al,0
        je      request_init
        cmp     cs:connected,0
        jne     short request_dispatch
        push    ax
        call    connect_server
        pop     ax
        jc      request_not_ready
request_dispatch:
        cmp     al,1
        je      request_media
        cmp     al,2
        je      request_bpb
        cmp     al,4
        je      request_read
        cmp     al,8
        je      request_write
        cmp     al,9
        je      request_write
        cmp     al,5
        je      request_busy
        cmp     al,6
        je      request_done
        cmp     al,7
        je      request_done
        cmp     al,10
        je      request_done
        cmp     al,11
        je      request_done
        cmp     al,13
        je      request_done
        cmp     al,14
        je      request_done
        cmp     al,15
        je      request_removable
        jmp     request_bad_command

request_init:
        call    parse_config
        jc      init_failed
        call    init_serial
        call    connect_server
        jc      init_failed
        lds     bx,cs:request_ptr
        mov     al,cs:unit_count
        mov     byte ptr [bx+13],al
        mov     word ptr [bx+14],OFFSET resident_end
        mov     word ptr [bx+16],cs
        mov     word ptr [bx+18],OFFSET bpb_pointers
        mov     word ptr [bx+20],cs
        call    install_multiplex
        jmp     request_done
init_failed:
        lds     bx,cs:request_ptr
        mov     byte ptr [bx+13],0
        mov     word ptr [bx+14],OFFSET resident_end
        mov     word ptr [bx+16],cs
        mov     word ptr [bx+3],8102h
        jmp     request_exit

connect_server PROC NEAR
        cmp     cs:com_explicit,0
        jne     short connect_selected_port
        push    bx
        mov     bl,1
connect_scan_port:
        mov     cs:com_number,bl
        xor     bh,bh
        dec     bx
        shl     bx,1
        mov     ax,cs:com_bases[bx]
        mov     cs:com_port,ax
        shr     bx,1
        inc     bx
        call    init_serial
        call    connect_on_port
        jnc     short connect_scan_found
        inc     bl
        cmp     bl,4
        jbe     short connect_scan_port
        pop     bx
        stc
        ret
connect_scan_found:
        pop     bx
        clc
        ret
connect_selected_port:
        call    connect_on_port
        ret
connect_server ENDP

connect_on_port PROC NEAR
        mov     cs:connected,0
        mov     cs:current_unit,0
        mov     word ptr cs:sector_number,0
        mov     word ptr cs:sector_number+2,0
        xor     al,al
        xor     dx,dx
        call    send_request
        jc      init_failed_connect
        call    receive_status
        jc      init_failed_connect
        call    receive_byte
        jc      init_failed_connect
        or      al,al
        jz      init_failed_connect
        cmp     al,5
        ja      init_failed_connect
        cmp     al,cs:drive_limit
        jbe     short init_count_ready
        mov     al,cs:drive_limit
init_count_ready:
        cmp     cs:installed_units,0
        je      short init_store_count
        cmp     al,cs:installed_units
        jne     init_failed_connect
        jmp     short init_have_count
init_store_count:
        mov     cs:unit_count,al
        mov     cs:installed_units,al
init_have_count:
        mov     cs:current_unit,0
init_geometry_loop:
        mov     al,1
        xor     dx,dx
        call    send_request
        jc      init_failed_connect
        call    receive_status
        jc      init_failed_connect
        push    cs
        pop     es
        mov     di,OFFSET boot_sector
        call    receive_sector
        jc      init_failed_connect
        push    cs
        pop     ds
        mov     si,OFFSET boot_sector+11
        xor     ax,ax
        mov     al,cs:current_unit
        mov     dx,25
        mul     dx
        mov     di,OFFSET remote_bpbs
        add     di,ax
        xor     bx,bx
        mov     bl,cs:current_unit
        shl     bx,1
        mov     word ptr cs:bpb_pointers[bx],di
        mov     cx,25
        rep     movsb
        inc     cs:current_unit
        mov     al,cs:current_unit
        cmp     al,cs:unit_count
        jb      init_geometry_loop
        mov     cs:connected,1
        clc
        ret
init_failed_connect:
        mov     cs:connected,0
        stc
        ret
connect_on_port ENDP

request_media:
        mov     byte ptr [bx+14],1
        jmp     request_done
request_bpb:
        xor     ax,ax
        mov     al,[bx+1]
        cmp     al,cs:unit_count
        jae     request_bad_command
        shl     ax,1
        mov     si,ax
        mov     ax,cs:bpb_pointers[si]
        mov     word ptr [bx+18],ax
        mov     word ptr [bx+20],cs
        jmp     request_done
request_busy:
        mov     word ptr [bx+3],0300h
        jmp     request_exit
request_removable:
        mov     word ptr [bx+3],0300h   ; busy bit denotes non-removable media
        jmp     request_exit

request_read:
        mov     al,2
        call    prepare_io
        jc      request_io_error
read_sector_loop:
        call    send_current_request
        jc      request_io_error
        call    receive_status
        jc      request_io_error
        les     di,cs:transfer_ptr
        call    receive_sector
        jc      request_io_error
        call    advance_transfer
        dec     word ptr cs:io_remaining
        jnz     read_sector_loop
        jmp     request_done

request_write:
        mov     al,3
        call    prepare_io
        jc      request_io_error
write_sector_loop:
        call    send_current_request
        jc      request_io_error
        les     si,cs:transfer_ptr
        call    send_sector
        jc      request_io_error
        call    receive_status
        jc      request_io_error
        call    advance_transfer
        dec     word ptr cs:io_remaining
        jnz     write_sector_loop
        jmp     request_done

request_not_ready:
        mov     word ptr [bx+3],8102h
        jmp     request_exit
request_io_error:
        mov     cs:connected,0
        lds     bx,cs:request_ptr
        mov     word ptr [bx+3],810bh
        jmp     request_exit
request_bad_command:
        mov     word ptr [bx+3],8103h
        jmp     request_exit
request_done:
        lds     bx,cs:request_ptr
        mov     word ptr [bx+3],0100h
request_exit:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
interrupt ENDP

prepare_io PROC NEAR
        ; AL is protocol command. Traditional DOS request packets provide a
        ; 16-bit starting sector at +20 and count at +18.
        mov     cs:io_command,al
        lds     bx,cs:request_ptr
        mov     al,[bx+1]
        cmp     al,cs:unit_count
        jae     short prepare_bad
        mov     cs:current_unit,al
        mov     cx,[bx+18]
        jcxz    short prepare_bad
        mov     cs:io_remaining,cx
        mov     ax,[bx+20]
        mov     word ptr cs:sector_number,ax
        mov     word ptr cs:sector_number+2,0
        mov     ax,[bx+14]
        mov     word ptr cs:transfer_ptr,ax
        mov     ax,[bx+16]
        mov     word ptr cs:transfer_ptr+2,ax
        clc
        ret
prepare_bad:
        stc
        ret
prepare_io ENDP

send_current_request PROC NEAR
        mov     al,cs:io_command
        mov     dx,word ptr cs:sector_number
        call    send_request
        ret
send_current_request ENDP

advance_transfer PROC NEAR
        inc     word ptr cs:sector_number
        jnz     short sector_advanced
        inc     word ptr cs:sector_number+2
sector_advanced:
        add     word ptr cs:transfer_ptr,512
        jnc     short transfer_advanced
        add     word ptr cs:transfer_ptr+2,1000h
transfer_advanced:
        ret
advance_transfer ENDP

send_request PROC NEAR
        ; AL command, DX low sector; high word is resident sector_number+2.
        push    ax
        mov     al,0a5h
        call    send_byte
        jc      short send_request_failed_pop
        mov     al,05ah
        call    send_byte
        jc      short send_request_failed_pop
        pop     ax
        call    send_byte
        jc      short send_request_failed
        mov     al,cs:current_unit
        call    send_byte
        jc      short send_request_failed
        mov     al,dl
        call    send_byte
        jc      short send_request_failed
        mov     al,dh
        call    send_byte
        jc      short send_request_failed
        mov     al,byte ptr cs:sector_number+2
        call    send_byte
        jc      short send_request_failed
        mov     al,byte ptr cs:sector_number+3
        call    send_byte
        ret
send_request_failed_pop:
        pop     ax
send_request_failed:
        ret
send_request ENDP

receive_status PROC NEAR
        call    receive_byte
        jc      short status_bad
        cmp     al,05ah
        jne     short status_bad
        call    receive_byte
        jc      short status_bad
        cmp     al,0a5h
        jne     short status_bad
        call    receive_byte
        jc      short status_bad
        or      al,al
        jne     short status_bad
        clc
        ret
status_bad:
        stc
        ret
receive_status ENDP

send_sector PROC NEAR
        mov     cx,512
send_sector_loop:
        mov     al,es:[si]
        inc     si
        call    send_byte
        jc      short send_sector_done
        loop    send_sector_loop
        clc
send_sector_done:
        ret
send_sector ENDP

receive_sector PROC NEAR
        mov     cx,512
receive_sector_loop:
        call    receive_byte
        jc      short receive_sector_done
        stosb
        loop    receive_sector_loop
        clc
receive_sector_done:
        ret
receive_sector ENDP

send_byte PROC NEAR
        push    ax
        push    cx
        push    dx
        mov     dx,cs:com_port
        add     dx,5
        mov     cx,0ffffh
client_send_ready:
        in      al,dx
        test    al,20h
        jnz     short client_send_now
        loop    client_send_ready
        pop     dx
        pop     cx
        pop     ax
        stc
        ret
client_send_now:
        pop     dx
        pop     cx
        pop     ax
        push    dx
        mov     dx,cs:com_port
        out     dx,al
        pop     dx
        clc
        ret
send_byte ENDP

receive_byte PROC NEAR
        push    bx
        push    cx
        push    dx
        mov     dx,cs:com_port
        add     dx,5
        mov     bx,32
client_receive_retry:
        mov     cx,0ffffh
client_receive_ready:
        in      al,dx
        test    al,1
        jnz     short client_receive_now
        loop    client_receive_ready
        dec     bx
        jnz     client_receive_retry
        pop     dx
        pop     cx
        pop     bx
        stc
        ret
client_receive_now:
        mov     dx,cs:com_port
        in      al,dx
        clc
        pop     dx
        pop     cx
        pop     bx
        ret
receive_byte ENDP

init_serial PROC NEAR
        mov     dx,cs:com_port
        inc     dx
        xor     al,al
        out     dx,al
        mov     dx,cs:com_port
        add     dx,3
        mov     al,80h
        out     dx,al
        mov     dx,cs:com_port
        mov     al,1
        out     dx,al
        mov     dx,cs:com_port
        inc     dx
        xor     al,al
        out     dx,al
        mov     dx,cs:com_port
        add     dx,3
        mov     al,3
        out     dx,al
        mov     dx,cs:com_port
        add     dx,2
        mov     al,0c7h
        out     dx,al
        mov     dx,cs:com_port
        add     dx,4
        mov     al,0bh
        out     dx,al
        ret
init_serial ENDP

; Parse the tail supplied after DEVICE=... in CONFIG.SYS.
parse_config PROC NEAR
        lds     bx,cs:request_ptr
        lds     si,dword ptr [bx+18]
config_scan:
        lodsb
        or      al,al
        jnz     short config_check_cr
        jmp     config_ok
config_check_cr:
        cmp     al,13
        jne     short config_check_lf
        jmp     config_ok
config_check_lf:
        cmp     al,10
        jne     short config_check_switch
        jmp     config_ok
config_check_switch:
        cmp     al,'/'
        jne     config_scan
        lodsb
        and     al,0dfh
        cmp     al,'C'
        je      short config_com
        cmp     al,'D'
        je      short config_drives
        cmp     al,'N'
        je      short config_noprinter
        jmp     config_bad
config_com:
        lodsw
        and     ax,0dfdfh
        cmp     ax,'MO'
        jne     short config_com_bad
        lodsb
        cmp     al,':'
        jne     short config_com_bad
        lodsb
        sub     al,'0'
        cmp     al,1
        jb      short config_com_bad
        cmp     al,4
        ja      short config_com_bad
        mov     cs:com_number,al
        mov     cs:com_explicit,1
        dec     al
        xor     ah,ah
        shl     ax,1
        mov     bx,ax
        mov     ax,cs:com_bases[bx]
        mov     cs:com_port,ax
        jmp     config_scan
config_com_bad:
        jmp     config_bad
config_drives:
        lodsw
        and     ax,0dfdfh
        cmp     ax,'IR'
        jne     short config_bad
        lodsw
        and     ax,0dfdfh
        cmp     ax,'EV'
        jne     short config_bad
        lodsb
        and     al,0dfh
        cmp     al,'S'
        jne     short config_bad
        lodsb
        cmp     al,':'
        jne     short config_bad
        lodsb
        sub     al,'0'
        cmp     al,1
        jb      short config_bad
        cmp     al,5
        ja      short config_bad
        mov     cs:drive_limit,al
        jmp     config_scan
config_noprinter:
        lodsw
        and     ax,0dfdfh
        cmp     ax,'PO'
        jne     short config_bad
        lodsw
        and     ax,0dfdfh
        cmp     ax,'IR'
        jne     short config_bad
        lodsw
        and     ax,0dfdfh
        cmp     ax,'TN'
        jne     short config_bad
        lodsw
        and     ax,0dfdfh
        cmp     ax,'RE'
        jne     short config_bad
        jmp     config_scan
config_ok:
        clc
        ret
config_bad:
        stc
        ret
parse_config ENDP

install_multiplex PROC NEAR
        mov     ax,352fh
        int     21h
        mov     word ptr cs:old_int2f,bx
        mov     word ptr cs:old_int2f+2,es
        push    ds
        push    cs
        pop     ds
        mov     dx,OFFSET multiplex
        mov     ax,252fh
        int     21h
        pop     ds
        ret
install_multiplex ENDP

multiplex PROC FAR
        cmp     ax,0e902h
        je      short multiplex_disconnect
        cmp     ax,0e901h
        je      short multiplex_reconnect
        cmp     ax,0e900h
        jne     short chain_multiplex
        mov     ax,0ff00h
        xor     bx,bx
        mov     bl,cs:connected
        xor     cx,cx
        mov     cl,cs:unit_count
        xor     dx,dx
        mov     dl,cs:com_number
        iret
multiplex_disconnect:
        mov     cs:connected,0
        mov     ax,0ff00h
        iret
multiplex_reconnect:
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        call    init_serial
        call    connect_server
        mov     ax,0
        jc      short reconnect_result
        mov     ax,0ff00h
reconnect_result:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        iret
chain_multiplex:
        jmp     dword ptr cs:old_int2f
multiplex ENDP

old_int2f       dd 0
transfer_ptr    dd 0
io_command      db 0
io_remaining    dw 0
com_bases       dw 03f8h,02f8h,03e8h,02e8h
resident_end LABEL BYTE

CODE ENDS
        END
