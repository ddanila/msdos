
bits 16
org 0

%define mz_image            110h
%define mz_relocation_count 116h
%define mz_header_size      118h
%define mz_initial_ss       11eh
%define mz_initial_sp       120h
%define mz_initial_ip       124h
%define mz_initial_cs       126h
%define mz_relocation_table 128h

; These macros preserve Microsoft CONVERT's byte-exact instruction encodings.
%macro add_cx_ax 0
    db 03h, 0c8h
%endmacro
%macro add_bp_ax 0
    db 03h, 0e8h
%endmacro
%macro mov_si_dx 0
    db 08bh, 0f2h
%endmacro
%macro mov_cx_bx 0
    db 08bh, 0cbh
%endmacro
%macro sub_cx_si 0
    db 02bh, 0ceh
%endmacro

entry_ip:   dw 0
entry_cs:   dw 0
stack_sp:   dw 0
stack_ss:   dw 0

loader:
    call    .base
.base:
    pop     bx
    push    ax
    mov     ax, es
    add     ax, strict word 10h

    mov     cx, [mz_initial_ss]
    add_cx_ax
    mov     [bx + stack_ss - .base], cx
    mov     cx, [mz_initial_cs]
    add_cx_ax
    mov     [bx + entry_cs - .base], cx
    mov     cx, [mz_initial_sp]
    mov     [bx + stack_sp - .base], cx
    mov     cx, [mz_initial_ip]
    mov     [bx + entry_ip - .base], cx

    mov     di, [mz_relocation_table]
    mov     dx, [mz_header_size]
    mov     cl, 4
    shl     dx, cl
    mov     cx, [mz_relocation_count]
    jcxz    .move_image
.relocate:
    lds     si, [es:di + mz_image]
    add     di, byte 4
    mov     bp, ds
    add     bp, [es:mz_header_size]
    add     bp, byte 1
    add_bp_ax
    mov     ds, bp
    add     [si], ax
    loop    .relocate

.move_image:
    push    cs
    pop     ds
    mov     di, 100h
    mov_si_dx
    add     si, strict word mz_image
    mov_cx_bx
    sub_cx_si
    rep movsb

    pop     ax
    cli
    mov     ss, [bx + stack_ss - .base]
    mov     sp, [bx + stack_sp - .base]
    sti
    jmp     far [bx + entry_ip - .base]
