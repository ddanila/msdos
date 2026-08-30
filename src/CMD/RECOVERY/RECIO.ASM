        .model  small, c
        .286

        .data
packet  dd      0
        dw      0
        dw      0, 0

        .code
        public  abs_read
        public  abs_write

; unsigned abs_read(unsigned drive, unsigned long sector,
;                   unsigned count, void *buffer)
abs_read proc near
        push    bp
        mov     bp, sp
        push    bx
        push    cx
        push    dx

        mov     ax, [bp+6]
        mov     word ptr packet, ax
        mov     ax, [bp+8]
        mov     word ptr packet+2, ax
        mov     ax, [bp+10]
        mov     word ptr packet+4, ax
        mov     dx, [bp+12]
        mov     ax, dx
        and     dx, 000fh
        mov     cl, 4
        shr     ax, cl
        mov     cx, ds
        add     ax, cx
        mov     word ptr packet+6, dx
        mov     word ptr packet+8, ax

        mov     ax, [bp+4]
        mov     bx, offset packet
        mov     cx, 0ffffh
        int     25h
        popf
        jc      short read_done
        xor     ax, ax
read_done:
        pop     dx
        pop     cx
        pop     bx
        pop     bp
        ret
abs_read endp

; unsigned abs_write(unsigned drive, unsigned long sector,
;                    unsigned count, void *buffer)
abs_write proc near
        push    bp
        mov     bp, sp
        push    bx
        push    cx
        push    dx

        mov     ax, [bp+6]
        mov     word ptr packet, ax
        mov     ax, [bp+8]
        mov     word ptr packet+2, ax
        mov     ax, [bp+10]
        mov     word ptr packet+4, ax
        mov     dx, [bp+12]
        mov     ax, dx
        and     dx, 000fh
        mov     cl, 4
        shr     ax, cl
        mov     cx, ds
        add     ax, cx
        mov     word ptr packet+6, dx
        mov     word ptr packet+8, ax

        mov     ax, [bp+4]
        mov     bx, offset packet
        mov     cx, 0ffffh
        int     26h
        popf
        jc      short write_done
        xor     ax, ax
write_done:
        pop     dx
        pop     cx
        pop     bx
        pop     bp
        ret
abs_write endp

        end
