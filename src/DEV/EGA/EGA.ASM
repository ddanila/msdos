; Clean-room EGA Register Interface driver for MS-DOS 5/6 compatibility.
;
; EGA.SYS is independent of DOSSHELL here.  It exposes the documented RIL
; functions on INT 10h (AH=F0h..F7h, FAh) and the DOS/Windows installation
; and version checks on INT 2Fh.  Register values are shadowed so software can
; safely recover the state of write-only EGA registers.

        .model  tiny
        .286
        .code
        org     0

device_header:
        dw      0ffffh, 0ffffh
        dw      08000h
        dw      strategy
        dw      interrupt
        db      'EGA$    '

REQUEST_TABLE:
        dw      initialize

request_ptr     dd      0
old_int10       dd      0
old_int2f       dd      0
multiplex       db      0bch
ril_version     db      2, 11

; CRTC, sequencer, graphics controller, attribute controller, and singles.
registers       db      63 dup (0)
defaults        db      63 dup (0)
default_defined db      0
bios_ax         dw      0
bios_bx         dw      0

strategy proc far
        mov     word ptr cs:[request_ptr], bx
        mov     word ptr cs:[request_ptr+2], es
        ret
strategy endp

interrupt proc far
        push    ax
        push    bx
        push    ds
        les     bx, cs:[request_ptr]
        cmp     byte ptr es:[bx+2], 0
        jne     short request_bad
        push    cs
        pop     ds
        call    initialize
        jmp     short request_done
request_bad:
        mov     word ptr es:[bx+3], 08103h
request_done:
        pop     ds
        pop     bx
        pop     ax
        ret
interrupt endp

int2f_handler proc far
        cmp     ah, cs:[multiplex]
        jne     short int2f_chain
        mov     bx, 05456h
        or      al, al
        jz      short int2f_installed
        cmp     al, 6
        jne     short int2f_done
        mov     cx, 020bh
        mov     dl, 9
int2f_done:
        iret
int2f_installed:
        mov     al, 0ffh
        iret
int2f_chain:
        jmp     dword ptr cs:[old_int2f]
int2f_handler endp

int10_handler proc far
        cmp     ah, 0f0h
        jb      short int10_bios
        cmp     ah, 0f7h
        jbe     short int10_ril
        cmp     ah, 0fah
        jne     short int10_chain
        or      bx, bx
        jne     short int10_done
        push    cs
        pop     es
        mov     bx, offset ril_version
int10_done:
        iret
int10_bios:
        ; Mode, palette, font, and alternate-function calls can change EGA
        ; registers behind the RIL.  Let the BIOS finish, then resample the
        ; hardware so subsequent F0/F2/F4 reads see the resulting state.
        cmp     ah, 00h
        je      short int10_bios_shadow
        cmp     ah, 10h
        jb      short int10_chain
        cmp     ah, 12h
        ja      short int10_chain
int10_bios_shadow:
        mov     cs:[bios_ax], ax
        mov     cs:[bios_bx], bx
        pushf
        call    dword ptr cs:[old_int10]
        pushf
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        call    capture_hardware
        call    track_bios_palette
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        popf
        iret
int10_chain:
        jmp     dword ptr cs:[old_int10]
int10_ril:
        cmp     ah, 0f0h
        je      ril_read_one
        cmp     ah, 0f1h
        je      ril_write_one
        cmp     ah, 0f2h
        je      ril_read_range
        cmp     ah, 0f3h
        je      ril_write_range
        cmp     ah, 0f4h
        je      ril_read_set
        cmp     ah, 0f5h
        je      ril_write_set
        cmp     ah, 0f6h
        je      ril_restore_defaults
        jmp     ril_define_defaults
int10_handler endp

; Input DX=group, BL=register. Output SI=shadow offset and carry clear.
lookup_register proc near
        push    ax
        xor     si, si
        or      dx, dx
        jz      short lookup_indexed
        cmp     dx, 8
        jne     short lookup_graphics
        mov     si, 25
        cmp     bl, 5
        jmp     short lookup_indexed_check
lookup_graphics:
        cmp     dx, 10h
        jne     short lookup_attribute
        mov     si, 30
        cmp     bl, 9
        jmp     short lookup_indexed_check
lookup_attribute:
        cmp     dx, 18h
        jne     short lookup_single
        mov     si, 39
        cmp     bl, 20
        jmp     short lookup_indexed_check
lookup_single:
        cmp     dx, 20h
        jb      short lookup_fail
        cmp     dx, 38h
        ja      short lookup_fail
        test    dl, 7
        jnz     short lookup_fail
        mov     ax, dx
        sub     ax, 20h
        shr     ax, 1
        shr     ax, 1
        shr     ax, 1
        add     ax, 59
        mov     si, ax
        clc
        pop     ax
        ret
