; MS-DOS 6 compatible CD-ROM redirector loader and INT 2Fh interface.
;
; Hardware-specific CD-ROM drivers remain separate.  MSCDEX discovers their
; character-device headers by /D:name and publishes the standard 15xxh API.

MAX_DRIVERS EQU 8

CODE SEGMENT PUBLIC
        ORG     100h
        ASSUME  CS:CODE,DS:CODE,ES:NOTHING,SS:CODE

start:
        cld
        mov     cs:psp_segment,cs
        push    cs
        pop     ds
        push    ds
        push    es
        push    si
        push    di
        mov     ax,1500h
        xor     bx,bx
        int     2fh
        pop     di
        pop     si
        pop     es
        pop     ds
        or      bx,bx
        jz      first_install
        mov     dx,OFFSET already_msg
        call    print_dollar
        xor     al,al
        jmp     terminate

first_install:
        call    parse_command_tail
        jc      terminate
        cmp     cs:driver_count,0
        jne     have_driver_names
        mov     dx,OFFSET usage_msg
        call    print_dollar
        mov     al,1
        jmp     terminate

have_driver_names:
        cmp     cs:use_ems,0
        je      discover_drivers
        mov     ax,4300h
        int     2fh
        cmp     al,80h
        je      discover_drivers
        mov     dx,OFFSET no_ems_msg
        call    print_dollar
        mov     al,1
        jmp     terminate

discover_drivers:
        xor     bx,bx
find_next_driver:
        mov     si,bx
        shl     si,1
        shl     si,1
        shl     si,1
        add     si,OFFSET driver_names
        push    bx
        call    find_device_header
        pop     bx
        jnc     driver_found
        mov     dx,OFFSET driver_missing_msg
        call    print_dollar
        mov     si,bx
        shl     si,1
        shl     si,1
        shl     si,1
        add     si,OFFSET driver_names
        call    print_name
        mov     dx,OFFSET quote_crlf
        call    print_dollar
        mov     al,1
        jmp     terminate
driver_found:
        mov     si,bx
        shl     si,1
        mov     cs:driver_offsets[si],di
        mov     cs:driver_segments[si],es
        inc     bx
        cmp     bl,cs:driver_count
        jb      find_next_driver

        cmp     cs:first_drive,0ffh
        jne     drive_selected
        mov     ah,19h
        int     21h
        inc     al
        mov     cs:first_drive,al
drive_selected:
        xor     ah,ah
        mov     al,cs:first_drive
        xor     bx,bx
        mov     bl,cs:driver_count
        add     ax,bx
        cmp     ax,26
        jbe     drive_range_ok
        mov     dx,OFFSET drive_range_msg
        call    print_dollar
        mov     al,1
        jmp     terminate
drive_range_ok:

        mov     ax,352fh
        int     21h
        mov     cs:old_2f_off,bx
        mov     cs:old_2f_seg,es
        push    cs
        pop     ds
        mov     dx,OFFSET int2f_handler
        mov     ax,252fh
        int     21h

        mov     es,cs:psp_segment
        mov     es,word ptr es:[2ch]
        mov     ah,49h
        int     21h
        push    cs
        pop     ds
        cmp     cs:verbose,0
        je      installation_line
        mov     dx,OFFSET version_msg
        call    print_dollar
installation_line:
        mov     dx,OFFSET installed_msg
        call    print_dollar
        xor     ax,ax
        mov     al,cs:first_drive
        add     al,'A'
        mov     dl,al
        mov     ah,2
        int     21h
        mov     dx,OFFSET colon_crlf
        call    print_dollar
        mov     dx,(resident_end-start+100h+15)/16
        mov     ax,3100h
        int     21h

terminate:
        mov     ah,4ch
        int     21h

; ---------------------------------------------------------------------------
; Resident MSCDEX multiplex API
; ---------------------------------------------------------------------------
int2f_handler PROC FAR
        cmp     ah,15h
        jne     chain_2f
        cmp     al,00h
        je      api_install_check
        cmp     al,01h
        je      api_device_list
        cmp     al,0bh
        je      api_drive_check
        cmp     al,0ch
        je      api_version
        cmp     al,0dh
        je      api_drive_list
        cmp     al,08h
        je      api_absolute_read
        cmp     al,10h
        je      api_driver_request
chain_2f:
        jmp     dword ptr cs:old_2f_off

api_install_check:
        xor     bx,bx
        mov     bl,cs:driver_count
        xor     cx,cx
        mov     cl,cs:first_drive
        iret

