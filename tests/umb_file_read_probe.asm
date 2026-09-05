; Compare identical file reads into conventional and mapped upper allocations.
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
    mov bx,40h
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
.case:
    mov si,[test_index]
    mov ax,[sizes+si]
    mov [count],ax
    mov dx,ready
    mov ah,09h
    int 21h
    mov bp,[count]
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
    mov dx,31
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
    mov di,31
    mov cx,[count]
    repe cmpsb
    jne data_fail
    cmp byte [es:30],0cch
    jne data_fail
    cmp byte [es:di],0cch
    jne data_fail
    mov bx,[handle]
    mov ah,3eh
    int 21h
    jc fail
    add word [test_index],2
    cmp word [test_index],sizes_end-sizes
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
    sub bp,32
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
sizes dw 512,513,4096,8192
sizes_end:
filename db 'UMBREAD.DAT',0
ready db 'UMB_READ_COUNT=$'
target_message db 'UMB_READ_TARGET=$'
newline db 13,10,'$'
passed db 'UMB_FILE_READ_PASS',13,10,'$'
failed db 'UMB_FILE_READ_API_FAIL',13,10,'$'
bad_data db 'UMB_FILE_READ_DATA_FAIL offset=$'
data times 8192 db 0
    times 512 db 0
program_end:
