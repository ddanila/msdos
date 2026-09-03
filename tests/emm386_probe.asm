bits 16
org 100h

start:
%ifdef EXPECT_OFF
    mov bx, 1
    mov ah, 43h
    int 67h
    cmp ah, 81h
    jne off_failed
    mov dx, off_pass_message
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h
off_failed:
    mov dx, off_fail_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h
%endif

    mov ah, 40h
    int 67h
    test ah, ah
    jnz status_failed

    mov ah, 41h
    int 67h
    test ah, ah
    jnz frame_failed
    test bx, bx
    jz frame_failed
    mov [frame], bx

    mov ah, 46h
    int 67h
    test ah, ah
    jnz version_failed
    cmp al, 40h
    jne version_failed

    call test_external_map_rejection
    jc external_map_failed

    push ds
    pop es
    mov di, frame_array
    mov ax, 5801h
    int 67h
    test ah, ah
    jnz frame_array_failed
    test cx, cx
    jz frame_array_failed
    mov bp, cx
    mov ax, 5800h
    int 67h
    test ah, ah
    jnz frame_array_failed
    cmp cx, bp
    jne frame_array_failed
    mov si, frame_array
.find_high_frame:
    mov ax, [si]
    cmp ax, 0a000h
    jae .found_high_frame
    add si, 4
    loop .find_high_frame
    jmp frame_array_failed
.found_high_frame:
    mov [partial_map + 2], ax

    push ds
    pop es
    mov si, partial_map
    mov di, partial_state
    mov ax, 4f00h
    int 67h
    test ah, ah
    jnz partial_failed

    mov ah, 42h
    int 67h
    test ah, ah
    jnz pages_failed
    test dx, dx
    jz pages_failed

    mov bx, 1
    mov ah, 43h
    int 67h
    test ah, ah
    jnz alloc_failed
    mov [handle], dx

    xor al, al
    xor bx, bx
    mov dx, [handle]
    mov ah, 44h
    int 67h
    test ah, ah
    jnz map_failed

    mov es, [frame]
    mov word [es:0], 0a55ah

    mov al, 1
    xor bx, bx
    mov dx, [handle]
    mov ah, 44h
    int 67h
    test ah, ah
    jnz map_failed
    cmp word [es:4000h], 0a55ah
    jne memory_failed

    mov dx, [handle]
    mov ah, 45h
    int 67h
    test ah, ah
    jnz release_failed

    mov dx, pass_message
    mov ah, 09h
    int 21h
%ifndef NO_QEMU_EXIT
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
%endif
    mov ax, 4c00h
    int 21h

test_external_map_rejection:
    push ds
    pop es
    mov di, saved_map
    mov ax, 4e00h
    int 67h
    test ah, ah
    jnz .failed

    mov si, saved_map
    mov di, corrupt_map
    mov cx, 130
    rep movsw

    inc word [corrupt_map]
    mov si, corrupt_map
    mov ax, 4e01h
    int 67h
    cmp ah, 0a3h
    jne .failed

    mov ah, 40h
    int 67h
    test ah, ah
    jnz .failed

    mov si, saved_map
    mov di, corrupt_map
    mov cx, 130
    rep movsw
    mov word [corrupt_map + 2], 0fffeh
    mov si, corrupt_map
    mov ax, 4e01h
    int 67h
    cmp ah, 0a3h
    jne .failed

    mov si, saved_map
    mov ax, 4e01h
    int 67h
    test ah, ah
    jnz .failed

    mov ah, 40h
    int 67h
    test ah, ah
    jnz .failed
    clc
    ret
.failed:
    stc
    ret

map_failed:
    mov dx, [handle]
    mov ah, 45h
    int 67h
    mov dx, map_fail
    jmp fail

memory_failed:
    mov dx, [handle]
    mov ah, 45h
    int 67h
    mov dx, memory_fail
    jmp fail

status_failed:
    mov dx, status_fail
    jmp fail
frame_failed:
    mov dx, frame_fail
    jmp fail
version_failed:
    mov dx, version_fail
    jmp fail
frame_array_failed:
    mov dx, frame_array_fail
    jmp fail
partial_failed:
    cmp ah, 8bh
    je partial_range_failed
    cmp ah, 0a3h
    je partial_source_failed
    mov dx, partial_fail
    jmp fail
partial_range_failed:
    mov dx, partial_range_fail
    jmp fail
partial_source_failed:
    mov dx, partial_source_fail
    jmp fail
pages_failed:
    mov dx, pages_fail
    jmp fail
alloc_failed:
    mov dx, alloc_fail
    jmp fail
release_failed:
    mov dx, release_fail
    jmp fail
external_map_failed:
    mov dx, external_map_fail

fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

handle       dw 0
frame        dw 0
pass_message db 'EMM386_API_PASS', 13, 10, '$'
status_fail  db 'EMM386_STATUS_FAIL', 13, 10, '$'
frame_fail   db 'EMM386_FRAME_FAIL', 13, 10, '$'
version_fail db 'EMM386_VERSION_FAIL', 13, 10, '$'
frame_array_fail db 'EMM386_FRAME_ARRAY_FAIL', 13, 10, '$'
partial_fail db 'EMM386_PARTIAL_MAP_FAIL', 13, 10, '$'
partial_range_fail db 'EMM386_PARTIAL_RANGE_FAIL', 13, 10, '$'
partial_source_fail db 'EMM386_PARTIAL_SOURCE_FAIL', 13, 10, '$'
pages_fail   db 'EMM386_PAGES_FAIL', 13, 10, '$'
alloc_fail   db 'EMM386_ALLOC_FAIL', 13, 10, '$'
map_fail     db 'EMM386_MAP_FAIL', 13, 10, '$'
memory_fail  db 'EMM386_MEMORY_FAIL', 13, 10, '$'
release_fail db 'EMM386_RELEASE_FAIL', 13, 10, '$'
off_pass_message db 'EMM386_OFF_API_PASS', 13, 10, '$'
off_fail_message db 'EMM386_OFF_API_FAIL', 13, 10, '$'
external_map_fail db 'EMM386_EXTERNAL_MAP_FAIL', 13, 10, '$'
partial_map  dw 1, 0
frame_array  times 64 dw 0, 0
partial_state times 130 dw 0
saved_map    times 130 dw 0
corrupt_map  times 130 dw 0