lookup_indexed:
        cmp     bl, 25
lookup_indexed_check:
        jae     short lookup_fail
        xor     ah, ah
        mov     al, bl
        add     si, ax
        clc
        pop     ax
        ret
lookup_fail:
        stc
        pop     ax
        ret
lookup_register endp

ril_read_one:
        push    si
        call    lookup_register
        jc      short read_one_done
        mov     bl, cs:[registers+si]
read_one_done:
        pop     si
        iret

ril_write_one:
        push    ax
        push    si
        mov     al, bl
        cmp     dx, 20h
        jae     short write_one_single
        mov     bl, al
        call    lookup_register
        jc      short write_one_done
        mov     cs:[registers+si], bh
        call    write_hardware_indexed
        mov     bl, bh
        jmp     short write_one_done
write_one_single:
        xor     bl, bl
        call    lookup_register
        jc      short write_one_done
        mov     cs:[registers+si], al
        mov     bl, al
        call    write_hardware_single
write_one_done:
        pop     si
        pop     ax
        iret

ril_read_range:
        push    ax
        push    cx
        push    di
        push    si
        mov     di, bx
        mov     bl, ch
        call    lookup_register
        jc      short read_range_done
        xor     ch, ch
read_range_loop:
        jcxz    short read_range_done
        mov     al, cs:[registers+si]
        mov     es:[di], al
        inc     si
        inc     di
        dec     cx
        jmp     short read_range_loop
read_range_done:
        pop     si
        pop     di
        pop     cx
        pop     ax
        iret

ril_write_range:
        push    ax
        push    bx
        push    cx
        push    di
        push    si
        mov     di, bx
        mov     bl, ch
        call    lookup_register
        jc      short write_range_done
        xor     ch, ch
write_range_loop:
        jcxz    short write_range_done
        mov     al, es:[di]
        mov     cs:[registers+si], al
        mov     bh, al
        call    write_hardware_indexed
        inc     bl
        inc     si
        inc     di
        dec     cx
        jmp     short write_range_loop
write_range_done:
        pop     si
        pop     di
        pop     cx
        pop     bx
        pop     ax
        iret

ril_read_set:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
read_set_loop:
        jcxz    short read_set_done
        mov     dx, es:[bx]
        mov     al, es:[bx+2]
        push    bx
        mov     bl, al
        call    lookup_register
        pop     bx
        jc      short read_set_next
        mov     al, cs:[registers+si]
        mov     es:[bx+3], al
read_set_next:
        add     bx, 4
        dec     cx
        jmp     short read_set_loop
read_set_done:
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        iret

ril_write_set:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
write_set_loop:
        jcxz    short write_set_done
        mov     dx, es:[bx]
        mov     al, es:[bx+2]
        mov     ah, es:[bx+3]
        push    bx
        mov     bl, al
        call    lookup_register
        jc      short write_set_next
        mov     cs:[registers+si], ah
        mov     bh, ah
        cmp     dx, 20h
        jae     short write_set_single
        call    write_hardware_indexed
        jmp     short write_set_next
write_set_single:
        mov     bl, ah
        call    write_hardware_single
write_set_next:
        pop     bx
        add     bx, 4
        dec     cx
        jmp     short write_set_loop
write_set_done:
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        iret

ril_restore_defaults:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        push    si
        push    ds
        push    es
        push    cs
        pop     ds
        push    cs
        pop     es
        mov     si, offset defaults
        mov     di, offset registers
        mov     cx, 63
        cld
        rep     movsb
        test    cs:[default_defined], 01h
        jz      short restore_no_crtc
        xor     dx, dx
        xor     si, si
        mov     cx, 25
        call    restore_indexed_group
restore_no_crtc:
        test    cs:[default_defined], 02h
        jz      short restore_no_seq
        mov     dx, 8
        mov     si, 25
        mov     cx, 5
        call    restore_indexed_group
restore_no_seq:
        test    cs:[default_defined], 04h
        jz      short restore_no_graphics
        mov     dx, 10h
        mov     si, 30
        mov     cx, 9
        call    restore_indexed_group
restore_no_graphics:
        test    cs:[default_defined], 08h
        jz      short restore_no_attribute
        mov     dx, 18h
        mov     si, 39
        mov     cx, 20
        call    restore_indexed_group
restore_no_attribute:
        test    cs:[default_defined], 10h
        jz      short restore_no_misc
        mov     dx, 20h
        mov     bl, cs:[registers+59]
        call    write_hardware_single
