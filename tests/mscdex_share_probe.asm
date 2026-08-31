bits 16
org 100h

start:
    mov ah, 52h
    int 21h
    les di, [es:bx + 22]
    add di, 4 * 88                    ; E: CDS
    mov dx, [es:di + 67]
    test dx, 8000h                    ; redirector-managed drive
    jz fail
%ifdef EXPECT_SHARE
    test dx, 1000h                    ; local/shareable redirector
    jz fail
%else
    test dx, 1000h
    jnz fail
%endif
    mov dx, pass_message
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

fail:
    mov dx, fail_message
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

%ifdef EXPECT_SHARE
pass_message db 'MSCDEX_SHARE_PASS',13,10,'$'
%else
pass_message db 'MSCDEX_NOSHARE_PASS',13,10,'$'
%endif
fail_message db 'MSCDEX_SHARE_FLAGS_FAIL',13,10,'$'
