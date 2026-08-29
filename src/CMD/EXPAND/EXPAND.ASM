.model small
.stack 256
.data

signature       db      'SZDD',88h,0f0h,27h,33h
usage           db      'Expands compressed MS-DOS 5.0 files.',13,10
                db      'Usage: EXPAND source [source ...] destination',13,10,'$'
bad_args        db      'Invalid number of parameters',13,10,'$'
bad_wild        db      'Wildcards are not allowed',13,10,'$'
bad_dest        db      'Multiple source files require a destination directory',13,10,'$'
open_error      db      'Unable to open input file',13,10,'$'
format_error    db      'Invalid or truncated compressed file',13,10,'$'
create_error    db      'Unable to create output file',13,10,'$'
write_error     db      'Error writing output file',13,10,'$'

arg_count       db      0
arg_ptrs        dw      32 dup (0)
dest_is_dir     db      0
source_handle   dw      0ffffh
dest_handle     dw      0ffffh
source_time     dw      0
source_date     dw      0
header          db      14 dup (0)
remaining_lo    dw      0
remaining_hi    dw      0
window_pos      dw      0feeh
match_pos       dw      0
match_left      db      0
flag_bits       db      0
flag_mask       db      0
input_pos       dw      0
input_count     dw      0
output_count    dw      0
dest_path       db      128 dup (0)
input_buffer    db      1024 dup (0)
output_buffer   db      1024 dup (0)
window          db      4096 dup (20h)
command_tail    db      128 dup (0)

.code
start:
        cld
        mov     dx,@data
        mov     es,dx
        xor     ch,ch
        mov     cl,ds:[80h]
        mov     al,cl
        mov     es:command_tail,al
        mov     si,81h
        mov     di,offset command_tail+1
        rep     movsb
        mov     ds,dx
        push    ds
        pop     es
main:
        cld
        call    parse_tail
        jc      argument_failure
        cmp     arg_count,1
        jne     not_help
        mov     si,arg_ptrs
        cmp     byte ptr [si],'/'
        jne     not_help
        cmp     byte ptr [si+1],'?'
        jne     not_help
        cmp     byte ptr [si+2],0
        jne     not_help
        mov     dx,offset usage
        mov     ah,9
        int     21h
        jmp     success
not_help:
        cmp     arg_count,2
        jb      argument_failure

        mov     al,arg_count
        xor     ah,ah
        dec     ax
        shl     ax,1
        mov     si,ax
        mov     dx,arg_ptrs[si]
        call    reject_wildcard
        jc      wildcard_failure
        call    has_directory_suffix
        jnc     query_destination
        mov     dest_is_dir,1
query_destination:
        mov     ax,4300h
        int     21h
        jc      destination_checked
        test    cx,10h
        jz      destination_checked
        mov     dest_is_dir,1
destination_checked:
        cmp     arg_count,2
        jbe     process_sources
        cmp     dest_is_dir,1
        jne     destination_failure

process_sources:
        xor     bp,bp
source_loop:
        mov     al,arg_count
        xor     ah,ah
        dec     ax
        cmp     bp,ax
        jae     success
        mov     si,bp
        shl     si,1
        mov     dx,arg_ptrs[si]
        call    reject_wildcard
        jc      wildcard_failure
        call    expand_one
        jc      fatal_exit
        inc     bp
        jmp     source_loop

argument_failure:
        mov     dx,offset bad_args
        jmp     short message_failure
wildcard_failure:
        mov     dx,offset bad_wild
        jmp     short message_failure
destination_failure:
        mov     dx,offset bad_dest
message_failure:
        mov     ah,9
        int     21h
fatal_exit:
        mov     ax,4c01h
        int     21h
success:
        mov     ax,4c00h
        int     21h

; Tokenize the PSP command tail in place. Quotes are accepted for paths even
; though retail DOS filenames normally do not need them.
parse_tail proc near
        xor     ch,ch
        mov     cl,command_tail
        mov     si,offset command_tail+1
        mov     di,offset arg_ptrs
parse_skip:
        jcxz    parse_done
        mov     al,[si]
        cmp     al,' '
        je      parse_skip_one
        cmp     al,9
        jne     parse_token
parse_skip_one:
        inc     si
        dec     cx
        jmp     parse_skip
parse_token:
        cmp     arg_count,32
        jae     parse_bad
        xor     bl,bl
        cmp     byte ptr [si],'"'
        jne     parse_store
        mov     bl,1
        inc     si
        dec     cx
parse_store:
        mov     [di],si
        add     di,2
        inc     arg_count
