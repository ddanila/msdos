        .model  tiny
        .286
        .code
        org     100h

start:
        push    cs
        pop     ds
        cld
        call    parse_topic
        jc      show_usage
        mov     dx, offset database_name
        mov     ax, 3d00h
        int     21h
        jc      database_missing
        mov     [handle], ax

search_next:
        call    read_line
        jc      topic_missing
        cmp     byte ptr [line_buffer], '@'
        jne     short search_next
        mov     si, offset line_buffer+1
        mov     di, offset topic
compare_topic:
        mov     al, [si]
        cmp     al, [di]
        jne     short search_next
        or      al, al
        jz      short topic_found
        inc     si
        inc     di
        jmp     short compare_topic

topic_found:
        call    read_line
        jc      help_done
        cmp     byte ptr [line_buffer], '@'
        je      short help_done
        mov     bx, 1
        mov     cx, [line_length]
        mov     dx, offset line_buffer
        mov     ah, 40h
        int     21h
        mov     bx, 1
        mov     cx, 2
        mov     dx, offset newline
        mov     ah, 40h
        int     21h
        jmp     short topic_found

topic_missing:
        mov     dx, offset missing_message
        call    print_message
        mov     bx, [handle]
        mov     ah, 3eh
        int     21h
        jmp     short exit_failure
database_missing:
        mov     dx, offset database_message
        call    print_message
        jmp     short exit_failure
show_usage:
        mov     dx, offset usage_message
        call    print_message
        cmp     byte ptr [topic], '/'
        jne     short exit_failure
        cmp     byte ptr [topic+1], '?'
        jne     short exit_failure
        cmp     byte ptr [topic+2], 0
        jne     short exit_failure
        jmp     short exit_success
help_done:
        mov     bx, [handle]
        mov     ah, 3eh
        int     21h
exit_success:
        mov     ax, 4c00h
        int     21h
exit_failure:
        mov     ax, 4c01h
        int     21h

; Return a normalized topic in TOPIC. An empty command line selects INDEX.
parse_topic proc near
        mov     si, 81h
        xor     cx, cx
        mov     cl, byte ptr ds:[80h]
parse_skip_space:
        jcxz    short parse_default
        cmp     byte ptr [si], ' '
        je      short parse_skip_next
        cmp     byte ptr [si], 9
        jne     short parse_copy
parse_skip_next:
        inc     si
        dec     cx
        jmp     short parse_skip_space
parse_copy:
        mov     di, offset topic
        xor     bx, bx
parse_copy_loop:
        jcxz    short parse_done
        mov     al, [si]
        cmp     al, ' '
        je      short parse_trailing
        cmp     al, 9
        je      short parse_trailing
        cmp     bx, 15
        jae     short parse_bad
        cmp     al, 'a'
        jb      short parse_store
        cmp     al, 'z'
        ja      short parse_store
        sub     al, 20h
parse_store:
        stosb
        inc     bx
        inc     si
        dec     cx
        jmp     short parse_copy_loop
parse_trailing:
        inc     si
        dec     cx
parse_trailing_loop:
        jcxz    short parse_done
        cmp     byte ptr [si], ' '
        je      short parse_trailing_next
        cmp     byte ptr [si], 9
        jne     short parse_bad
parse_trailing_next:
        inc     si
        dec     cx
        jmp     short parse_trailing_loop
parse_done:
        mov     byte ptr [di], 0
        cmp     byte ptr [topic], '/'
        jne     short parse_ok
        cmp     byte ptr [topic+1], '?'
        je      short parse_bad
parse_ok:
        clc
        ret
parse_default:
        mov     si, offset index_topic
        mov     di, offset topic
parse_default_loop:
        lodsb
        stosb
        or      al, al
        jnz     short parse_default_loop
        clc
        ret
parse_bad:
        stc
        ret
parse_topic endp

; Read one CR/LF-delimited line. Carry is set only at clean EOF.
read_line proc near
        mov     di, offset line_buffer
        xor     bp, bp
read_line_byte:
        mov     bx, [handle]
        mov     cx, 1
        mov     dx, offset read_byte
        mov     ah, 3fh
        int     21h
        jc      short read_line_eof
        or      ax, ax
        jz      short read_line_eof
        mov     al, [read_byte]
        cmp     al, 10
        je      short read_line_lf
        cmp     al, 13
        je      short read_line_done
        cmp     bp, 126
        jae     short read_line_byte
        stosb
        inc     bp
        jmp     short read_line_byte
read_line_lf:
        or      bp, bp
        jz      short read_line_byte
read_line_done:
        mov     byte ptr [di], 0
        mov     [line_length], bp
        clc
        ret
read_line_eof:
        or      bp, bp
        jnz     short read_line_done
        stc
        ret
read_line endp

print_message proc near
        mov     ah, 09h
        int     21h
        ret
print_message endp

handle           dw 0
line_length      dw 0
read_byte        db 0
topic            db 16 dup (0)
line_buffer      db 128 dup (0)
database_name    db 'HELP.HLP',0
index_topic      db 'INDEX',0
newline          db 13,10
usage_message    db 'Displays help for MS-DOS commands.',13,10
                 db 'HELP [command]',13,10,'$'
missing_message  db 'No help is available for that command.',13,10,'$'
database_message db 'HELP.HLP was not found.',13,10,'$'

        end     start
