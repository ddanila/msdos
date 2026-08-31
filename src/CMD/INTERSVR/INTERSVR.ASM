; Serial and LapLink-style parallel Interlnk server. Exports up to five DOS
; volumes as remote block devices; INTERLNK.EXE performs ordinary DOS
; filesystem work through sector requests.

CODE SEGMENT PUBLIC
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE

start:
        cld
        push    cs
        pop     ds
        mov     ah,62h
        int     21h
        mov     es,bx
        cmp     byte ptr es:[80h],3
        jne     server_parse
        cmp     byte ptr es:[81h],' '
        jne     server_parse
        cmp     word ptr es:[82h],3f2fh ; '/?'
        je      server_help
server_parse:
        call    parse_tail
        jc      syntax_error
        push    cs
        pop     es
        cmp     cs:rcopy_mode,0
        je      short server_normal
        call    remote_copy
        mov     ah,4ch
        int     21h
server_normal:
        call    init_serial            ; 115200 baud, 8-N-1
        mov     dx,OFFSET banner
        mov     ah,9
        int     21h
        xor     bx,bx
banner_drive_loop:
        mov     dl,cs:server_drives[bx]
        add     dl,'A'
        mov     ah,2
        int     21h
        inc     bx
        cmp     bl,cs:drive_count
        jae     short banner_done
        mov     dl,' '
        mov     ah,2
        int     21h
        jmp     banner_drive_loop
banner_done:
        mov     dx,OFFSET banner_suffix
        mov     ah,9
        int     21h
server_loop:
        mov     ah,1
        int     16h
        jz      short server_receive
        cmp     ah,3bh                 ; F1: live connection statistics
        jne     short server_check_shutdown
        mov     ah,0
        int     16h
        call    display_status
        jmp     server_loop
server_check_shutdown:
        mov     ah,2
        int     16h
        test    al,8                   ; Alt held?
        jz      short server_receive
        mov     ah,1
        int     16h
        jz      short server_receive
        cmp     ah,3eh                 ; F4 scan code
        je      short server_shutdown
        cmp     ah,6bh                 ; enhanced BIOS Alt+F4 code
        jne     short server_receive
server_shutdown:
        mov     ah,0
        int     16h                    ; consume the shutdown key
        mov     ax,4c00h
        int     21h
server_receive:
        call    receive_byte
        jnc     short server_have_byte
        call    advance_scan_port
        jmp     server_loop
server_have_byte:
        cmp     al,0a5h
        jne     server_loop
server_sync_second:
        call    receive_byte
        jc      server_loop
        cmp     al,0a5h
        je      server_sync_second     ; retain a repeated sync-start byte
        cmp     al,05ah
        jne     server_loop
        call    receive_byte
        jc      server_loop
        mov     cs:request_command,al
        mov     cs:request_checksum,al
        call    receive_byte
        jc      server_loop
        mov     cs:request_unit,al
        add     cs:request_checksum,al
        call    receive_sector_number
        jc      server_loop
        call    receive_byte
        jc      server_loop
        cmp     al,cs:request_checksum
        jne     protocol_failed
        mov     al,cs:request_command
        cmp     al,0
        je      discovery_request
        cmp     al,1
        je      geometry_request
        cmp     al,2
        je      read_request
        cmp     al,3
        je      write_request
        cmp     al,4
        je      printer_request
        mov     al,1
        call    send_status
        jmp     server_loop

discovery_request:
        inc     cs:discovery_count
        mov     cs:connected,1
        xor     al,al
        call    send_status
        mov     al,cs:drive_count
        call    send_byte
        xor     bx,bx
discovery_drive_loop:
        mov     al,cs:server_drives[bx]
        call    send_byte
        inc     bx
        cmp     bl,cs:drive_count
        jb      discovery_drive_loop
        jmp     server_loop

geometry_request:
        inc     cs:geometry_count
        call    read_boot_sector
        jc      request_failed
        xor     al,al
        call    send_status
        mov     si,OFFSET sector_buffer
        call    send_sector
        jmp     server_loop

read_request:
        inc     cs:read_count
        call    absolute_read
        jc      request_failed
        xor     al,al
        call    send_status
        mov     si,OFFSET sector_buffer
        call    send_sector
        jmp     server_loop

write_request:
        inc     cs:write_count
        mov     di,OFFSET sector_buffer
        call    receive_sector
        jc      request_failed
        call    absolute_write
        jc      request_failed
        xor     al,al
        call    send_status
        jmp     server_loop

printer_request:
        inc     cs:printer_count
        cmp     cs:request_unit,2
        ja      request_failed
        mov     al,byte ptr cs:sector_number
        xor     dx,dx
        mov     dl,cs:request_unit
        mov     ah,0
        int     17h
        mov     cs:printer_status,ah
        xor     al,al
        call    send_status
        mov     al,cs:printer_status
        call    send_byte
        jmp     server_loop

request_failed:
        inc     cs:error_count
        mov     al,1
        call    send_status
        jmp     server_loop

protocol_failed:
        inc     cs:error_count
        jmp     server_loop

advance_scan_port PROC NEAR
        cmp     cs:scan_ports,0
        je      short advance_scan_done
        inc     cs:scan_index
        mov     al,cs:scan_index
        cmp     cs:transport_type,0
        jne     short advance_scan_lpt
        cmp     al,4
        jb      short advance_scan_load_com
        mov     cs:scan_index,0
advance_scan_load_com:
        xor     ah,ah
        shl     ax,1
        mov     bx,ax
        mov     ax,cs:com_bases[bx]
        mov     cs:com_port,ax
        mov     al,cs:scan_index
        inc     al
        mov     cs:com_number,al
        call    init_serial
        ret
