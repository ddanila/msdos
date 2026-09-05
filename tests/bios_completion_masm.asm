; Execute the completion macro across distinct segments with the device frame.
.8086
_TEXT SEGMENT PARA PUBLIC 'CODE'
ASSUME CS:_TEXT
org 100h
BIOS_SERVICE_SEPARATE_DATA EQU 1
include MSBSEG.INC
start:
        mov ax,cs
        mov cs:[entry+2],ax
        mov dx,OFFSET low_complete
        mov cl,4
        shr dx,cl
        add ax,dx
        mov cs:[completion+2],ax
        mov cs:[saved_sp],sp
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
        cmp ax,1111h
        jne fail
        cmp bx,2222h
        jne fail
        cmp cx,3333h
        jne fail
        cmp dx,4444h
        jne fail
        cmp si,5555h
        jne fail
        cmp di,6666h
        jne fail
        cmp bp,7777h
        jne fail
        mov ax,ds
        cmp ax,1111h
        jne fail
        mov ax,es
        cmp ax,2222h
        jne fail
        mov ax,4c00h
        int 21h
fail:
        mov ax,4c01h
        int 21h
high_entry:
        ; MSBIO1 ENTRY1's nine saved words above the original FAR return.
        push si
        push ax
        push cx
        push dx
        push di
        push bp
        push ds
        push es
        push bx
        BIOS_JUMP_LOW low_complete,completion
entry dw OFFSET high_entry,0
completion dw 0,0
saved_sp dw 0
align 16
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
_TEXT ENDS
END start
