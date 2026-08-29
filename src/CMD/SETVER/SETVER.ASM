; MS-DOS 5 SETVER-compatible resident version-table editor.

CODE SEGMENT PUBLIC
        ORG     100h
        ASSUME  CS:CODE,DS:CODE,ES:NOTHING,SS:CODE

start:
        cld
        call    tokenize
        cmp     cs:token_count,0
        je      query_table
        mov     si,cs:token1
        call    is_help
        jc      show_help
query_table:
        mov     ax,1200h                ; DOS internal multiplex present?
        int     2fh
        cmp     al,0ffh
        jne     not_supported
        mov     ax,1231h                ; resident SETVER table
        int     2fh
        cmp     cx,512
        jne     not_supported
        mov     cs:table_off,di
        mov     cs:table_seg,es
        mov     cs:table_size,cx

        cmp     cs:token_count,0
        je      list_table
        cmp     cs:token_count,1
        je      list_table              ; optional SETVER.EXE path
        cmp     cs:token_count,4
        ja      syntax_error

        cmp     cs:token_count,2
        je      args_ready
        cmp     cs:token_count,3
        jne     four_args
        mov     si,cs:token2
        call    is_delete
        jnc     path_args
        mov     si,cs:token3
        call    is_quiet
        jnc     syntax_error
        mov     cs:quiet_flag,1
        mov     si,cs:token1
        mov     cs:name_arg,si
        mov     si,cs:token2
        mov     cs:value_arg,si
        jmp     short parse_name
path_args:
        mov     si,cs:token2             ; ignore optional SETVER.EXE path
        mov     cs:name_arg,si
        mov     si,cs:token3
        mov     cs:value_arg,si
        jmp     short parse_name
four_args:
        mov     si,cs:token3
        call    is_delete
        jnc     syntax_error
        mov     si,cs:token4
        call    is_quiet
        jnc     syntax_error
        mov     cs:quiet_flag,1
        mov     si,cs:token2             ; ignore optional SETVER.EXE path
        mov     cs:name_arg,si
        mov     si,cs:token3
        mov     cs:value_arg,si
        jmp     short parse_name
args_ready:
        mov     si,cs:token1
        mov     cs:name_arg,si
        mov     si,cs:token2
        mov     cs:value_arg,si

parse_name:
        mov     si,cs:name_arg
        call    normalize_name
        jc      bad_name
        mov     si,cs:value_arg
        call    is_delete
        jc      delete_entry
        call    parse_version
        jc      bad_version
        mov     cs:new_major,al
        mov     cs:new_minor,ah
        call    find_entry
        jnc     update_entry

        ; DI is the zero-length terminator.  Require entry plus a new terminator.
        mov     ax,di
        sub     ax,cs:table_off
        xor     bx,bx
        mov     bl,cs:name_len
        add     bx,5
        add     ax,bx
        cmp     ax,cs:table_size
        ja      table_full
        mov     al,cs:name_len
        stosb
        push    ds
        pop     es
        mov     si,OFFSET name_buf
        xor     cx,cx
        mov     cl,cs:name_len
        ; Restore the table segment for the copy destination.
        push    cs:table_seg
        pop     es
        rep     movsb
        mov     al,cs:new_major
        stosb
        mov     al,cs:new_minor
        stosb
        mov     al,0ffh
        stosb
        xor     al,al
        stosb
        mov     dx,OFFSET added_msg
        jmp     short success

update_entry:
        xor     bx,bx
        mov     bl,es:[di]
        add     di,bx
        inc     di
        mov     al,cs:new_major
        mov     es:[di],al
        mov     al,cs:new_minor
        mov     es:[di+1],al
        mov     byte ptr es:[di+2],0ffh
        mov     dx,OFFSET updated_msg
success:
        call    print_dollar
        jmp     exit_ok

delete_entry:
        call    find_entry
        jc      not_found
        mov     bx,di                    ; destination
        xor     ax,ax
        mov     al,es:[di]
        add     ax,4
        add     di,ax                    ; source
        mov     ax,di
        sub     ax,cs:table_off
        mov     cx,cs:table_size
        sub     cx,ax
        mov     si,di
        mov     di,bx
        rep     movsb                    ; overlap is forward-safe
        cmp     cs:quiet_flag,0
        jne     exit_ok
        mov     dx,OFFSET deleted_msg
        jmp     short success

list_table:
        mov     dx,OFFSET heading
        call    print_dollar
        mov     es,cs:table_seg
        mov     di,cs:table_off
list_next:
        xor     cx,cx
        mov     cl,es:[di]
        jcxz    list_done
        inc     di
        push    cx
