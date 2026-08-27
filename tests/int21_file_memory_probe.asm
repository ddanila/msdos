bits 16
org 100h

; Focused contracts for the DOS directory, file-handle, search, extended-error,
; and memory APIs.  Every call is followed by an assertion on its documented
; result; a failure identifies the function that violated its contract.

%macro fail_if_carry 1
    jnc %%ok
    mov dx, fail_%1
    jmp fail
%%ok:
%endmacro

%macro fail_unless_carry 1
    jc %%ok
    mov dx, fail_%1
    jmp fail
%%ok:
%endmacro

%macro require_error 2
    jc %%carried
    mov dx, %2
    jmp fail
%%carried:
    cmp ax, %1
    je %%ok
    mov dx, %2
    jmp fail
%%ok:
%endmacro

start:
    push cs
    pop ds

    ; A COM process initially owns the remaining arena.  Shrink its PSP block
    ; first, then exercise allocate/resize/free on a separate block.
    push ds
    pop es
    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    fail_if_carry 4a

    mov bx, 32
    mov ah, 48h
    int 21h
    fail_if_carry 48
    mov [memory_segment], ax

    mov es, ax
    mov bx, 16
    mov ah, 4ah
    int 21h
    fail_if_carry 4a

    mov es, [memory_segment]
    mov ah, 49h
    int 21h
    fail_if_carry 49
    push ds
    pop es

    ; Exhaust the arena deliberately. AH=48h must return error 8 and the
    ; largest available block. That block must be allocatable; while held, a
    ; one-paragraph request must fail, then succeed after the block is freed.
    mov bx, 0ffffh
    mov ah, 48h
    int 21h
    jnc memory_exhaust_failed
    cmp ax, 8
    jne memory_exhaust_failed
    test bx, bx
    jz memory_exhaust_failed
    mov ah, 48h
    int 21h
    jc memory_exhaust_failed
    mov [memory_segment], ax
    mov bx, 1
    mov ah, 48h
    int 21h
    jnc memory_exhaust_failed
    cmp ax, 8
    jne memory_exhaust_failed
    mov es, [memory_segment]
    mov ah, 49h
    int 21h
    jc memory_exhaust_failed
    mov bx, 1
    mov ah, 48h
    int 21h
    jc memory_exhaust_failed
    mov es, ax
    mov ah, 49h
    int 21h
    jc memory_exhaust_failed
    push ds
    pop es

    mov dx, directory
    mov ah, 39h
    int 21h
    fail_if_carry 39

    mov dx, directory
    mov ah, 3bh
    int 21h
    fail_if_carry 3b

    xor dl, dl
    mov si, cwd_buffer
    mov ah, 47h
    int 21h
    fail_if_carry 47
    cmp byte [cwd_buffer], 'I'
    je cwd_ok
    mov dx, fail_47
    jmp fail
cwd_ok:

    xor cx, cx
    mov dx, original_name
    mov ah, 3ch
    int 21h
    fail_if_carry 3c
    mov [file_handle], ax

    mov bx, ax
    mov cx, payload_size
    mov dx, payload
    mov ah, 40h
    int 21h
    fail_if_carry 40
    cmp ax, payload_size
    je write_ok
    mov dx, fail_40
    jmp fail
write_ok:

    mov bx, [file_handle]
    mov ah, 68h
    int 21h
    fail_if_carry 68

    mov bx, [file_handle]
    xor cx, cx
    xor dx, dx
    xor al, al
    mov ah, 42h
    int 21h
    fail_if_carry 42
    or ax, dx
    jz seek_ok
    mov dx, fail_42
    jmp fail
seek_ok:

    mov bx, [file_handle]
    mov ah, 3eh
    int 21h
    fail_if_carry 3e

    ; Fill the default 20-entry JFT with duplicates of stdout. The next DUP
    ; and a forced duplicate beyond the table must both report error 4.
    xor si, si
    mov di, open_handles
.dup_until_full:
    mov bx, 1
    mov ah, 45h
    int 21h
    jc .dup_full
    stosw
    inc si
    cmp si, 20
    jb .dup_until_full
    jmp dup_exhaust_failed
.dup_full:
    cmp ax, 4
    jne dup_exhaust_failed
    mov bx, 1
    mov cx, 20
    mov ah, 46h
    int 21h
    require_error 6, fail_dup2_exhaust
    mov cx, si
    mov di, open_handles
