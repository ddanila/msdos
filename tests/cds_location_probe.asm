.8086
option oldstructs
.model tiny
.code
org 100h
BREAK macro args:VARARG
endm
include SYSVAR.INC
include CURDIR.INC

start:
    mov ah,52h
    int 21h
    cmp byte ptr es:[bx.SYSI_NCDS],26
    jne failed
    les di,es:[bx.SYSI_CDS]
    or di,di
    jnz failed
    mov ax,es
    cmp ax,70h
    jb failed
IF EXPECT_HIGH
    cmp ax,0a000h
    jb failed
    cmp ax,0f000h
    jae failed
    sub ax,2                    ; system MCB, then CDS DEVMARK
    mov es,ax
    cmp word ptr es:[1],8
    jne failed
    cmp word ptr es:[3],(26 * curdirLen + 15) / 16 + 1
    jne failed
ELSE
    cmp ax,0a000h
    jae failed
ENDIF
    mov dx,offset passed_message
    mov ax,4c00h
    jmp short finish
failed:
    mov dx,offset failed_message
    mov ax,4c01h
finish:
    push ax
    push cs
    pop ds
    mov ah,9
    int 21h
    pop ax
    int 21h
passed_message db 'CDS_LOCATION_PASS',13,10,'$'
failed_message db 'CDS_LOCATION_FAIL',13,10,'$'
end start
