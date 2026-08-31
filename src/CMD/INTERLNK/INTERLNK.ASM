; Command-side status display for the installable INTERLNK.EXE client.

CODE SEGMENT PUBLIC
        ORG     100h
        ASSUME  CS:CODE,DS:CODE,SS:CODE
start:
        xor     cx,cx
        mov     cl,byte ptr ds:[80h]
        mov     si,81h
command_skip_space:
        or      cx,cx
        jnz     short command_have_character
        jmp     command_query
command_have_character:
        lodsb
        dec     cx
        cmp     al,' '
        je      command_skip_space
        cmp     al,'/'
        jne     command_mapping
        or      cx,cx
        jnz     short command_have_switch
        jmp     command_syntax
command_have_switch:
        lodsb
        dec     cx
        cmp     al,'?'
        je      command_help_tail
        and     al,0dfh
        cmp     al,'R'
        jne     command_syntax
        mov     di,OFFSET reconnect_name+1
        mov     bx,8
command_reconnect_tail:
        jcxz    command_reconnect
        lodsb
        dec     cx
        and     al,0dfh
        cmp     al,[di]
        jne     command_syntax
        inc     di
        dec     bx
        jnz     command_reconnect_tail
command_reconnect_spaces:
        jcxz    command_reconnect
        lodsb
        dec     cx
        cmp     al,' '
        je      command_reconnect_spaces
        jmp     command_syntax
command_reconnect:
        or      bx,bx
        jnz     command_syntax
        mov     ax,0e901h
        int     2fh
        cmp     ax,0ff00h
        jne     not_installed
        mov     dx,OFFSET reconnected
        mov     ah,9
        int     21h
        mov     ax,4c00h
        int     21h
command_mapping:
        and     al,0dfh
        sub     al,'A'
        cmp     al,25
        ja      command_syntax
        mov     bl,al
        jcxz    command_syntax
        lodsb
        dec     cx
        cmp     al,':'
        jne     short command_mapping_equal
        jcxz    command_syntax
        lodsb
        dec     cx
command_mapping_equal:
        cmp     al,'='
        jne     command_syntax
        mov     bh,0ffh
command_mapping_server_space:
        jcxz    command_mapping_apply
        lodsb
        dec     cx
        cmp     al,' '
        je      command_mapping_server_space
        and     al,0dfh
        sub     al,'A'
        cmp     al,25
        ja      command_syntax
        mov     bh,al
        jcxz    command_mapping_apply
        lodsb
        dec     cx
        cmp     al,':'
        jne     short command_mapping_tail_char
        jcxz    command_mapping_apply
        lodsb
        dec     cx
command_mapping_tail_char:
        cmp     al,' '
        jne     command_syntax
command_mapping_tail:
        jcxz    command_mapping_apply
        lodsb
        dec     cx
        cmp     al,' '
        je      command_mapping_tail
        jmp     command_syntax
command_mapping_apply:
        mov     ax,0e903h
        int     2fh
        cmp     ax,0ff00h
        jne     not_installed
        mov     dx,OFFSET remapped
        mov     ah,9
        int     21h
        mov     ax,4c00h
        int     21h
command_help_tail:
        jcxz    command_help
        lodsb
        dec     cx
        cmp     al,' '
        je      command_help_tail
command_syntax:
        push    cs
        pop     ds
        mov     dx,OFFSET syntax
        mov     ah,9
        int     21h
        mov     ax,4c01h
        int     21h
command_help:
        push    cs
        pop     ds
        mov     dx,OFFSET help
        mov     ah,9
        int     21h
        mov     ax,4c00h
        int     21h
command_query:
        push    cs
        pop     ds
        mov     ax,0e900h
        int     2fh
        cmp     ax,0ff00h
        jne     not_installed
        mov     al,cl
        add     al,'0'
        mov     cs:banner_count,al
        mov     al,dl
        or      al,al
        jnz     short command_query_numbered_port
        mov     al,'@'-'0'
command_query_numbered_port:
        add     al,'0'
        mov     cs:banner_port,al
        or      dh,dh
        jz      short command_query_kind_done
        mov     byte ptr cs:banner_kind,'L'
        mov     byte ptr cs:banner_kind+1,'P'
        mov     byte ptr cs:banner_kind+2,'T'
command_query_kind_done:
        mov     dx,OFFSET banner
        mov     ah,9
        int     21h
        mov     ax,4c00h
        int     21h
not_installed:
        mov     dx,OFFSET missing
        mov     ah,9
        int     21h
        mov     ax,4c01h
        int     21h
banner  db 'Microsoft Interlnk version 1.00',13,10
        db 'Port-'
banner_kind db 'COM'
banner_port db '0',13,10
        db 'Drive letters redirected: '
banner_count db '0',13,10,'$'
missing db 'INTERLNK is not installed or the server is unavailable.',13,10,'$'
syntax  db 'Invalid INTERLNK parameter.',13,10,'$'
help    db 'Displays or changes the Interlnk client connection.',13,10
        db 'Syntax: INTERLNK [client[:]=[server][:]]',13,10
        db 'Repository extension: INTERLNK /RECONNECT',13,10
        db 'CONFIG.SYS: DEVICE=INTERLNK.EXE [/DRIVES:n] [/NOPRINTER]',13,10
        db ' [/COM[:][n|address] | /LPT[:][n|address]] [/BAUD:rate] [/AUTO] [/NOSCAN] [/LOW] [/V]',13,10,'$'
reconnect_name db 'RECONNECT'
reconnected db 'Interlnk connection renewed.',13,10,'$'
remapped db 'Interlnk drive redirection updated.',13,10,'$'
CODE ENDS
STACKSEG SEGMENT PARA STACK 'STACK'
        db 256 dup(0)
STACKSEG ENDS
        END start
