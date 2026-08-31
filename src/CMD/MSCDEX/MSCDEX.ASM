; MS-DOS 6 compatible CD-ROM redirector loader and INT 2Fh interface.
;
; Hardware-specific CD-ROM drivers remain separate.  MSCDEX discovers their
; character-device headers by /D:name and publishes the standard 15xxh API.

MAX_NAMES   EQU 8
MAX_DRIVES  EQU 26
MAX_BUFFERS EQU 16

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
        mov     al,cs:driver_count
        mov     cs:name_count,al
        mov     cs:driver_count,0
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
        mov     al,es:[di+21]         ; CD-ROM header number of subunits
        or      al,al
        jnz     short driver_units_known
        mov     al,1
driver_units_known:
        mov     cs:found_units,al
        mov     cs:found_subunit,0
driver_add_unit:
        mov     al,cs:driver_count
        cmp     al,MAX_DRIVES
        jae     drive_range_error
        xor     ah,ah
        mov     si,ax
        mov     al,cs:found_subunit
        mov     cs:driver_subunits[si],al
        shl     si,1
        mov     cs:driver_offsets[si],di
        mov     cs:driver_segments[si],es
        inc     cs:driver_count
        inc     cs:found_subunit
        mov     al,cs:found_subunit
        cmp     al,cs:found_units
        jb      driver_add_unit
        inc     bx
        cmp     bl,cs:name_count
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
drive_range_error:
        mov     dx,OFFSET drive_range_msg
        call    print_dollar
        mov     al,1
        jmp     terminate
drive_range_ok:
        cmp     cs:use_ems,0
        je      short cache_storage_ready
        call    initialize_ems_cache
        jnc     short cache_storage_ready
        mov     dx,OFFSET no_ems_msg
        call    print_dollar
        mov     al,1
        jmp     terminate
cache_storage_ready:
        ; Publish the first assigned drive letter in each unique device header.
        xor     si,si
        xor     bx,bx
publish_driver_letters:
        cmp     bl,cs:driver_count
        jae     short driver_letters_done
        cmp     cs:driver_subunits[bx],0
        jne     short publish_next_drive
        mov     di,cs:driver_offsets[si]
        mov     ax,cs:driver_segments[si]
        mov     es,ax
        mov     al,cs:first_drive
        add     al,bl
        inc     al
        mov     es:[di+20],al
publish_next_drive:
        inc     bx
        add     si,2
        jmp     publish_driver_letters
driver_letters_done:

        mov     ax,352fh
        int     21h
        mov     cs:old_2f_off,bx
        mov     cs:old_2f_seg,es
        push    cs
        pop     ds
        mov     dx,OFFSET int2f_handler
        mov     ax,252fh
        int     21h
        call    install_redirected_drives

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
        cmp     cs:use_ems,0
        je      installation_line
        mov     dx,OFFSET ems_cache_msg
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
        ; Keep only the selected number of 2 KiB cache buffers resident.
        ; The parser caps the count so the COM image remains below 64 KiB.
        mov     ax,(cache_data-start+100h+15)/16
        cmp     cs:use_ems,0
        jne     short resident_size_ready
        mov     bx,cs:buffer_count
        mov     dx,128                 ; paragraphs per 2048-byte sector
        xchg    ax,bx
        mul     dx
        add     ax,bx
resident_size_ready:
        mov     dx,ax
        mov     ax,3100h
        int     21h

terminate:
        mov     ah,4ch
        int     21h

; ---------------------------------------------------------------------------
; Resident MSCDEX multiplex API
; ---------------------------------------------------------------------------
int2f_handler PROC FAR
        cmp     ah,11h
        je      redirector_dispatch
        cmp     ah,15h
        jne     chain_2f
        cmp     al,00h
        je      api_install_check
        cmp     al,01h
        je      api_device_list
        cmp     al,02h
        je      api_metadata_name
        cmp     al,03h
        je      api_metadata_name
        cmp     al,04h
        je      api_metadata_name
        cmp     al,05h
        je      api_read_vtoc
        cmp     al,06h
        je      api_debug_noop
        cmp     al,07h
        je      api_debug_noop
        cmp     al,0bh
        je      api_drive_check
        cmp     al,0ch
        je      api_version
        cmp     al,0dh
        je      api_drive_list
        cmp     al,0eh
        je      api_volume_preference
        cmp     al,0fh
        je      api_directory_entry
        cmp     al,08h
        je      api_absolute_read
        cmp     al,10h
        je      api_driver_request
        cmp     al,11h
        je      api_smartdrv_cache
chain_2f:
        jmp     dword ptr cs:old_2f_off

redirector_dispatch:
        or      al,al
        jz      redirector_install_check
        cmp     al,05h
        je      redirector_chdir
        cmp     al,06h
        je      redirector_close
        cmp     al,07h
        je      redirector_commit
        cmp     al,08h
        je      redirector_read
        cmp     al,0ch
        je      redirector_disk_info
        cmp     al,16h
        je      redirector_open
        cmp     al,21h
        je      redirector_seek_end
        cmp     al,2eh
        je      redirector_open
        jmp     chain_2f

redirector_install_check:
        mov     al,0ffh
        iret

redirector_chdir:
redirector_commit:
        jmp     api_return_clear

redirector_disk_info:
        ; One 2048-byte sector per allocation unit; report read-only space.
        mov     ax,1
        mov     bx,0ffffh
        mov     cx,2048
        xor     dx,dx
        jmp     api_return_clear