advance_scan_lpt:
        cmp     al,3
        jb      short advance_scan_load_lpt
        mov     cs:scan_index,0
advance_scan_load_lpt:
        xor     ah,ah
        shl     ax,1
        mov     bx,ax
        mov     ax,cs:lpt_bases[bx]
        mov     cs:lpt_port,ax
        mov     al,cs:scan_index
        inc     al
        mov     cs:com_number,al
        call    init_serial
advance_scan_done:
        ret
advance_scan_port ENDP

display_status PROC NEAR
        mov     dx,OFFSET status_heading
        mov     ah,9
        int     21h
        cmp     cs:connected,0
        je      short display_status_offline
        mov     dx,OFFSET status_connected
        jmp     short display_status_connection
display_status_offline:
        mov     dx,OFFSET status_waiting
display_status_connection:
        mov     ah,9
        int     21h
        mov     dx,OFFSET status_discovery
        mov     ax,cs:discovery_count
        call    display_counter
        mov     dx,OFFSET status_geometry
        mov     ax,cs:geometry_count
        call    display_counter
        mov     dx,OFFSET status_reads
        mov     ax,cs:read_count
        call    display_counter
        mov     dx,OFFSET status_writes
        mov     ax,cs:write_count
        call    display_counter
        mov     dx,OFFSET status_printer
        mov     ax,cs:printer_count
        call    display_counter
        mov     dx,OFFSET status_errors
        mov     ax,cs:error_count
        call    display_counter
        ret
display_status ENDP

display_counter PROC NEAR
        push    ax
        mov     ah,9
        int     21h
        pop     ax
        call    display_decimal
        mov     dx,OFFSET newline
        mov     ah,9
        int     21h
        ret
display_counter ENDP

display_decimal PROC NEAR
        push    ax
        push    bx
        push    cx
        push    dx
        xor     cx,cx
        mov     bx,10
display_decimal_split:
        xor     dx,dx
        div     bx
        push    dx
        inc     cx
        or      ax,ax
        jnz     display_decimal_split
display_decimal_emit:
        pop     dx
        add     dl,'0'
        mov     ah,2
        int     21h
        loop    display_decimal_emit
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
display_decimal ENDP

; Request sector is little-endian 32-bit.  DOS 6 FAT volumes are bounded by
; the legacy absolute-I/O interface here, so reject a nonzero high word.
receive_sector_number PROC NEAR
        call    receive_byte
        jc      short receive_sector_failed
        mov     byte ptr cs:sector_number,al
        add     cs:request_checksum,al
        call    receive_byte
        jc      short receive_sector_failed
        mov     byte ptr cs:sector_number+1,al
        add     cs:request_checksum,al
        call    receive_byte
        jc      short receive_sector_failed
        mov     byte ptr cs:sector_number+2,al
        add     cs:request_checksum,al
        call    receive_byte
        jc      short receive_sector_failed
        mov     byte ptr cs:sector_number+3,al
        add     cs:request_checksum,al
        clc
receive_sector_failed:
        ret
receive_sector_number ENDP

read_boot_sector PROC NEAR
        mov     word ptr cs:sector_number,0
        mov     word ptr cs:sector_number+2,0
        jmp     short absolute_read
read_boot_sector ENDP

absolute_read PROC NEAR
        cmp     word ptr cs:sector_number+2,0
        jne     short absolute_bad
        push    ds
        push    cs
        pop     ds
        call    select_drive
        jc      short absolute_read_bad_pushed
        cmp     al,2
        jb      short absolute_read_floppy
        mov     bx,OFFSET sector_buffer
        mov     cx,1
        mov     dx,word ptr cs:sector_number
        int     25h
        pop     ax                      ; discard flags left by INT 25h
        pop     ds
        jc      short absolute_bad
        clc
        ret
absolute_read_floppy:
        pop     ds
        mov     ah,2
        call    bios_floppy_io
        ret
absolute_read_bad_pushed:
        pop     ds
absolute_bad:
        stc
        ret
absolute_read ENDP

absolute_write PROC NEAR
        cmp     word ptr cs:sector_number+2,0
        jne     short absolute_bad_write
        push    ds
        push    cs
        pop     ds
        call    select_drive
        jc      short absolute_write_bad_pushed
        cmp     al,2
        jb      short absolute_write_floppy
        mov     bx,OFFSET sector_buffer
        mov     cx,1
        mov     dx,word ptr cs:sector_number
        int     26h
        pop     ax
        pop     ds
        jc      short absolute_bad_write
        clc
        ret
absolute_write_floppy:
        pop     ds
        mov     ah,3
        call    bios_floppy_io
        ret
absolute_write_bad_pushed:
        pop     ds
absolute_bad_write:
        stc
        ret
absolute_write ENDP

; Read or write one physical floppy sector.  INT 25h can alias B: to A: on
; systems configured for single-drive swapping, so use the BIOS drive number
; for floppy exports.  AL is the zero-based drive and AH is 2 (read) or 3
; (write).
bios_floppy_io PROC NEAR
        mov     cs:bios_drive,al
        mov     cs:bios_command,ah
        mov     dl,al
        mov     ah,8
        int     13h
        jc      short bios_floppy_done
        inc     dh
        mov     cs:bios_heads,dh
        and     cl,3fh
        xor     bx,bx
        mov     bl,cl
        mov     ax,word ptr cs:sector_number
        xor     dx,dx
        div     bx
        inc     dl
        mov     cs:bios_sector,dl
        xor     bx,bx
        mov     bl,cs:bios_heads
        xor     dx,dx
        div     bx
        mov     ch,al
        mov     cl,cs:bios_sector
        mov     dh,dl
        mov     dl,cs:bios_drive
        push    cs
        pop     es
        mov     bx,OFFSET sector_buffer
        xor     ah,ah
        int     13h
        mov     ah,cs:bios_command
        mov     al,1
        int     13h
