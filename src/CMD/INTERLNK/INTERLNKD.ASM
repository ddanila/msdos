; INTERLNK block-device client for the serial INTERSVR transport.

CODE SEGMENT PUBLIC
        ORG     0
        ASSUME  CS:CODE,DS:NOTHING,ES:NOTHING,SS:NOTHING

device_header:
        dd      0ffffffffh
        dw      0800h
        dw      strategy
        dw      interrupt
unit_count      db      1
        db      7 dup(0)

request_ptr     dd 0
connected       db 0
com_port        dw 0
sector_number   dd 0
bpb_pointer     dw OFFSET remote_bpb
remote_bpb      db 25 dup(0)
boot_sector     db 512 dup(0)

strategy PROC FAR
        mov     word ptr cs:request_ptr,bx
        mov     word ptr cs:request_ptr+2,es
        ret
strategy ENDP

interrupt PROC FAR
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        lds     bx,cs:request_ptr
        mov     al,[bx+2]
        cmp     al,0
        je      request_init
        cmp     cs:connected,0
        je      request_not_ready
        cmp     al,1
        je      request_media
        cmp     al,2
        je      request_bpb
        cmp     al,4
        je      request_read
        cmp     al,8
        je      request_write
        cmp     al,9
        je      request_write
        cmp     al,5
        je      request_busy
        cmp     al,6
        je      request_done
        cmp     al,7
        je      request_done
        cmp     al,10
        je      request_done
        cmp     al,11
        je      request_done
        cmp     al,13
        je      request_done
        cmp     al,14
        je      request_done
        cmp     al,15
        je      request_removable
        jmp     request_bad_command

request_init:
        call    init_serial
        mov     al,1
        xor     dx,dx
        call    send_request
        call    receive_status
        jc      init_failed
        push    cs
        pop     es
        mov     di,OFFSET boot_sector
        call    receive_sector
        jc      init_failed
        push    cs
        pop     ds
        mov     si,OFFSET boot_sector+11
        mov     di,OFFSET remote_bpb
        mov     cx,25
        rep     movsb
        lds     bx,cs:request_ptr
        mov     byte ptr [bx+13],1
        mov     word ptr [bx+14],OFFSET resident_end
        mov     word ptr [bx+16],cs
        mov     word ptr [bx+18],OFFSET bpb_pointer
        mov     word ptr [bx+20],cs
        mov     cs:connected,1
        call    install_multiplex
        jmp     request_done
init_failed:
        lds     bx,cs:request_ptr
        mov     byte ptr [bx+13],0
        mov     word ptr [bx+14],OFFSET resident_end
        mov     word ptr [bx+16],cs
        mov     word ptr [bx+3],8102h
        jmp     request_exit

request_media:
        mov     byte ptr [bx+14],1
        jmp     request_done
request_bpb:
        mov     word ptr [bx+18],OFFSET remote_bpb
        mov     word ptr [bx+20],cs
        jmp     request_done
request_busy:
        mov     word ptr [bx+3],0300h
        jmp     request_exit
request_removable:
        mov     word ptr [bx+3],0300h   ; busy bit denotes non-removable media
        jmp     request_exit

request_read:
        mov     al,2
        call    prepare_io
        jc      request_io_error
read_sector_loop:
        call    send_current_request
        call    receive_status
        jc      request_io_error
        les     di,cs:transfer_ptr
        call    receive_sector
        jc      request_io_error
        call    advance_transfer
        dec     word ptr cs:io_remaining
        jnz     read_sector_loop
        jmp     request_done

request_write:
        mov     al,3
        call    prepare_io
        jc      request_io_error
write_sector_loop:
        call    send_current_request
        les     si,cs:transfer_ptr
        call    send_sector
        call    receive_status
        jc      request_io_error
        call    advance_transfer
        dec     word ptr cs:io_remaining
        jnz     write_sector_loop
        jmp     request_done

request_not_ready:
        mov     word ptr [bx+3],8102h
        jmp     request_exit
request_io_error:
        lds     bx,cs:request_ptr
        mov     word ptr [bx+3],810bh
        jmp     request_exit
request_bad_command:
        mov     word ptr [bx+3],8103h
        jmp     request_exit
request_done:
        lds     bx,cs:request_ptr
        mov     word ptr [bx+3],0100h
request_exit:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
interrupt ENDP