parse_scan:
        jcxz    parse_terminate
        mov     al,[si]
        cmp     bl,0
        jne     parse_quote
        cmp     al,' '
        je      parse_end_token
        cmp     al,9
        je      parse_end_token
        inc     si
        dec     cx
        jmp     parse_scan
parse_quote:
        cmp     al,'"'
        je      parse_end_quote
        inc     si
        dec     cx
        jmp     parse_scan
parse_end_quote:
        mov     byte ptr [si],0
        inc     si
        dec     cx
        jcxz    parse_done
        mov     al,[si]
        cmp     al,' '
        je      parse_skip
        cmp     al,9
        je      parse_skip
        jmp     parse_bad
parse_end_token:
        mov     byte ptr [si],0
        inc     si
        dec     cx
        jmp     parse_skip
parse_terminate:
        mov     byte ptr [si],0
parse_done:
        clc
        ret
parse_bad:
        stc
        ret
parse_tail endp

reject_wildcard proc near
        push    si
        mov     si,dx
wild_scan:
        lodsb
        or      al,al
        jz      wild_ok
        cmp     al,'*'
        je      wild_bad
        cmp     al,'?'
        jne     wild_scan
wild_bad:
        pop     si
        stc
        ret
wild_ok:
        pop     si
        clc
        ret
reject_wildcard endp

has_directory_suffix proc near
        push    si
        mov     si,dx
suffix_scan:
        mov     al,[si]
        or      al,al
        jz      suffix_end
        inc     si
        jmp     suffix_scan
suffix_end:
        cmp     si,dx
        je      suffix_no
        mov     al,[si-1]
        cmp     al,'\'
        je      suffix_yes
        cmp     al,'/'
        je      suffix_yes
suffix_no:
        pop     si
        clc
        ret
suffix_yes:
        pop     si
        stc
        ret
has_directory_suffix endp

expand_one proc near
        mov     source_handle,0ffffh
        mov     dest_handle,0ffffh
        mov     ax,3d00h
        int     21h
        jc      expand_open_failed
        mov     source_handle,ax
        mov     bx,ax
        mov     ax,5700h
        int     21h
        jc      time_saved
        mov     source_time,cx
        mov     source_date,dx
time_saved:
        mov     bx,source_handle
        mov     dx,offset header
        mov     cx,14
        mov     ah,3fh
        int     21h
        jc      expand_format_failed
        cmp     ax,14
        jne     expand_format_failed
        mov     si,offset header
        mov     di,offset signature
        mov     cx,8
        repe    cmpsb
        jne     expand_format_failed
        cmp     byte ptr header[8],41h
        jne     expand_format_failed
        mov     ax,word ptr header[10]
        mov     remaining_lo,ax
        mov     ax,word ptr header[12]
        mov     remaining_hi,ax

        call    build_destination
        jc      expand_create_failed
        mov     dx,offset dest_path
        xor     cx,cx
        mov     ah,3ch
        int     21h
        jc      expand_create_failed
        mov     dest_handle,ax
        mov     input_pos,0
        mov     input_count,0
        mov     output_count,0
        mov     window_pos,0feeh
        mov     di,offset window
        mov     cx,4096
        mov     al,20h
        rep     stosb

decode_group:
        call    remaining_nonzero
        jz      decode_done
        call    read_byte
        jc      expand_format_failed
        mov     flag_bits,al
        mov     flag_mask,1
decode_token:
        call    remaining_nonzero
        jz      decode_done
        mov     al,flag_bits
        test    al,flag_mask
        jz      decode_match
        call    read_byte
        jc      expand_format_failed
        call    emit_byte
        jc      expand_write_failed
        jmp     short decode_next
decode_match:
        call    read_byte
        jc      expand_format_failed
        mov     bl,al
        xor     bh,bh
        call    read_byte
        jc      expand_format_failed
        mov     dl,al
        and     dl,0fh
        add     dl,3
        mov     match_left,dl
        mov     bh,al
        mov     cl,4
        shr     bh,cl
        mov     match_pos,bx
decode_match_loop:
        call    remaining_nonzero
        jz      decode_done
        mov     bx,match_pos
        mov     al,window[bx]
        call    emit_byte
        jc      expand_write_failed
        inc     bx
        and     bx,0fffh
        mov     match_pos,bx
        dec     match_left
        jnz     decode_match_loop
decode_next:
        shl     flag_mask,1
        jnz     decode_token
        jmp     decode_group

