; Source form of the byte-exact loader embedded by bin/convert.
; It runs at the end of the generated COM file and treats the embedded MZ file
; as data. Absolute addresses below refer to MZ fields after the 16-byte COM
; prefix at runtime offset 100h: 110h + MZ field offset.

bits 16
org 0

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

    mov     cx, [11eh]          ; MZ header paragraphs
    db      03h, 0c8h            ; add cx, ax (preserve legacy encoding)
    mov     [bx + stack_ss - .base], cx
    mov     cx, [126h]          ; initial CS
    db      03h, 0c8h            ; add cx, ax (preserve legacy encoding)
    mov     [bx + entry_cs - .base], cx
    mov     cx, [120h]          ; initial SP
    mov     [bx + stack_sp - .base], cx
    mov     cx, [124h]          ; initial IP
    mov     [bx + entry_ip - .base], cx

    mov     di, [128h]          ; relocation-table offset
    mov     dx, [118h]          ; header paragraphs
    mov     cl, 4
    shl     dx, cl
    mov     cx, [116h]          ; relocation count
    jcxz    .move_image
.relocate:
    lds     si, [es:di + 110h]  ; relocation offset:segment pair
    add     di, byte 4
    mov     bp, ds
    add     bp, [es:118h]
    add     bp, byte 1          ; account for the 16-byte COM prefix
    db      03h, 0e8h            ; add bp, ax (preserve legacy encoding)
    mov     ds, bp
    add     [si], ax
    loop    .relocate

.move_image:
    push    cs
    pop     ds
    mov     di, 100h
    db      08bh, 0f2h           ; mov si, dx (preserve legacy encoding)
    add     si, strict word 110h
    db      08bh, 0cbh           ; mov cx, bx (preserve legacy encoding)
    db      02bh, 0ceh           ; sub cx, si (preserve legacy encoding)
    rep movsb

    pop     ax
    cli
    mov     ss, [bx + stack_ss - .base]
    mov     sp, [bx + stack_sp - .base]
    sti
    jmp     far [bx + entry_ip - .base]
