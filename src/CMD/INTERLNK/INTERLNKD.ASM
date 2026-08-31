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
io_unit         db 0
drive_limit     db 5
installed_units db 0
server_units    db 0
first_drive     db 0
unit_map        db 0,1,2,3,4
unit_changed    db 5 dup(0)
remote_drives   db 5 dup(0ffh)

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
        cmp     al,1                   ; offline media/BPB use placeholders
        je      short request_dispatch
        cmp     al,2
        je      short request_dispatch
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
        cmp     cs:no_scan,0
        jne     short init_offline
        call    connect_server
        jnc     short init_install
        cmp     cs:auto_install,0
        jne     init_failed
init_offline:
        call    prepare_offline_units
init_install:
        lds     bx,cs:request_ptr
        mov     al,cs:unit_count
        mov     byte ptr [bx+13],al
        mov     word ptr [bx+14],OFFSET resident_end
        mov     word ptr [bx+16],cs
        mov     word ptr [bx+18],OFFSET bpb_pointers
        mov     word ptr [bx+20],cs
        call    install_multiplex
        cmp     cs:printer_enabled,0
        je      short request_init_done
        call    install_printer
request_init_done:
        lds     bx,cs:request_ptr
        mov     al,[bx+22]
        mov     cs:first_drive,al
        jmp     request_done
init_failed:
        lds     bx,cs:request_ptr
        mov     byte ptr [bx+13],0
        mov     word ptr [bx+14],OFFSET resident_end
        mov     word ptr [bx+16],cs
        mov     word ptr [bx+3],8102h
        jmp     request_exit

prepare_offline_units PROC NEAR
        push    cs
        pop     ds
        push    cs
        pop     es
        mov     al,cs:drive_limit
        mov     cs:unit_count,al
        mov     cs:installed_units,al
        or      al,al
        jz      short offline_bpb_done
        xor     bx,bx
offline_bpb_loop:
        mov     ax,bx
        mov     dx,25
        mul     dx
        mov     di,OFFSET remote_bpbs
        add     di,ax
        mov     ax,bx
        shl     ax,1
        mov     si,ax
        mov     word ptr cs:bpb_pointers[si],di
        mov     si,OFFSET default_bpb
        mov     cx,25
        rep     movsb
        inc     bx
        xor     ax,ax
        mov     al,cs:unit_count
        cmp     bx,ax
        jb      short offline_bpb_loop
offline_bpb_done:
        ret
prepare_offline_units ENDP

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
        mov     cs:server_units,al
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
        xor     bx,bx
init_drive_name_loop:
        call    receive_byte
        jc      init_failed_connect
        mov     cs:remote_drives[bx],al
        inc     bx
        cmp     bl,cs:server_units
        jb      init_drive_name_loop
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
        cmp     al,cs:server_units
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
        xor     ax,ax
        mov     al,[bx+1]
        cmp     al,cs:unit_count
        jae     request_bad_command
        mov     si,ax
        cmp     cs:unit_changed[si],0
        je      short request_media_unchanged
        mov     byte ptr cs:unit_changed[si],0
        mov     byte ptr [bx+14],0ffh
        jmp     request_done
request_media_unchanged:
        mov     byte ptr [bx+14],1
        jmp     request_done
request_bpb:
        xor     ax,ax
        mov     al,[bx+1]
        cmp     al,cs:unit_count
        jae     request_bad_command
        xor     ah,ah
        mov     si,ax
        mov     al,cs:unit_map[si]
        cmp     al,0ffh
        je      request_not_ready
        xor     ah,ah
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
        mov     byte ptr cs:read_retries,3
        mov     byte ptr cs:read_reconnects,1
read_sector_retry:
        call    send_current_request
        jc      short read_sector_failed
        call    receive_status
        jc      short read_sector_failed
        les     di,cs:transfer_ptr
        call    receive_sector
        jnc     short read_sector_complete
read_sector_failed:
        dec     byte ptr cs:read_retries
        jnz     read_sector_retry
        cmp     byte ptr cs:read_reconnects,0
        je      request_io_error
        dec     byte ptr cs:read_reconnects
        mov     cs:connected,0
        call    connect_server
        jc      request_io_error
        mov     byte ptr cs:read_retries,3
        jmp     read_sector_retry
