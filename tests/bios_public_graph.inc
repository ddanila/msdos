; Public INT 21h/52h graph, with structure offsets compiled from repository INCs.
; Called while LOWTEST.TMP is open; preserve its handle and the caller's DS.
check_public_graph:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov ah,19h
    int 21h
    mov [cs:public_current_drive],al
    mov ah,52h
    int 21h
    mov [cs:public_list],bx
    mov [cs:public_list+2],es
%ifdef EXPECT_TABLES_UPPER
    push es
    push bx
    les si,[es:bx+PUB_SYSI_SFT]
    les si,[es:si+PUB_SFLINK]
    mov ax,es
%if EXPECT_TABLES_UPPER
    cmp ax,0a000h
    jb fail
    dec ax
    mov [cs:public_table_owner],ax
    push es
    dec ax
    mov es,ax
    cmp word [es:1],8
    jne fail
    cmp word [es:3],EXPECT_TABLE_PARAS
    jne fail
    pop es
%else
    cmp ax,0a000h
    jae fail
%endif
    cmp word [es:si+PUB_SFCOUNT],EXPECT_EXTRA_SFT
    jne fail
    pop bx
    pop es
    push es
    les si,[es:bx+PUB_SYSI_FCB]
%ifdef EXPECT_FCB_REPLACED
    ; SHARE replaces the default 4,0 cache with its own resident 16,8 cache.
    ; This is the active cache exercised by I21FCB, not the retired boot cache.
    cmp word [es:si+PUB_SFCOUNT],16
    jne fail
    cmp word [es:si+PUB_SFLINK],0ffffh
    jne fail
    mov ax,es
    cmp ax,0a000h
    jae fail
%else
    cmp word [es:si+PUB_SFCOUNT],4
    jne fail
    mov ax,es
%if EXPECT_TABLES_UPPER
    sub ax,[cs:public_table_owner]
    cmp ax,EXPECT_FCB_DELTA
    jne fail
%else
    cmp ax,0a000h
    jae fail
%endif
%endif
    pop es
%endif
%if EXPECT_TABLES_UPPER
    call check_upper_table_access
%endif
%ifdef STALE_CDS_CONTROL
    ; Deliberately restore an external pointer to the retired owner. A simple
    ; successful DOS call must not let this broken graph earn a PASS result.
    push es
    mov ax,70h
    mov es,ax
    mov ax,[es:RB_FROM]
    pop es
    push es
    les si,[es:bx+PUB_SYSI_CDS]
    mov [es:si+PUB_CURDIR_DEVPTR+2],ax
    pop es
    push bx
    push es
    mov dx,public_control_ready
    mov ah,9
    int 21h
    pop es
    pop bx
%endif
%if EXPECT_REBASE
    push es
    mov ax,70h
    mov es,ax
    mov ax,[es:RB_TO]
    pop es
    mov dx,es
    cmp ax,dx
    jne fail
%endif
    cmp byte [es:bx+PUB_SYSI_NCDS],EXPECT_CDS
    jne fail
    xor cx,cx
    mov cl,[es:bx+PUB_SYSI_NUMIO]
    cmp cx,2
    jb fail
    cmp cx,6
    ja fail
    mov [cs:public_drives],cx
    les si,[es:bx+PUB_SYSI_DPB]
    xor bp,bp
.dpb:
    call check_public_owner
    mov ax,bp
    cmp [es:si],al
    jne fail
    cmp word [es:si+PUB_DPB_SECTOR_SIZE],512
    jne fail
    mov di,bp
    shl di,1
    shl di,1
    mov [cs:public_dpbs+di],si
    mov [cs:public_dpbs+di+2],es
    push es
    push si
    les si,[es:si+PUB_DPB_DRIVER_ADDR]
    call check_public_owner
    test word [es:si+PUB_SDEVATT],8000h
    jnz fail
    pop si
    pop es
    les si,[es:si+PUB_DPB_NEXT_DPB]
    inc bp
    loop .dpb
    cmp si,0ffffh
    jne fail

    les bx,[cs:public_list]
    les si,[es:bx+PUB_SYSI_CDS]
    mov cx,[cs:public_drives]
    xor di,di
.cds:
    mov ax,[es:si+PUB_CURDIR_DEVPTR]
    cmp ax,[cs:public_dpbs+di]
    jne fail
    mov ax,[es:si+PUB_CURDIR_DEVPTR+2]
    cmp ax,[cs:public_dpbs+di+2]
    jne fail
    add di,4
    add si,PUB_CURDIRLEN
    loop .cds

    ; NUL anchors the driver list; every successor must terminate within budget.
    les bx,[cs:public_list]
    lea si,[bx+PUB_SYSI_DEV]
    cmp word [es:si+PUB_SDEVNAME],'NU'
    jne fail
    mov cx,32
    xor bp,bp
.device:
    call check_public_owner
    inc bp
    les si,[es:si+PUB_SDEVNEXT]
    cmp si,0ffffh
    je .devices_done
    loop .device
    jmp fail
.devices_done:
    cmp bp,5
    jb fail

    ; Walk active SFTs, including the live temporary disk file's DPB pointer.
    les bx,[cs:public_list]
    les si,[es:bx+PUB_SYSI_SFT]
    mov bp,32
    mov byte [cs:public_found],0
.sft_table:
    call check_public_owner
    mov cx,[es:si+PUB_SFCOUNT]
    cmp cx,255
    ja fail
    push es
    push si
    add si,PUB_SFTABLE
.sft_entry:
    jcxz .sft_next
    cmp word [es:si+PUB_SF_REF_COUNT],0
    je .sft_skip
    push es
    push si
    les si,[es:si+PUB_SF_DEVPTR]
    call check_public_owner
    pop si
    pop es
    push cx
    push si
    lea di,[si+PUB_SF_NAME]
    mov si,public_name
    push cs
    pop ds
    mov cx,11
    cld
    repe cmpsb
    pop si
    pop cx
    jne .sft_skip
%if EXPECT_TABLES_UPPER
    mov ax,es
    cmp ax,0a000h
    jb fail
%endif
    xor di,di
    mov dl,[cs:public_current_drive]
    xor dh,dh
    cmp dx,[cs:public_drives]
    jae fail
    mov di,dx
    shl di,1
    shl di,1
    mov ax,[es:si+PUB_SF_DEVPTR]
    cmp ax,[cs:public_dpbs+di]
    jne fail
    mov ax,[es:si+PUB_SF_DEVPTR+2]
    cmp ax,[cs:public_dpbs+di+2]
    jne fail
    inc byte [cs:public_found]
.sft_skip:
    add si,PUB_SF_ENTRY_SIZE
    loop .sft_entry
.sft_next:
    pop si
    pop es
    les si,[es:si+PUB_SFLINK]
    cmp si,0ffffh
    je .sft_done
    dec bp
    jnz .sft_table
    jmp fail
.sft_done:
    cmp byte [cs:public_found],1
    jne fail
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

check_public_owner:
%if EXPECT_REBASE
    push ax
    push dx
    push ds
    mov ax,70h
    mov ds,ax
    mov dx,es
    cmp dx,[RB_FROM]
    je fail
    pop ds
    pop dx
    pop ax
%endif
    ret
public_list dd 0
public_drives dw 0
public_dpbs times 6 dd 0
public_found db 0
public_current_drive db 0
public_table_owner dw 0
%if EXPECT_TABLES_UPPER
%include "bios_upper_access.inc"
%endif
public_name db 'LOWTEST TMP'
%ifdef STALE_CDS_CONTROL
public_control_ready db 'BIOS_PUBLIC_CONTROL_READY',13,10,'$'
%endif
