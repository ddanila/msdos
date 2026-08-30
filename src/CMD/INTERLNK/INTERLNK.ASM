; Command-side status display for the installable INTERLNK.EXE client.

CODE SEGMENT PUBLIC
        ORG     100h
        ASSUME  CS:CODE,DS:CODE,SS:CODE
start:
        xor     cx,cx
        mov     cl,byte ptr ds:[80h]
        mov     si,81h
command_skip_space:
        jcxz    command_query
        lodsb
        dec     cx
        cmp     al,' '
        je      command_skip_space
        cmp     al,'/'
        jne     command_syntax
        jcxz    command_syntax
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
        add     al,'0'
        mov     cs:banner_port,al
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
        db 'Port-COM'
banner_port db '0',13,10
        db 'Drive letters redirected: '
banner_count db '0',13,10,'$'
missing db 'INTERLNK is not installed or the server is unavailable.',13,10,'$'
syntax  db 'Invalid INTERLNK parameter.',13,10,'$'
help    db 'Displays or renews the Interlnk client connection.',13,10
        db 'Syntax: INTERLNK [/RECONNECT]',13,10
        db 'CONFIG.SYS: DEVICE=INTERLNK.EXE [/DRIVES:n] [/NOPRINTER] [/COM:n]',13,10,'$'
reconnect_name db 'RECONNECT'
reconnected db 'Interlnk connection renewed.',13,10,'$'
CODE ENDS
STACKSEG SEGMENT PARA STACK 'STACK'
        db 256 dup(0)
STACKSEG ENDS
        END start
