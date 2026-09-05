; Compare file reads/writes through conventional and mapped upper allocations.
bits 16
org 100h
start:
    mov sp,program_end
    mov bx,(program_end-$$+100h+15)/16
    mov ah,4ah
    int 21h
    jc fail
%if EXPECT_HIGH
    mov ax,5800h
    int 21h
    jc fail
    mov [old_strategy],ax
    mov ax,5802h
    int 21h
    jc fail
    mov [old_link],al
    mov bx,1
    mov ax,5803h
    int 21h
    jc fail
%ifdef UMB_LAST
    mov bx,42h
%else
    mov bx,40h
%endif
    mov ax,5801h
    int 21h
    jc fail
%endif
    mov bx,300h
    mov ah,48h
    int 21h
    jc fail
    mov [target],ax
%if EXPECT_HIGH
    cmp ax,0a000h
    jb fail
    mov bx,[old_strategy]
    mov ax,5801h
    int 21h
    jc fail
    xor bx,bx
    mov bl,[old_link]
    mov ax,5803h
    int 21h
    jc fail
%else
    cmp ax,0a000h
    jae fail
%endif
    mov dx,target_message
    mov ah,09h
    int 21h
    mov bp,[target]
    call hex
    mov dx,newline
    mov ah,09h
    int 21h
    push cs
    pop es
    mov di,data
    mov cx,4096
    xor ax,ax
.fill:
    stosw
    inc ax
    loop .fill
    mov dx,filename
    xor cx,cx
    mov ah,3ch
    int 21h
    jc fail
    mov bx,ax
    mov [handle],ax
    mov cx,8192
    mov dx,data
    mov ah,40h
    int 21h
    jc fail
    cmp ax,8192
    jne fail
    mov bx,[handle]
    mov ah,3eh
    int 21h
    jc fail
    mov word [test_index],0
    mov word [offset_index],0
.case:
    mov si,[offset_index]
    mov ax,[offsets+si]
    mov [transfer_offset],ax
    mov si,[test_index]
    mov ax,[sizes+si]
    mov [count],ax
    mov dx,ready
    mov ah,09h
    int 21h
    mov bp,[count]
    call hex
    mov dx,offset_message
    mov ah,09h
    int 21h
    mov bp,[transfer_offset]
    call hex
    mov dx,newline
    mov ah,09h
    int 21h
    mov ah,0dh
    int 21h
    mov ax,3d00h
    mov dx,filename
    int 21h
    jc fail
    mov [handle],ax
    mov es,[target]
    xor di,di
    mov ax,0cccch
    mov cx,1800h
    rep stosw
    mov bx,[handle]
    mov cx,[count]
    mov dx,[transfer_offset]
    mov ds,[target]
    mov ah,3fh
    int 21h
    push cs
    pop ds
    jc fail
    cmp ax,[count]
    jne fail
    mov es,[target]
    mov si,data
    mov di,[transfer_offset]
    mov cx,[count]
    repe cmpsb
    jne data_fail
    mov bx,[transfer_offset]
    or bx,bx
    jz .no_prefix
    cmp byte [es:bx-1],0cch
    jne data_fail
.no_prefix:
    cmp byte [es:di],0cch
    jne data_fail
    mov bx,[handle]
    mov ah,3eh
    int 21h
    jc fail
    call check_write
    add word [test_index],2
    cmp word [test_index],sizes_end-sizes
    jb .case
    mov word [test_index],0
    add word [offset_index],2
    cmp word [offset_index],offsets_end-offsets
    jb .case
    mov dx,filename
    mov ah,41h
    int 21h
    jc fail
    mov es,[target]
    mov ah,49h
    int 21h
    jc fail
    mov dx,passed
    mov ah,09h
    int 21h
    mov ax,4c00h
    int 21h
data_fail:
    mov dx,bad_data
    mov ah,09h
    int 21h
    mov bp,di
    sub bp,[transfer_offset]
    dec bp
    call hex
    mov dx,newline
    jmp print_fail
fail:
    push cs
    pop ds
    mov dx,failed
print_fail:
    mov ah,09h
    int 21h
    mov ax,4c01h
    int 21h
check_write:
    mov dx,write_name
    xor cx,cx
    mov ah,3ch
    int 21h
    jc fail
    mov [handle],ax
    mov bx,ax
    mov cx,[count]
    mov dx,[transfer_offset]
    mov ds,[target]
    mov ah,40h
    int 21h
    push cs
    pop ds
    jc fail
    cmp ax,[count]
    jne fail
    mov bx,[handle]
    mov ah,3eh
    int 21h
    jc fail
    mov ah,0dh
    int 21h
    mov dx,write_name
    mov ax,3d00h
    int 21h
    jc fail
    mov [handle],ax
    mov bx,ax
    mov cx,[count]
    mov dx,write_check
    mov ah,3fh
    int 21h
    jc fail
    cmp ax,[count]
    jne fail
    push cs
    pop es
    mov si,data
    mov di,write_check
    mov cx,[count]
    repe cmpsb
    jne write_fail
    mov bx,[handle]
    mov ah,3eh
    int 21h
    jc fail
    mov dx,write_name
    mov ah,41h
    int 21h
    jc fail
    ret
write_fail:
    mov dx,bad_write
    jmp print_fail
hex:
    mov cx,4
.digit:
    push cx
    mov cl,4
    rol bp,cl
    mov dx,bp
    and dl,15
    add dl,'0'
    cmp dl,'9'
    jbe .emit
    add dl,7
.emit:
    mov ah,02h
    int 21h
    pop cx
    loop .digit
    ret
target dw 0
old_strategy dw 0
old_link db 0
handle dw 0
count dw 0
test_index dw 0
offset_index dw 0
transfer_offset dw 0
offsets dw 0,31,4095
offsets_end:
offset_message db ' offset=$'
sizes dw 512,513,4096,8192
sizes_end:
filename db 'UMBREAD.DAT',0
write_name db 'UMBWRT.DAT',0
ready db 'UMB_READ_COUNT=$'
target_message db 'UMB_READ_TARGET=$'
newline db 13,10,'$'
passed db 'UMB_FILE_READ_PASS',13,10,'$'
failed db 'UMB_FILE_READ_API_FAIL',13,10,'$'
bad_data db 'UMB_FILE_READ_DATA_FAIL offset=$'
bad_write db 'UMB_FILE_READ_WRITE_FAIL',13,10,'$'
data times 8192 db 0
write_check times 8192 db 0
    times 512 db 0
program_end:
