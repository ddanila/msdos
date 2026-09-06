; Independent UMB test owner inside the installed protected provider.
; Callers must freeze their original allocator before publication and own the
; backing. This entry never switches HIMEM's public/peer entries by itself.
MAX_UMB_BLOCKS equ 32
UMB_BLOCK_SIZE equ 4
UMB_ALLOCATED equ 08000h
include XMSUMBPEER.INC
public XmsUmbOwner, XmsUmbActive, XmsUmbImports, XmsUmbStorageEnd
XmsUmbOwner proc near
        pushad
        push ds
        cmp si,65536-20
        ja umb_owner_bad
        cmp word ptr es:[si+4],1
        jne umb_owner_bad
        cmp word ptr es:[si+8],0
        jne umb_owner_bad
        mov bp,si
        mov ax,VDMCA_GSEL
        mov ds,ax
        mov ax,es:[bp+6]
        or ax,ax
        jz umb_owner_receipt
        cmp ax,1
        je umb_owner_import
        cmp [XmsUmbActive],1
        jne umb_owner_bad
        mov dx,es:[bp+12]
        mov bx,es:[bp+14]
        cmp ax,12h
        je umb_owner_register
        cmp ax,13h
        je umb_owner_unregister
        cmp ax,10h
        je umb_owner_allocate
        cmp ax,11h
        jne umb_owner_bad
        push bp
        call xms_umb_release
        pop bp
        jmp umb_owner_result
umb_owner_allocate:
        push bp
        call xms_umb_request
        pop bp
        jmp umb_owner_result
umb_owner_import:
        cmp [XmsUmbActive],0
        jne umb_owner_bad
        ; Swap explicit owners: DS client, ES high destination. BP retains
        ; the client packet offset; the staging helper preserves registers.
        push ds
        push es
        pop ds
        pop es
        mov si,ds:[bp+16]
        mov cx,ds:[bp+18]
        mov di,offset umb_count
        mov bx,MAX_UMB_BLOCKS
        call xms_stage_umb
        push ds
        push es
        pop ds
        pop es
        jc umb_owner_bad
        mov [XmsUmbActive],1
        inc [XmsUmbImports]
        jmp short umb_owner_receipt
umb_owner_register:
        mov si,es:[bp+16]
        cmp si,0fffch
        ja umb_owner_bad
        mov cx,es:[bp+18]
        ; The shared validator takes count/records, after the version word.
        push ds
        push es
        pop ds
        add si,2
        call xms_validate_umb
        lea si,[si-2]         ; restore packet start without changing CF
        pop ds
        jc umb_owner_bad
        push bp
        push dx
        call umb_high_register
        pop dx
        pop bp
        jmp short umb_owner_result
umb_owner_unregister:
        call umb_high_unregister
        jmp short umb_owner_result
umb_owner_receipt:
        xor ax,ax
        mov al,[XmsUmbActive]
        mov bx,[XmsUmbImports]
        xor dx,dx
        or ax,ax
        jz umb_owner_result
        mov dx,[umb_count]
umb_owner_result:
        mov es:[bp+10],ax
        mov es:[bp+12],dx
        mov es:[bp+14],bx
        pop ds
        popad
        clc
        ret
umb_owner_bad:
        pop ds
        popad
        stc
        ret
XmsUmbOwner endp
umb_high_register proc near
        HIMEM_UMB_REGISTER
private_done:
        ret
umb_high_register endp
umb_high_unregister proc near
        HIMEM_UMB_UNREGISTER
private_unregister_done:
        ret
umb_high_unregister endp
include XMSUMB.INC
include XMSUMBSTATE.INC
XmsUmbActive db 0
XmsUmbImports dw 0
umb_count dw 0
umb_blocks db MAX_UMB_BLOCKS*UMB_BLOCK_SIZE dup (0)
umb_blocks_end label byte
XmsUmbStorageEnd label byte