redirector_close:
        cmp     word ptr es:[di],0
        je      redirector_close_done
        dec     word ptr es:[di]
redirector_close_done:
        jmp     api_return_clear

redirector_seek_end:
        add     dx,word ptr es:[di+17]
        adc     cx,word ptr es:[di+19]
        mov     word ptr es:[di+21],dx
        mov     word ptr es:[di+23],cx
        jmp     api_return_clear

; Resolve the caller's canonical filename with MSCDEX's ISO API and fill the
; SFT as a read-only remote file.
redirector_open:
        cld
        mov     cs:redir_sft_off,di
        mov     cs:redir_sft_seg,es
        push    ds
        mov     ax,1218h
        int     2fh
        mov     bx,[si+6]
        mov     ax,[si+14]
        mov     es,ax
        mov     al,es:[bx]
        and     al,0dfh
        sub     al,'A'
        cmp     al,cs:first_drive
        jb      redirector_open_not_ours
        mov     dl,cs:first_drive
        add     dl,cs:driver_count
        cmp     al,dl
        jae     redirector_open_not_ours
        xor     cx,cx
        mov     cl,al
        mov     cs:redir_open_drive,cl
        add     bx,2
        push    cs
        pop     si
        mov     di,OFFSET vtoc_buffer
        mov     cs:redir_direct_io,1
        mov     ax,150fh
        call    redirector_nested_int2f
        mov     cs:redir_direct_io,0
        jnc     short redirector_open_lookup_ok
        pop     ds
        jmp     redirector_open_failed
redirector_open_lookup_ok:
        pop     ds
        test    byte ptr cs:vtoc_buffer+25,2
        jnz     redirector_open_is_dir
        mov     di,cs:redir_sft_off
        mov     ax,cs:redir_sft_seg
        mov     es,ax
        or      byte ptr es:[di+2],2
        mov     byte ptr es:[di+4],1
        mov     ax,8040h
        xor     bx,bx
        mov     bl,cs:redir_open_drive
        or      ax,bx
        mov     es:[di+5],ax
        mov     word ptr es:[di+13],0
        mov     word ptr es:[di+15],0
        mov     ax,word ptr cs:vtoc_buffer+10
        mov     word ptr es:[di+17],ax
        mov     ax,word ptr cs:vtoc_buffer+12
        mov     word ptr es:[di+19],ax
        mov     word ptr es:[di+21],0
        mov     word ptr es:[di+23],0
        mov     ax,word ptr cs:vtoc_buffer+2
        mov     word ptr es:[di+25],ax
        mov     ax,word ptr cs:vtoc_buffer+4
        mov     word ptr es:[di+27],ax
        mov     word ptr es:[di+29],0
        mov     byte ptr es:[di+31],0
        push    es
        push    di
        add     di,32
        mov     cx,11
        mov     al,' '
        rep     stosb
        pop     di
        pop     es
        mov     cx,1
        xor     ax,ax
        jmp     api_return_clear
redirector_open_not_ours:
        pop     ds
        jmp     chain_2f
redirector_open_is_dir:
        mov     ax,5
        jmp     api_return_carry
redirector_open_failed:
        jmp     api_return_carry

; DOS invokes redirectors with very little stack space.  Run nested MSCDEX
; filesystem work on a private resident stack before returning to DOS.
redirector_nested_int2f PROC NEAR
        pushf
        pop     cs:redir_saved_flags
        cli
        mov     cs:redir_saved_ss,ss
        mov     cs:redir_saved_sp,sp
        push    cs
        pop     ss
        mov     sp,OFFSET redir_stack_top
        push    cs:redir_saved_flags
        popf
        int     2fh
        mov     cs:redir_nested_ax,ax
        pushf
        pop     cs:redir_nested_flags
        cli
        mov     ss,cs:redir_saved_ss
        mov     sp,cs:redir_saved_sp
        push    cs:redir_saved_flags
        popf
        mov     ax,cs:redir_nested_ax
        test    cs:redir_nested_flags,1
        jnz     short redirector_nested_carry
        clc
        ret
redirector_nested_carry:
        stc
        ret
redirector_nested_int2f ENDP

; Copy CX bytes from the ISO extent stored in the SFT to DOS's current DTA.
redirector_read:
        cld
        mov     cs:redir_caller_ds,ds
        mov     cs:redir_entry_bx,bx
        mov     cs:redir_entry_dx,dx
        mov     cs:redir_entry_si,si
        mov     cs:redir_entry_di,di
        mov     cs:redir_entry_es,es
        mov     cs:redir_entry_bp,bp
        mov     cs:redir_sft_off,di
        mov     cs:redir_sft_seg,es
        mov     ax,1218h
        int     2fh
        mov     bx,[si+6]
        mov     ax,[si+14]
        mov     cs:redir_target_off,bx
        mov     cs:redir_target_seg,ax
        mov     ax,cs:redir_sft_seg
        mov     es,ax
        mov     di,cs:redir_sft_off
        mov     ax,word ptr es:[di+17]
        sub     ax,word ptr es:[di+21]
        mov     dx,word ptr es:[di+19]
        sbb     dx,word ptr es:[di+23]
        or      dx,dx
        jnz     redirector_read_count_ready
        cmp     cx,ax
        jbe     redirector_read_count_ready
        mov     cx,ax
redirector_read_count_ready:
        mov     cs:redir_remaining,cx
        mov     cs:redir_completed,0
        or      cx,cx
        jnz     redirector_read_have_bytes
        jmp     redirector_read_done
