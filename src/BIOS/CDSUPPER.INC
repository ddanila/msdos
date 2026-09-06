; Development: move the complete newly initialized CDS allocation, not a
; later application's cached table. The low block includes its DEVMARK.
        INCLUDE CDSUPPER_DEFS.INC
        IFDEF BIOS_CDS_SKIP_CACHE_REBASE
        IFNDEF BIOS_CDS_CACHE_CASE
        .ERR <CDS cache mutation requires the test fixture>
        ENDIF
        ENDIF
CdsLowStart DW 0
CdsParagraphs DW 0
CdsBytes DW 0
CdsUpper DW 0
CdsOldStrategy DW 0
CdsOldLink DW 0
CdsRestoreFailed DB 0
MoveBootCdsUpper PROC NEAR
        pushf
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push ds
        push es
        cld
        cmp cs:[DosUmbRequested],0
        je CdsDone
        cmp cs:[CdsUpper],0
        jne CdsDone
        mov ax,1232h
        int 2fh
        or ax,ax
        jz CdsDone
        cmp cs:[MemLo],0
        jne CdsDone
        les di,cs:[DosInfo]
        cmp word ptr es:[di.SYSI_CDS],0
        jne CdsDone
        mov ax,cs:[CdsLowStart]
        inc ax
        cmp ax,word ptr es:[di.SYSI_CDS+2]
        jne CdsDone
        mov al,es:[di.SYSI_NCDS]
        or al,al
        jz CdsDone
        cmp al,26
        ja CdsDone
        mov ah,size curdir_list
        mul ah
        mov cs:[CdsBytes],ax
        call ParaRound
        inc ax                  ; include DEVMARK
        mov cs:[CdsParagraphs],ax
        add ax,cs:[CdsLowStart]
        cmp ax,cs:[MemHi]
        jne CdsDone
        call AcquireUmbs
        mov ax,5800h
        int 21h
        jc CdsDone
        mov cs:[CdsOldStrategy],ax
        mov ax,5802h
        int 21h
        jc CdsDone
        xor ah,ah
        mov cs:[CdsOldLink],ax
        mov bx,1
        mov ax,5803h
        int 21h
        jc CdsDone
        mov bx,40h
        mov ax,5801h
        int 21h
        jc CdsRestore
        mov bx,cs:[CdsParagraphs]
        IFDEF BIOS_CDS_FAIL_ALLOC
        mov bx,0ffffh
        ENDIF
        mov ah,48h
        int 21h
        jc CdsRestore
        mov cs:[CdsUpper],ax
CdsRestore:
        mov bx,cs:[CdsOldStrategy]
        mov ax,5801h
        int 21h
        jnc CdsRestoreLink
        mov cs:[CdsRestoreFailed],1
CdsRestoreLink:
        mov bx,cs:[CdsOldLink]
        mov ax,5803h
        int 21h
        jnc CdsRestored
        mov cs:[CdsRestoreFailed],1
CdsRestored:
        IFDEF BIOS_CDS_CACHE_CASE
        call CdsCacheSeed
        ENDIF
        cmp cs:[CdsUpper],0
        je CdsDone
        cmp cs:[CdsRestoreFailed],0
        je CdsPublish
        mov es,cs:[CdsUpper]
        mov ah,49h
        int 21h
        mov cs:[CdsUpper],0
        jmp CdsDone
CdsPublish:
        cli
        mov es,cs:[CdsUpper]
        mov ds,cs:[CdsLowStart]
        xor si,si
        xor di,di
        mov cx,cs:[CdsParagraphs]
        shl cx,1
        shl cx,1
        shl cx,1
        rep movsw
        mov ax,es
        inc ax
        mov es:[DEVMARK_SEG],ax
        les di,cs:[DosInfo]
        mov dx,cs:[CdsLowStart]
        inc dx
        cmp word ptr es:[CDS_THISCDS+2],dx
        jne CdsPublicRoot
        mov bx,word ptr es:[CDS_THISCDS]
        cmp bx,cs:[CdsBytes]
        jae CdsPublicRoot
        IFNDEF BIOS_CDS_SKIP_CACHE_REBASE
        mov word ptr es:[CDS_THISCDS+2],ax
        ENDIF
CdsPublicRoot:
        mov word ptr es:[di.SYSI_CDS+2],ax
        mov ax,cs:[CdsUpper]
        dec ax
        mov es,ax
        mov es:[arena_owner],8
        mov ax,cs:[CdsLowStart]
        mov cs:[MemHi],ax
        mov cs:[MemLo],0
CdsDone:
        IFDEF BIOS_CDS_CACHE_CASE
        call CdsCacheCheck
        ENDIF
        pop es
        pop ds
        pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        popf
        ret
MoveBootCdsUpper ENDP
        IFDEF BIOS_CDS_CACHE_CASE
        INCLUDE CDSCACHE.INC
        ENDIF