decode_done:
        call    flush_output
        jc      expand_write_failed
        mov     bx,dest_handle
        mov     cx,source_time
        mov     dx,source_date
        mov     ax,5701h
        int     21h
        mov     bx,dest_handle
        mov     ah,3eh
        int     21h
        mov     dest_handle,0ffffh
        mov     bx,source_handle
        mov     ah,3eh
        int     21h
        mov     source_handle,0ffffh
        clc
        ret

expand_open_failed:
        mov     dx,offset open_error
        jmp     short expand_report
expand_format_failed:
        mov     dx,offset format_error
        jmp     short expand_cleanup
expand_create_failed:
        mov     dx,offset create_error
        jmp     short expand_cleanup
expand_write_failed:
        mov     dx,offset write_error
expand_cleanup:
        push    dx
        cmp     dest_handle,0ffffh
        je      cleanup_source
        mov     bx,dest_handle
        mov     ah,3eh
        int     21h
        mov     dx,offset dest_path
        mov     ah,41h
        int     21h
cleanup_source:
        cmp     source_handle,0ffffh
        je      cleanup_report
        mov     bx,source_handle
        mov     ah,3eh
        int     21h
cleanup_report:
        pop     dx
expand_report:
        mov     ah,9
        int     21h
        stc
        ret
expand_one endp

remaining_nonzero proc near
        mov     ax,remaining_lo
        or      ax,remaining_hi
        ret
remaining_nonzero endp

read_byte proc near
        push    bx
        push    cx
        push    dx
        mov     bx,input_pos
        cmp     bx,input_count
        jb      read_buffered
        mov     bx,source_handle
        mov     dx,offset input_buffer
        mov     cx,1024
        mov     ah,3fh
        int     21h
        jc      read_failed
        or      ax,ax
        jz      read_failed
        mov     input_count,ax
        mov     input_pos,0
        xor     bx,bx
read_buffered:
        mov     al,input_buffer[bx]
        inc     bx
        mov     input_pos,bx
        pop     dx
        pop     cx
        pop     bx
        clc
        ret
read_failed:
        pop     dx
        pop     cx
        pop     bx
        stc
        ret
read_byte endp

emit_byte proc near
        push    bx
        mov     bx,output_count
        mov     output_buffer[bx],al
        inc     bx
        mov     output_count,bx
        mov     bx,window_pos
        mov     window[bx],al
        inc     bx
        and     bx,0fffh
        mov     window_pos,bx
        sub     remaining_lo,1
        sbb     remaining_hi,0
        cmp     output_count,1024
        jb      emit_ok
        call    flush_output
        jc      emit_failed
emit_ok:
        pop     bx
        clc
        ret
emit_failed:
        pop     bx
        stc
        ret
emit_byte endp

flush_output proc near
        push    ax
        push    bx
        push    cx
        push    dx
        mov     cx,output_count
        jcxz    flush_ok
        mov     bx,dest_handle
        mov     dx,offset output_buffer
        mov     ah,40h
        int     21h
        jc      flush_bad
        cmp     ax,cx
        jne     flush_bad
        mov     output_count,0
flush_ok:
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        clc
        ret
flush_bad:
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        stc
        ret
flush_output endp

build_destination proc near
        mov     al,arg_count
        xor     ah,ah
        dec     ax
        shl     ax,1
        mov     si,ax
        mov     si,arg_ptrs[si]
        mov     di,offset dest_path
copy_dest:
        lodsb
        stosb
        or      al,al
        jnz     copy_dest
        cmp     dest_is_dir,1
        jne     destination_ready
        dec     di
        cmp     di,offset dest_path
        je      append_separator
        mov     al,[di-1]
        cmp     al,'\'
        je      find_basename
        cmp     al,'/'
        je      find_basename
        cmp     al,':'
        je      find_basename
append_separator:
        mov     byte ptr [di],'\'
        inc     di
find_basename:
        mov     si,bp
        shl     si,1
        mov     si,arg_ptrs[si]
        mov     dx,si
basename_scan:
        lodsb
        or      al,al
        jz      basename_copy_start
        cmp     al,'\'
        je      basename_mark
        cmp     al,'/'
        je      basename_mark
        cmp     al,':'
        jne     basename_scan
basename_mark:
        mov     dx,si
        jmp     basename_scan
basename_copy_start:
        mov     si,dx
basename_copy:
        lodsb
        stosb
        or      al,al
        jnz     basename_copy
        cmp     byte ptr header[9],0
        je      destination_ready
        sub     di,2
        cmp     di,offset dest_path
        jb      destination_bad
        mov     al,header[9]
        mov     [di],al
destination_ready:
        clc
        ret
destination_bad:
        stc
        ret
build_destination endp

end start
