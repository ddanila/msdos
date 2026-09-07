; Disposable SYSINIT transaction. Keep the existing interrupt code/control low;
; initialize the entire entry table and stack pool directly in its final UMB.
; AX = rounded pool paragraphs. Preserve registers; CF = upper pool selected.
StackPoolParas DW 0
StackPoolUpper DW 0
StackPoolStrategy DW 0
StackPoolLink DW 0
StackPoolRestoreFailed DB 0
AllocateStackPoolUpper PROC NEAR
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
        mov cs:[StackPoolParas],ax
        ; HMA availability is not DOS-high selection: DOS_HMA_PREPARE may
        ; acquire HMA even for DOS=LOW. Preserve the explicitly low path.
        cmp cs:[DosHighRequested],0
        je StackPoolDone
        cmp cs:[DosUmbRequested],0
        je StackPoolDone
        mov ax,1232h
        int 2fh
        or ax,ax
        jz StackPoolDone
        call AcquireUmbs
        mov ax,5800h
        int 21h
        jc StackPoolDone
        mov cs:[StackPoolStrategy],ax
        mov ax,5802h
        int 21h
        jc StackPoolDone
        xor ah,ah
        mov cs:[StackPoolLink],ax
        mov bx,1
        mov ax,5803h
        int 21h
        jc StackPoolRestore
        mov bx,40h                   ; upper only, never take a second low pool
        mov ax,5801h
        int 21h
        jc StackPoolRestore
        mov bx,cs:[StackPoolParas]
        inc bx                       ; separate S mark
        IFDEF BIOS_STACK_POOL_FAIL_ALLOC
        mov bx,0ffffh
        ENDIF
        mov ah,48h
        int 21h
        jc StackPoolRestore
        mov cs:[StackPoolUpper],ax
StackPoolRestore:
        mov bx,cs:[StackPoolStrategy]
        mov ax,5801h
        int 21h
        jnc StackPoolRestoreLink
        mov cs:[StackPoolRestoreFailed],1
StackPoolRestoreLink:
        mov bx,cs:[StackPoolLink]
        mov ax,5803h
        int 21h
        jnc StackPoolRestored
        mov cs:[StackPoolRestoreFailed],1
StackPoolRestored:
        cmp cs:[StackPoolUpper],0
        je StackPoolDone
        cmp cs:[StackPoolRestoreFailed],0
        jne StackPoolRelease
        cmp cs:[StackPoolUpper],0a000h
        jb StackPoolRelease
        mov ax,cs:[StackPoolUpper]
        add ax,cs:[StackPoolParas]
        jc StackPoolRelease
        inc ax
        jz StackPoolRelease
        ; Nothing points at this pool yet. Zero its mark, entries and padding;
        ; StackInit builds entries/back-pointers before installing any vectors.
        mov es,cs:[StackPoolUpper]
        xor di,di
        mov cx,cs:[StackPoolParas]
        inc cx
        shl cx,1
        shl cx,1
        shl cx,1
        xor ax,ax
        rep stosw
        mov es:[DEVMARK_ID],DEVMARK_STK
        mov ax,cs:[StackPoolUpper]
        inc ax
        mov es:[DEVMARK_SEG],ax
        mov dx,cs:[StackPoolParas]
        mov es:[DEVMARK_SIZE],dx
        mov word ptr cs:[STACK_ADDR],0
        mov word ptr cs:[STACK_ADDR+2],ax
        sub ax,2
        mov es,ax
        mov es:[arena_owner],8
        jmp short StackPoolDone
StackPoolRelease:
        mov es,cs:[StackPoolUpper]
        mov ah,49h
        int 21h
        mov cs:[StackPoolUpper],0
StackPoolDone:
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
        cmp cs:[StackPoolUpper],0
        je StackPoolLow
        stc
        ret
StackPoolLow:
        clc
        ret
AllocateStackPoolUpper ENDP
