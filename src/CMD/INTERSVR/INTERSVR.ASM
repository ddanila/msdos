; Serial Interlnk server.  Exports up to five DOS volumes as remote block
; devices; INTERLNK.EXE performs ordinary DOS filesystem work through sector
; requests.

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
        jc      server_loop
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
        call    receive_byte
        jc      server_loop
        mov     cs:request_unit,al
        call    receive_sector_number
        jc      server_loop
        mov     al,cs:request_command
        cmp     al,0
        je      discovery_request
        cmp     al,1
        je      geometry_request
        cmp     al,2
        je      read_request
        cmp     al,3
        je      write_request
        mov     al,1
        call    send_status
        jmp     server_loop

discovery_request:
        xor     al,al
        call    send_status
        mov     al,cs:drive_count
        call    send_byte
        jmp     server_loop

geometry_request:
        call    read_boot_sector
        jc      request_failed
        xor     al,al
        call    send_status
        mov     si,OFFSET sector_buffer
        call    send_sector
        jmp     server_loop

read_request:
        call    absolute_read
        jc      request_failed
        xor     al,al
        call    send_status
        mov     si,OFFSET sector_buffer
        call    send_sector
        jmp     server_loop

write_request:
        mov     di,OFFSET sector_buffer
        call    receive_sector
        jc      request_failed
        call    absolute_write
        jc      request_failed
        xor     al,al
        call    send_status
        jmp     server_loop

request_failed:
        mov     al,1
        call    send_status
        jmp     server_loop

; Request sector is little-endian 32-bit.  DOS 6 FAT volumes are bounded by
; the legacy absolute-I/O interface here, so reject a nonzero high word.
receive_sector_number PROC NEAR
        call    receive_byte
        jc      short receive_sector_failed
        mov     byte ptr cs:sector_number,al
        call    receive_byte
        jc      short receive_sector_failed
        mov     byte ptr cs:sector_number+1,al
        call    receive_byte
        jc      short receive_sector_failed
        mov     byte ptr cs:sector_number+2,al
        call    receive_byte
        jc      short receive_sector_failed
        mov     byte ptr cs:sector_number+3,al
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
send_sector_loop:
        lodsb
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

receive_byte PROC NEAR
        push    bx
        push    cx
        push    dx
        mov     dx,cs:com_port
        add     dx,5
        mov     bx,32
receive_retry:
        mov     cx,0ffffh
receive_ready:
        in      al,dx
        test    al,1
        jnz     short receive_now
        loop    receive_ready
        dec     bx
        jnz     receive_retry
        pop     dx
        pop     cx
        pop     bx
        stc
        ret
receive_now:
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
        jmp     parse_space
parse_monochrome_flag:
        mov     cs:monochrome_mode,1
        jmp     short parse_flag_end
parse_timer_safe:
        mov     cs:timer_safe_mode,1
parse_flag_end:
        jcxz    parse_done
        cmp     byte ptr es:[si],' '
        jne     parse_bad
        jmp     parse_space
parse_com:
        cmp     cx,4
        jb      parse_bad
        mov     al,es:[si]
        inc     si
        and     al,0dfh
        cmp     al,'O'
        jne     parse_bad
        mov     al,es:[si]
        inc     si
        and     al,0dfh
        cmp     al,'M'
        jne     parse_bad
        mov     al,es:[si]
        inc     si
        cmp     al,':'
        jne     parse_bad
        mov     al,es:[si]
        inc     si
        sub     cx,4
        sub     al,'0'
        cmp     al,1
        jb      parse_bad
        cmp     al,4
        ja      parse_bad
        mov     cs:com_number,al
        mov     cs:banner_port,al
        add     cs:banner_port,'0'
        dec     al
        xor     ah,ah
        shl     ax,1
        mov     bx,ax
        mov     ax,cs:com_bases[bx]
        mov     cs:com_port,ax
        jmp     parse_space
parse_done:
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
baud_divisor    dw 1
monochrome_mode db 0
timer_safe_mode db 0
exclude_mode    db 0
has_exclusions  db 0
excluded_drives db 26 dup(0)
drive_count     db 0
server_drives   db 5 dup(0)
request_command db 0
request_unit    db 0
bios_drive      db 0
bios_command    db 0
bios_sector     db 0
bios_heads      db 0
sector_number   dd 0
banner          db 'Microsoft Interlnk server compatible transport',13,10
                db 'Port-COM'
banner_port     db '1  Drives $'
banner_suffix   db ' available',13,10,'$'
usage           db 'Syntax: INTERSVR [drive: ...] [/X=drive: ...] [/COM:n] [/BAUD:rate] [/B] [/V]',13,10,'$'
sector_buffer   db 512 dup(0)
com_bases       dw 03f8h,02f8h,03e8h,02e8h

CODE ENDS
STACKSEG SEGMENT PARA STACK 'STACK'
        db 512 dup(0)
STACKSEG ENDS
        END start
