; All seven production tail stubs, with CS distinct from the high target.
.8086
_TEXT SEGMENT PARA PUBLIC 'CODE'
ASSUME CS:_TEXT
org 100h
include MSBSEG.INC
start:
        mov cs:[entry+2],cs
        mov cs:[completion+2],cs
        mov ax,OFFSET high_service
        mov cl,4
        shr ax,cl
        mov dx,cs
        add dx,ax
        mov si,OFFSET slots
        mov cx,7
bind:
        lodsw
        mov bx,ax
        mov word ptr [bx],0
        mov [bx+2],dx
        loop bind
        mov cs:[saved_sp],sp
        mov ax,sp
        sub ax,22               ; original FAR return and nine saved words
        mov cs:[service_sp],ax
next_entry:
        mov bx,cs:[index]
        mov ax,cs:[entries+bx]
        mov cs:[chosen],ax
        mov ax,1111h
        mov bx,2222h
        mov cx,3333h
        mov dx,4444h
        mov si,5555h
        mov di,6666h
        mov bp,7777h
        mov ds,ax
        mov es,bx
        stc
        call DWORD PTR cs:[entry]
        jnc fail
        cmp sp,cs:[saved_sp]
        jne fail
        cmp byte ptr cs:[bad],0
        jne fail
        add word ptr cs:[index],2
        cmp word ptr cs:[index],14
        jb next_entry
        cmp word ptr cs:[restore_count],7
        jne fail
        mov ax,4c00h
        int 21h
fail:
        mov ax,4c01h
        int 21h
device_entry:
        push si
        push ax
        push cx
        push dx
        push di
        push bp
        push ds
        push es
        push bx
        jmp word ptr cs:[chosen]
BIOS_HMA_ROM_RESTORE:
        pushf
        inc word ptr cs:[restore_count]
        popf
        ret
include HIGHDEV.INC
entries dw BIOS_DEVICE_READ,BIOS_DEVICE_WRITE,BIOS_DEVICE_VERIFY
        dw BIOS_DEVICE_REMOVABLE,BIOS_DEVICE_IOCTL
        dw BIOS_DEVICE_GETOWNER,BIOS_DEVICE_SETOWNER
slots   dw BIOS_HIGH_READ_ENTRY,BIOS_HIGH_WRITE_ENTRY,BIOS_HIGH_VERIFY_ENTRY
        dw BIOS_HIGH_REMOVABLE_ENTRY,BIOS_HIGH_IOCTL_ENTRY
        dw BIOS_HIGH_GETOWNER_ENTRY,BIOS_HIGH_SETOWNER_ENTRY
entry dw OFFSET device_entry,0
chosen dw 0
index dw 0
saved_sp dw 0
service_sp dw 0
restore_count dw 0
bad db 0
low_complete:
        pop bx
        pop es
        pop ds
        pop bp
        pop di
        pop dx
        pop cx
        pop ax
        pop si
        retf
align 16
high_service:
        jnc high_bad
        cmp sp,ss:[service_sp]
        jne high_bad
        cmp ax,1111h
        jne high_bad
        cmp bx,2222h
        jne high_bad
        cmp cx,3333h
        jne high_bad
        cmp dx,4444h
        jne high_bad
        cmp si,5555h
        jne high_bad
        cmp di,6666h
        jne high_bad
        cmp bp,7777h
        jne high_bad
        mov ax,ds
        cmp ax,1111h
        jne high_bad
        mov ax,es
        cmp ax,2222h
        jne high_bad
        jmp short high_done
high_bad:
        mov byte ptr ss:[bad],1
high_done:
        stc
        jmp DWORD PTR cs:[completion-high_service]
completion dw OFFSET low_complete,0
_TEXT ENDS
END start