.close_dups:
    jcxz .dups_closed
    mov bx, [di]
    mov ah, 3eh
    int 21h
    jc dup_exhaust_failed
    add di, 2
    loop .close_dups
.dups_closed:

    ; Expand the process JFT beyond CONFIG.SYS FILES=12 and consume the
    ; global SFT by repeatedly opening the same file. The next open must
    ; report error 4, and closing the acquired handles must restore service.
    mov bx, 64
    mov ah, 67h
    int 21h
    jc sft_exhaust_failed
    xor si, si
    mov di, open_handles
.open_until_full:
    mov ax, 3d00h
    mov dx, original_name
    int 21h
    jc .sft_full
    stosw
    inc si
    cmp si, 64
    jb .open_until_full
    jmp sft_exhaust_failed
.sft_full:
    cmp ax, 4
    jne sft_exhaust_failed
    test si, si
    jz sft_exhaust_failed
    push si
    xor cx, cx
    mov dx, sft_create_name
    mov ah, 3ch
    int 21h
    require_error 4, fail_sft_exhaust
    xor cx, cx
    mov dx, sft_temp_template
    mov ah, 5ah
    int 21h
    require_error 4, fail_sft_exhaust
    xor cx, cx
    mov dx, sft_new_name
    mov ah, 5bh
    int 21h
    require_error 4, fail_sft_exhaust
    pop si
    mov cx, si
    mov di, open_handles
.close_exhausted:
    mov bx, [di]
    mov ah, 3eh
    int 21h
    jc sft_exhaust_failed
    add di, 2
    loop .close_exhausted
    mov ax, 3d00h
    mov dx, original_name
    int 21h
    jc sft_exhaust_failed
    mov bx, ax
    mov ah, 3eh
    int 21h
    jc sft_exhaust_failed

    ; Every handle-oriented entry in DOS's live error map must reject FFFFh
    ; with error 6. Keep these together so one probe traces the shared negative
    ; boundary without allowing a successful-path assertion to stand in for it.
    mov bx, 0ffffh
    mov ah, 3eh                    ; Close.
    int 21h
    require_error 6, fail_invalid_handle
    mov bx, 0ffffh
    mov cx, 1
    mov dx, read_buffer
    mov ah, 3fh                    ; Read.
    int 21h
    require_error 6, fail_invalid_handle
    mov bx, 0ffffh
    mov cx, 1
    mov dx, payload
    mov ah, 40h                    ; Write.
    int 21h
    require_error 6, fail_invalid_handle
    mov bx, 0ffffh
    xor cx, cx
    xor dx, dx
    xor al, al
    mov ah, 42h                    ; Seek.
    int 21h
    require_error 6, fail_invalid_handle
    mov bx, 0ffffh
    mov ax, 4400h                  ; IOCTL get device information.
    int 21h
    require_error 6, fail_invalid_handle
    mov bx, 0ffffh
    mov ah, 45h                    ; Duplicate.
    int 21h
    require_error 6, fail_invalid_handle
    mov bx, 0ffffh
    mov cx, 15
    mov ah, 46h                    ; Force duplicate.
    int 21h
    require_error 6, fail_invalid_handle
    mov bx, 0ffffh
    mov ax, 5700h                  ; Get file time.
    int 21h
    require_error 6, fail_invalid_handle
    mov bx, 0ffffh
    xor cx, cx
    xor dx, dx
    xor si, si
    xor di, di
    mov ax, 5c00h                  ; Lock range.
    int 21h
    require_error 6, fail_invalid_handle
    mov bx, 0ffffh
    mov ah, 6ah                    ; DOS 4 commit alias.
    int 21h
    require_error 6, fail_invalid_handle

    ; Safe selector/argument boundaries from the live error table.
    mov ax, 3d03h                  ; Open access modes stop at 2.
    mov dx, original_name
    int 21h
    require_error 12, fail_invalid_open

    mov ax, 3d00h
    mov dx, original_name
    int 21h
    jc invalid_selector_failed
    mov [error_handle], ax
    mov bx, ax
    xor cx, cx
    xor dx, dx
    mov ax, 4203h                  ; Seek origins stop at 2.
    int 21h
    require_error 1, fail_invalid_seek
    mov bx, [error_handle]
    xor cx, cx
    xor dx, dx
    xor si, si
    xor di, di
    mov ax, 5c02h                  ; Lock/unlock selectors stop at 1.
    int 21h
    require_error 1, fail_invalid_lock
    mov bx, [error_handle]
    mov ah, 3eh
    int 21h
    jc invalid_selector_failed

    mov ax, 4302h                  ; Attribute subfunctions stop at 1.
    mov dx, original_name
    int 21h
    require_error 1, fail_invalid_attr
    mov ax, 44ffh                  ; Undefined IOCTL selector.
    int 21h
    require_error 1, fail_invalid_ioctl
    mov ax, 5804h                  ; Allocation-strategy selectors stop at 3.
    int 21h
    require_error 1, fail_invalid_allocop
    mov ax, 65ffh                  ; Undefined extended-country selector.
    int 21h
    require_error 1, fail_invalid_country
    mov ax, 66ffh                  ; Undefined code-page selector.
    int 21h
    require_error 1, fail_invalid_codepage
    xor bx, bx
    mov ax, 69ffh                  ; Media-ID selectors stop at 1.
    int 21h
    require_error 1, fail_invalid_media

    mov ax, 1
    mov es, ax
    mov ah, 49h                    ; Segment 0001h is not an allocated block.
    int 21h
    require_error 9, fail_invalid_free
    mov bx, 1
    mov ah, 4ah
    int 21h
    require_error 7, fail_invalid_resize
    push ds
    pop es

    mov ax, 3d02h
    mov dx, original_name
    int 21h
    fail_if_carry 3d
    mov [file_handle], ax

    mov bx, ax
    mov cx, payload_size
    mov dx, read_buffer
    mov ah, 3fh
    int 21h
    fail_if_carry 3f
    cmp ax, payload_size
    jne read_failed
    mov si, payload
    mov di, read_buffer
    mov cx, payload_size
    repe cmpsb
    je read_ok
read_failed:
    mov dx, fail_3f
    jmp fail
read_ok:

    mov bx, [file_handle]
    mov ax, 5700h
    int 21h
    fail_if_carry 57
    mov ax, 5701h
    int 21h
    fail_if_carry 57

    mov bx, [file_handle]
    mov ah, 45h
    int 21h
    fail_if_carry 45
    mov bx, ax
    mov ah, 3eh
    int 21h
    fail_if_carry 45

    mov bx, [file_handle]
    mov cx, 15
    mov ah, 46h
    int 21h
    fail_if_carry 46
    mov bx, 15
    mov ah, 3eh
    int 21h
    fail_if_carry 46

    mov bx, [file_handle]
    mov ah, 3eh
    int 21h
    fail_if_carry 3e

    mov ax, 4300h
    mov dx, original_name
    int 21h
    fail_if_carry 43
    mov ax, 4301h
    xor cx, cx
    int 21h
    fail_if_carry 43

    mov dx, original_name
    mov di, renamed_name
    mov ah, 56h
    int 21h
    fail_if_carry 56

    mov dx, dta
    mov ah, 1ah
    int 21h

    xor cx, cx
    mov dx, renamed_name
    mov ah, 4eh
    int 21h
    fail_if_carry 4e

    mov ah, 4fh
    int 21h
    fail_unless_carry 4f
    cmp ax, 12h                    ; no more files
    je find_next_ok
    mov dx, fail_4f
    jmp fail
find_next_ok:

    mov ax, 3d00h
    mov dx, missing_name
    int 21h
    fail_unless_carry 59
    xor bx, bx
    mov ah, 59h
    int 21h
    fail_if_carry 59
    cmp ax, 2                      ; file not found
    je extended_error_ok
    mov dx, fail_59
    jmp fail
extended_error_ok:

    mov dx, renamed_name
    mov ah, 41h
    int 21h
    fail_if_carry 41

    mov dx, root_directory
    mov ah, 3bh
    int 21h
    fail_if_carry 3b

    mov dx, directory
    mov ah, 3ah
    int 21h
    fail_if_carry 3a

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

memory_exhaust_failed:
    mov dx, fail_memory_exhaust
    jmp fail
sft_exhaust_failed:
    mov dx, fail_sft_exhaust
    jmp fail
invalid_selector_failed:
    mov dx, fail_invalid_selector
    jmp fail
dup_exhaust_failed:
    mov dx, fail_dup_exhaust
    jmp fail

fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