api_drive_check:
        xor     ax,ax
        xor     cx,cx
        mov     cl,cs:first_drive
        cmp     bx,cx
        jb      api_drive_check_done
        add     cl,cs:driver_count
        cmp     bx,cx
        jae     api_drive_check_done
        mov     ax,0adadh
api_drive_check_done:
        iret

api_version:
        mov     bx,0217h              ; MSCDEX 2.23
        iret

api_device_list:
        push    ax
        push    cx
        push    si
        push    di
        mov     di,bx
        xor     cx,cx
        mov     cl,cs:driver_count
        xor     si,si
api_device_next:
        mov     byte ptr es:[di],0    ; subunit number
        mov     ax,cs:driver_offsets[si]
        mov     es:[di+1],ax
        mov     ax,cs:driver_segments[si]
        mov     es:[di+3],ax
        add     di,5
        add     si,2
        loop    api_device_next
        pop     di
        pop     si
        pop     cx
        pop     ax
        iret

api_drive_list:
        push    ax
        push    cx
        push    di
        mov     di,bx
        xor     cx,cx
        mov     cl,cs:driver_count
        mov     al,cs:first_drive
api_drive_next:
        mov     es:[di],al
        inc     al
        inc     di
        loop    api_drive_next
        pop     di
        pop     cx
        pop     ax
        iret

; AX=1508h, ES:BX=destination, CX=drive, DX=count, SI:DI=starting sector.
; Convert the call to the CD-ROM driver's command 80h READ LONG packet.
api_absolute_read:
        mov     word ptr cs:read_request+14,bx
        mov     word ptr cs:read_request+16,es
        mov     word ptr cs:read_request+18,dx
        mov     word ptr cs:read_request+20,di
        mov     word ptr cs:read_request+22,si
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        push    cs
        pop     es
        mov     bx,OFFSET read_request
        call    forward_driver_request
        mov     cs:api_failed,0
        jnc     short api_read_save
        mov     cs:api_failed,1
        cmp     ax,000fh
        je      short api_read_save
        mov     ax,0015h              ; DOS error_not_ready
api_read_save:
        mov     cs:api_result,ax
api_read_restore:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        mov     ax,cs:api_result
        cmp     cs:api_failed,0
        jne     short api_return_carry
api_return_clear:
        push    bp
        mov     bp,sp
        and     word ptr ss:[bp+6],0fffeh
        pop     bp
        iret
api_return_carry:
        push    bp
        mov     bp,sp
        or      word ptr ss:[bp+6],1
        pop     bp
        iret

; AX=1510h, CX=zero-based DOS drive, ES:BX=request header.  Forward the
; packet through the selected CD-ROM driver's strategy and interrupt entries.
api_driver_request:
        call    forward_driver_request
        jc      short api_return_carry
        jmp     short api_return_clear
int2f_handler ENDP

forward_driver_request PROC NEAR
        mov     cs:request_offset,bx
        mov     cs:request_segment,es
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        mov     ax,cx
        xor     dx,dx
        mov     dl,cs:first_drive
        sub     ax,dx
        jc      short api_request_bad
        xor     dx,dx
        mov     dl,cs:driver_count
        cmp     ax,dx
        jae     short api_request_bad
        shl     ax,1
        mov     si,ax
        mov     di,cs:driver_offsets[si]
        mov     ax,cs:driver_segments[si]
        mov     ds,ax
        mov     ax,[di+6]
        mov     word ptr cs:strategy_entry,ax
        mov     ax,[di+8]
        mov     word ptr cs:interrupt_entry,ax
        mov     word ptr cs:strategy_entry+2,ds
        mov     word ptr cs:interrupt_entry+2,ds
        mov     ax,cs:request_segment
        mov     es,ax
        mov     bx,cs:request_offset
        mov     byte ptr es:[bx+1],0
        call    dword ptr cs:strategy_entry
        call    dword ptr cs:interrupt_entry
        test    word ptr es:[bx+3],8000h
        jnz     short api_request_driver_bad
        xor     ax,ax
        mov     cs:api_failed,0
        jmp     short api_request_done
api_request_driver_bad:
        mov     ax,word ptr es:[bx+3]
        and     ax,00ffh
        mov     cs:api_failed,1
        jmp     short api_request_done
api_request_bad:
        mov     ax,cs:request_segment
        mov     es,ax
        mov     bx,cs:request_offset
        mov     word ptr es:[bx+3],810fh
        mov     ax,000fh
        mov     cs:api_failed,1
