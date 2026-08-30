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
        call    receive_byte
        jc      server_loop
        cmp     al,0a5h
        jne     server_loop
        call    receive_byte
        jc      server_loop
        cmp     al,05ah
        jne     server_loop
        call    receive_byte
        jc      server_loop
        mov     cs:request_command,al
        call    receive_byte
        jc      server_loop
        mov     cs:request_unit,al
        call    receive_sector_number
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
        mov     byte ptr cs:sector_number,al
        call    receive_byte
        mov     byte ptr cs:sector_number+1,al
        call    receive_byte
        mov     byte ptr cs:sector_number+2,al
        call    receive_byte
        mov     byte ptr cs:sector_number+3,al
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

parse_tail PROC NEAR
        mov     si,81h
        xor     cx,cx
        mov     cl,byte ptr es:[80h]
parse_space:
        jcxz    short parse_at_end
        mov     al,es:[si]
        inc     si
        dec     cx
        cmp     al,' '
        je      parse_space
        cmp     al,'/'
        je      parse_switch
        and     al,0dfh
        cmp     al,'A'
        jb      parse_bad
        cmp     al,'Z'
        ja      parse_bad
        sub     al,'A'
        xor     bx,bx
        mov     bl,cs:drive_count
        cmp     bl,5
        jae     parse_bad
        mov     cs:server_drives[bx],al
        inc     cs:drive_count
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
        jcxz    parse_done
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
        jcxz    parse_bad
        mov     al,es:[si]
        inc     si
        dec     cx
        and     al,0dfh
        cmp     al,'C'
        jne     parse_bad
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
        mov     cs:server_drives,0
        mov     cs:drive_count,1
parse_have_drive:
        clc
        ret
parse_bad:
        stc
        ret
parse_tail ENDP

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
usage           db 'Syntax: INTERSVR [drive: ...] [/COM:n]',13,10,'$'
sector_buffer   db 512 dup(0)
com_bases       dw 03f8h,02f8h,03e8h,02e8h

CODE ENDS
STACKSEG SEGMENT PARA STACK 'STACK'
        db 512 dup(0)
STACKSEG ENDS
        END start