bios_floppy_done:
        ret
bios_floppy_io ENDP

select_drive PROC NEAR
        xor     bx,bx
        mov     bl,cs:request_unit
        cmp     bl,cs:drive_count
        jae     short select_drive_bad
        mov     al,cs:server_drives[bx]
        clc
        ret
select_drive_bad:
        stc
        ret
select_drive ENDP

send_status PROC NEAR
        push    ax
        mov     al,05ah
        call    send_byte
        mov     al,0a5h
        call    send_byte
        pop     ax
        call    send_byte
        ret
send_status ENDP

send_sector PROC NEAR
        mov     cx,512
        xor     dx,dx
send_sector_loop:
        lodsb
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
        cmp     cs:transport_type,0
        je      short send_byte_serial
        jmp     send_byte_parallel
send_byte_serial:
        push    ax
        push    cx
        push    dx
        mov     dx,cs:com_port
        add     dx,5
        mov     cx,0ffffh
send_ready:
        in      al,dx
        test    al,20h
        jnz     short send_now
        loop    send_ready
        pop     dx
        pop     cx
        pop     ax
        stc
        ret
send_now:
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

; Remote copy also runs at the retail 2400-baud default, so use a real-time
; deadline instead of the normal transport's deliberately tight retry loop.
rcopy_send_byte PROC NEAR
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        mov     bx,cs:com_port
        add     bx,5
        mov     ah,0
        int     1ah
        mov     si,dx
rcopy_send_ready:
        mov     dx,bx
        in      al,dx
        test    al,20h
        jnz     short rcopy_send_now
        mov     ah,0
        int     1ah
        sub     dx,si
        cmp     dx,18
        jb      rcopy_send_ready
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        stc
        ret
rcopy_send_now:
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        push    dx
        mov     dx,cs:com_port
        out     dx,al
        pop     dx
        clc
        ret
rcopy_send_byte ENDP

send_byte_parallel PROC NEAR
        push    ax
        push    bx
        push    cx
        mov     bl,al
        and     al,0fh
        call    send_parallel_nibble
        jc      short server_send_parallel_done
        mov     al,bl
        mov     cl,4
        shr     al,cl
        call    send_parallel_nibble
server_send_parallel_done:
        pop     cx
        pop     bx
        pop     ax
        ret
send_byte_parallel ENDP

send_parallel_nibble PROC NEAR
        push    ax
        push    bx
        push    dx
        push    si
        and     al,0fh
        mov     bl,al
        mov     al,cs:lpt_shadow
        xor     al,10h
        and     al,10h
        or      al,bl
        mov     cs:lpt_shadow,al
        mov     dx,cs:lpt_port
        out     dx,al
        mov     ah,0
        int     1ah
        mov     si,dx
server_parallel_send_wait:
        mov     dx,cs:lpt_port
        inc     dx
        in      al,dx
        and     al,80h
        test    byte ptr cs:lpt_shadow,10h
        jnz     short server_parallel_send_expect_low
        cmp     al,80h
        je      short server_parallel_send_ok
        jmp     short server_parallel_send_timeout
server_parallel_send_expect_low:
        or      al,al
        jz      short server_parallel_send_ok
server_parallel_send_timeout:
        mov     ah,0
        int     1ah
        sub     dx,si
        cmp     dx,18
        jb      server_parallel_send_wait
        stc
        jmp     short server_parallel_send_return
server_parallel_send_ok:
        clc
server_parallel_send_return:
        pop     si
        pop     dx
        pop     bx
        pop     ax
        ret
send_parallel_nibble ENDP

receive_byte PROC NEAR
        cmp     cs:transport_type,0
        je      short receive_byte_serial
        jmp     receive_byte_parallel
receive_byte_serial:
        push    bx
        push    cx
        push    dx
        push    si
        mov     bx,cs:com_port
        add     bx,5
        mov     ah,0
        int     1ah
        mov     si,dx
receive_ready:
        mov     dx,bx
        in      al,dx
        test    al,1
        jnz     short receive_now
        mov     ah,0
        int     1ah
        sub     dx,si
        cmp     dx,18
        jb      receive_ready
        pop     si
        pop     dx
        pop     cx
        pop     bx
        stc
        ret
receive_now:
        mov     dx,cs:com_port
        in      al,dx
        clc
        pop     si
        pop     dx
        pop     cx
        pop     bx
        ret
receive_byte ENDP

receive_byte_parallel PROC NEAR
        push    bx
        push    cx
        call    receive_parallel_nibble
        jc      short server_receive_parallel_done
        mov     bl,al
        call    receive_parallel_nibble
        jc      short server_receive_parallel_done
        mov     cl,4
        shl     al,cl
        or      al,bl
        clc
server_receive_parallel_done:
        pop     cx
        pop     bx
        ret
receive_byte_parallel ENDP

receive_parallel_nibble PROC NEAR
        push    bx
        push    dx
        push    si
        mov     ah,0
        int     1ah
        mov     si,dx
server_parallel_receive_wait:
        mov     dx,cs:lpt_port
        inc     dx
        in      al,dx
        mov     bl,al
        and     al,80h
        test    byte ptr cs:lpt_shadow,10h
        jnz     short server_parallel_receive_expect_high
        or      al,al
        jz      short server_parallel_receive_ready
        jmp     short server_parallel_receive_timeout
server_parallel_receive_expect_high:
        cmp     al,80h
        je      short server_parallel_receive_ready
server_parallel_receive_timeout:
        mov     ah,0
        int     1ah
        sub     dx,si
        cmp     dx,18
        jb      server_parallel_receive_wait
        stc
        jmp     short server_parallel_receive_return