redirector_read_have_bytes:
redirector_read_loop:
        mov     ax,cs:redir_sft_seg
        mov     es,ax
        mov     di,cs:redir_sft_off
        mov     ax,word ptr es:[di+21]
        mov     dx,word ptr es:[di+23]
        mov     bx,ax
        and     bx,2047
        mov     cs:redir_sector_offset,bx
        mov     cl,11
redirector_read_shift:
        shr     dx,1
        rcr     ax,1
        dec     cl
        jnz     redirector_read_shift
        add     ax,word ptr es:[di+25]
        adc     dx,word ptr es:[di+27]
        push    cs
        pop     es
        mov     bx,OFFSET directory_buffer
        xor     cx,cx
        mov     cl,cs:redir_open_drive
        mov     di,ax
        mov     si,dx
        mov     dx,1
        mov     ax,1508h
        mov     cs:redir_direct_io,1
        call    redirector_nested_int2f
        mov     cs:redir_direct_io,0
        jc      redirector_read_error
        mov     ax,2048
        sub     ax,cs:redir_sector_offset
        cmp     ax,cs:redir_remaining
        jbe     redirector_read_piece_ready
        mov     ax,cs:redir_remaining
redirector_read_piece_ready:
        mov     cs:redir_piece,ax
        push    cs
        pop     ds
        mov     si,OFFSET directory_buffer
        add     si,cs:redir_sector_offset
        mov     es,cs:redir_target_seg
        mov     di,cs:redir_target_off
        mov     cx,ax
        rep     movsb
        mov     cs:redir_target_off,di
        mov     ax,cs:redir_piece
        add     cs:redir_completed,ax
        sub     cs:redir_remaining,ax
        mov     bx,cs:redir_sft_off
        mov     es,cs:redir_sft_seg
        add     word ptr es:[bx+21],ax
        adc     word ptr es:[bx+23],0
        cmp     cs:redir_remaining,0
        jne     redirector_read_loop
redirector_read_done:
        mov     cx,cs:redir_completed
        mov     ds,cs:redir_caller_ds
        mov     bx,cs:redir_entry_bx
        mov     dx,cs:redir_entry_dx
        mov     si,cs:redir_entry_si
        mov     di,cs:redir_entry_di
        mov     es,cs:redir_entry_es
        mov     bp,cs:redir_entry_bp
        xor     ax,ax
        jmp     api_return_clear
redirector_read_error:
        mov     ds,cs:redir_caller_ds
        mov     bx,cs:redir_entry_bx
        mov     dx,cs:redir_entry_dx
        mov     si,cs:redir_entry_si
        mov     di,cs:redir_entry_di
        mov     es,cs:redir_entry_es
        mov     bp,cs:redir_entry_bp
        mov     ax,21
        jmp     api_return_carry

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
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        mov     di,bx
        xor     cx,cx
        mov     cl,cs:driver_count
        xor     si,si
        xor     dx,dx
api_device_next:
        mov     bx,dx
        mov     al,cs:driver_subunits[bx]
        mov     byte ptr es:[di],al
        mov     ax,cs:driver_offsets[si]
        mov     es:[di+1],ax
        mov     ax,cs:driver_segments[si]
        mov     es:[di+3],ax
        add     di,5
        add     si,2
        inc     dx
        loop    api_device_next
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
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

api_debug_noop:
        xor     ax,ax
        jmp     api_return_clear

; Private cooperation point used by SMARTDRV.EXE.  BX=0 disables the CD
; sector cache, BX=1 enables it, and BX=2 queries the current state in BX.
api_smartdrv_cache:
        cmp     bx,2
        je      short api_smartdrv_query
        cmp     bx,1
        ja      short api_smartdrv_bad_function
        mov     cs:cache_enabled,bl
        call    invalidate_sector_cache
api_smartdrv_query:
        xor     bx,bx
        mov     bl,cs:cache_enabled
        xor     ax,ax
        jmp     api_return_clear
api_smartdrv_bad_function:
        mov     ax,1
        jmp     api_return_carry

invalidate_sector_cache PROC NEAR
        push    ax
        push    cx
        push    di
        push    es
        push    cs
        pop     es
        mov     di,OFFSET cache_valid
        mov     cx,MAX_BUFFERS
        xor     al,al
        rep     stosb
        pop     es
        pop     di
        pop     cx
        pop     ax
        ret
invalidate_sector_cache ENDP

; AX=150Eh, BX=0 get or 1 set, CX=drive, DX=preference.  The supported DOS
; 6.22 preferences are primary ISO (0100h) and shift-JIS supplementary (0201h).
api_volume_preference:
        push    si
        mov     ax,cx
        xor     si,si
        mov     si,ax
        xor     ax,ax
        mov     al,cs:first_drive
        sub     si,ax
        jc      short api_preference_bad_drive
        xor     ax,ax
        mov     al,cs:driver_count
        cmp     si,ax
        jae     short api_preference_bad_drive
        shl     si,1
        or      bx,bx
        jz      short api_preference_get
        cmp     bx,1
        jne     short api_preference_bad_function
        cmp     dx,0100h
        je      short api_preference_set
        cmp     dx,0201h
        jne     short api_preference_bad_function
api_preference_set:
        mov     cs:volume_preferences[si],dx
        xor     ax,ax
        pop     si
        jmp     api_return_clear
api_preference_get:
        mov     dx,cs:volume_preferences[si]
        xor     ax,ax
        pop     si
        jmp     api_return_clear