read_sector_complete:
        call    advance_transfer
        dec     word ptr cs:io_remaining
        jnz     read_sector_loop
        jmp     request_done

request_write:
        mov     al,3
        call    prepare_io
        jc      request_io_error
write_sector_loop:
        mov     byte ptr cs:write_retries,4
        mov     byte ptr cs:write_reconnects,1
write_sector_retry:
        call    send_current_request
        jc      short write_sector_failed
        les     si,cs:transfer_ptr
        call    send_sector
        jc      short write_sector_failed
        call    receive_status
        jnc     short write_sector_complete
write_sector_failed:
        dec     byte ptr cs:write_retries
        jnz     write_sector_retry
        cmp     byte ptr cs:write_reconnects,0
        je      request_io_error
        dec     byte ptr cs:write_reconnects
        mov     cs:connected,0
        call    connect_server
        jc      request_io_error
        mov     byte ptr cs:write_retries,4
        jmp     write_sector_retry
write_sector_complete:
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
        xor     ah,ah
        xor     si,si
        mov     si,ax
        cmp     cs:unit_map[si],0ffh
        je      short prepare_bad
        mov     cs:current_unit,al
        mov     cs:io_unit,al
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
        push    bx
        xor     bx,bx
        mov     bl,cs:io_unit
        mov     bl,cs:unit_map[bx]
        mov     bh,cs:current_unit
        mov     cs:current_unit,bl
        mov     al,cs:io_command
        mov     dx,word ptr cs:sector_number
        call    send_request
        mov     cs:current_unit,bh
        pop     bx
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
        mov     cs:packet_checksum,al
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
        add     cs:packet_checksum,al
        call    send_byte
        jc      short send_request_failed
        mov     al,dl
        add     cs:packet_checksum,al
        call    send_byte
        jc      short send_request_failed
        mov     al,dh
        add     cs:packet_checksum,al
        call    send_byte
        jc      short send_request_failed
        mov     al,byte ptr cs:sector_number+2
        add     cs:packet_checksum,al
        call    send_byte
        jc      short send_request_failed
        mov     al,byte ptr cs:sector_number+3
        add     cs:packet_checksum,al
        call    send_byte
        jc      short send_request_failed
        mov     al,cs:packet_checksum
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
        xor     dx,dx
send_sector_loop:
        mov     al,es:[si]
        inc     si
        xor     ah,ah
        add     dx,ax
        call    send_byte
        jc      short send_sector_done
        loop    send_sector_loop
        mov     al,dl
        call    send_byte
        jc      short send_sector_done
        mov     al,dh
        call    send_byte
        jc      short send_sector_done
        clc
send_sector_done:
        ret
send_sector ENDP

receive_sector PROC NEAR
        mov     cx,512
        xor     bx,bx
receive_sector_loop:
        call    receive_byte
        jc      short receive_sector_done
        stosb
        xor     ah,ah
        add     bx,ax
        loop    receive_sector_loop
        call    receive_byte
        jc      short receive_sector_done
        mov     dl,al
        call    receive_byte
        jc      short receive_sector_done
        cmp     dl,bl
        jne     short receive_sector_bad
        cmp     al,bh
        jne     short receive_sector_bad
        clc
        ret
receive_sector_bad:
        stc
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
        push    si
        mov     bx,cs:com_port
        add     bx,5
        mov     ah,0
        int     1ah
        mov     si,dx
client_receive_ready:
        mov     dx,bx
        in      al,dx
        test    al,1
        jnz     short client_receive_now
        mov     ah,0
        int     1ah
        sub     dx,si
        cmp     dx,18
        jb      client_receive_ready
        pop     si
        pop     dx
        pop     cx
        pop     bx
        stc
        ret
client_receive_now:
        mov     dx,cs:com_port
        in      al,dx
        clc
        pop     si
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
        mov     ax,cs:baud_divisor
        out     dx,al
        mov     dx,cs:com_port
        inc     dx
        mov     al,ah
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
        jne     short config_check_noprinter
        jmp     config_drives
config_check_noprinter:
        cmp     al,'N'
        jne     short config_check_baud
        jmp     config_n_option