api_request_done:
        mov     cs:api_result,ax
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        mov     ax,cs:api_result
        cmp     cs:api_failed,0
        jne     short forward_failed
        clc
        ret
forward_failed:
        stc
        ret
forward_driver_request ENDP

old_2f_off      dw 0
old_2f_seg      dw 0
strategy_entry  dd 0
interrupt_entry dd 0
request_offset  dw 0
request_segment dw 0
api_result      dw 0
api_failed      db 0
read_request    db 27,0,80h
                dw 0
                db 8 dup(0)
                db 0                   ; HSG addressing mode
                dw 0,0                 ; transfer offset:segment
                dw 0                   ; sector count
                dd 0                   ; starting sector
                db 0,0,0               ; cooked, no interleave
psp_segment     dw 0
driver_offsets  dw MAX_DRIVERS dup(0)
driver_segments dw MAX_DRIVERS dup(0)
driver_count    db 0
first_drive     db 0ffh
buffer_count    dw 10
use_ems         db 0
kanji_mode      db 0
share_mode      db 0
verbose         db 0
resident_end LABEL BYTE

; ---------------------------------------------------------------------------
; Transient parser and DOS device-chain discovery
; ---------------------------------------------------------------------------
parse_command_tail PROC NEAR
        mov     es,cs:psp_segment
        xor     cx,cx
        mov     cl,es:[80h]
        mov     si,81h
parse_skip_space:
        or      cx,cx
        jnz     short parse_have_char
        jmp     parse_done
parse_have_char:
        mov     al,es:[si]
        cmp     al,' '
        jne     parse_token
        inc     si
        dec     cx
        jmp     parse_skip_space
parse_token:
        cmp     al,'/'
        je      parse_switch
        cmp     al,'-'
        jne     parse_error
parse_switch:
        inc     si
        dec     cx
        or      cx,cx
        jnz     short parse_have_switch
        jmp     parse_error
parse_have_switch:
        mov     al,es:[si]
        cmp     al,'?'
        je      parse_illegal_help
        and     al,0dfh
        inc     si
        dec     cx
        cmp     al,'D'
        je      parse_driver
        cmp     al,'L'
        je      parse_letter
        cmp     al,'M'
        je      parse_buffers
        cmp     al,'E'
        je      parse_flag_ems
        cmp     al,'K'
        je      parse_flag_kanji
        cmp     al,'S'
        je      parse_flag_share
        cmp     al,'V'
        je      parse_flag_verbose
        jmp     parse_error

parse_flag_ems:
        mov     cs:use_ems,1
        jmp     require_token_end
parse_flag_kanji:
        mov     cs:kanji_mode,1
        jmp     require_token_end
parse_flag_share:
        mov     cs:share_mode,1
        jmp     require_token_end
parse_flag_verbose:
        mov     cs:verbose,1
require_token_end:
        or      cx,cx
        jnz     short require_check_space
        jmp     parse_done
require_check_space:
        cmp     byte ptr es:[si],' '
        jne     parse_error
        jmp     parse_skip_space

parse_driver:
        or      cx,cx
        jnz     short parse_driver_colon
        jmp     parse_error
parse_driver_colon:
        cmp     byte ptr es:[si],':'
        jne     parse_error
        inc     si
        dec     cx
        mov     al,cs:driver_count
        cmp     al,MAX_DRIVERS
        jae     parse_error
        xor     ah,ah
        mov     di,ax
        shl     di,1
        shl     di,1
        shl     di,1
        add     di,OFFSET driver_names
        push    cx
        push    es
        push    cs
        pop     es
        mov     cx,8
        mov     al,' '
        rep     stosb
        pop     es
        pop     cx
        sub     di,8
        xor     bx,bx
parse_driver_char:
        jcxz    parse_driver_end
        mov     al,es:[si]
        cmp     al,' '
        je      parse_driver_end
        cmp     bx,8
        jae     parse_error
        cmp     al,'a'
        jb      short parse_driver_store
        cmp     al,'z'
        ja      short parse_driver_store
        sub     al,'a'-'A'
parse_driver_store:
        mov     cs:[di+bx],al
        inc     bx
        inc     si
        dec     cx
        jmp     parse_driver_char
parse_driver_end:
        or      bx,bx
        jz      parse_error
        inc     cs:driver_count
        jmp     parse_skip_space

