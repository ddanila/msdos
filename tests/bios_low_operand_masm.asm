; Execute the real separate-data macro expansion with CS != data owner.
.8086
_TEXT SEGMENT PARA PUBLIC 'CODE'
ASSUME CS:_TEXT
org 100h
BIOS_SERVICE_SEPARATE_DATA EQU 1
include MSBSEG.INC
start:
        mov ax,cs
        mov dx,OFFSET low_data
        mov cl,4
        shr dx,cl
        add ax,dx
        mov cs:[BIOS_SERVICE_LOW_SEGMENT],ax
        mov ax,1111h
        mov ds,ax
        mov ax,2222h
        mov es,ax
        mov bp,0aaaah
        mov cs:[initial_sp],sp

        IFDEF BAD_BORROW
        BIOS_LOW_READ LDS,SI,<DWORD PTR [4]>,DS
        ENDIF
        IFDEF BAD_STACK
        BIOS_LOW_MEM MOV,<WORD PTR [8]>,SP,DS
        ENDIF
        IFDEF BAD_SEGMENT
        BIOS_LOW_READ MOV,AX,<WORD PTR [2]>,SS
        ENDIF
        IFDEF BAD_VALUE
        BIOS_LOW_MEM MOV,<WORD PTR [8]>,DS,DS
        ENDIF
        IFDEF BAD_RESULT
        BIOS_LOW_READ MOV,ES,<WORD PTR [2]>,ES
        ENDIF

        stc
        BIOS_LOW_READ MOV,AX,<WORD PTR [2]>,DS
        jnc fail
        cmp ax,5678h
        jne fail
        stc
        BIOS_LOW_MEM MOV,<WORD PTR [8]>,AX,DS
        jnc fail
        BIOS_LOW_READ MOV,AX,<WORD PTR [8]>,ES
        cmp ax,5678h
        jne fail
        mov ax,0
        stc
        BIOS_LOW_READ ADC,AX,<WORD PTR [2]>,ES
        cmp ax,5679h
        jne fail
        stc
        BIOS_LOW_MEM XCHG,<WORD PTR [8]>,AX,DS
        jnc fail
        cmp ax,5678h
        jne fail
        BIOS_LOW_READ MOV,AX,<WORD PTR [8]>,DS
        cmp ax,5679h
        jne fail
        BIOS_LOW_MEM CMP,<BYTE PTR [0]>,2ah,DS
        jne fail
        BIOS_LOW_MEM CMP,<BYTE PTR [0]>,2bh,ES
        jnc fail
        mov ax,ds
        cmp ax,1111h
        jne fail
        mov ax,es
        cmp ax,2222h
        jne fail

        stc
        BIOS_LOW_READ LDS,SI,<DWORD PTR [4]>,ES
        jnc fail
        cmp si,2468h
        jne fail
        mov ax,ds
        cmp ax,3456h
        jne fail
        mov ax,es
        cmp ax,2222h
        jne fail
        BIOS_LOW_MEM MOV,<WORD PTR [10]>,DS,ES
        BIOS_LOW_READ MOV,AX,<WORD PTR [10]>,DS
        cmp ax,3456h
        jne fail

        stc
        BIOS_LOW_READ LES,DI,<DWORD PTR [4]>,DS
        jnc fail
        cmp di,2468h
        jne fail
        mov ax,es
        cmp ax,3456h
        jne fail
        mov ax,ds
        cmp ax,3456h
        jne fail
        cmp bp,0aaaah
        jne fail
        cmp sp,cs:[initial_sp]
        jne fail
        mov ax,4c00h
        int 21h
fail:
        mov ax,4c01h
        int 21h
BIOS_SERVICE_LOW_SEGMENT dw 0
initial_sp dw 0
align 16
low_data:
        db 2ah,0
        dw 5678h
        dw 2468h,3456h
        dw 0,0
_TEXT ENDS
end start