api_preference_bad_drive:
        xor     dx,dx
        mov     ax,000fh
        pop     si
        jmp     api_return_carry
api_preference_bad_function:
        xor     dx,dx
        mov     ax,0001h
        pop     si
        jmp     api_return_carry

; AX=1505h, ES:BX=2048-byte buffer, CX=drive, DX=descriptor index.
api_read_vtoc:
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        call    read_vtoc_sector
        jc      short api_vtoc_failed
        mov     bx,word ptr cs:read_request+14
        mov     ax,word ptr cs:read_request+16
        mov     es,ax
        mov     al,es:[bx]
        xor     ah,ah
        cmp     al,1
        je      short api_vtoc_save
        cmp     al,0ffh
        je      short api_vtoc_save
        xor     ax,ax
api_vtoc_save:
        mov     cs:api_result,ax
        mov     cs:api_failed,0
        jmp     short api_vtoc_restore
api_vtoc_failed:
        mov     cs:api_result,ax
        mov     cs:api_failed,1
api_vtoc_restore:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        mov     ax,cs:api_result
        cmp     cs:api_failed,0
        jne     api_return_carry
        jmp     api_return_clear

; AX=1502h..1504h.  Read the primary ISO descriptor and return its fixed-width
; copyright, abstract, or bibliographic filename as a trimmed ASCIIZ string.
api_metadata_name:
        mov     cs:metadata_function,al
        mov     cs:metadata_target_off,bx
        mov     cs:metadata_target_seg,es
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        push    cs
        pop     es
        mov     bx,OFFSET vtoc_buffer
        call    load_preferred_vtoc
        jc      short api_metadata_failed
        mov     si,702
        cmp     cs:metadata_function,2
        je      short api_metadata_offset_ready
        mov     si,739
        cmp     cs:metadata_function,3
        je      short api_metadata_offset_ready
        mov     si,776
api_metadata_offset_ready:
        add     si,OFFSET vtoc_buffer
        mov     ax,cs:metadata_target_seg
        mov     es,ax
        mov     di,cs:metadata_target_off
        mov     cx,37
api_metadata_copy:
        mov     al,cs:[si]
        inc     si
        cmp     al,' '
        je      short api_metadata_terminate
        or      al,al
        jz      short api_metadata_terminate
        stosb
        loop    api_metadata_copy
api_metadata_terminate:
        xor     al,al
        stosb
        xor     ax,ax
        mov     cs:api_result,ax
        mov     cs:api_failed,0
        jmp     short api_metadata_restore
api_metadata_failed:
        mov     cs:api_result,ax
        mov     cs:api_failed,1
api_metadata_restore:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        mov     ax,cs:api_result
        cmp     cs:api_failed,0
        jne     api_return_carry
        jmp     api_return_clear

; AX=150Fh, CX=drive, ES:BX=ASCIIZ path, SI:DI=destination record.  Walk ISO
; directory records from the PVD root and copy the matching on-disc record.
api_directory_entry:
        mov     cs:lookup_drive,cx
        mov     cs:lookup_path_off,bx
        mov     cs:lookup_path_seg,es
        mov     cs:lookup_output_off,di
        mov     cs:lookup_output_seg,si
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        push    cs
        pop     es
        mov     bx,OFFSET vtoc_buffer
        call    load_preferred_vtoc
        jc      lookup_failed
        cmp     byte ptr cs:vtoc_buffer,1
        je      short lookup_descriptor_type_ok
        cmp     byte ptr cs:vtoc_buffer,2
        jne     lookup_not_ready
lookup_descriptor_type_ok:
        cmp     word ptr cs:vtoc_buffer+1,'DC'
        jne     lookup_not_ready
        cmp     word ptr cs:vtoc_buffer+3,'00'
        jne     lookup_not_ready
        cmp     byte ptr cs:vtoc_buffer+5,'1'
        jne     lookup_not_ready
        mov     ax,word ptr cs:vtoc_buffer+158
        mov     word ptr cs:lookup_extent,ax
        mov     ax,word ptr cs:vtoc_buffer+160
        mov     word ptr cs:lookup_extent+2,ax
        mov     ax,word ptr cs:vtoc_buffer+166
        mov     word ptr cs:lookup_length,ax
        mov     ax,word ptr cs:vtoc_buffer+168
        mov     word ptr cs:lookup_length+2,ax

lookup_component:
        mov     ax,cs:lookup_path_seg
        mov     ds,ax
        mov     si,cs:lookup_path_off
lookup_skip_separator:
        mov     al,[si]
        cmp     al,'\'
        jne     short lookup_component_start
        inc     si
        jmp     lookup_skip_separator
lookup_component_start:
        or      al,al
        jz      lookup_return_root
        push    cs
        pop     es
        mov     di,OFFSET lookup_component_name
        xor     cx,cx
lookup_collect:
        mov     al,[si]
        or      al,al
        jz      short lookup_component_done
        cmp     al,'\'
        je      short lookup_component_done
        cmp     cx,31
        jae     lookup_not_found
        cmp     al,'a'
        jb      short lookup_store_component
        cmp     al,'z'
        ja      short lookup_store_component
        sub     al,20h
lookup_store_component:
        stosb
        inc     si
        inc     cx
        jmp     lookup_collect
lookup_component_done:
        mov     cs:lookup_component_len,cl
        mov     cs:lookup_path_off,si
        mov     cs:lookup_more,0
        cmp     byte ptr [si],'\'
        jne     short lookup_scan_start
        mov     cs:lookup_more,1
