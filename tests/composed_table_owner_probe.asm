; Inspect our matched EMM386's retained roots and actual table descriptor.
bits 16
org 100h
%include "table-defs.inc"
    mov ax,3567h
    int 21h
    mov ax,es
    add ax,DATA_PARAGRAPH
    mov es,ax
    mov [data_segment],ax
    mov ax,[es:SAVE_MAP]
    mov [table_start],ax
    mov ax,[es:EMM_BRK]
    mov [table_end],ax
    mov bx,[es:TABLE_SELECTOR]
    mov [selector],bx
    mov ax,[es:GDT_SEG]
    mov es,ax
    mov di,descriptor
    mov cx,4
.copy:
    mov ax,[es:bx]
    mov [di],ax
    add di,2
    add bx,2
    loop .copy
    mov dx,filename
    xor cx,cx
    mov ah,3ch
    int 21h
    jc failed
    mov bx,ax
    mov dx,record
    mov cx,record_end-record
    mov ah,40h
    int 21h
    jc failed
    cmp ax,record_end-record
    jne failed
    mov ah,3eh
    int 21h
    jc failed
    mov ax,4c00h
    int 21h
failed:
    mov ax,4c01h
    int 21h
filename db 'TABLES.BIN',0
record:
data_segment dw 0
table_start dw 0
table_end dw 0
selector dw 0
descriptor times 8 db 0
record_end:
