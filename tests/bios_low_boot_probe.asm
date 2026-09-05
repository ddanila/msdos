bits 16
org 100h
%include "low-defs.inc"
%ifdef EXPECT_REBASE
%include "BIOSREBASE_DEFS.INC"
%include "public-layout.inc"
%endif
%ifndef EXPECT_ACTIVE
%define EXPECT_ACTIVE 0
%endif
%ifdef ACTIVATE_HIGH
%include "activation-defs.inc"
%define CHECK_RAW_DISK
%endif
%if EXPECT_ACTIVE
%define CHECK_RAW_DISK
%endif
start:
%ifdef EXPECT_CDS
    mov ah,19h
    int 21h
    mov dl,al
    push dx
    mov dl,25
    mov ah,0eh
    int 21h
    cmp al,EXPECT_CDS
    pop dx
    jne fail
    mov ah,0eh
    int 21h
%endif
    mov ax,70h
    mov es,ax
%ifdef EXPECT_REBASE
%if EXPECT_REBASE
    mov ax,[es:RB_FROM]
    or ax,ax
    jz fail
    mov bx,[es:RB_PERMANENT_END]
    add bx,70h
    cmp bx,[es:RB_TO]
    jne fail
%ifndef EXPECT_COMPACT
    push es
    mov es,ax
    xor di,di
    mov cx,RB_LOW_PARAS*8
    mov ax,0a5a5h
    cld
    repe scasw
    pop es
    jne fail
%endif
    push es
    mov ax,0ffffh
    mov es,ax
    cmp bx,[es:RB_LOW_OWNER]
%ifdef EXPECT_COMPACT
    jne fail
    add bx,RB_LOW_PARAS
    cmp bx,[es:RB_ARENA_HEAD]
%endif
    pop es
    jne fail
%else
    cmp word [es:RB_FROM],0
    jne fail
    cmp word [es:RB_TO],0
    jne fail
%endif
%endif
%ifdef PERMANENT_END_OFFSET
    ; Boot selected a permanent prefix below the separately reserved fallback.
    ; Keeping the fallback reserved is intentional until DOS can be rebased.
    mov ax,[es:PERMANENT_END_OFFSET]
    or ax,ax
    jz fail
    cmp ax,SERVICE_START/16
    ja fail
%endif
    cmp byte [es:ACTIVE_OFFSET],EXPECT_ACTIVE
    jne fail
%if EXPECT_ACTIVE
%ifndef EXPECT_COMPACT
    mov di,SERVICE_START
    mov cx,SERVICE_SIZE/2
    mov ax,0f4fah
    cld
    repe scasw
    jne fail
%endif
%endif
    mov si,slots
    mov cx,SLOT_WORD_COUNT
.slot:
    lodsw
    mov bx,ax
    cmp word [es:bx],0
%if EXPECT_ACTIVE
    je fail
%else
    jne fail
%endif
    loop .slot
    mov ax,1236h
    mov cx,16
    int 2fh
%if EXPECT_HIGH
    or ax,ax
    jz fail
    mov ax,es
    cmp ax,0ffffh
    jne fail
    mov word [es:di],0a55ah
    cmp word [es:di],0a55ah
    jne fail
%else
    or ax,ax
    jnz fail
%endif
%ifdef ACTIVATE_HIGH
    call activate_live_bios
%endif
%ifdef EXPECT_REBASE
    call check_ctrlc_path
%endif
    mov dx,filename
    xor cx,cx
    mov ah,3ch
    int 21h
    jc fail
    mov bx,ax
%ifdef EXPECT_REBASE
    call check_public_graph
%endif
    mov dx,pattern
    mov cx,4
    mov ah,40h
    int 21h
    jc fail
    cmp ax,4
    jne fail
    xor cx,cx
    xor dx,dx
    mov ax,4200h
    int 21h
    jc fail
    mov dx,buffer
    mov cx,4
    mov ah,3fh
    int 21h
    jc fail
    cmp ax,4
    jne fail
    mov ah,3eh
    int 21h
    jc fail
    mov ax,[pattern]
    cmp [buffer],ax
    jne fail
    mov ax,[pattern+2]
    cmp [buffer+2],ax
    jne fail
    mov dx,filename
    mov ah,41h
    int 21h
    jc fail
%ifdef CHECK_RAW_DISK
    ; Force BIOS-backed writes, then a raw read through the live INT 13h entry.
    mov ah,0dh
    int 21h
    push cs
    pop es
    mov bx,sector
    mov ax,0201h
    mov cx,1
    xor dx,dx
    int 13h
    jc fail
    cmp word [sector+510],0aa55h
    jne fail
    cmp word [sector_before],1234h
    jne fail
    cmp word [sector_after],5678h
    jne fail
%endif
%ifdef WARM_RESET
    ; Repeat every preceding assertion after a host-controlled hardware reset.
    mov dx,warm_tag
    mov ax,3d00h
    int 21h
    jnc warm_second_boot
    cmp ax,2
    jne fail
    xor cx,cx
    mov ah,3ch
    int 21h
    jc fail
    mov bx,ax
    mov ah,3eh
    int 21h
    jc fail
    mov ah,0dh
    int 21h
    mov dx,warm_ready
    mov ah,9
    int 21h
warm_wait:
    sti
    hlt
    jmp warm_wait
warm_second_boot:
    mov bx,ax
    mov ah,3eh
    int 21h
    jc fail
    mov dx,warm_tag
    mov ah,41h
    int 21h
    jc fail
%endif
    mov dx,passed
    mov ah,9
    int 21h
    mov ax,10h
    jmp finish
fail:
    push cs
    pop ds
    mov dx,failed
    mov ah,9
    int 21h
    mov ax,11h
finish:
    mov dx,0f4h
    out dx,ax
    mov ax,4c00h
    int 21h
filename db 'LOWTEST.TMP',0
pattern db 'BIOS'
buffer times 4 db 0
passed db 'BIOS_LOW_BOOT_PASS',13,10,'$'
failed db 'BIOS_LOW_BOOT_FAIL',13,10,'$'
%ifdef WARM_RESET
warm_tag db 'LOWWARM.TAG',0
warm_ready db 'BIOS_WARM_RESET_READY',13,10,'$'
%endif
slots:
%include "low-slots.inc"
%ifdef EXPECT_REBASE
%include "bios_public_graph.inc"
%include "bios_ctrlc_probe.inc"
%endif
%ifdef ACTIVATE_HIGH
%include "bios_live_activate.inc"
%endif
%ifdef CHECK_RAW_DISK
sector_before dw 1234h
sector times 512 db 0
sector_after dw 5678h
%endif