list_name:
        mov     dl,es:[di]
        call    put_char
        inc     di
        loop    list_name
        mov     dl,' '
        call    put_char
        mov     al,es:[di]
        call    print_u8
        mov     dl,'.'
        call    put_char
        mov     al,es:[di+1]
        call    print_two_digits
        mov     dx,OFFSET crlf
        call    print_dollar
        add     di,3
        pop     cx
        jmp     short list_next
list_done:
        jmp     exit_ok

; Find normalized name_buf.  CF clear and DI at entry, or CF set at terminator.
find_entry:
        mov     es,cs:table_seg
        mov     di,cs:table_off
find_next:
        mov     al,es:[di]
        or      al,al
        jz      find_miss
        cmp     al,cs:name_len
        jne     find_skip
        push    di
        push    ds
        push    cs
        pop     ds
        mov     si,OFFSET name_buf
        inc     di
        xor     cx,cx
        mov     cl,al
        repe    cmpsb
        pop     ds
        pop     di
        je      find_hit
find_skip:
        xor     ah,ah
        add     di,ax
        add     di,4
        jmp     short find_next
find_hit:
        clc
        ret
find_miss:
        stc
        ret

; Strip drive/path, uppercase ASCII, and validate an 8.3-sized basename.
normalize_name:
        push    cs
        pop     es
        mov     bx,si
name_scan:
        mov     al,[si]
        or      al,al
        jz      name_copy
        cmp     al,':'
        je      name_mark
        cmp     al,'\'
        je      name_mark
        cmp     al,'/'
        jne     name_advance
name_mark:
        lea     bx,[si+1]
name_advance:
        inc     si
        jmp     short name_scan
name_copy:
        mov     si,bx
        mov     di,OFFSET name_buf
        xor     cx,cx
copy_name_char:
        lodsb
        or      al,al
        jz      name_done
        cmp     al,'a'
        jb      name_upper
        cmp     al,'z'
        ja      name_upper
        sub     al,20h
name_upper:
        cmp     al,' '
        jbe     name_bad
        cmp     cx,12
        jae     name_bad
        stosb
        inc     cx
        jmp     short copy_name_char
name_done:
        jcxz    name_bad
        mov     cs:name_len,cl
        clc
        ret
name_bad:
        stc
        ret

; Parse M[.mm], returning AL=major and AH=minor.
parse_version:
        xor     ax,ax
        xor     bx,bx
version_major:
        mov     dl,[si]
        cmp     dl,'.'
        je      version_dot
        cmp     dl,'0'
        jb      version_bad
        cmp     dl,'9'
        ja      version_bad
        sub     dl,'0'
        mov     bl,10
        mul     bl
        or      ah,ah
        jnz     version_bad
        add     al,dl
        jc      version_bad
        inc     si
        jmp     short version_major
version_dot:
        cmp     al,9
        ja      version_bad
        mov     bl,al
        inc     si
        mov     dl,[si]
        cmp     dl,'0'
        jb      version_bad
        cmp     dl,'9'
        ja      version_bad
        sub     dl,'0'
        mov     bh,dl
        inc     si
        mov     dl,[si]
        or      dl,dl
        jz      version_one_minor
        cmp     dl,'0'
        jb      version_bad
        cmp     dl,'9'
        ja      version_bad
        sub     dl,'0'
        mov     al,bh
        mov     ah,10
        mul     ah
        add     al,dl
        mov     bh,al
        inc     si
        cmp     byte ptr [si],0
        jne     version_bad
        jmp     short version_good
version_one_minor:
        mov     al,bh
        mov     ah,10
        mul     ah                      ; 3.3 means 3.30
        mov     bh,al
version_good:
        mov     al,bl
        mov     ah,bh
        clc
        ret
version_bad:
        stc
        ret

is_help:
        cmp     byte ptr [si],'/'
        jne     no_match
        cmp     byte ptr [si+1],'?'
        jne     no_match
        cmp     byte ptr [si+2],0
        jne     no_match
        stc
        ret
is_delete:
        cmp     byte ptr [si],'/'
        jne     no_match
        inc     si
        cmp     byte ptr [si],'d'
        je      delete_short
        cmp     byte ptr [si],'D'
        jne     delete_long
delete_short:
        cmp     byte ptr [si+1],0
        je      matched_switch
delete_long:
        mov     di,OFFSET delete_word
        mov     cx,6
delete_cmp:
        mov     al,[si]
        cmp     al,'a'
        jb      delete_upper
        cmp     al,'z'
        ja      delete_upper
        sub     al,20h