restore_no_misc:
        test    cs:[default_defined], 20h
        jz      short restore_no_feature
        mov     dx, 28h
        mov     bl, cs:[registers+60]
        call    write_hardware_single
restore_no_feature:
        pop     es
        pop     ds
        pop     si
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        iret

ril_define_defaults:
        push    ax
        push    bx
        push    cx
        push    di
        push    si
        mov     di, bx
        xor     bl, bl
        call    lookup_register
        jc      short define_done
        mov     cx, 1
        cmp     dx, 20h
        jae     short define_copy
        mov     cx, 25
        cmp     dx, 8
        jne     short define_graphics
        mov     cx, 5
        jmp     short define_copy
define_graphics:
        cmp     dx, 10h
        jne     short define_attribute
        mov     cx, 9
        jmp     short define_copy
define_attribute:
        mov     cx, 20
define_copy:
        mov     al, es:[di]
        mov     cs:[defaults+si], al
        inc     di
        inc     si
        loop    define_copy
        mov     cl, dl
        shr     cl, 1
        shr     cl, 1
        shr     cl, 1
        mov     al, 1
        shl     al, cl
        or      cs:[default_defined], al
define_done:
        pop     si
        pop     di
        pop     cx
        pop     bx
        pop     ax
        iret

restore_indexed_group proc near
        xor     bl, bl
restore_indexed_loop:
        mov     bh, cs:[registers+si]
        call    write_hardware_indexed
        inc     bl
        inc     si
        loop    restore_indexed_loop
        ret
restore_indexed_group endp

write_hardware_indexed proc near
        push    ax
        push    dx
        or      dx, dx
        jnz     short indexed_not_crtc
        push    es
        xor     ax, ax
        mov     es, ax
        mov     dx, es:[0463h]
        pop     es
        jmp     short indexed_port_ready
indexed_not_crtc:
        cmp     dx, 8
        jne     short indexed_not_seq
        mov     dx, 03c4h
        jmp     short indexed_port_ready
indexed_not_seq:
        cmp     dx, 10h
        jne     short indexed_attribute
        mov     dx, 03ceh
        jmp     short indexed_port_ready
indexed_attribute:
        push    es
        xor     ax, ax
        mov     es, ax
        mov     dx, es:[0463h]
        add     dx, 6
        in      al, dx
        pop     es
        mov     dx, 03c0h
        mov     al, bl
        out     dx, al
        mov     al, bh
        out     dx, al
        pop     dx
        pop     ax
        ret
indexed_port_ready:
        mov     al, bl
        out     dx, al
        inc     dx
        mov     al, bh
        out     dx, al
        pop     dx
        pop     ax
        ret
write_hardware_indexed endp

write_hardware_single proc near
        push    ax
        push    dx
        cmp     dx, 20h
        jne     short single_feature
        mov     dx, 03c2h
        mov     al, bl
        out     dx, al
        jmp     short single_done
single_feature:
        cmp     dx, 28h
        jne     short single_done
        push    es
        xor     ax, ax
        mov     es, ax
        mov     dx, es:[0463h]
        add     dx, 6
        mov     al, bl
        out     dx, al
        pop     es
single_done:
        pop     dx
        pop     ax
        ret
write_hardware_single endp

; Refresh the readable EGA/VGA register banks after BIOS operations.  The two
; graphics-position entries have no portable readback and remain maintained by
; RIL writes, as on adapters where those latches are write-only.
capture_hardware proc near
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    ds
        push    es
        push    cs
        pop     es

        ; CRTC registers 00h..18h; the active base is in the BIOS data area.
        xor     ax, ax
        mov     ds, ax
        mov     dx, [0463h]
        push    cs
        pop     ds
        xor     si, si
        mov     cx, 25
capture_crtc:
        mov     ax, si
        out     dx, al
        inc     dx
        in      al, dx
        dec     dx
        mov     [registers+si], al
        inc     si
        loop    capture_crtc

        ; Sequencer registers 00h..04h.
        mov     dx, 03c4h
        mov     cx, 5
capture_seq:
        mov     ax, si
        sub     ax, 25
        out     dx, al
        inc     dx
        in      al, dx
        dec     dx
        mov     [registers+si], al
        inc     si
        loop    capture_seq

        ; Graphics controller registers 00h..08h.
        mov     dx, 03ceh
        mov     cx, 9
capture_graphics:
        mov     ax, si
        sub     ax, 30
        out     dx, al
        inc     dx
        in      al, dx
        dec     dx
        mov     [registers+si], al
        inc     si
        loop    capture_graphics

        ; Attribute controller registers 00h..13h.  Reading input status 1
        ; resets the address/data flip-flop; index 20h restores video output.
        xor     ax, ax
        mov     ds, ax
        mov     dx, [0463h]
        add     dx, 6
        in      al, dx
        push    cs
        pop     ds
        mov     dx, 03c0h
        mov     cx, 20