directory      db 'I21TEST', 0
root_directory db '\', 0
original_name  db 'DATA.BIN', 0
renamed_name   db 'RENAMED.BIN', 0
missing_name   db 'MISSING.BIN', 0
payload        db 'DOS4TEST'
payload_size   equ $ - payload
pass_message   db 'INT21_FILE_MEMORY_PASS', 13, 10, '$'
fail_1a        db 'INT21_1A_FAIL', 13, 10, '$'
fail_39        db 'INT21_39_FAIL', 13, 10, '$'
fail_3a        db 'INT21_3A_FAIL', 13, 10, '$'
fail_3b        db 'INT21_3B_FAIL', 13, 10, '$'
fail_3c        db 'INT21_3C_FAIL', 13, 10, '$'
fail_3d        db 'INT21_3D_FAIL', 13, 10, '$'
fail_3e        db 'INT21_3E_FAIL', 13, 10, '$'
fail_3f        db 'INT21_3F_FAIL', 13, 10, '$'
fail_40        db 'INT21_40_FAIL', 13, 10, '$'
fail_41        db 'INT21_41_FAIL', 13, 10, '$'
fail_42        db 'INT21_42_FAIL', 13, 10, '$'
fail_43        db 'INT21_43_FAIL', 13, 10, '$'
fail_45        db 'INT21_45_FAIL', 13, 10, '$'
fail_46        db 'INT21_46_FAIL', 13, 10, '$'
fail_47        db 'INT21_47_FAIL', 13, 10, '$'
fail_48        db 'INT21_48_FAIL', 13, 10, '$'
fail_49        db 'INT21_49_FAIL', 13, 10, '$'
fail_4a        db 'INT21_4A_FAIL', 13, 10, '$'
fail_4e        db 'INT21_4E_FAIL', 13, 10, '$'
fail_4f        db 'INT21_4F_FAIL', 13, 10, '$'
fail_56        db 'INT21_56_FAIL', 13, 10, '$'
fail_57        db 'INT21_57_FAIL', 13, 10, '$'
fail_59        db 'INT21_59_FAIL', 13, 10, '$'
fail_68        db 'INT21_68_FAIL', 13, 10, '$'
fail_memory_exhaust db 'INT21_MEMORY_EXHAUST_FAIL', 13, 10, '$'
fail_sft_exhaust db 'INT21_SFT_EXHAUST_FAIL', 13, 10, '$'
fail_jft_exhaust db 'INT21_JFT_EXHAUST_FAIL', 13, 10, '$'
fail_dup_exhaust db 'INT21_DUP_EXHAUST_FAIL', 13, 10, '$'
fail_dup2_exhaust db 'INT21_DUP2_EXHAUST_FAIL', 13, 10, '$'
fail_invalid_handle db 'INT21_INVALID_HANDLE_FAIL', 13, 10, '$'
fail_invalid_selector db 'INT21_INVALID_SELECTOR_FAIL', 13, 10, '$'
fail_invalid_open db 'INT21_INVALID_OPEN_FAIL', 13, 10, '$'
fail_invalid_seek db 'INT21_INVALID_SEEK_FAIL', 13, 10, '$'
fail_invalid_lock db 'INT21_INVALID_LOCK_FAIL', 13, 10, '$'
fail_invalid_attr db 'INT21_INVALID_ATTR_FAIL', 13, 10, '$'
fail_invalid_ioctl db 'INT21_INVALID_IOCTL_FAIL', 13, 10, '$'
fail_invalid_allocop db 'INT21_INVALID_ALLOCOP_FAIL', 13, 10, '$'
fail_invalid_country db 'INT21_INVALID_COUNTRY_FAIL', 13, 10, '$'
fail_invalid_codepage db 'INT21_INVALID_CODEPAGE_FAIL', 13, 10, '$'
fail_invalid_media db 'INT21_INVALID_MEDIA_FAIL', 13, 10, '$'
fail_invalid_free db 'INT21_INVALID_FREE_FAIL', 13, 10, '$'
fail_invalid_resize db 'INT21_INVALID_RESIZE_FAIL', 13, 10, '$'
file_handle    dw 0
error_handle   dw 0
sft_create_name db 'SFTCREATE.TST', 0
sft_new_name db 'SFTNEW.TST', 0
sft_temp_template db 'A:', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
memory_segment dw 0
open_handles   times 64 dw 0
cwd_buffer     times 64 db 0
read_buffer    times payload_size db 0
dta            times 128 db 0
program_end:
