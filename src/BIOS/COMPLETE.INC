; Retained-low device completion paths. PTRSAV is owned by CS; the request
; itself is a caller-owned far pointer. Consume MSBIO1's nine saved register
; words and original FAR return without introducing an intermediate frame.
        public BUS$EXIT
BUS$EXIT proc far
        assume ds:nothing
        mov ah,00000011b
        jmp short ERR1
        public CMDERR
CMDERR:
        mov al,3
        public ERR$CNT
ERR$CNT:
        lds bx,cs:[PTRSAV]
        assume ds:nothing
        sub word ptr [bx].COUNT,cx
        public ERR$EXIT
ERR$EXIT:
        mov ah,10000001b
        jmp short ERR1
BUS$EXIT endp
EXITP proc far
        assume ds:CODE
PUBLIC EXIT$ZER
EXIT$ZER:
        lds bx,[PTRSAV]
        assume ds:nothing
        xor ax,ax
        mov word ptr [bx].COUNT,ax
        public EXIT
EXIT:
        assume ds:nothing
        mov ah,00000001b
ERR1:
        assume ds:nothing
        lds bx,cs:[PTRSAV]
        mov word ptr [bx].STATUS,ax
        pop bx
        pop es
        pop ds
        pop bp
        pop di
        pop dx
        pop cx
        pop ax
        pop si
        ret
EXITP endp