lookup_scan_start:
        mov     ax,word ptr cs:lookup_length
        mov     word ptr cs:lookup_bytes_left,ax
        mov     ax,word ptr cs:lookup_length+2
        mov     word ptr cs:lookup_bytes_left+2,ax
        mov     word ptr cs:lookup_sector_index,0

lookup_next_sector:
        mov     ax,word ptr cs:lookup_bytes_left
        or      ax,word ptr cs:lookup_bytes_left+2
        jz      lookup_not_found
        mov     di,word ptr cs:lookup_extent
        mov     si,word ptr cs:lookup_extent+2
        add     di,cs:lookup_sector_index
        adc     si,0
        push    cs
        pop     es
        mov     bx,OFFSET directory_buffer
        mov     cx,cs:lookup_drive
        call    read_raw_sector
        jc      lookup_failed
        mov     word ptr cs:lookup_record_off,0
lookup_next_record:
        mov     bx,cs:lookup_record_off
        cmp     bx,2048
        jb      short lookup_record_in_sector
        jmp     lookup_advance_sector
lookup_record_in_sector:
        mov     al,cs:directory_buffer[bx]
        or      al,al
        jnz     short lookup_record_present
        jmp     lookup_advance_sector
lookup_record_present:
        xor     ah,ah
        mov     cs:lookup_record_len,ax
        mov     al,cs:directory_buffer[bx+32]
        cmp     al,cs:lookup_component_len
        jae     short lookup_record_long_enough
        jmp     lookup_record_miss
lookup_record_long_enough:
        xor     si,si
lookup_compare_name:
        xor     ax,ax
        mov     al,cs:lookup_component_len
        cmp     si,ax
        jae     short lookup_name_prefix
        mov     di,bx
        add     di,33
        add     di,si
        mov     al,cs:directory_buffer[di]
        cmp     al,'a'
        jb      short lookup_compare_folded
        cmp     al,'z'
        ja      short lookup_compare_folded
        sub     al,20h
lookup_compare_folded:
        cmp     al,cs:lookup_component_name[si]
        je      short lookup_name_character_ok
        jmp     lookup_record_miss
lookup_name_character_ok:
        inc     si
        jmp     lookup_compare_name
lookup_name_prefix:
        mov     al,cs:directory_buffer[bx+32]
        cmp     al,cs:lookup_component_len
        je      short lookup_record_found
        mov     di,bx
        add     di,33
        add     di,si
        cmp     byte ptr cs:directory_buffer[di],';'
        jne     short lookup_record_miss
lookup_record_found:
        cmp     cs:lookup_more,0
        je      short lookup_copy_record
        test    byte ptr cs:directory_buffer[bx+25],2
        jz      lookup_not_found
        mov     ax,word ptr cs:directory_buffer[bx+2]
        mov     word ptr cs:lookup_extent,ax
        mov     ax,word ptr cs:directory_buffer[bx+4]
        mov     word ptr cs:lookup_extent+2,ax
        mov     ax,word ptr cs:directory_buffer[bx+10]
        mov     word ptr cs:lookup_length,ax
        mov     ax,word ptr cs:directory_buffer[bx+12]
        mov     word ptr cs:lookup_length+2,ax
        jmp     lookup_component
lookup_copy_record:
        push    cs
        pop     ds
        mov     si,OFFSET directory_buffer
        add     si,bx
        mov     ax,cs:lookup_output_seg
        mov     es,ax
        mov     di,cs:lookup_output_off
        mov     cx,cs:lookup_record_len
        rep     movsb
        mov     ax,1
        mov     cs:api_result,ax
        mov     cs:api_failed,0
        jmp     short lookup_restore
lookup_record_miss:
        mov     ax,cs:lookup_record_len
        add     cs:lookup_record_off,ax
        jmp     lookup_next_record
lookup_advance_sector:
        inc     cs:lookup_sector_index
        sub     word ptr cs:lookup_bytes_left,2048
        sbb     word ptr cs:lookup_bytes_left+2,0
        jnc     lookup_next_sector
        mov     word ptr cs:lookup_bytes_left,0
        mov     word ptr cs:lookup_bytes_left+2,0
        jmp     lookup_next_sector
lookup_return_root:
        push    cs
        pop     ds
        mov     si,OFFSET vtoc_buffer+156
        mov     ax,cs:lookup_output_seg
        mov     es,ax
        mov     di,cs:lookup_output_off
        xor     cx,cx
        mov     cl,cs:vtoc_buffer+156
        rep     movsb
        mov     cs:api_result,1
        mov     cs:api_failed,0
        jmp     short lookup_restore
lookup_not_ready:
        mov     ax,0015h
        jmp     short lookup_store_failure
lookup_not_found:
        mov     ax,0002h
        jmp     short lookup_store_failure
lookup_failed:
        cmp     ax,000fh
        je      short lookup_store_failure
        mov     ax,0015h
lookup_store_failure:
        mov     cs:api_result,ax
        mov     cs:api_failed,1
lookup_restore:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        mov     ax,cs:api_result
        cmp     cs:api_failed,0
        jne     api_return_carry
        jmp     api_return_clear

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
        mov     bx,ax
        mov     al,cs:driver_subunits[bx]
        mov     cs:request_subunit,al
        mov     ax,bx
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
        mov     al,cs:request_subunit
        mov     byte ptr es:[bx+1],al
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

; Read volume descriptor 16+DX to ES:BX through the selected CX drive.
read_vtoc_sector PROC NEAR
        mov     ax,dx
        add     ax,16
        mov     di,ax
        xor     si,si
        jmp     read_raw_sector
