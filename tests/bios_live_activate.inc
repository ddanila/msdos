; Development-image integration probe, NOT the boot-time reclaim installer.
; All low addresses and high bytes are generated from the same linked image.
activate_live_bios:
    cld
    mov ax,0e700h
    int 2fh
    cmp ax,0e7ffh
    jne fail
    cmp bx,4d55h
    jne fail
    mov ax,70h
    mov es,ax
    xor ax,ax
    mov fs,ax
    cmp word [fs:13h*4],ORIGINAL_BLOCK13
    jne fail
    cmp word [fs:13h*4+2],70h
    jne fail
    ; Validate every command entry and boot patch before reserving HMA.
    %include "activation-preflight.inc"
    mov ax,1236h
    mov cx,high_payload_end-high_payload
    int 2fh
    or ax,ax
    jz fail
    mov [high_origin],di
    mov bx,di
    mov si,high_payload
    mov cx,high_payload_end-high_payload
    cld
    rep movsb
    mov si,activation_fixups
    mov cx,ACTIVATION_FIXUP_COUNT
.fixup:
    lodsw
    mov di,ax
    add di,bx
    add [es:di],bx
    loop .fixup
    ; Fixups precede policy NOPs; otherwise relocation would corrupt NOPs.
    %include "activation-bind-high.inc"
    pushf
    cli
    mov ax,70h
    mov es,ax
%ifndef OMIT_LIVE_PUBLICATION
    %include "activation-bind-low.inc"
    mov word [fs:13h*4],NEW_BLOCK13
    mov word [fs:13h*4+2],70h
    mov byte [es:ACTIVE_OFFSET],1
%endif
    ; Deliberately make the original service code non-executable. Any stale
    ; entry reaches CLI/HLT within two instructions. Its allocation remains;
    ; this proves exercised routes moved, not that memory was reclaimed.
    mov di,OLD_SERVICE_START
    mov cx,OLD_SERVICE_SIZE/2
    mov ax,0f4fah
    rep stosw
    popf
    mov dx,live_message
    mov ah,9
    int 21h
    ret
high_origin dw 0
live_message db 'BIOS_LIVE_READY',13,10,'$'
%include "activation-data.inc"
high_payload:
    incbin "high/bios-high.bin"
high_payload_end:
