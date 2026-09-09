; Exercise the actual linked test routine with independently checked memory
; guards and CPU state, without installing an XMS manager over the test span.
bits 16
cpu 386
org 100h

%ifndef SPAN_KB
%define SPAN_KB 2051
%endif
%define SPAN_BYTES (SPAN_KB*1024)

start:
    cld
    mov ax,cs
    add ax,(driver_blob-$$+100h)/16
    mov [entry+2],ax
    mov [set_entry+2],ax
    mov [query_entry+2],ax
    mov es,ax
    mov word [es:EXTENDED_KB_OFFSET],SPAN_KB
    o32 sgdt [original_gdtr]
    mov ax,3502h
    int 21h
    mov [original_nmi],bx
    mov [original_nmi+2],es
    mov dx,nmi_handler
    mov ax,2502h
    int 21h
    mov byte [a20_case],0
.case:
    mov word [nmi_count],0
    mov byte [stage],1
    ; Seed both ends of the span and a guard immediately beyond its end.
    mov eax,100000h
    call seed
    mov eax,100000h+SPAN_BYTES-32
    call seed
    mov eax,100000h+SPAN_BYTES
    call seed
    push ds
    mov ds,[entry+2]
    mov al,[cs:a20_case]
    call far [cs:set_entry]
    pop ds
    jc fail
    mov byte [stage],2
    ; A nonzero high GDTR byte detects accidental 24-bit SGDT/LGDT saves.
    o32 lgdt [sentinel_gdtr]
    o32 sgdt [before_gdtr]
    o32 sidt [before_idtr]
    mov eax,cr0
    mov [before_cr0],eax
    in al,70h
    mov [before_cmos],al
    mov ax,2345h
    mov es,ax
    mov [before_sp],sp
    cmp byte [a20_case],0
    jne .keep_if
    cli
.keep_if:
    pushfd
    pop eax
    or eax,4000h                 ; Real-mode NT must not become a task return.
    push eax
    popfd
    mov ds,[entry+2]
    std
    pushfd
    pop eax
    mov [cs:before_flags],eax
    call far [cs:entry]
    pushfd
    pop eax
    mov [cs:after_flags],eax
    mov [cs:after_ds],ds
    push cs
    pop ds
    o32 sgdt [after_gdtr]
    o32 sidt [after_idtr]
    mov eax,cr0
    mov [after_cr0],eax
    in al,70h
    mov [after_cmos],al
    o32 lgdt [original_gdtr]
    pushfd
    pop eax
    and eax,0ffffbfffh
    push eax
    popfd
    sti
    cld
%ifdef EXPECT_NMI
    cmp word [nmi_count],(SPAN_KB+63)/64
%else
    cmp word [nmi_count],0
%endif
    jne fail
    mov byte [stage],3
    cmp sp,[before_sp]
    jne fail
    mov ax,es
    cmp ax,2345h
    jne fail
    mov ax,[after_ds]
    cmp ax,[entry+2]
    jne fail
    mov eax,[after_cr0]
    cmp eax,[before_cr0]
    jne fail
    mov al,[after_cmos]
    cmp al,[before_cmos]
    jne fail
    mov byte [stage],4
    mov eax,[before_flags]
    xor eax,[after_flags]
    test eax,4600h                ; NT, IF and DF must survive each call.
    jnz fail
    push ds
    pop es
    mov si,before_gdtr
    mov di,after_gdtr
    mov cx,12                    ; GDTR followed by IDTR, full 32-bit bases.
    repe cmpsb
    jne fail
    mov byte [stage],5
    mov eax,[after_flags]
%ifdef EXPECT_FAILURE
    test al,1
    jz fail
%else
    test al,1
    jnz fail
%endif
    push ds
    mov ds,[entry+2]
    call far [cs:query_entry]
    pop ds
    cmp al,[a20_case]
    jne fail
    mov byte [stage],6
    ; SeaBIOS may infer A20 from port 92h after our forced KBC backend has
    ; disabled the physical line. Verify restoration first (above), then
    ; explicitly enable A20 for independent BIOS readback.
    push ds
    mov ds,[entry+2]
    mov al,1
    call far [cs:set_entry]
    pop ds
    jc fail
    ; The independent BIOS move path reads back the entire successful span.
