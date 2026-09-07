; MSINIT, before DOS/CONFIG can publish or cache descriptor addresses.
; AX is the end of the selected BIOS/firmware additions. All original
; descriptors remain intact until the complete graph has been validated.
EXTRN BIOS_BDS_TEMPLATES_START:BYTE, BIOS_BDS_TEMPLATES_END:BYTE
EXTRN CompactDpbStorage:WORD
PUBLIC PackBootDriveGraph, BIOS_PACKED_GRAPH_START, BIOS_PACKED_GRAPH_END
BIOS_PACKED_GRAPH_START DW 0
BIOS_PACKED_GRAPH_END DW 0
PackBootDriveGraph PROC NEAR
        pushf
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push ds
        push es
        push cs
        pop ds
        push cs
        pop es
        mov bp,ax
        mov ax,cs
        cmp WORD PTR START_BDS+2,ax
        jne PackGraphBad
        xor ax,ax
        mov al,DRVMAX
        cmp al,2
        jb PackGraphBad
        cmp al,26
        ja PackGraphBad
        mov cx,ax
        mov bx,SIZE BDS_TYPE
        mul bx
        add ax,bp
        jc PackGraphBad
        mov di,ax
        mov al,DRVMAX
        xor ah,ah
        sub ax,2
        mov bx,33               ; checked against DPBSIZ in SYSCONF
        mul bx
        add ax,di
        jc PackGraphBad
        cmp ax,OFFSET BIOS_BDS_TEMPLATES_START
        ja PackGraphBad         ; never overwrite a still-needed template
        mov BIOS_PACKED_GRAPH_END,ax
        mov si,WORD PTR START_BDS
        xor bx,bx
PackGraphValidate:
        cmp si,-1
        je PackGraphBad
        cmp FakeFloppyDrv,1
        jne PackGraphCheckLetter
        cmp bx,2
        jb PackGraphCheckRange  ; fake A/B templates have no initialized letters
PackGraphCheckLetter:
        cmp [si.DRIVELET],bl
        jne PackGraphBad
PackGraphCheckRange:
        mov ax,si
        add ax,SIZE BDS_TYPE
        jc PackGraphBad
        cmp si,bp               ; destination must not overlap any source
        jae PackGraphValidateTail
        cmp ax,bp
        ja PackGraphBad
        jmp short PackGraphValidateNext
PackGraphValidateTail:
        cmp si,BIOS_PACKED_GRAPH_END
        jb PackGraphBad
PackGraphValidateNext:
        cmp WORD PTR [si.LINK],-1
        je PackGraphValidateLast
        mov ax,cs
        cmp WORD PTR [si.LINK+2],ax
        jne PackGraphBad
PackGraphValidateLast:
        mov si,WORD PTR [si.LINK]
        inc bx
        loop PackGraphValidate
        cmp si,-1
        jne PackGraphBad

        cli
        cld
        mov BIOS_PACKED_GRAPH_START,bp
        mov CompactDpbStorage,di
        mov di,bp
        mov si,WORD PTR START_BDS
        mov bx,OFFSET DSKDRVS
        xor dx,dx
        mov dl,DRVMAX
PackGraphCopy:
        push WORD PTR [si.LINK]
        mov ax,di
        add ax,BYTEPERSEC
        mov [bx],ax             ; complete active BPB-pointer array
        add bx,2
        push di
        mov cx,SIZE BDS_TYPE
        rep movsb
        pop si
        mov al,DRVMAX
        sub al,dl
        mov BYTE PTR [si.DRIVELET],al
        mov WORD PTR [si.LINK],di
        mov WORD PTR [si.LINK+2],cs
        pop si
        dec dx
        jnz PackGraphCopy
        mov WORD PTR [di-SIZE BDS_TYPE+LINK],-1
        mov WORD PTR START_BDS,bp
        mov WORD PTR START_BDS+2,cs
        mov cx,BIOS_PACKED_GRAPH_END
        sub cx,di
        xor ax,ax
        rep stosb               ; selected-size overflow DPBs
        push di
        mov di,OFFSET BIOS_BDS_TEMPLATES_START
        mov cx,OFFSET BIOS_BDS_TEMPLATES_END
        sub cx,di
        mov al,0a5h             ; catch every stale template consumer
        rep stosb
        pop ax
        pop es
        pop ds
        pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        popf
        ret
PackGraphBad:
        ; A malformed/overlapping graph must not earn a shortened low break.
        mov ax,0e47h
        xor bx,bx
        int 10h
        cli
PackGraphHalt:
        hlt
        jmp short PackGraphHalt
PackBootDriveGraph ENDP