config_check_baud:
        cmp     al,'B'
        je      short config_baud
        cmp     al,'A'
        je      short config_auto
        cmp     al,'V'
        je      short config_timer_safe
        jmp     config_bad
config_auto:
        lodsb
        and     al,0dfh
        cmp     al,'U'
        jne     short config_auto_bad
        lodsw
        and     ax,0dfdfh
        cmp     ax,'OT'
        jne     short config_auto_bad
        mov     cs:auto_install,1
        jmp     config_scan
config_timer_safe:
        mov     cs:timer_safe_mode,1
        jmp     config_scan
config_auto_bad:
        jmp     config_bad
config_baud:
        lodsb
        and     al,0dfh
        cmp     al,'A'
        jne     short config_baud_bad
        lodsb
        and     al,0dfh
        cmp     al,'U'
        jne     short config_baud_bad
        lodsb
        and     al,0dfh
        cmp     al,'D'
        jne     short config_baud_bad
        lodsb
        cmp     al,':'
        jne     short config_baud_bad
        call    parse_config_baud_rate
        jc      short config_baud_bad
        mov     cs:baud_divisor,bx
        cmp     al,' '
        je      config_scan
        jmp     config_ok
config_baud_bad:
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
        je      short config_drives_ev
        jmp     config_bad
config_drives_ev:
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
config_n_option:
        lodsb
        and     al,0dfh
        cmp     al,'O'
        jne     short config_n_bad
        lodsb
        and     al,0dfh
        cmp     al,'P'
        je      short config_noprinter
        cmp     al,'S'
        je      short config_noscan
config_n_bad:
        jmp     config_bad
config_noprinter:
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
        mov     cs:printer_enabled,0
        jmp     config_scan
config_noscan:
        lodsw
        and     ax,0dfdfh
        cmp     ax,'AC'
        jne     short config_n_bad
        lodsb
        and     al,0dfh
        cmp     al,'N'
        jne     short config_n_bad
        mov     cs:no_scan,1
        jmp     config_scan
config_ok:
        clc
        ret
config_bad:
        stc
        ret
parse_config ENDP

parse_config_baud_rate PROC NEAR
        xor     ax,ax
        xor     dx,dx
config_baud_digit:
        mov     bl,[si]
        inc     si
        cmp     bl,' '
        je      short config_baud_done
        cmp     bl,0
        je      short config_baud_done
        cmp     bl,13
        je      short config_baud_done
        cmp     bl,10
        je      short config_baud_done
        sub     bl,'0'
        cmp     bl,9
        ja      short config_baud_rate_bad
        xor     bh,bh
        mov     di,dx
        push    bx
        mov     bx,ax
        shl     ax,1
        rcl     dx,1
        shl     bx,1
        rcl     di,1
        shl     bx,1
        rcl     di,1
        shl     bx,1
        rcl     di,1
        add     ax,bx
        adc     dx,di
        pop     bx
        add     ax,bx
        adc     dx,0
        jmp     config_baud_digit
config_baud_done:
        mov     cs:baud_terminator,bl
        cmp     dx,0
        jne     short config_baud_115200
        cmp     ax,9600
        jne     short config_baud_19200
        mov     bx,12
        jmp     short config_baud_rate_good
config_baud_19200:
        cmp     ax,19200
        jne     short config_baud_38400
        mov     bx,6
        jmp     short config_baud_rate_good
config_baud_38400:
        cmp     ax,38400
        jne     short config_baud_57600
        mov     bx,3
        jmp     short config_baud_rate_good
config_baud_57600:
        cmp     ax,57600
        jne     short config_baud_rate_bad
        mov     bx,2
        jmp     short config_baud_rate_good
config_baud_115200:
        cmp     dx,1
        jne     short config_baud_rate_bad
        cmp     ax,0c200h
        jne     short config_baud_rate_bad
        mov     bx,1
config_baud_rate_good:
        mov     al,cs:baud_terminator
        clc
        ret
config_baud_rate_bad:
        stc
        ret
parse_config_baud_rate ENDP

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

