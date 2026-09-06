; Exercise installed GETBP with a private BDS and synthetic read-only INT 13h
; results: invalid-boot/F9 fallback or a valid BPB with optional extended IDs.
; No disk is modified.
bits 16
org 100h
%include "media-defs.inc"
start:
    mov al,'B'
    out 0e9h,al
    cli
    cld
    mov ax,70h
    mov es,ax
%if ID_MODE
    mov al,[es:ID_FLAG]
    mov [saved_id_flag],al
    mov byte [es:ID_FLAG],1
%if ID_MODE = 3
    mov byte [es:ID_FLAG],0
%endif
%endif
    cmp byte [es:ACTIVE],EXPECT_ACTIVE
    jne fail
%if EXPECT_POISON
    mov di,OLD_START
    mov cx,OLD_SIZE/2
    mov ax,0f4fah
    repe scasw
    jne fail
%endif
    ; Brief same-segment near caller, restored before ending the probe.
    xor si,si
    mov di,saved_entry
    mov cx,8
.save:
    mov ax,[es:si]
    mov [di],ax
    add si,2
    add di,2
    loop .save
    mov byte [es:0],0e8h
    mov word [es:1],GETBP_ENTRY-3
    mov byte [es:3],0cbh
%if !ID_MODE
    ; Boot may purge this call for the detected ROM. Select the compiled
    ; density branch explicitly for this bounded test, then restore it.
    mov bx,PATCH_OFFSET
%if EXPECT_ACTIVE
    add bx,[es:HIGH_GETBP]
    sub bx,HIGH_GETBP_OFFSET
    mov ax,0ffffh
    mov es,ax
%endif
    mov [patch_address],bx
    mov ax,es
    mov [patch_segment],ax
    mov al,[es:bx]
    mov [patch_saved],al
    mov ax,[es:bx+1]
    mov [patch_saved+1],ax
    cmp byte [patch_saved],0e8h
    jne .expect_purged
    cmp ax,PATCH_DISPLACEMENT
    jne fail
    jmp .select_density
.expect_purged:
    cmp byte [patch_saved],090h
    jne fail
    cmp ax,09090h
    jne fail
.select_density:
    mov byte [es:bx],0e8h
    mov word [es:bx+1],PATCH_DISPLACEMENT
    mov ax,70h
    mov es,ax
%endif
%if OMIT_UNWIND
    mov bx,[es:HIGH_GETBP]
    sub bx,HIGH_GETBP_OFFSET
    add bx,HIGH_UNWIND_OFFSET
    push es
    mov ax,0ffffh
    mov es,ax
    cmp word [es:bx],0c483h
    jne fail
    cmp byte [es:bx+2],2
    jne fail
    mov word [es:bx],09090h
    mov byte [es:bx+2],090h
    pop es
%endif
%if OMIT_ID_COPY
    mov bx,[es:HIGH_GETBP]
    sub bx,HIGH_GETBP_OFFSET
    add bx,HIGH_ID_COPY_OFFSET
    push es
    mov ax,0ffffh
    mov es,ax
    cmp byte [es:bx],ID_COPY_OPCODE
    jne fail
    mov byte [es:bx],0c3h
    pop es
%endif
    xor ax,ax
    mov es,ax
    mov ax,[es:13h*4]
    mov [old13],ax
    mov ax,[es:13h*4+2]
    mov [old13+2],ax
    mov word [es:13h*4],read_hook
    mov [es:13h*4+2],cs
    mov word [bds+B_BYTEPERSEC],512
    mov word [bds+B_RESSEC],1
    mov byte [bds+B_CFAT],2
    mov word [bds+B_FLAGS],B_FCHANGELINE
    mov byte [bds+B_FORMFACTOR],B_FF96TPI
%if ID_MODE
    push ds
    pop es
    mov di,bds+B_VOL_SERIAL
    mov ax,0cccch
    stosw
    stosw
    mov di,bds+B_VOLID
    mov cx,12
    mov al,0a5h
    rep stosb
    mov di,bds+B_FILESYS_ID
    mov cx,9
    mov al,05ah
    rep stosb
%endif
    mov ax,1234h
    mov es,ax
    mov bx,5678h
    mov cx,9abch
    mov dx,0def0h
    mov di,bds
    mov bp,4242h
    mov [saved_sp],sp
    mov al,'D'
    out 0e9h,al
    call 70h:0
    mov byte [cs:stage],1
    jc fail
    mov byte [cs:stage],2
    cmp sp,[cs:saved_sp]
    jne fail
    cmp bx,5678h
    jne fail
    cmp cx,9abch
    jne fail
    cmp dx,0def0h
    jne fail
    cmp bp,4242h
    jne fail
    cmp di,bds
    jne fail
    mov ax,es
    cmp ax,1234h
    jne fail
    mov ax,ds
    mov bx,cs
    cmp ax,bx
    jne fail
    cmp byte [reads],EXPECTED_READS
    jne fail
    mov byte [stage],3
%macro check_word 2
    inc byte [stage]
    cmp word [bds+B_%1],%2
    jne fail
%endmacro
%macro check_byte 2
    inc byte [stage]
    cmp byte [bds+B_%1],%2
    jne fail