%ifndef EXPECT_FAILURE
    mov dword [position],100000h
.scan:
    mov eax,100000h+SPAN_BYTES
    sub eax,[position]
    cmp eax,8192
    jbe .size
    mov eax,8192
.size:
    shr ax,1
    mov [words],ax
    mov eax,[position]
    mov byte [stage],8
    call read_block
    mov byte [stage],6
    mov di,buffer
    mov cx,[words]
    mov ax,55aah
    repe scasw
    jne fail
    movzx eax,word [words]
    shl eax,1
    add [position],eax
    cmp dword [position],100000h+SPAN_BYTES
    jb .scan
%endif
    mov byte [stage],7
    mov word [words],16
    mov eax,100000h+SPAN_BYTES
    mov byte [stage],8
    call read_block
    mov byte [stage],6
    mov di,buffer
    mov ax,0ca17h
    mov cx,16
    repe scasw
    jne fail
    cmp byte [a20_case],0
    jne passed
    inc byte [a20_case]
    jmp .case
passed:
    mov dx,pass_msg
    jmp finish
fail:
    push cs
    pop ds
    cld
    o32 lgdt [original_gdtr]
    mov al,[stage]
    add al,'0'
    mov [fail_stage],al
    mov dx,fail_msg
finish:
    push dx
    push ds
    mov dx,[original_nmi]
    mov ds,[original_nmi+2]
    mov ax,2502h
    int 21h
    pop ds
    pop dx
    mov ah,9
    int 21h
    mov dx,0f4h
    mov ax,10h
    out dx,ax
    mov ax,4c00h
    int 21h
nmi_handler:
    inc word [cs:nmi_count]
    iret

; BIOS INT 15h/87h transfer, with independent descriptors and small buffers.
seed:
    push eax
    mov di,move_dest
    call descriptor
    xor eax,eax
    mov ax,cs
    shl eax,4
    add eax,guard
    mov di,move_source
    call descriptor
    mov cx,16
    call bios_move
    pop eax
    ret
read_block:
    mov di,move_source
    call descriptor
    xor eax,eax
    mov ax,cs
    shl eax,4
    add eax,buffer
    mov di,move_dest
    call descriptor
    mov cx,[words]
    call bios_move
    ret
descriptor:
    mov [di+2],ax
    shr eax,16
    mov [di+4],al
    mov [di+7],ah
    ret
bios_move:
    push ds
    pop es
    mov si,move_gdt
    mov ah,87h
    int 15h
    jc fail
    push cs
    pop ds
    push ds
    pop es
    cld
    ret

entry dw driver_stub-driver_blob,0
set_entry dw set_stub-driver_blob,0
query_entry dw query_stub-driver_blob,0
original_nmi dd 0
nmi_count dw 0
position dd 0
words dw 0
a20_case db 0
stage db 0
before_sp dw 0
before_flags dd 0
after_flags dd 0
after_ds dw 0
before_cmos db 0
after_cmos db 0
before_cr0 dd 0
after_cr0 dd 0
original_gdtr times 6 db 0
sentinel_gdtr dw 1357h
              dd 12345678h
before_gdtr times 6 db 0
before_idtr times 6 db 0
after_gdtr times 6 db 0
after_idtr times 6 db 0
move_gdt times 16 db 0
move_source dw 0ffffh,0
            db 0,93h,0,0
move_dest dw 0ffffh,0
          db 0,93h,0,0
times 16 db 0
guard times 16 dw 0ca17h
buffer times 8192 db 0
pass_msg db 'HIMEM_TESTMEM_STATE_PASS',13,10,'$'
fail_msg db 'HIMEM_TESTMEM_STATE_FAIL stage='
fail_stage db '0',13,10,'$'
align 16
driver_blob:
    incbin HIMEM_BINARY
driver_stub:
    db 0e8h
    dw TEST_ENTRY-(driver_stub-driver_blob+3)
    retf
set_stub:
    db 0e8h
    dw SET_ENTRY-(set_stub-driver_blob+3)
    retf
query_stub:
    db 0e8h
    dw QUERY_ENTRY-(query_stub-driver_blob+3)
    retf