install_printer PROC NEAR
        mov     ax,3517h
        int     21h
        mov     word ptr cs:old_int17,bx
        mov     word ptr cs:old_int17+2,es
        push    ds
        push    cs
        pop     ds
        mov     dx,OFFSET printer_handler
        mov     ax,2517h
        int     21h
        mov     ax,3521h
        int     21h
        mov     word ptr cs:old_int21,bx
        mov     word ptr cs:old_int21+2,es
        mov     dx,OFFSET dos_printer_handler
        mov     ax,2521h
        int     21h
        pop     ds
        ret
install_printer ENDP

; AL is the character and DL is the zero-based printer number. The caller
; has already established a live connection and preserved its registers.
send_printer_connected PROC NEAR
        mov     cs:printer_byte,al
        mov     cs:current_unit,dl
        xor     dx,dx
        mov     dl,cs:printer_byte
        mov     word ptr cs:sector_number+2,0
        mov     al,4
        call    send_request
        jc      short printer_send_failed
        call    receive_status
        jc      short printer_send_failed
        call    receive_byte
        ret
printer_send_failed:
        mov     cs:connected,0
        stc
        ret
send_printer_connected ENDP

identify_printer_name PROC NEAR
        mov     si,dx
        mov     di,si
        cmp     byte ptr [si+1],':'
        jne     short printer_name_scan
        lea     di,[si+2]
printer_name_scan:
        mov     al,[si]
        or      al,al
        jz      short printer_name_compare
        cmp     al,5ch
        je      short printer_name_new_base
        cmp     al,'/'
        jne     short printer_name_next
printer_name_new_base:
        lea     di,[si+1]
printer_name_next:
        inc     si
        jmp     printer_name_scan
printer_name_compare:
        mov     al,[di]
        and     al,0dfh
        cmp     al,'P'
        jne     short printer_name_not_prn
        mov     al,[di+1]
        and     al,0dfh
        cmp     al,'R'
        jne     short printer_name_lpt
        mov     al,[di+2]
        and     al,0dfh
        cmp     al,'N'
        jne     short printer_name_lpt
        mov     al,[di+3]
        call    printer_name_end
        jc      short printer_name_none
        mov     al,1
        ret
printer_name_not_prn:
        cmp     al,'L'
        jne     short printer_name_none
printer_name_lpt:
        mov     al,[di]
        and     al,0dfh
        cmp     al,'L'
        jne     short printer_name_none
        mov     al,[di+1]
        and     al,0dfh
        cmp     al,'P'
        jne     short printer_name_none
        mov     al,[di+2]
        and     al,0dfh
        cmp     al,'T'
        jne     short printer_name_none
        mov     al,[di+3]
        cmp     al,'1'
        jb      short printer_name_none
        cmp     al,'3'
        ja      short printer_name_none
        mov     ah,al
        mov     al,[di+4]
        call    printer_name_end
        jc      short printer_name_none
        mov     al,ah
        sub     al,'0'                 ; 1..3 encodes unit+1
        ret
printer_name_none:
        xor     al,al
        ret
identify_printer_name ENDP

printer_name_end PROC NEAR
        or      al,al
        jz      short printer_name_valid_end
        cmp     al,':'
        je      short printer_name_valid_end
        cmp     al,'.'
        je      short printer_name_valid_end
        stc
        ret
printer_name_valid_end:
        clc
        ret
printer_name_end ENDP

dos_printer_handler PROC FAR
        cmp     cs:printer_enabled,0
        je      chain_dos_printer
        cmp     ah,3dh
        je      dos_printer_open
        cmp     ah,3eh
        je      dos_printer_close
        cmp     ah,45h
        je      dos_printer_duplicate
        cmp     ah,46h
        je      dos_printer_force_duplicate
        cmp     ah,40h
        jne     chain_dos_printer
        cmp     cs:connected,0
        je      chain_dos_printer
        cmp     bx,256
        jae     chain_dos_printer
        mov     al,cs:printer_handles[bx]
        cmp     al,0ffh
        je      chain_dos_printer
        mov     cs:printer_write_unit,al
        jmp     short dos_printer_write
dos_printer_write:
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        mov     cs:printer_count,cx
        mov     si,dx