server_parallel_receive_ready:
        mov     al,cs:lpt_shadow
        xor     al,10h
        and     al,10h
        mov     cs:lpt_shadow,al
        mov     dx,cs:lpt_port
        out     dx,al
        mov     al,bl
        mov     cl,3
        shr     al,cl
        and     al,0fh
        clc
server_parallel_receive_return:
        pop     si
        pop     dx
        pop     bx
        ret
receive_parallel_nibble ENDP

init_serial PROC NEAR
        cmp     cs:transport_type,0
        je      short server_init_uart
        mov     cs:lpt_shadow,0
        mov     dx,cs:lpt_port
        xor     al,al
        out     dx,al
        ret
server_init_uart:
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

; Reproduce the retail remote-copy workflow.  The remote machine has issued
; MODE and CTTY, so its command interpreter is listening on the selected COM
; port. Install a temporary receiver, then stream the two Interlnk executables
; with sizes and additive checksums.
remote_copy PROC NEAR
        call    rcopy_preflight
        jc      rcopy_missing
        mov     dx,OFFSET rcopy_intro
        mov     ah,9
        int     21h
        call    init_serial
        call    rcopy_pause
        mov     al,cs:com_number
        or      al,al
        jnz     short rcopy_have_number
        mov     al,1
rcopy_have_number:
        add     al,'0'
        mov     cs:rcopy_run_port,al
        call    rcopy_install_fxb
        jc      rcopy_link_error
        call    rcopy_pause
        mov     si,OFFSET rcopy_run_command
        mov     cx,rcopy_run_command_end-rcopy_run_command
        call    rcopy_send_buffer
        jc      rcopy_link_error
        call    rcopy_pause
        call    rcopy_drain_input
        mov     si,OFFSET rcopy_magic
        mov     cx,5
        call    rcopy_send_buffer
        jc      rcopy_link_error
        mov     dx,OFFSET interlnk_name
        mov     si,OFFSET interlnk_header_name
        call    rcopy_send_file
        jc      rcopy_link_error
        mov     dx,OFFSET intersvr_name
        mov     si,OFFSET intersvr_header_name
        call    rcopy_send_file
        jc      rcopy_link_error
        mov     bl,04h
        call    rcopy_wait_control
        jc      rcopy_link_error
        call    rcopy_pause
        call    rcopy_pause
        call    rcopy_pause
        call    rcopy_pause
        mov     si,OFFSET rcopy_cleanup_command
        mov     cx,rcopy_cleanup_command_end-rcopy_cleanup_command
        call    rcopy_send_buffer
        mov     dx,OFFSET rcopy_complete
        mov     ah,9
        int     21h
        xor     al,al
        ret
rcopy_missing:
        mov     dx,OFFSET rcopy_missing_files
        jmp     short rcopy_report_error
rcopy_link_error:
        mov     dx,OFFSET rcopy_failed
rcopy_report_error:
        mov     ah,9
        int     21h
        mov     al,1
        ret
remote_copy ENDP

; Build FXB.COM through DEBUG commands on the remote console.  This avoids
; relying on device-EOF behavior while retaining the documented MODE/CTTY
; setup and temporary-receiver workflow.
rcopy_install_fxb PROC NEAR
        mov     si,OFFSET rcopy_debug_command
        mov     cx,rcopy_debug_command_end-rcopy_debug_command
        call    rcopy_send_buffer
        jc      rcopy_install_done
        call    rcopy_pause
        mov     si,OFFSET rcopy_name_command
        mov     cx,rcopy_name_command_end-rcopy_name_command
        call    rcopy_send_buffer
        jc      rcopy_install_done
        mov     si,OFFSET fxb_image
        mov     dx,100h
        mov     bp,fxb_image_end-fxb_image
rcopy_debug_line:
        or      bp,bp
        jz      short rcopy_debug_finish
        push    si
        mov     si,OFFSET rcopy_enter_prefix
        mov     cx,2
        call    rcopy_send_buffer
        pop     si
        jc      short rcopy_install_done
        mov     ax,dx
        call    rcopy_send_hex_word
        jc      short rcopy_install_done
        mov     cx,16
        cmp     bp,cx
        jae     short rcopy_debug_have_count
        mov     cx,bp
rcopy_debug_have_count:
        sub     bp,cx
        add     dx,cx
rcopy_debug_byte:
        mov     al,' '
        call    rcopy_send_byte
        jc      short rcopy_install_done
        lodsb
        call    rcopy_send_hex_byte
        jc      short rcopy_install_done
        loop    rcopy_debug_byte
        mov     al,13
        call    rcopy_send_byte
        jc      short rcopy_install_done
        jmp     rcopy_debug_line
rcopy_debug_finish:
        mov     si,OFFSET rcopy_cx_command
        mov     cx,rcopy_cx_command_end-rcopy_cx_command
        call    rcopy_send_buffer
        jc      short rcopy_install_done
        mov     ax,fxb_image_end-fxb_image
        call    rcopy_send_hex_word
        jc      short rcopy_install_done
        mov     si,OFFSET rcopy_write_command
        mov     cx,rcopy_write_command_end-rcopy_write_command
        call    rcopy_send_buffer
        jc      short rcopy_install_done
        call    rcopy_pause
        clc
rcopy_install_done:
        ret
rcopy_install_fxb ENDP

rcopy_send_hex_word PROC NEAR
        push    ax
        mov     al,ah
        call    rcopy_send_hex_byte
        pop     ax
        jc      short rcopy_send_hex_word_done
        call    rcopy_send_hex_byte
rcopy_send_hex_word_done:
        ret
rcopy_send_hex_word ENDP