%endmacro
    check_word BYTEPERSEC,512
    check_word RESSEC,1
    check_byte CFAT,2
    check_byte SECPERCLUS,1
    check_word CDIR,224
    check_word DRVLIM,2400
    check_byte MEDIAD,0f9h
    check_word CSECFAT,7
    check_word SECLIM,15
    check_word HDLIM,2
    check_word HIDSEC_L,0
    check_word HIDSEC_H,0
    check_word DRVLIM_H,0
%if ID_MODE
    mov byte [stage],32
    push ds
    pop es
%if ID_MODE = 1
    cmp word [bds+B_VOL_SERIAL],0c3d4h
    jne fail
    cmp word [bds+B_VOL_SERIAL+2],0a1b2h
    jne fail
    mov si,volume_label
    mov di,bds+B_VOLID
    mov cx,11
    repe cmpsb
    jne fail
    mov si,filesystem_id
    mov di,bds+B_FILESYS_ID
    mov cx,8
    repe cmpsb
    jne fail
%else
    cmp word [bds+B_VOL_SERIAL],0cccch
    jne fail
    cmp word [bds+B_VOL_SERIAL+2],0cccch
    jne fail
    mov di,bds+B_VOLID
    mov cx,11
    mov al,0a5h
    repe scasb
    jne fail
    mov di,bds+B_FILESYS_ID
    mov cx,8
    mov al,05ah
    repe scasb
    jne fail
%endif
    cmp byte [bds+B_VOLID+11],0a5h
    jne fail
    cmp byte [bds+B_FILESYS_ID+8],05ah
    jne fail
    mov ax,70h
    mov es,ax
    cmp byte [es:ID_FLAG],EXPECTED_ID_FLAG
    jne fail
    mov al,[saved_id_flag]
    mov [es:ID_FLAG],al
%endif
    push ds
    pop es
    mov di,guard_before
    mov cx,8
    mov ax,0a5a5h
    repe scasw
    jne fail
    mov di,guard_after
    mov cx,8
    mov ax,05a5ah
    repe scasw
    jne fail
%if !ID_MODE
    mov es,[patch_segment]
    mov bx,[patch_address]
    mov al,[patch_saved]
    mov [es:bx],al
    mov ax,[patch_saved+1]
    mov [es:bx+1],ax
%endif
    xor ax,ax
    mov es,ax
    mov ax,[old13]
    mov [es:13h*4],ax
    mov ax,[old13+2]
    mov [es:13h*4+2],ax
    mov ax,70h
    mov es,ax
    mov si,saved_entry
    xor di,di
    mov cx,8
    rep movsw
    mov al,'P'
    out 0e9h,al
    mov ax,10h
    mov dx,0f4h
    out dx,ax
    hlt
fail:
    mov al,[cs:stage]
    out 0e9h,al
    mov ax,11h
    mov dx,0f4h
    out dx,ax
    hlt
    jmp fail
read_hook:
    cmp ax,0201h
    jne fail
    cmp cx,1
    jb fail
    cmp cx,2
    ja fail
    pusha
    inc byte [cs:reads]
    cmp cl,[cs:reads]
    jne fail
    mov al,cl
    add al,'0'
    out 0e9h,al
    mov di,bx
    push cx
    mov cx,256
    xor ax,ax
    rep stosw
    pop cx
%if ID_MODE
    cmp cl,1
    jne fail
    mov word [es:bx],03cebh
    mov byte [es:bx+2],090h
    push ds
    push cs
    pop ds
    mov si,synthetic_bpb
    lea di,[bx+11]
    mov cx,synthetic_bpb_end-synthetic_bpb
    rep movsb
    mov byte [es:bx+SECTOR_SIGNATURE],EXT_SIGNATURE
    mov word [es:bx+SECTOR_SERIAL],0c3d4h
    mov word [es:bx+SECTOR_SERIAL+2],0a1b2h
    lea di,[bx+SECTOR_LABEL]
    mov si,volume_label
    mov cx,11
    rep movsb
    lea di,[bx+SECTOR_FILESYSTEM]
    mov si,filesystem_id
    mov cx,8
    rep movsb
    pop ds
%else
    cmp cl,2
    jne .done
    mov byte [es:bx],0f9h
%endif
.done:
%if EXPECT_ACTIVE
    ; Return with A20 off; the actual retained firmware-return gate must
    ; restore it before resuming high READ_SECTOR/GETBP.
    push ds
    mov si,500h
.find_distinct:
    xor ax,ax
    mov ds,ax
    mov dx,[si]
    mov ax,0ffffh
    mov ds,ax
    cmp dx,[si+10h]
    jne .distinct
    add si,2
    cmp si,540h
    jb .find_distinct
    jmp fail
.distinct:
    in al,92h
    and al,0fch
    out 92h,al
    cmp dx,[si+10h]           ; physical alias proves A20 actually went off
    jne fail
    pop ds
%endif
    popa
    push bp
    mov bp,sp
    and word [ss:bp+6],0fffeh
    pop bp
    iret
old13 dd 0
saved_entry times 16 db 0
saved_sp dw 0
reads db 0
stage db 0
saved_id_flag db 0
volume_label db 'MEDIA TEST '
filesystem_id db 'FAT12   '
synthetic_bpb:
    dw 512
    db 1
    dw 1
    db 2
    dw 224,2400
    db 0f9h
    dw 7,15,2
    dd 0,0
synthetic_bpb_end:
patch_address dw 0
patch_segment dw 0
patch_saved times 3 db 0
guard_before times 16 db 0a5h
bds times B_SIZE db 0
guard_after times 16 db 05ah