dos_printer_loop:
        jcxz    short dos_printer_success
        mov     al,[si]
        xor     dx,dx
        mov     dl,cs:printer_write_unit
        call    send_printer_connected
        jc      short dos_printer_error
        inc     si
        loop    dos_printer_loop
dos_printer_success:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        mov     ax,cs:printer_count
        push    bp
        mov     bp,sp
        and     word ptr ss:[bp+6],0fffeh
        pop     bp
        iret
dos_printer_error:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        mov     ax,29                   ; write fault
        push    bp
        mov     bp,sp
        or      word ptr ss:[bp+6],1
        pop     bp
        iret
dos_printer_open:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    es
        call    identify_printer_name
        mov     cs:pending_printer_unit,al
        pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        cmp     cs:pending_printer_unit,0
        je      chain_dos_printer
        push    bx
        pushf
        call    dword ptr cs:old_int21
        jc      short dos_printer_open_error
        cmp     ax,256
        jae     short dos_printer_open_success
        push    ax
        mov     bx,ax
        mov     al,cs:pending_printer_unit
        dec     al
        mov     cs:printer_handles[bx],al
        pop     ax
dos_printer_open_success:
        pop     bx
        jmp     dos_printer_clear_carry
dos_printer_open_error:
        pop     bx
        jmp     dos_printer_set_carry
dos_printer_close:
        cmp     bx,256
        jae     chain_dos_printer
        cmp     byte ptr cs:printer_handles[bx],0ffh
        je      chain_dos_printer
        push    bx
        pushf
        call    dword ptr cs:old_int21
        jc      short dos_printer_close_error
        pop     bx
        mov     byte ptr cs:printer_handles[bx],0ffh
        jmp     dos_printer_clear_carry
dos_printer_close_error:
        pop     bx
        jmp     dos_printer_set_carry
dos_printer_duplicate:
        call    printer_unit_for_handle
        or      al,al
        jz      chain_dos_printer
        mov     cs:pending_printer_unit,al
        push    bx
        pushf
        call    dword ptr cs:old_int21
        jc      short dos_printer_duplicate_error
        cmp     ax,256
        jae     short dos_printer_duplicate_success
        push    ax
        mov     bx,ax
        mov     al,cs:pending_printer_unit
        dec     al
        mov     cs:printer_handles[bx],al
        pop     ax
dos_printer_duplicate_success:
        pop     bx
        jmp     short dos_printer_clear_carry
dos_printer_duplicate_error:
        pop     bx
        jmp     short dos_printer_set_carry
dos_printer_force_duplicate:
        call    printer_unit_for_handle
        mov     cs:pending_printer_unit,al
        or      al,al
        jnz     short dos_printer_force_call
        cmp     cx,256
        jae     chain_dos_printer
        push    bx
        mov     bx,cx
        cmp     byte ptr cs:printer_handles[bx],0ffh
        pop     bx
        je      chain_dos_printer
dos_printer_force_call:
        push    ax
        push    bx
        pushf
        call    dword ptr cs:old_int21
        jc      short dos_printer_force_error
        cmp     cx,256
        jae     short dos_printer_force_success
        mov     bx,cx
        mov     al,cs:pending_printer_unit
        or      al,al
        jnz     short dos_printer_force_decrement
        mov     al,0ffh
        jmp     short dos_printer_force_store
dos_printer_force_decrement:
        dec     al
dos_printer_force_store:
        mov     cs:printer_handles[bx],al
dos_printer_force_success:
        pop     bx
        pop     ax
        jmp     short dos_printer_clear_carry
dos_printer_force_error:
        pop     bx
        pop     ax
dos_printer_set_carry:
        push    bp
        mov     bp,sp
        or      word ptr ss:[bp+6],1
        pop     bp
        iret
dos_printer_clear_carry:
        push    bp
        mov     bp,sp
        and     word ptr ss:[bp+6],0fffeh
        pop     bp
        iret
chain_dos_printer:
        jmp     dword ptr cs:old_int21
dos_printer_handler ENDP

; Return zero for an ordinary handle or unit+1 for a redirected printer.
printer_unit_for_handle PROC NEAR
        cmp     bx,256
        jae     short printer_unit_none
        mov     al,cs:printer_handles[bx]
        cmp     al,0ffh
        je      short printer_unit_none
        inc     al
        ret