parse_letter:
        jcxz    parse_error
        cmp     byte ptr es:[si],':'
        jne     parse_error
        inc     si
        dec     cx
        jcxz    parse_error
        mov     al,es:[si]
        and     al,0dfh
        sub     al,'A'
        cmp     al,25
        ja      parse_error
        mov     cs:first_drive,al
        inc     si
        dec     cx
        jmp     require_token_end

parse_buffers:
        jcxz    parse_error
        cmp     byte ptr es:[si],':'
        jne     parse_error
        inc     si
        dec     cx
        xor     ax,ax
        xor     bx,bx
parse_buffer_digit:
        jcxz    parse_buffer_end
        mov     dl,es:[si]
        cmp     dl,' '
        je      parse_buffer_end
        cmp     dl,'0'
        jb      parse_error
        cmp     dl,'9'
        ja      parse_error
        sub     dl,'0'
        xor     dh,dh
        push    dx
        mov     dx,10
        mul     dx
        pop     dx
        add     ax,dx
        jc      parse_error
        inc     bx
        inc     si
        dec     cx
        jmp     parse_buffer_digit
parse_buffer_end:
        or      bx,bx
        jz      parse_error
        or      ax,ax
        jz      parse_error
        mov     cs:buffer_count,ax
        jmp     parse_skip_space

parse_illegal_help:
        mov     dx,OFFSET illegal_help_msg
        call    print_dollar
        mov     dx,OFFSET usage_msg
        call    print_dollar
        mov     al,1
        stc
        ret
parse_error:
        mov     dx,OFFSET usage_msg
        call    print_dollar
        mov     al,1
        stc
        ret
parse_done:
        clc
        ret
parse_command_tail ENDP

; DS:SI points to an eight-byte, space-padded device name.
; Returns ES:DI at its character device header.
find_device_header PROC NEAR
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    si
        mov     ah,52h
        int     21h
        pop     si
        ; DOS 4+ publishes the NUL/device-chain head at LoL +22h.
        mov     di,es:[bx+22h]
        mov     ax,es:[bx+24h]
        mov     es,ax
        mov     dx,64
find_header_loop:
        dec     dx
        jz      find_header_fail
        cmp     di,0ffffh
        je      find_header_fail
        mov     ax,es
        cmp     ax,0ffffh
        je      find_header_fail
        test    word ptr es:[di+4],8000h
        jz      find_header_next
        mov     ax,cs:[si]
        cmp     ax,es:[di+10]
        jne     find_header_next
        mov     ax,cs:[si+2]
        cmp     ax,es:[di+12]
        jne     find_header_next
        mov     ax,cs:[si+4]
        cmp     ax,es:[di+14]
        jne     find_header_next
        mov     ax,cs:[si+6]
        cmp     ax,es:[di+16]
        jne     find_header_next
        clc
        jmp     find_header_done
find_header_next:
        mov     bx,es:[di]
        mov     ax,es:[di+2]
        mov     di,bx
        mov     es,ax
        jmp     find_header_loop
find_header_fail:
        stc
find_header_done:
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
find_device_header ENDP

print_name PROC NEAR
        push    ax
        push    cx
        push    dx
        mov     cx,8
print_name_loop:
        mov     dl,cs:[si]
        cmp     dl,' '
        je      print_name_done
        mov     ah,2
        int     21h
        inc     si
        loop    print_name_loop
print_name_done:
        pop     dx
        pop     cx
        pop     ax
        ret
print_name ENDP

print_dollar PROC NEAR
        mov     ah,9
        int     21h
        ret
print_dollar ENDP

minus_one          dw 0ffffh
driver_names       db MAX_DRIVERS*8 dup(' ')
illegal_help_msg   db "Illegal option '?'",13,10,'$'
usage_msg          db 'usage: MSCDEX [/E/K/S/V] [/D:<driver> ... ] [/L:<letter>] [/M:<buffers>]',13,10,'$'
no_ems_msg         db 'Expanded memory not present or not-usable',13,10,'$'
driver_missing_msg db "Device driver not found: '",'$'
quote_crlf         db "'.",13,10,'No valid CDROM device drivers selected',13,10,'$'
drive_range_msg    db 'Not enough drive letters available',13,10,'$'
already_msg        db 'MSCDEX already installed.',13,10,'$'
version_msg        db 'MSCDEX Version 2.23',13,10,'$'
installed_msg      db 'Drive assigned to driver: $'
colon_crlf         db ':',13,10,'$'

CODE ENDS
        END start