rcopy_send_hex_byte PROC NEAR
        push    ax
        push    cx
        mov     ah,al
        mov     cl,4
        shr     al,cl
        call    rcopy_send_hex_nibble
        pop     cx
        pop     ax
        jc      short rcopy_send_hex_byte_done
        and     al,0fh
        call    rcopy_send_hex_nibble
rcopy_send_hex_byte_done:
        ret
rcopy_send_hex_byte ENDP

rcopy_send_hex_nibble PROC NEAR
        and     al,0fh
        add     al,'0'
        cmp     al,'9'
        jbe     short rcopy_send_hex_nibble_emit
        add     al,'A'-'9'-1
rcopy_send_hex_nibble_emit:
        call    rcopy_send_byte
        ret
rcopy_send_hex_nibble ENDP

rcopy_preflight PROC NEAR
        mov     dx,OFFSET interlnk_name
        call    rcopy_check_file
        jc      short rcopy_preflight_done
        mov     dx,OFFSET intersvr_name
        call    rcopy_check_file
rcopy_preflight_done:
        ret
rcopy_preflight ENDP

rcopy_check_file PROC NEAR
        mov     ax,3d00h
        int     21h
        jc      short rcopy_check_done
        mov     bx,ax
        mov     ah,3eh
        int     21h
        clc
rcopy_check_done:
        ret
rcopy_check_file ENDP

; DS:DX is the local ASCIIZ name and DS:SI is its 12-byte wire name.
rcopy_send_file PROC NEAR
        push    si
        mov     ax,3d00h
        int     21h
        jc      rcopy_send_file_bad_pop
        mov     cs:rcopy_handle,ax
        mov     bx,ax
        xor     cx,cx
        xor     dx,dx
        mov     ax,4202h
        int     21h
        jc      rcopy_send_file_close_bad_pop
        mov     cs:rcopy_size_low,ax
        mov     cs:rcopy_size_high,dx
        xor     cx,cx
        xor     dx,dx
        mov     ax,4200h
        int     21h
        pop     si
        mov     cx,12
        call    rcopy_send_buffer
        jc      rcopy_send_file_close_bad
        mov     ax,cs:rcopy_size_low
        call    rcopy_send_word
        jc      short rcopy_send_file_close_bad
        mov     ax,cs:rcopy_size_high
        call    rcopy_send_word
        jc      short rcopy_send_file_close_bad
        mov     bl,06h
        call    rcopy_wait_control
        jc      short rcopy_send_file_close_bad
        call    rcopy_pause
        mov     word ptr cs:rcopy_checksum,0
rcopy_file_block:
        mov     bx,cs:rcopy_handle
        mov     dx,OFFSET sector_buffer
        mov     cx,16
        mov     ah,3fh
        int     21h
        jc      short rcopy_file_read_error
        or      ax,ax
        jz      short rcopy_file_sent
        mov     cx,ax
        mov     si,OFFSET sector_buffer
rcopy_file_byte:
        lodsb
        xor     ah,ah
        add     cs:rcopy_checksum,ax
        call    rcopy_send_byte
        jc      short rcopy_file_send_error
        loop    rcopy_file_byte
        mov     bl,06h
        call    rcopy_wait_control
        jc      short rcopy_send_file_close_bad
        jmp     rcopy_file_block
rcopy_file_read_error:
        mov     dx,OFFSET rcopy_read_failed
        mov     ah,9
        int     21h
        jmp     short rcopy_send_file_close_bad
rcopy_file_send_error:
        mov     dx,OFFSET rcopy_send_failed
        mov     ah,9
        int     21h
        jmp     short rcopy_send_file_close_bad
rcopy_file_sent:
        mov     ax,cs:rcopy_checksum
        call    rcopy_send_word
        jc      short rcopy_send_file_close_bad
        mov     bx,cs:rcopy_handle
        mov     ah,3eh
        int     21h
        mov     bl,06h
        call    rcopy_wait_control
        ret
rcopy_send_file_close_bad_pop:
        pop     si
rcopy_send_file_close_bad:
        mov     bx,cs:rcopy_handle
        mov     ah,3eh
        int     21h
        stc
        ret
rcopy_send_file_bad_pop:
        pop     si
        stc
        ret
rcopy_send_file ENDP

rcopy_send_word PROC NEAR
        push    ax
        call    rcopy_send_byte
        pop     ax
        jc      short rcopy_send_word_done
        mov     al,ah
        call    rcopy_send_byte
rcopy_send_word_done:
        ret
rcopy_send_word ENDP

rcopy_send_buffer PROC NEAR
        lodsb
        call    rcopy_send_byte
        jc      short rcopy_send_buffer_done
        loop    rcopy_send_buffer
        clc
rcopy_send_buffer_done:
        ret
rcopy_send_buffer ENDP

; Ignore command echoes and bootstrap diagnostics until the receiver's control
; byte arrives. receive_byte already supplies a one-second deadline.
rcopy_wait_control PROC NEAR
        mov     cx,30
rcopy_wait_again:
        call    receive_byte
        jc      short rcopy_wait_next
        cmp     al,15h
        je      short rcopy_wait_bad
        cmp     al,bl
        je      short rcopy_wait_good
rcopy_wait_next:
        loop    rcopy_wait_again
rcopy_wait_bad:
        stc
        ret
rcopy_wait_good:
        clc
        ret
rcopy_wait_control ENDP

; DEBUG and COMMAND echo the bootstrap script over CTTY.  Consume that text
; through the first one-second idle interval before expecting binary ACKs.
rcopy_drain_input PROC NEAR
rcopy_drain_again:
        call    receive_byte
        jnc     rcopy_drain_again
        ret
rcopy_drain_input ENDP

rcopy_pause PROC NEAR
        mov     ah,0
        int     1ah
        mov     bx,dx
