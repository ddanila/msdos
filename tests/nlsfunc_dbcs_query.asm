bits 16
cpu 8086
org 100h

; Compatibility oracle for the existing COUNTRY.SYS DBCS records. These are
; external queries from a Baltic SBCS environment, not DBCS country installs.
    cld
    push cs
    pop ds
    push cs
    pop es
    mov bp, records
next_record:
    mov dx, [bp]
    mov bx, [bp+2]
    mov ax, 6507h
    mov cx, 5
    mov di, result
    int 21h
    jc fail
    cmp cx, 5
    jne fail
    cmp byte [result], 7
    jne fail
    push ds
    lds si, [result+1]
    mov cx, [es:bp+4]
    cmp [si], cx
    jne restore_fail
    add si, 2
    mov di, bp
    add di, 6
    repe cmpsb
    jne restore_fail
    pop ds
    mov dx, passed
    mov ah, 9
    int 21h
    add bp, 12
    cmp bp, records_end
    jb next_record
    mov ax, 4c00h
    int 21h
restore_fail:
    pop ds
fail:
    mov dx, failed
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

records:
    dw 81,932,6
    db 81h,9fh,0e0h,0fch,0,0
    dw 82,934,4
    db 81h,0bfh,0,0,0,0
    dw 86,936,4
    db 81h,0fch,0,0,0,0
    dw 88,938,4
    db 81h,0fch,0,0,0,0
records_end:
result: times 5 db 0
passed: db 'DBCS_QUERY_PASS',13,10,'$'
failed: db 'DBCS_QUERY_FAIL',13,10,'$'