read_vtoc_sector ENDP

; Load the descriptor selected by function 150Eh into vtoc_buffer.  SVD mode
; scans for type 2 and falls back to the first PVD at the terminator.
load_preferred_vtoc PROC NEAR
        mov     cs:preferred_drive,cx
        mov     ax,cx
        xor     dx,dx
        mov     dl,cs:first_drive
        sub     ax,dx
        jnc     short preferred_check_high
        jmp     preferred_invalid_drive
preferred_check_high:
        xor     dx,dx
        mov     dl,cs:driver_count
        cmp     ax,dx
        jb      short preferred_drive_valid
        jmp     preferred_invalid_drive
preferred_drive_valid:
        shl     ax,1
        mov     si,ax
        mov     ax,cs:volume_preferences[si]
        mov     cs:preferred_setting,ax
        mov     cs:preferred_fallback,0
        xor     dx,dx
preferred_scan:
        push    cs
        pop     es
        mov     bx,OFFSET vtoc_buffer
        call    read_vtoc_sector
        jc      short preferred_done
        mov     al,cs:vtoc_buffer
        cmp     al,1
        je      short preferred_primary
        cmp     al,2
        je      short preferred_supplementary
        cmp     al,0ffh
        je      short preferred_terminator
preferred_next:
        inc     dx
        cmp     dx,32
        jb      preferred_scan
        jmp     short preferred_not_ready
preferred_primary:
        cmp     cs:preferred_setting,0100h
        je      short preferred_success
        push    cs
        pop     ds
        push    cs
        pop     es
        mov     si,OFFSET vtoc_buffer
        mov     di,OFFSET primary_vtoc_buffer
        mov     cx,1024
        rep     movsw
        mov     cs:preferred_fallback,1
        mov     cx,cs:preferred_drive
        jmp     preferred_next
preferred_supplementary:
        cmp     cs:preferred_setting,0201h
        je      short preferred_success
        jmp     preferred_next
preferred_terminator:
        cmp     cs:preferred_fallback,0
        je      short preferred_not_ready
        push    cs
        pop     ds
        push    cs
        pop     es
        mov     si,OFFSET primary_vtoc_buffer
        mov     di,OFFSET vtoc_buffer
        mov     cx,1024
        rep     movsw
preferred_success:
        xor     ax,ax
        clc
preferred_done:
        ret
preferred_invalid_drive:
        mov     ax,000fh
        stc
        ret
preferred_not_ready:
        mov     ax,0015h
        stc
        ret
load_preferred_vtoc ENDP

; Read one cooked sector SI:DI from CX drive into ES:BX.
read_raw_sector PROC NEAR
        mov     cs:cache_target_off,bx
        mov     cs:cache_target_seg,es
        mov     word ptr cs:read_request+14,bx
        mov     word ptr cs:read_request+16,es
        mov     cs:cache_drive,cx
        mov     word ptr cs:cache_sector,di
        mov     word ptr cs:cache_sector+2,si
        cmp     cs:redir_direct_io,0
        je      short cache_scan
        jmp     NEAR PTR cache_miss
cache_scan:
        cmp     cs:cache_enabled,0
        jne     short cache_scan_enabled
        jmp     NEAR PTR cache_miss
cache_scan_enabled:
        xor     dx,dx
cache_find_loop:
        cmp     dx,cs:buffer_count
        jae     short cache_miss
        mov     bx,dx
        cmp     byte ptr cs:cache_valid[bx],0
        je      short cache_find_next
        shl     bx,1
        mov     ax,cs:cache_drive
        cmp     cs:cache_drives[bx],ax
        jne     short cache_find_next
        shl     bx,1
        mov     ax,word ptr cs:cache_sector
        cmp     word ptr cs:cache_sectors[bx],ax
        jne     short cache_find_next
        mov     ax,word ptr cs:cache_sector+2
        cmp     word ptr cs:cache_sectors[bx+2],ax
        jne     short cache_find_next
        mov     ax,dx
        mov     cl,11
        shl     ax,cl
        mov     si,OFFSET cache_data
        add     si,ax
        cmp     cs:use_ems,0
        je      short cache_hit_conventional
        mov     ax,dx
        call    map_ems_cache_slot
        mov     si,ax
        mov     ax,cs:ems_frame
        mov     ds,ax
        jmp     short cache_hit_copy
cache_hit_conventional:
        push    cs
        pop     ds
cache_hit_copy:
        mov     ax,cs:cache_target_seg
        mov     es,ax
        mov     di,cs:cache_target_off
        mov     cx,1024
        rep     movsw
        push    cs
        pop     ds
        cmp     cs:use_ems,0
        je      short cache_hit_complete
        call    restore_ems_cache_map
cache_hit_complete:
        xor     ax,ax
        clc
        ret
cache_find_next:
        inc     dx
        jmp     cache_find_loop
cache_miss:
        mov     bx,cs:cache_target_off
        mov     es,cs:cache_target_seg
        mov     cx,cs:cache_drive
        mov     di,word ptr cs:cache_sector
        mov     si,word ptr cs:cache_sector+2
        mov     word ptr cs:read_request+14,bx
        mov     word ptr cs:read_request+16,es
        mov     word ptr cs:read_request+18,1
        mov     word ptr cs:read_request+20,di
        mov     word ptr cs:read_request+22,si
        push    cs
        pop     es
        mov     bx,OFFSET read_request
        call    forward_driver_request
        jnc     short read_raw_done
        cmp     ax,000fh
        je      short read_raw_done
        mov     ax,0015h
        stc