rcopy_pause_loop:
        mov     ah,0
        int     1ah
        sub     dx,bx
        cmp     dx,9
        jb      rcopy_pause_loop
        ret
rcopy_pause ENDP

parse_tail PROC NEAR
        mov     si,81h
        xor     cx,cx
        mov     cl,byte ptr es:[80h]
parse_space:
        jcxz    short parse_space_at_end
        mov     al,es:[si]
        inc     si
        dec     cx
        cmp     al,' '
        je      parse_space
        cmp     al,'/'
        je      parse_switch
        jmp     short parse_drive_token
parse_space_at_end:
        jmp     parse_at_end
parse_drive_token:
        and     al,0dfh
        cmp     al,'A'
        jb      parse_bad
        cmp     al,'Z'
        ja      parse_bad
        sub     al,'A'
        mov     dl,al
        cmp     cs:exclude_mode,0
        je      short parse_include_drive
        xor     bx,bx
        mov     bl,dl
        mov     cs:excluded_drives[bx],1
        jmp     short parse_drive_stored
parse_include_drive:
        cmp     cs:has_exclusions,0
        jne     parse_bad
        xor     bx,bx
        mov     bl,cs:drive_count
        cmp     bl,5
        jae     parse_bad
        mov     cs:server_drives[bx],dl
        inc     cs:drive_count
parse_drive_stored:
        jcxz    short parse_drive_at_end
        mov     al,es:[si]
        inc     si
        dec     cx
        cmp     al,':'
        je      parse_drive_tail
        cmp     al,' '
        jne     parse_bad
        jmp     parse_space
parse_drive_at_end:
        jmp     parse_done
parse_drive_tail:
        jcxz    parse_at_end
        mov     al,es:[si]
        inc     si
        dec     cx
        cmp     al,' '
        jne     parse_bad
        jmp     parse_space
parse_at_end:
        jmp     parse_done
parse_switch:
        ; Serial COM1 through COM4 are supported; parallel ports remain a gap.
        jcxz    short parse_switch_bad
        mov     al,es:[si]
        inc     si
        dec     cx
        and     al,0dfh
        cmp     al,'C'
        jne     short parse_check_b
        jmp     parse_com
parse_check_b:
        cmp     al,'B'
        je      short parse_monochrome
        cmp     al,'V'
        jne     short parse_check_x
        jmp     parse_timer_safe
parse_check_x:
        cmp     al,'X'
        je      short parse_exclude
        cmp     al,'L'
        je      parse_lpt
        cmp     al,'R'
        je      parse_rcopy
parse_switch_bad:
        jmp     parse_bad
parse_exclude:
        cmp     cs:drive_count,0
        jne     parse_bad
        jcxz    short parse_switch_bad
        cmp     byte ptr es:[si],'='
        jne     parse_bad
        inc     si
        dec     cx
        jcxz    short parse_switch_bad
        mov     cs:exclude_mode,1
        mov     cs:has_exclusions,1
        jmp     parse_space
parse_rcopy:
        cmp     cx,4
        jb      parse_bad
        mov     ax,es:[si]
        and     ax,0dfdfh
        cmp     ax,'OC'
        jne     parse_bad
        mov     ax,es:[si+2]
        and     ax,0dfdfh
        cmp     ax,'YP'
        jne     parse_bad
        add     si,4
        sub     cx,4
        mov     cs:rcopy_mode,1
        jmp     parse_flag_end
parse_monochrome:
        cmp     cx,4
        jb      short parse_monochrome_flag
        mov     al,es:[si]
        and     al,0dfh
        cmp     al,'A'
        jne     short parse_monochrome_flag
        mov     al,es:[si+1]
        and     al,0dfh
        cmp     al,'U'
        jne     parse_bad
        mov     al,es:[si+2]
        and     al,0dfh
        cmp     al,'D'
        jne     parse_bad
        cmp     byte ptr es:[si+3],':'
        jne     parse_bad
        add     si,4
        sub     cx,4
        call    parse_baud_rate
        jc      parse_bad
        mov     cs:baud_divisor,bx
        mov     cs:baud_explicit,1
        jmp     parse_space
parse_monochrome_flag:
        mov     cs:monochrome_mode,1
        jmp     short parse_flag_end
parse_timer_safe:
        mov     cs:timer_safe_mode,1
parse_flag_end:
        or      cx,cx
        jnz     short parse_flag_more
        jmp     parse_done
parse_flag_more:
        cmp     byte ptr es:[si],' '
        jne     parse_bad
        jmp     parse_space
parse_com:
        cmp     cs:port_selected,0
        jne     parse_bad
        cmp     cx,2
        jb      parse_bad
        mov     al,es:[si]
        inc     si
        dec     cx
        and     al,0dfh
        cmp     al,'O'
        jne     parse_bad
        mov     al,es:[si]
        inc     si
        dec     cx
        and     al,0dfh
        cmp     al,'M'
        jne     parse_bad
        mov     cs:port_table,OFFSET com_bases
        mov     cs:port_maximum,4
        call    parse_port_spec
        jc      parse_bad
        mov     al,cs:parsed_number
        mov     cs:com_number,al
        mov     cs:port_selected,1
        mov     ax,cs:parsed_port
        mov     cs:com_port,ax
        mov     al,cs:parsed_number
        or      al,al
        jz      short parse_com_address_banner
        add     al,'0'
        jmp     short parse_com_store_banner
parse_com_address_banner:
        mov     al,'@'
parse_com_store_banner:
        mov     cs:banner_port,al
        mov     al,cs:parsed_explicit
        xor     al,1
        mov     cs:scan_ports,al
        jmp     parse_space
