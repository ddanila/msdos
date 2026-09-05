; Development-only relocation of the newly initialized extra SFT/FCB block.
; Keep the fixed-profile UMB cost bounded to 74 payload paragraphs + one MCB.
TableLowStart DW 0
TableParagraphs DW 0
TableFcbDelta DW 0
TableRoot DD 0
TableOldStrategy DW 0
TableOldLink DW 0
TableUpper DW 0
MoveBootTablesUpper PROC NEAR
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
        cmp cs:[TableUpper],0
        jne TableDone
        cmp cs:[DosUmbRequested],0
        je TableDone
        cmp cs:[Files],5
        jbe TableDone
        cmp cs:[Fcbs],0
        je TableDone
        mov ax,1232h
        int 2fh
        or ax,ax
        jz TableDone
        mov ax,cs:[MemHi]
        sub ax,cs:[TableLowStart]
        jbe TableDone
        cmp ax,74
        ja TableDone
        mov cs:[TableParagraphs],ax
        cmp cs:[MemLo],0
        jne TableDone
        les di,cs:[DosInfo]
        lds si,es:[di.SYSI_SFT]
        mov word ptr cs:[TableRoot],si
        mov word ptr cs:[TableRoot+2],ds
        lds si,ds:[si.SFLink]
        or si,si
        jnz TableDone
        mov ax,ds
        dec ax
        cmp ax,cs:[TableLowStart]
        jne TableDone
        xor cx,cx
        mov cl,cs:[Files]
        sub cx,5
        call TableValidateEmpty
        jc TableDone
        lds si,es:[di.SYSI_FCB]
        or si,si
        jnz TableDone
        mov ax,ds
        sub ax,cs:[TableLowStart]
        jbe TableDone
        cmp ax,cs:[TableParagraphs]
        jae TableDone
        mov cs:[TableFcbDelta],ax
        xor cx,cx
        mov cl,cs:[Fcbs]
        call TableValidateEmpty
        jc TableDone
        call AcquireUmbs
        mov ax,5800h
        int 21h
        jc TableDone
        mov cs:[TableOldStrategy],ax
        mov ax,5802h
        int 21h
        jc TableDone
        xor ah,ah
        mov cs:[TableOldLink],ax
        mov bx,1
        mov ax,5803h
        int 21h
        jc TableDone
        mov bx,40h
        mov ax,5801h
        int 21h
        jc TableRestore
        mov bx,cs:[TableParagraphs]
        IFDEF BIOS_TABLES_FAIL_ALLOC
        mov bx,0ffffh
        ENDIF
        mov ah,48h
        int 21h
        jc TableRestore
        mov cs:[TableUpper],ax
TableRestore:
        mov bx,cs:[TableOldStrategy]
        mov ax,5801h
        int 21h
        mov bx,cs:[TableOldLink]
        mov ax,5803h
        int 21h
        cmp cs:[TableUpper],0
        je TableDone
        ; No DOS calls after publication until both views are coherent.
        cli
        mov es,cs:[TableUpper]
        mov ds,cs:[TableLowStart]
        xor si,si
        xor di,di
        mov cx,cs:[TableParagraphs]
        shl cx,1
        shl cx,1
        shl cx,1
        rep movsw
        mov ax,es
        inc ax
        mov es:[DEVMARK_SEG],ax
        mov bx,cs:[TableFcbDelta]
        dec bx
        shl bx,1
        shl bx,1
        shl bx,1
        shl bx,1
        mov dx,cs:[TableUpper]
        add dx,cs:[TableFcbDelta]
        mov es:[bx.DEVMARK_SEG],dx
        lds si,cs:[TableRoot]
        mov word ptr ds:[si.SFLink+2],ax
        les di,cs:[DosInfo]
        mov word ptr es:[di.SYSI_FCB+2],dx
        mov ax,cs:[TableUpper]
        dec ax
        mov es,ax
        mov es:[arena_owner],8
        mov ax,cs:[TableLowStart]
        mov cs:[MemHi],ax
        mov cs:[MemLo],0
        ; EndFile will construct the next marked allocation at the old start.
TableDone:
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
MoveBootTablesUpper ENDP

; DS:0 is a single terminal table, CX its expected count. Preserve ES:DI.
TableValidateEmpty PROC NEAR
        cmp word ptr ds:[SFLink],-1
        jne TableNotEmpty
        cmp ds:[SFCount],cx
        jne TableNotEmpty
        mov si,SFTable
TableEntry:
        cmp word ptr ds:[si.sf_ref_count],0
        jne TableNotEmpty
        add si,size sf_entry
        loop TableEntry
        clc
        ret
TableNotEmpty:
        stc
        ret
TableValidateEmpty ENDP