capture_attribute:
        mov     ax, si
        sub     ax, 39
        out     dx, al
        mov     dx, 03c1h
        in      al, dx
        mov     [registers+si], al
        mov     dx, 03c0h
        inc     si
        loop    capture_attribute
        mov     al, 20h
        out     dx, al

        mov     dx, 03cch
        in      al, dx
        mov     [registers+59], al
        mov     dx, 03cah
        in      al, dx
        mov     [registers+60], al

        pop     es
        pop     ds
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
capture_hardware endp

; Some BIOSes do not expose attribute-controller readback reliably.  Preserve
; the defined result of the standard set-one-palette-register call explicitly.
track_bios_palette proc near
        cmp     byte ptr cs:[bios_ax+1], 10h
        jne     short track_palette_done
        cmp     byte ptr cs:[bios_ax], 00h
        jne     short track_palette_done
        push    ax
        push    bx
        push    si
        mov     bx, cs:[bios_bx]
        cmp     bl, 20
        jae     short track_palette_pop
        xor     ah, ah
        mov     al, bl
        mov     si, ax
        mov     cs:[registers+39+si], bh
track_palette_pop:
        pop     si
        pop     bx
        pop     ax
track_palette_done:
        ret
track_bios_palette endp

resident_end label byte

initialize proc near
        les     bx, cs:[request_ptr]
        call    parse_options
        jc      short initialize_fail

        ; Require EGA/VGA BIOS support.
        mov     ah, 12h
        mov     bl, 10h
        int     10h
        cmp     bl, 10h
        je      short initialize_fail

        ; Reject a conflicting or existing multiplex owner.
        mov     ah, cs:[multiplex]
        xor     al, al
        int     2fh
        or      al, al
        jne     short initialize_fail

        mov     ax, 3510h
        int     21h
        mov     word ptr cs:[old_int10], bx
        mov     word ptr cs:[old_int10+2], es
        call    capture_hardware
        mov     ax, 352fh
        int     21h
        mov     word ptr cs:[old_int2f], bx
        mov     word ptr cs:[old_int2f+2], es
        push    ds
        push    cs
        pop     ds
        mov     dx, offset int10_handler
        mov     ax, 2510h
        int     21h
        mov     dx, offset int2f_handler
        mov     ax, 252fh
        int     21h
        pop     ds

        les     bx, cs:[request_ptr]
        mov     word ptr es:[bx+14], offset resident_end
        mov     word ptr es:[bx+16], cs
        mov     word ptr es:[bx+3], 0100h
        ret
initialize_fail:
        les     bx, cs:[request_ptr]
        mov     word ptr es:[bx+14], 0
        mov     word ptr es:[bx+16], cs
        mov     word ptr es:[bx+3], 08103h
        ret
initialize endp

; Parse the optional FUNC=80..FF hexadecimal multiplex number.
parse_options proc near
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    ds
        les     bx, cs:[request_ptr]
        lds     si, es:[bx+12h]
parse_scan:
        lodsb
        or      al, al
        jz      short parse_ok
        cmp     al, 0dh
        je      short parse_ok
        and     al, 0dfh
        cmp     al, 'F'
        jne     short parse_scan
        cmp     byte ptr [si], 'U'
        je      short parse_func
        cmp     byte ptr [si], 'u'
        jne     short parse_scan
parse_func:
        inc     si
        mov     ax, [si]
        and     ax, 0dfdfh
        cmp     ax, 'CN'
        jne     short parse_scan
        add     si, 2
        cmp     byte ptr [si], '='
        jne     short parse_fail
        inc     si
        lodsb
        call    hex_digit
        jc      short parse_fail
        mov     dl, al
        shl     dl, 1
        shl     dl, 1
        shl     dl, 1
        shl     dl, 1
        lodsb
        call    hex_digit
        jc      short parse_fail
        or      dl, al
        cmp     dl, 80h
        jb      short parse_fail
        mov     cs:[multiplex], dl
parse_ok:
        clc
        jmp     short parse_exit
parse_fail:
        stc
parse_exit:
        pop     ds
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
parse_options endp

hex_digit proc near
        and     al, 0dfh
        cmp     al, '0'
        jb      short hex_bad
        cmp     al, '9'
        jbe     short hex_number
        cmp     al, 'A'
        jb      short hex_bad
        cmp     al, 'F'
        ja      short hex_bad
        sub     al, 'A'-10
        clc
        ret
hex_number:
        sub     al, '0'
        clc
        ret
hex_bad:
        stc
        ret
hex_digit endp

        end     device_header