parse_lpt:
        cmp     cs:port_selected,0
        jne     parse_bad
        cmp     cx,2
        jb      parse_bad
        mov     al,es:[si]
        inc     si
        dec     cx
        and     al,0dfh
        cmp     al,'P'
        jne     parse_bad
        mov     al,es:[si]
        inc     si
        dec     cx
        and     al,0dfh
        cmp     al,'T'
        jne     parse_bad
        mov     cs:port_table,OFFSET lpt_bases
        mov     cs:port_maximum,3
        call    parse_port_spec
        jc      parse_bad
        mov     al,cs:parsed_number
        mov     cs:com_number,al
        mov     cs:port_selected,1
        or      al,al
        jz      short parse_lpt_address_banner
        add     al,'0'
        jmp     short parse_lpt_store_banner
parse_lpt_address_banner:
        mov     al,'@'
parse_lpt_store_banner:
        mov     cs:banner_port,al
        mov     byte ptr cs:banner_kind,'L'
        mov     byte ptr cs:banner_kind+1,'P'
        mov     byte ptr cs:banner_kind+2,'T'
        mov     cs:transport_type,1
        mov     ax,cs:parsed_port
        mov     cs:lpt_port,ax
        mov     al,cs:parsed_explicit
        xor     al,1
        mov     cs:scan_ports,al
        jmp     parse_space

; Parse the suffix of /COM or /LPT. A missing suffix selects all ports in the
; corresponding BIOS order. An optional colon may precede a one-digit port
; number or a hexadecimal I/O base address.
parse_port_spec PROC NEAR
        mov     cs:parsed_explicit,0
        mov     cs:parsed_number,0
        or      cx,cx
        jnz     short parse_port_have_suffix
        jmp     parse_port_bare
parse_port_have_suffix:
        cmp     byte ptr es:[si],' '
        jne     short parse_port_check_colon
        jmp     parse_port_bare
parse_port_check_colon:
        cmp     byte ptr es:[si],':'
        jne     short parse_port_value
        inc     si
        dec     cx
        or      cx,cx
        jnz     short parse_port_after_colon
        jmp     parse_port_bad
parse_port_after_colon:
        cmp     byte ptr es:[si],' '
        jne     short parse_port_value
        jmp     parse_port_bad
parse_port_value:
        xor     ax,ax
        xor     dx,dx                    ; digit count
parse_port_digit:
        or      cx,cx
        jz      short parse_port_digits_done
        mov     bl,es:[si]
        cmp     bl,' '
        je      short parse_port_digits_done
        cmp     bl,'0'
        jb      short parse_port_bad
        cmp     bl,'9'
        jbe     short parse_port_decimal
        and     bl,0dfh
        sub     bl,'A'-10
        cmp     bl,15
        ja      short parse_port_bad
        jmp     short parse_port_have_digit
parse_port_decimal:
        sub     bl,'0'
parse_port_have_digit:
        cmp     ax,0fffh
        ja      short parse_port_bad
        mov     bh,0
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        add     ax,bx
        inc     si
        dec     cx
        inc     dx
        jmp     parse_port_digit
parse_port_digits_done:
        or      dx,dx
        jz      short parse_port_bad
        cmp     dx,1
        jne     short parse_port_address
        cmp     al,1
        jb      short parse_port_address
        cmp     al,cs:port_maximum
        ja      short parse_port_address
        mov     cs:parsed_number,al
        dec     al
        xor     ah,ah
        shl     ax,1
        mov     bx,cs:port_table
        add     bx,ax
        mov     ax,cs:[bx]
parse_port_address:
        or      ax,ax
        jz      short parse_port_bad
        mov     cs:parsed_port,ax
        mov     cs:parsed_explicit,1
        clc
        ret
parse_port_bare:
        mov     bx,cs:port_table
        mov     ax,cs:[bx]
        mov     cs:parsed_port,ax
        mov     cs:parsed_number,1
        clc
        ret
parse_port_bad:
        stc
        ret
parse_port_spec ENDP
parse_done:
        cmp     cs:rcopy_mode,0
        je      short parse_regular_server
        cmp     cs:drive_count,0
        jne     short parse_bad
        cmp     cs:has_exclusions,0
        jne     short parse_bad
        cmp     cs:transport_type,0
        jne     short parse_bad
        cmp     cs:baud_explicit,0
        jne     short parse_rcopy_rate_ready
        mov     cs:baud_divisor,48      ; retail bootstrap default is 2400 baud
parse_rcopy_rate_ready:
        clc
        ret
parse_regular_server:
        cmp     cs:transport_type,0
        je      short parse_transport_valid
        cmp     cs:baud_explicit,0
        jne     short parse_bad
parse_transport_valid:
        cmp     cs:drive_count,0
        jne     short parse_have_drive
        call    enumerate_default_drives
        cmp     cs:drive_count,0
        je      short parse_bad
parse_have_drive:
        clc
        ret
parse_bad:
        stc
        ret
parse_tail ENDP

; With no explicit drive list, retail INTERSVR shares available DOS drives
; except those named after /X=. Keep the resident protocol's five-unit cap.
enumerate_default_drives PROC NEAR
        xor     si,si
enumerate_drive:
        cmp     cs:excluded_drives[si],0
        jne     short enumerate_next
        mov     dx,si
        inc     dl
        mov     ah,36h
        int     21h
        cmp     ax,0ffffh
        je      short enumerate_next
        xor     bx,bx
        mov     bl,cs:drive_count
        mov     ax,si
        mov     cs:server_drives[bx],al
        inc     cs:drive_count
        cmp     cs:drive_count,5
        jae     short enumerate_done
enumerate_next:
        inc     si
        cmp     si,26
        jb      short enumerate_drive
enumerate_done:
        ret
enumerate_default_drives ENDP

; Parse one of the five retail baud rates from ES:SI. Consume its trailing
; space, if present, and return the UART divisor in BX.
parse_baud_rate PROC NEAR
        xor     ax,ax
        xor     dx,dx