delete_upper:
        cmp     al,[di]
        jne     no_match
        inc     si
        inc     di
        loop    delete_cmp
        cmp     byte ptr [si],0
        jne     no_match
matched_switch:
        stc
        ret
is_quiet:
        cmp     byte ptr [si],'/'
        jne     no_match
        inc     si
        mov     di,OFFSET quiet_word
        mov     cx,5
quiet_cmp:
        mov     al,[si]
        cmp     al,'a'
        jb      quiet_upper
        cmp     al,'z'
        ja      quiet_upper
        sub     al,20h
quiet_upper:
        cmp     al,[di]
        jne     no_match
        inc     si
        inc     di
        loop    quiet_cmp
        cmp     byte ptr [si],0
        jne     no_match
        stc
        ret
no_match:
        clc
        ret

; Split PSP command tail in place.  At most four arguments are accepted.
tokenize:
        xor     ax,ax
        mov     al,byte ptr ds:[80h]
        mov     si,81h
        add     ax,si
        mov     bx,ax
        mov     byte ptr [bx],0
token_skip:
        cmp     si,bx
        jae     token_done
        mov     al,[si]
        cmp     al,' '
        je      token_space
        cmp     al,9
        jne     token_start
token_space:
        inc     si
        jmp     short token_skip
token_start:
        inc     cs:token_count
        mov     al,cs:token_count
        cmp     al,4
        ja      token_too_many
        xor     ah,ah
        dec     ax
        shl     ax,1
        mov     di,OFFSET token1
        add     di,ax
        mov     [di],si
token_body:
        cmp     si,bx
        jae     token_done
        mov     al,[si]
        cmp     al,' '
        je      token_end
        cmp     al,9
        je      token_end
        inc     si
        jmp     short token_body
token_end:
        mov     byte ptr [si],0
        inc     si
        jmp     short token_skip
token_too_many:
        mov     cs:token_count,5
token_done:
        ret

print_u8:
        aam
        push    ax
        cmp     ah,0
        je      print_ones
        mov     dl,ah
        add     dl,'0'
        call    put_char
print_ones:
        pop     ax
        mov     dl,al
        add     dl,'0'
        jmp     short put_char
print_two_digits:
        aam
        push    ax
        mov     dl,ah
        add     dl,'0'
        call    put_char
        pop     ax
        mov     dl,al
        add     dl,'0'
put_char:
        mov     ah,02h
        int     21h
        ret
print_dollar:
        mov     ah,09h
        int     21h
        ret

show_help:
        mov     dx,OFFSET help_msg
        jmp     short exit_message_ok
syntax_error:
        mov     dx,OFFSET syntax_msg
        jmp     short exit_message_bad
bad_name:
        mov     dx,OFFSET name_msg
        jmp     short exit_message_bad
bad_version:
        mov     dx,OFFSET version_msg
        jmp     short exit_message_bad
table_full:
        mov     dx,OFFSET full_msg
        jmp     short exit_message_bad
not_found:
        mov     dx,OFFSET missing_msg
        jmp     short exit_message_bad
not_supported:
        mov     dx,OFFSET support_msg
exit_message_bad:
        call    print_dollar
        mov     ax,4c01h
        int     21h
exit_message_ok:
        call    print_dollar
exit_ok:
        mov     ax,4c00h
        int     21h

token_count db 0
token1      dw 0
token2      dw 0
token3      dw 0
token4      dw 0
name_arg    dw 0
value_arg   dw 0
table_off   dw 0
table_seg   dw 0
table_size  dw 0
name_len    db 0
new_major   db 0
new_minor   db 0
quiet_flag  db 0
name_buf    db 12 dup(0)
delete_word db 'DELETE'
quiet_word  db 'QUIET'
crlf        db 13,10,'$'
heading     db 'MS-DOS Version Table',13,10,'$'
added_msg   db 'Entry added.',13,10,'$'
updated_msg db 'Entry updated.',13,10,'$'
deleted_msg db 'Entry deleted.',13,10,'$'
syntax_msg  db 'Invalid syntax. Use SETVER /? for help.',13,10,'$'
name_msg    db 'Invalid filename.',13,10,'$'
version_msg db 'Invalid version. Use major.minor.',13,10,'$'
full_msg    db 'Version table is full.',13,10,'$'
missing_msg db 'Entry not found.',13,10,'$'
support_msg db 'SETVER is not supported by this DOS kernel.',13,10,'$'
help_msg    db 'SETVER [path] [filename version | filename /DELETE [/QUIET]]',13,10
            db 'Lists or changes the DOS version reported to a program.',13,10,'$'

CODE ENDS
        END start