prepare_io PROC NEAR
        ; AL is protocol command. Traditional DOS request packets provide a
        ; 16-bit starting sector at +20 and count at +18.
        mov     cs:io_command,al
        lds     bx,cs:request_ptr
        mov     cx,[bx+18]
        jcxz    short prepare_bad
        mov     cs:io_remaining,cx
        mov     ax,[bx+20]
        mov     word ptr cs:sector_number,ax
        mov     word ptr cs:sector_number+2,0
        mov     ax,[bx+14]
        mov     word ptr cs:transfer_ptr,ax
        mov     ax,[bx+16]
        mov     word ptr cs:transfer_ptr+2,ax
        clc
        ret
prepare_bad:
        stc
        ret
prepare_io ENDP

send_current_request PROC NEAR
        mov     al,cs:io_command
        mov     dx,word ptr cs:sector_number
        call    send_request
        ret
send_current_request ENDP

advance_transfer PROC NEAR
        inc     word ptr cs:sector_number
        jnz     short sector_advanced
        inc     word ptr cs:sector_number+2
sector_advanced:
        add     word ptr cs:transfer_ptr,512
        jnc     short transfer_advanced
        add     word ptr cs:transfer_ptr+2,1000h
transfer_advanced:
        ret
advance_transfer ENDP

send_request PROC NEAR
        ; AL command, DX low sector; high word is resident sector_number+2.
        push    ax
        mov     al,0a5h
        call    send_byte
        mov     al,05ah
        call    send_byte
        pop     ax
        call    send_byte
        mov     al,dl
        call    send_byte
        mov     al,dh
        call    send_byte
        mov     al,byte ptr cs:sector_number+2
        call    send_byte
        mov     al,byte ptr cs:sector_number+3
        call    send_byte
        ret
send_request ENDP

receive_status PROC NEAR
        call    receive_byte
        jc      short status_bad
        cmp     al,05ah
        jne     short status_bad
        call    receive_byte
        jc      short status_bad
        cmp     al,0a5h
        jne     short status_bad
        call    receive_byte
        jc      short status_bad
        or      al,al
        jne     short status_bad
        clc
        ret
status_bad:
        stc
        ret
receive_status ENDP

send_sector PROC NEAR
        mov     cx,512
send_sector_loop:
        mov     al,es:[si]
        inc     si
        call    send_byte
        loop    send_sector_loop
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
        push    dx
        mov     dx,03fdh
client_send_ready:
        in      al,dx
        test    al,20h
        jz      client_send_ready
        pop     dx
        pop     ax
        push    dx
        mov     dx,03f8h
        out     dx,al
        pop     dx
        ret
send_byte ENDP

receive_byte PROC NEAR
        push    dx
        mov     dx,03fdh
client_receive_ready:
        in      al,dx
        test    al,1
        jz      client_receive_ready
        mov     dx,03f8h
        in      al,dx
        clc
        pop     dx
        ret
receive_byte ENDP

init_serial PROC NEAR
        mov     dx,03f9h
        xor     al,al
        out     dx,al
        mov     dx,03fbh
        mov     al,80h
        out     dx,al
        mov     dx,03f8h
        mov     al,1
        out     dx,al
        mov     dx,03f9h
        xor     al,al
        out     dx,al
        mov     dx,03fbh
        mov     al,3
        out     dx,al
        mov     dx,03fah
        mov     al,0c7h
        out     dx,al
        mov     dx,03fch
        mov     al,0bh
        out     dx,al
        ret
init_serial ENDP

install_multiplex PROC NEAR
        mov     ax,352fh
        int     21h
        mov     word ptr cs:old_int2f,bx
        mov     word ptr cs:old_int2f+2,es
        push    ds
        push    cs
        pop     ds
        mov     dx,OFFSET multiplex
        mov     ax,252fh
        int     21h
        pop     ds
        ret
install_multiplex ENDP

multiplex PROC FAR
        cmp     ax,0e900h
        jne     short chain_multiplex
        mov     ax,0ff00h
        xor     bx,bx
        mov     bl,cs:connected
        xor     cx,cx
        mov     cl,cs:unit_count
        iret
chain_multiplex:
        jmp     dword ptr cs:old_int2f
multiplex ENDP

old_int2f       dd 0
transfer_ptr    dd 0
io_command      db 0
io_remaining    dw 0
resident_end LABEL BYTE

CODE ENDS
        END