baud_digit:
        jcxz    short baud_done
        mov     bl,es:[si]
        cmp     bl,' '
        je      short baud_space
        sub     bl,'0'
        cmp     bl,9
        ja      short baud_bad
        inc     si
        dec     cx
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
        jmp     baud_digit
baud_space:
        inc     si
        dec     cx
baud_done:
        cmp     dx,0
        jne     short baud_115200
        cmp     ax,9600
        jne     short baud_19200
        mov     bx,12
        jmp     short baud_good
baud_19200:
        cmp     ax,19200
        jne     short baud_38400
        mov     bx,6
        jmp     short baud_good
baud_38400:
        cmp     ax,38400
        jne     short baud_57600
        mov     bx,3
        jmp     short baud_good
baud_57600:
        cmp     ax,57600
        jne     short baud_bad
        mov     bx,2
        jmp     short baud_good
baud_115200:
        cmp     dx,1
        jne     short baud_bad
        cmp     ax,0c200h
        jne     short baud_bad
        mov     bx,1
baud_good:
        clc
        ret
baud_bad:
        stc
        ret
parse_baud_rate ENDP

syntax_error:
        mov     dx,OFFSET usage
        mov     ah,9
        int     21h
        mov     ax,4c01h
        int     21h
server_help:
        mov     dx,OFFSET usage
        mov     ah,9
        int     21h
        mov     ax,4c00h
        int     21h

com_port        dw 03f8h
com_number      db 1
port_selected   db 0
baud_explicit   db 0
scan_ports      db 0
scan_index      db 0
port_table      dw 0
port_maximum    db 0
parsed_explicit db 0
parsed_number   db 0
parsed_port     dw 0
transport_type  db 0
lpt_port        dw 0378h
lpt_shadow      db 0
baud_divisor    dw 1
rcopy_mode      db 0
rcopy_handle    dw 0
rcopy_size_low  dw 0
rcopy_size_high dw 0
rcopy_checksum  dw 0
monochrome_mode db 0
timer_safe_mode db 0
exclude_mode    db 0
has_exclusions  db 0
excluded_drives db 26 dup(0)
drive_count     db 0
server_drives   db 5 dup(0)
request_command db 0
request_unit    db 0
request_checksum db 0
bios_drive      db 0
bios_command    db 0
bios_sector     db 0
bios_heads      db 0
sector_number   dd 0
banner          db 'Microsoft Interlnk server compatible transport',13,10
                db 'Port-'
banner_kind     db 'COM'
banner_port     db '1  Drives $'
banner_suffix   db ' available',13,10
                db 'F1 displays status; Alt+F4 exits.',13,10,'$'
printer_status  db 0
usage           db 'Syntax: INTERSVR [drive: ...] [/X=drive: ...]',13,10
                db '       [/COM[:][n|address] | /LPT[:][n|address]] [/BAUD:rate] [/B] [/V]',13,10
                db '       INTERSVR /RCOPY [/COM[:][n|address]] [/BAUD:rate]',13,10,'$'
rcopy_intro     db 'Remote copy over COM; the default rate is 2400 baud.',13,10
                db 'On the remote machine run MODE COMn:rate,N,8,1,P, then CTTY COMn.',13,10,'$'
rcopy_missing_files db 'INTERSVR: INTERLNK.EXE and INTERSVR.EXE must be in the current directory.',13,10,'$'
rcopy_failed    db 'INTERSVR: Remote copy failed.',13,10,'$'
rcopy_read_failed db 'INTERSVR: Could not read a transfer source.',13,10,'$'
rcopy_send_failed db 'INTERSVR: Serial transmit timed out.',13,10,'$'
rcopy_complete  db 'Remote copy complete.',13,10,'$'
rcopy_debug_command db 'DEBUG',13
rcopy_debug_command_end label byte
rcopy_name_command db 'N FXB.COM',13
rcopy_name_command_end label byte
rcopy_enter_prefix db 'E '
rcopy_cx_command db 'RCX',13
rcopy_cx_command_end label byte
rcopy_write_command db 13,'W',13,'Q',13
rcopy_write_command_end label byte
rcopy_run_command db 'FXB.COM '
rcopy_run_port db '1',13
rcopy_run_command_end label byte
rcopy_cleanup_command db 'DEL FXB.COM',13,'CTTY CON',13
rcopy_cleanup_command_end label byte
rcopy_magic     db 'IRCP',2
interlnk_name   db 'INTERLNK.EXE',0
intersvr_name   db 'INTERSVR.EXE',0
interlnk_header_name db 'INTERLNK.EXE'
intersvr_header_name db 'INTERSVR.EXE'
sector_buffer   db 512 dup(0)
connected       db 0
discovery_count dw 0
geometry_count  dw 0
read_count      dw 0
write_count     dw 0
printer_count   dw 0
error_count     dw 0
status_heading  db 13,10,'Interlnk server status',13,10,'$'
status_connected db 'Connection: active',13,10,'$'
status_waiting  db 'Connection: waiting',13,10,'$'
status_discovery db 'Discovery requests: $'
status_geometry db 'Geometry requests:  $'
status_reads    db 'Sector reads:       $'
status_writes   db 'Sector writes:      $'
status_printer  db 'Printer bytes:      $'
status_errors   db 'Protocol/I/O errors: $'
newline         db 13,10,'$'
com_bases       dw 03f8h,02f8h,03e8h,02e8h
lpt_bases       dw 0378h,0278h,03bch

fxb_image label byte
        INCBIN <FXB.COM>
fxb_image_end label byte

CODE ENDS
STACKSEG SEGMENT PARA STACK 'STACK'
        db 512 dup(0)
STACKSEG ENDS
        END start