read_raw_done:
        jc      read_raw_return
        cmp     cs:redir_direct_io,0
        je      short read_raw_cache_store
        jmp     NEAR PTR read_raw_direct_done
read_raw_cache_store:
        cmp     cs:cache_enabled,0
        jne     short read_raw_cache_enabled
        jmp     NEAR PTR read_raw_direct_done
read_raw_cache_enabled:
        xor     ax,ax
        mov     al,cs:cache_next
        xor     dx,dx
        mov     dl,byte ptr cs:buffer_count
        inc     cs:cache_next
        cmp     cs:cache_next,dl
        jb      short cache_next_ready
        mov     cs:cache_next,0
cache_next_ready:
        mov     bx,ax
        mov     byte ptr cs:cache_valid[bx],1
        shl     bx,1
        mov     dx,cs:cache_drive
        mov     cs:cache_drives[bx],dx
        shl     bx,1
        mov     dx,word ptr cs:cache_sector
        mov     word ptr cs:cache_sectors[bx],dx
        mov     dx,word ptr cs:cache_sector+2
        mov     word ptr cs:cache_sectors[bx+2],dx
        mov     cl,11
        shl     ax,cl
        mov     di,OFFSET cache_data
        add     di,ax
        cmp     cs:use_ems,0
        je      short cache_store_conventional
        xor     ah,ah
        mov     al,cs:cache_next
        or      al,al
        jnz     short cache_store_slot_ready
        mov     al,byte ptr cs:buffer_count
cache_store_slot_ready:
        dec     al
        xor     ah,ah
        call    map_ems_cache_slot
        mov     di,ax
        mov     ax,cs:ems_frame
        mov     es,ax
        jmp     short cache_store_copy
cache_store_conventional:
        push    cs
        pop     es
cache_store_copy:
        mov     ax,cs:cache_target_seg
        mov     ds,ax
        mov     si,cs:cache_target_off
        mov     cx,1024
        rep     movsw
        push    cs
        pop     ds
        push    cs
        pop     es
        cmp     cs:use_ems,0
        je      short cache_store_complete
        call    restore_ems_cache_map
cache_store_complete:
read_raw_direct_done:
        xor     ax,ax
        clc
read_raw_return:
        ret
read_raw_sector ENDP

; Publish each assigned CD-ROM letter as a read-only network-style CDS.  DOS
; then routes ordinary path operations through the 11xx redirector calls.
install_redirected_drives PROC NEAR
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    es
        mov     ah,52h
        int     21h
        mov     dl,es:[bx+33]
        mov     al,cs:first_drive
        add     al,cs:driver_count
        cmp     al,dl
        ja      install_redirected_done
        les     di,es:[bx+22]
        xor     ax,ax
        mov     al,cs:first_drive
        mov     cx,88
        mul     cx
        add     di,ax
        xor     cx,cx
        mov     cl,cs:driver_count
        mov     al,cs:first_drive
install_redirected_next:
        mov     ah,al
        add     ah,'A'
        mov     es:[di],ah
        mov     byte ptr es:[di+1],':'
        mov     byte ptr es:[di+2],'\'
        mov     byte ptr es:[di+3],0
        mov     word ptr es:[di+67],0c000h
        mov     word ptr es:[di+69],OFFSET redirector_device
        mov     word ptr es:[di+71],cs
        mov     word ptr es:[di+73],0
        mov     word ptr es:[di+75],0
        mov     word ptr es:[di+77],0
        mov     word ptr es:[di+79],2
        mov     byte ptr es:[di+81],4
        mov     word ptr es:[di+82],0
        mov     word ptr es:[di+84],0
        mov     word ptr es:[di+86],0
        add     di,88
        inc     al
        loop    install_redirected_next
install_redirected_done:
        pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
install_redirected_drives ENDP

initialize_ems_cache PROC NEAR
        mov     ax,4e03h
        int     67h
        or      ah,ah
        jnz     short initialize_ems_failed
        mov     ah,41h
        int     67h
        or      ah,ah
        jnz     short initialize_ems_failed
        mov     cs:ems_frame,bx
        mov     bx,cs:buffer_count
        add     bx,7
        mov     cl,3
        shr     bx,cl
        mov     ah,43h
        int     67h
        or      ah,ah
        jnz     short initialize_ems_failed
        mov     cs:ems_handle,dx
        clc
        ret
initialize_ems_failed:
        stc
        ret
initialize_ems_cache ENDP

; Map the 2 KiB cache slot in AX into EMS physical page zero.  Preserve the
; complete pre-existing map because another resident client may own that page.
map_ems_cache_slot PROC NEAR
        mov     cs:ems_slot,ax
        mov     cs:ems_map_saved,0
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        push    cs
        pop     es
        mov     di,OFFSET ems_saved_map
        mov     ax,4e00h
        int     67h
        or      ah,ah
        jnz     short ems_map_not_saved
        mov     cs:ems_map_saved,1
ems_map_not_saved:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        push    bx
        push    cx
        push    dx
        mov     bx,cs:ems_slot
        mov     ax,bx
        and     ax,7
        mov     cl,11
        shl     ax,cl
        mov     cs:ems_offset,ax
        mov     cl,3
        shr     bx,cl
        mov     dx,cs:ems_handle
        mov     ax,4400h
        int     67h
        pop     dx
        pop     cx
        pop     bx
        mov     ax,cs:ems_offset
        ret