printer_unit_none:
        xor     al,al
        ret
printer_unit_for_handle ENDP

printer_handler PROC FAR
        cmp     ah,0
        jne     short chain_printer
        cmp     dl,2
        ja      short chain_printer
        cmp     cs:connected,0
        je      short chain_printer
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        call    send_printer_connected
        jc      short printer_failed
        mov     cs:printer_status,al
        jmp     short printer_return
printer_failed:
        mov     cs:connected,0
        mov     cs:printer_status,1
printer_return:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        mov     ah,cs:printer_status
        iret
chain_printer:
        jmp     dword ptr cs:old_int17
printer_handler ENDP

multiplex PROC FAR
        cmp     ax,0e904h
        je      multiplex_query_map
        cmp     ax,0e903h
        je      multiplex_set_map
        cmp     ax,0e902h
        je      multiplex_disconnect
        cmp     ax,0e901h
        je      multiplex_reconnect
        cmp     ax,0e900h
        jne     chain_multiplex
        mov     ax,0ff00h
        xor     bx,bx
        mov     bl,cs:connected
        xor     cx,cx
        mov     cl,cs:unit_count
        xor     dx,dx
        mov     dl,cs:com_number
        xor     si,si
        cmp     cs:printer_enabled,0
        je      short multiplex_status_done
        inc     si
multiplex_status_done:
        iret
multiplex_query_map:
        cmp     bl,cs:unit_count
        jae     multiplex_map_error
        xor     bh,bh
        mov     dl,cs:first_drive
        add     dl,bl
        mov     al,cs:unit_map[bx]
        mov     dh,0ffh
        cmp     al,0ffh
        je      short multiplex_map_query_done
        xor     bx,bx
        mov     bl,al
        mov     dh,cs:remote_drives[bx]
multiplex_map_query_done:
        mov     ax,0ff00h
        iret
multiplex_set_map:
        cmp     bl,cs:first_drive
        jb      short multiplex_map_error
        sub     bl,cs:first_drive
        cmp     bl,cs:unit_count
        jae     short multiplex_map_error
        cmp     bh,0ffh
        je      short multiplex_map_store
        push    bx
        xor     si,si
multiplex_map_find:
        cmp     bh,cs:remote_drives[si]
        je      short multiplex_map_found
        inc     si
        xor     ax,ax
        mov     al,cs:unit_count
        cmp     si,ax
        jb      multiplex_map_find
        pop     bx
        jmp     short multiplex_map_error
multiplex_map_found:
        pop     ax
        mov     bl,al
        mov     ax,si
        mov     bh,al
multiplex_map_store:
        mov     dl,bh
        xor     bh,bh
        mov     cs:unit_map[bx],dl
        mov     byte ptr cs:unit_changed[bx],1
        cmp     dl,0ffh
        je      short multiplex_map_success
        mov     al,dl
        xor     ah,ah
        mov     si,ax
        mov     ax,25
        mul     si
        add     ax,OFFSET remote_bpbs
        shl     bx,1
        mov     cs:bpb_pointers[bx],ax
multiplex_map_success:
        mov     ax,0ff00h
        iret
multiplex_map_error:
        xor     ax,ax
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
old_int17       dd 0
old_int21       dd 0
transfer_ptr    dd 0
io_command      db 0
io_remaining    dw 0
packet_checksum db 0
read_retries    db 0
write_retries   db 0
read_reconnects db 0
write_reconnects db 0
baud_divisor    dw 1
baud_terminator db 0
auto_install    db 0
no_scan         db 0
timer_safe_mode db 0
printer_enabled db 1
printer_byte    db 0
printer_status  db 0
printer_count   dw 0
printer_write_unit db 0
pending_printer_unit db 0
printer_handles db 4 dup(0ffh),0,251 dup(0ffh)
default_bpb     dw 512
                db 1
                dw 1
                db 2
                dw 224,2880
                db 0f0h
                dw 9,18,2
                dd 0,0
com_bases       dw 03f8h,02f8h,03e8h,02e8h
resident_end LABEL BYTE

CODE ENDS
        END