map_ems_cache_slot ENDP

restore_ems_cache_map PROC NEAR
        cmp     cs:ems_map_saved,0
        je      short restore_ems_unmap
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        push    cs
        pop     ds
        mov     si,OFFSET ems_saved_map
        mov     ax,4e01h
        int     67h
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        mov     cs:ems_map_saved,0
        ret
restore_ems_unmap:
        push    bx
        push    dx
        mov     bx,0ffffh
        mov     dx,cs:ems_handle
        mov     ax,4400h
        int     67h
        pop     dx
        pop     bx
        ret
restore_ems_cache_map ENDP

old_2f_off      dw 0
old_2f_seg      dw 0
strategy_entry  dd 0
interrupt_entry dd 0
request_offset  dw 0
request_segment dw 0
request_subunit db 0
api_result      dw 0
api_failed      db 0
metadata_function db 0
metadata_target_off dw 0
metadata_target_seg dw 0
preferred_setting   dw 0
preferred_drive     dw 0
preferred_fallback  db 0
lookup_drive        dw 0
lookup_path_off     dw 0
lookup_path_seg     dw 0
lookup_output_off   dw 0
lookup_output_seg   dw 0
lookup_extent       dd 0
lookup_length       dd 0
lookup_bytes_left   dd 0
lookup_sector_index dw 0
lookup_record_off   dw 0
lookup_record_len   dw 0
lookup_component_len db 0
lookup_more         db 0
lookup_component_name db 31 dup(0)
read_request    db 27,0,80h
                dw 0
                db 8 dup(0)
                db 0                   ; HSG addressing mode
                dw 0,0                 ; transfer offset:segment
                dw 0                   ; sector count
                dd 0                   ; starting sector
                db 0,0,0               ; cooked, no interleave
vtoc_buffer     db 2048 dup(0)
primary_vtoc_buffer db 2048 dup(0)
directory_buffer db 2048 dup(0)
psp_segment     dw 0
driver_offsets  dw MAX_DRIVES dup(0)
driver_segments dw MAX_DRIVES dup(0)
driver_subunits db MAX_DRIVES dup(0)
volume_preferences dw MAX_DRIVES dup(0100h)
driver_count    db 0
name_count      db 0
found_units     db 0
found_subunit   db 0
first_drive     db 0ffh
buffer_count    dw 10
use_ems         db 0
kanji_mode      db 0
share_mode      db 0
verbose         db 0
cache_next      db 0
cache_enabled   db 1
cache_valid     db MAX_BUFFERS dup(0)
cache_drives    dw MAX_BUFFERS dup(0)
cache_sectors   dd MAX_BUFFERS dup(0)
cache_target_off dw 0
cache_target_seg dw 0
cache_drive     dw 0
cache_sector    dd 0
ems_handle      dw 0
ems_frame       dw 0
ems_slot        dw 0
ems_offset      dw 0
ems_map_saved   db 0
        ALIGN   16
ems_saved_map   db 256 dup(0)
redirector_device dd 0ffffffffh
                  dw 0c800h
                  dw 0,0
                  db 'MSCDROM '
redir_sft_off    dw 0
redir_sft_seg    dw 0
redir_open_drive db 0
redir_direct_io  db 0
redir_saved_ss    dw 0
redir_saved_sp    dw 0
redir_saved_flags dw 0
redir_nested_ax   dw 0
redir_nested_flags dw 0
redir_remaining  dw 0
redir_completed  dw 0
redir_target_off dw 0
redir_target_seg dw 0
redir_sector_offset dw 0
redir_piece      dw 0
redir_caller_ds  dw 0
redir_entry_bx   dw 0
redir_entry_dx   dw 0
redir_entry_si   dw 0
redir_entry_di   dw 0
redir_entry_es   dw 0
redir_entry_bp   dw 0
redir_stack      db 2048 dup(0)
redir_stack_top  LABEL BYTE
cache_data      db MAX_BUFFERS*2048 dup(0)
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
        cmp     al,MAX_NAMES
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
        or      cx,cx
        jnz     short parse_letter_colon
        jmp     parse_error
parse_letter_colon:
        cmp     byte ptr es:[si],':'
        jne     parse_error
        inc     si
        dec     cx
        or      cx,cx
        jnz     short parse_letter_value
        jmp     parse_error
parse_letter_value:
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
        cmp     ax,MAX_BUFFERS
        jbe     short parse_buffer_stored
        mov     cs:buffer_count,MAX_BUFFERS
parse_buffer_stored:
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
driver_names       db MAX_NAMES*8 dup(' ')
illegal_help_msg   db "Illegal option '?'",13,10,'$'
usage_msg          db 'usage: MSCDEX [/E/K/S/V] [/D:<driver> ... ] [/L:<letter>] [/M:<buffers>]',13,10,'$'
no_ems_msg         db 'Expanded memory not present or not-usable',13,10,'$'
driver_missing_msg db "Device driver not found: '",'$'
quote_crlf         db "'.",13,10,'No valid CDROM device drivers selected',13,10,'$'
drive_range_msg    db 'Not enough drive letters available',13,10,'$'
already_msg        db 'MSCDEX already installed.',13,10,'$'
version_msg        db 'MSCDEX Version 2.23',13,10,'$'
ems_cache_msg      db 'Cache storage: expanded memory',13,10,'$'
installed_msg      db 'Drive assigned to driver: $'
colon_crlf         db ':',13,10,'$'

CODE ENDS
        END start
