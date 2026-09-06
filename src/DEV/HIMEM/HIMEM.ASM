; Clean-room XMS 2.00 manager for the repository MS-DOS tree.
;
; It shares no source with Microsoft's published HIMEM implementation.

        .model  tiny
        .286
        .code
        org     0
ifdef HIMEM_PROTECTED_COPY_TEST
        include XMSCOPYABI.INC
endif

; lock count, nonzero base KiB, size KiB. Base zero marks a free record; every
; EMB begins above the separately reserved 64-KiB HMA, including zero-size EMBs.
        include XMSRECORD.INC
MAX_UMB_BLOCKS  equ     32
; segment and paragraph size; bit 15 of size marks an allocated block. A UMB
; is wholly below F000h, so its size is always less than 5000h paragraphs.
UMB_BLOCK_SIZE  equ     4
UMB_ALLOCATED   equ     08000h
HMA_OWNED       equ     080h

        include XMSERROR.INC
        include BOOTCOPY.INC
        include XMSUMBPEER.INC

device_header:
        dw      0ffffh, 0ffffh
        dw      08000h
        dw      strategy
        dw      interrupt
        db      'HIMEM$  '

request_ptr     dd      0
old_int2f       dd      0
old_int15       dd      0
extended_kb     dw      0
hma_min_kb      db      0
handle_limit    dw      32
int15_kb        dw      0
cpu_386         db      0
a20_initial     db      0
a20_local       dw      0
a20_global      dw      0
a20_target      db      0
caller_ds       dw      0
caller_si       dw      0
ifdef HIMEM_PROTECTED_COPY_TEST
; Paired development image only. Each move checks the matching backend's
; capability before using this packet; no provider handoff or low release.
protected_copy_packet db 'XCPY'
endif
move_length     dd      0
move_source     dd      0
move_dest       dd      0
ifdef HIMEM_PROTECTED_COPY_TEST
move_address_classes dd 0
endif
move_offset_error db    0
highest_page   dw      0
ifdef HIMEM_SHIFT_ENTRY_TEST
initial_segment dw 0
endif
ifdef HIMEM_PROTECTED_OWNER_TEST
; Temporary transport snapshot, not a second allocator or reclaimed low owner.
owner_query_active db 0
owner_packet db 'XOWN'
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
        dw 3
else
        dw 1
endif
owner_limit dw 0
owner_pool dw 0
owner_largest dw 0
owner_total dw 0
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
owner_bx dw 0
owner_operation dw 0
owner_import_offset dw offset handles
owner_record_scratch db HANDLE_SIZE dup (0)
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
bootstrap_stage_entry dw offset xms_control,0
bootstrap_detached db 0
bootstrap_frozen db 0
endif
else
owner_records db MAX_HANDLES*HANDLE_SIZE dup (0)
endif
endif

strategy proc far
        mov     word ptr cs:[request_ptr], bx
        mov     word ptr cs:[request_ptr+2], es
        ret
strategy endp

interrupt proc far
        push    ax
        push    bx
        push    ds
ifdef DEBUG
        mov     al, 'I'
        call    debug_mark
endif
        les     bx, cs:[request_ptr]
        mov     al, es:[bx+2]
        or      al, al
        jnz     short interrupt_bad
        push    cs
        pop     ds
        call    initialize
        jmp     short interrupt_done
interrupt_bad:
        mov     word ptr es:[bx+3], 08103h
interrupt_done:
        pop     ds
        pop     bx
        pop     ax
        ret
interrupt endp


ifdef DEBUG
debug_mark proc near
        push    dx
ifdef DEBUG_SERIAL
        push    ax
        mov     ah, 1
        xor     dx, dx
        int     14h
        pop     ax
else
        mov     dx, 0e9h
        out     dx, al
endif
        pop     dx
        ret
debug_mark endp
endif

multiplex_handler proc far
        cmp     ax, 04300h
        je      short multiplex_installed
        cmp     ax, 04310h
        je      short multiplex_entry
        cmp     ax, 0e700h
        je      short private_installed
        cmp     ax, 0e701h
        je      private_register
        cmp     ax, 0e702h
        je      private_unregister
        cmp     ax, 0e703h
        je      private_relocate
        cmp     ax, 0e705h
        je      private_force_a20
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
        cmp     ax, XCP_LAYOUT_QUERY
        je      private_bootstrap_layout
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp     ax, XCP_STAGE_BIND
        je      private_bootstrap_stage
        cmp     ax, XCP_STAGE_RESTORE
        je      private_bootstrap_stage
        cmp     ax, XCP_STAGE_RETARGET
        je      private_bootstrap_stage
        cmp     ax, XCP_STAGE_FREEZE
        je      private_bootstrap_stage
endif
endif
        jmp     dword ptr cs:[old_int2f]
multiplex_installed:
        mov     al, 080h
        iret
multiplex_entry:
        mov     bx, offset xms_control
ifdef HIMEM_SHIFT_ENTRY_TEST
        push    ax
        mov     ax,cs
        cmp     ax,cs:[initial_segment]
        je      short multiplex_original_entry
        mov     bx,offset xms_rebased_control
multiplex_original_entry:
        pop     ax
endif
        push    cs
        pop     es
        iret
private_installed:
        mov     ax, 0e7ffh
        mov     bx, 04d55h              ; 'UM'
        mov     cx, 1
        iret

; Repository-private SYSINIT handoff. DX is the segment containing a complete
; copy of this resident image. Keep HIMEM's saved BIOS successor untouched;
; SYSINIT separately rebases the BIOS gate's DOS successor before reclaiming
; low DOS. Move only HIMEM's two vector heads to this copy.
private_relocate:
        push    ds
        xor     ax, ax
        mov     ds, ax
        cli
        mov     word ptr ds:[02fh*4], offset multiplex_handler
        mov     word ptr ds:[02fh*4+2], dx
        mov     word ptr ds:[015h*4], offset int15_handler
        mov     word ptr ds:[015h*4+2], dx
        sti
        pop     ds
        mov     ax, 0e7ffh
        iret

; DOS's retained-low driver return gate must re-enter HMA code even when a
; legacy driver changed the physical A20 gate without using XMS. Restore the
; hardware state without changing the public global/local nesting counters.
private_force_a20:
        call    enable_a20
        jc      short private_force_a20_failed
        mov     ax, 0e7ffh
        iret
private_force_a20_failed:
        xor     ax, ax
        iret

multiplex_handler endp

; Internal repository peer call. DS:SI points to version, count, then sorted
; segment/size word pairs. This is deliberately not a public UMB API.
private_register:
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        push    ds
        pop     es
        push    cs
        pop     ds
ifdef HIMEM_UMB_HANDOFF_TEST
        mov     ax,12h
        call    umb_remote
        jnc     private_done
endif
        HIMEM_UMB_REGISTER
private_done:
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        iret

private_unregister:
        push    cx
        push    si
        push    ds
        push    cs
        pop     ds
ifdef HIMEM_UMB_HANDOFF_TEST
        push    dx
        mov     ax,13h
        call    umb_remote
        pop     dx
        jnc     private_unregister_done
endif
        HIMEM_UMB_UNREGISTER
private_unregister_done:
        pop     ds
        pop     si
        pop     cx
        iret

int15_handler proc far
        cmp     ah, 088h
        jne     short int15_chain
        mov     ax, cs:[int15_kb]
        clc
        retf    2
int15_chain:
        jmp     dword ptr cs:[old_int15]
int15_handler endp

xms_control proc far
ifdef HIMEM_SHIFT_ENTRY_TEST
        push    ax
        mov     ax,cs
        cmp     ax,cs:[initial_segment]
        pop     ax
        je      short xms_control_body
        xor     ax,ax                   ; old entry is invalid after relocation
        mov     bl,ERR_GENERAL
        retf
xms_control_body::
endif
        mov     word ptr cs:[caller_ds], ds
        mov     word ptr cs:[caller_si], si
        cmp     ah, 088h
        jae     short xms_extended_control
        push    cx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        push    cs
        pop     ds
        cmp     ah, 011h
        ja      short xms_unknown
        mov     al, ah
        xor     ah, ah
        mov     si, ax
        shl     si, 1
        call    word ptr cs:[xms_table+si]
        jmp     short xms_return
xms_unknown:
        mov     bl, ERR_NOT_IMPLEMENTED
        xor     ax, ax
xms_return:
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     cx
        retf
xms_extended_control:
        push    si
        push    di
        push    bp
        push    ds
        push    es
        push    cs
        pop     ds
        cmp     [cpu_386], 0
        je      short xms_extended_reject
xms_extended_dispatch:
        cmp     ah, 088h
        je      short xms_extended_query
        cmp     ah, 089h
        je      short xms_extended_allocate
        cmp     ah, 08eh
        je      short xms_extended_info
        cmp     ah, 08fh
        je      short xms_extended_reallocate
xms_extended_unknown:
        ; DOS 6.22 aliases otherwise undefined 8xh calls to their low-seven-bit
        ; XMS 2.x function (for example, 8Ah behaves as Free EMB/0Ah).
        and     ah, 07fh
        cmp     ah, 011h
        ja      short xms_extended_reject
        mov     al, ah
        xor     ah, ah
        mov     si, ax
        shl     si, 1
        call    word ptr cs:[xms_table+si]
        jmp     short xms_extended_return
xms_extended_query:
        call    xms_query_any_free
        jmp     short xms_extended_return
xms_extended_allocate:
        call    xms_allocate_any
        jmp     short xms_extended_return
xms_extended_info:
        call    xms_extended_handle_info
        jmp     short xms_extended_return
xms_extended_reallocate:
        call    xms_reallocate_any
        jmp     short xms_extended_return
xms_extended_reject:
        mov     bl, ERR_NOT_IMPLEMENTED
        xor     ax, ax
xms_extended_return:
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        retf
xms_control endp
ifdef HIMEM_SHIFT_ENTRY_TEST
xms_rebased_control proc far
        jmp     xms_control_body
xms_rebased_control endp
endif

xms_table:
        dw      xms_version, xms_hma_request, xms_hma_release
        dw      xms_global_enable, xms_global_disable
        dw      xms_local_enable, xms_local_disable, xms_a20_query
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
        dw      xms_gate_query, xms_gate_allocate, xms_gate_free, xms_move
        dw      xms_gate_lock, xms_gate_unlock, xms_gate_info, xms_gate_reallocate
else
        dw      xms_query_free, xms_allocate, xms_free, xms_move
        dw      xms_lock, xms_unlock, xms_handle_info, xms_reallocate
endif
ifdef HIMEM_UMB_HANDOFF_TEST
        dw      umb_gate_request, umb_gate_release
else
        dw      xms_umb_request, xms_umb_release
endif

xms_success:
        mov     ax, 1
        clc
        ret
xms_failure:
        xor     ax, ax
        clc
        ret
xms_bad_handle:
        mov     bl, ERR_BAD_HANDLE
        jmp     xms_failure
xms_a20_failed:
        mov     bl, ERR_A20
        jmp     xms_failure
xms_no_memory:
        mov     bl, ERR_NO_MEMORY
        jmp     xms_failure

xms_version proc near
        mov     ax, 0300h
        mov     bx, 0310h
        cmp     [extended_kb], 1
        sbb     dx, dx
        inc     dx
        ret
xms_version endp

; XMS 3.0 super-extended-memory functions. The manager's physical pool remains
; bounded to 65535 KiB, but these entry points honor the specification's
; 32-bit register contracts and reject unrepresentable requests safely.
ifdef FORCE_286
xms_query_any_free proc near
        mov     bl, ERR_NOT_IMPLEMENTED
        jmp     xms_failure
xms_query_any_free endp
xms_allocate_any proc near
        mov     bl, ERR_NOT_IMPLEMENTED
        jmp     xms_failure
xms_allocate_any endp
xms_extended_handle_info proc near
        mov     bl, ERR_NOT_IMPLEMENTED
        jmp     xms_failure
xms_extended_handle_info endp
xms_reallocate_any proc near
        mov     bl, ERR_NOT_IMPLEMENTED
        jmp     xms_failure
xms_reallocate_any endp
else
        .386
xms_query_any_free proc near
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
        call    xms_gate_query
else
ifdef HIMEM_PROTECTED_OWNER_TEST
ifndef HIMEM_OWNER_QUERY_2_ONLY
        call    xms_remote_query
else
        call    largest_gap
        call    total_free
endif
else
        call    largest_gap
        call    total_free
endif
endif
        movzx   edx, dx
        movzx   eax, ax
        movzx   ecx, word ptr [highest_page]
        or      ecx, ecx
        jnz     short xms3_highest_ready
        movzx   ecx, word ptr [extended_kb]
        shr     ecx, 6
        add     ecx, 16
        dec     ecx
xms3_highest_ready:
ifdef HIMEM_PROTECTED_OWNER_TEST
ifndef HIMEM_OWNER_QUERY_2_ONLY
        ; Preserve transport failure rather than relabelling it as exhaustion.
        cmp     bl, ERR_GENERAL
        je      short xms3_query_done
endif
endif
        or      edx, edx
        jz      short xms3_no_memory
        xor     bl, bl
xms3_query_done:
        clc
        ret
xms3_no_memory:
        xor     eax, eax
        mov     bl, ERR_NO_MEMORY
        clc
        ret
xms_query_any_free endp

xms_allocate_any proc near
        mov     eax, edx
        shr     eax, 16
        jnz     xms_no_memory
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
        jmp     xms_gate_allocate
else
        jmp     xms_allocate
endif
xms_allocate_any endp

xms_extended_handle_info proc near
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
        push cx
        call xms_gate_info
        pop cx
        or ax,ax
        jz short xms3_remote_info_done
        movzx edx,dx
        xor bl,bl
xms3_remote_info_done:
        clc
        ret
else
        push    cx
        call    validate_handle
        jc      short xms3_info_bad_handle
        pop     cx
        mov     bh, byte ptr [si+HANDLE_LOCK]
        movzx   edx, word ptr [si+HANDLE_LENGTH]
        mov     ax, 1
        xor     bl, bl
        clc
        ret
xms3_info_bad_handle:
        pop     cx
        jmp     xms_bad_handle
endif
xms_extended_handle_info endp

xms_reallocate_any proc near
        mov     eax, ebx
        shr     eax, 16
        jnz     xms_no_memory
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
        jmp     xms_gate_reallocate
else
        jmp     xms_reallocate
endif
xms_reallocate_any endp
        .286
endif

xms_hma_request proc near
        cmp     [extended_kb], 0
        je      short hma_missing
        test    [hma_min_kb], HMA_OWNED
        jne     short hma_used
        xor     ah, ah
        mov     al, [hma_min_kb]
        mov     cl, 10
        shl     ax, cl
        cmp     dx, ax
        jb      short hma_too_small
        or      [hma_min_kb], HMA_OWNED
        jmp     xms_success
hma_missing:
        mov     bl, ERR_HMA_MISSING
        jmp     short hma_failure
hma_used:
        mov     bl, ERR_HMA_USED
        jmp     short hma_failure
hma_too_small:
        mov     bl, ERR_HMA_SMALL
hma_failure:
        jmp     xms_failure
xms_hma_request endp

xms_hma_release proc near
        test    [hma_min_kb], HMA_OWNED
        je      short hma_not_owned
        and     [hma_min_kb], NOT HMA_OWNED
        jmp     xms_success
hma_not_owned:
        mov     bl, ERR_HMA_FREE
        jmp     xms_failure
xms_hma_release endp

xms_global_enable proc near
        inc     [a20_global]
        jmp     short xms_enable_a20
xms_global_enable endp

xms_global_disable proc near
        cmp     [a20_global], 0
        je      short global_disable_now
        dec     [a20_global]
global_disable_now:
        jmp     short xms_reconcile_a20
xms_global_disable endp

xms_local_enable proc near
        inc     [a20_local]
xms_local_enable endp

xms_enable_a20 proc near
        call    enable_a20
        jmp     short xms_a20_result
xms_enable_a20 endp

xms_local_disable proc near
        cmp     [a20_local], 0
        je      short a20_underflow
        dec     [a20_local]
xms_local_disable endp

xms_reconcile_a20 proc near
        call    reconcile_a20
xms_a20_result::
        jc      xms_a20_failed
        jmp     xms_success
xms_reconcile_a20 endp

a20_underflow:
        jmp     xms_a20_failed

xms_a20_query proc near
        call    query_a20_hardware
        xor     bl, bl
        ret
xms_a20_query endp

enable_a20 proc near
        mov     al, 1
        jmp     set_a20_hardware
enable_a20 endp

reconcile_a20 proc near
        mov     ax, [a20_global]
        or      ax, [a20_local]
        jne     short reconcile_on
        cmp     [a20_initial], 0
        jne     short reconcile_on
        xor     al, al
        jmp     set_a20_hardware
reconcile_on:
        jmp     enable_a20
reconcile_a20 endp

; Set A20 through the fast gate, BIOS service, then the 8042 controller. Every
; backend is verified through physical aliasing; unsupported ports therefore
; fail safely instead of being trusted by their readback value.
set_a20_hardware proc near
        mov     cs:[a20_target], al
ifndef A20_TEST_SKIP_FAST
        push    ax
        in      al, 092h
        and     al, 0fch               ; never assert the reset bit
        cmp     cs:[a20_target], 0
        je      short set_a20_fast_write
        or      al, 2
set_a20_fast_write:
        out     092h, al
        pop     ax
        call    verify_a20_target
        jnc     short set_a20_done
endif

ifndef A20_TEST_SKIP_BIOS
        mov     ax, 02400h
        cmp     cs:[a20_target], 0
        je      short set_a20_bios
        inc     ax
set_a20_bios:
        int     015h
        call    verify_a20_target
        jnc     short set_a20_done
endif

        call    kbc_wait_input
        jc      short set_a20_fail
        mov     al, 0d1h
        out     064h, al
        call    kbc_wait_input
        jc      short set_a20_fail
        mov     al, 0ddh
        cmp     cs:[a20_target], 0
        je      short set_a20_kbc_write
        mov     al, 0dfh
set_a20_kbc_write:
        out     060h, al
        call    kbc_wait_input
        jc      short set_a20_fail
        call    verify_a20_target
        ret
set_a20_done:
        clc
        ret
set_a20_fail:
        stc
        ret
set_a20_hardware endp

verify_a20_target proc near
        call    query_a20_hardware
        cmp     al, cs:[a20_target]
        jne     short verify_a20_failed
        clc
        ret
verify_a20_failed:
        stc
        ret
verify_a20_target endp

kbc_wait_input proc near
        mov     cx, 0ffffh
kbc_wait_loop:
        in      al, 064h
        test    al, 2
        jz      short kbc_wait_ready
        loop    kbc_wait_loop
        stc
        ret
kbc_wait_ready:
        clc
        ret
kbc_wait_input endp

; Return AL=1 when 0000:0500 and FFFF:0510 are distinct physical locations.
; Both words are restored before interrupts resume, including in wrap mode.
query_a20_hardware proc near
        pushf
        cli
        push    bx
        push    cx
        push    dx
        push    ds
        push    es
        xor     ax, ax
        mov     ds, ax
        dec     ax
        mov     es, ax
        mov     bx, word ptr ds:[0500h]
        mov     dx, word ptr es:[0510h]
        mov     word ptr ds:[0500h], 0000h
        mov     word ptr es:[0510h], 0ffffh
        xor     cx, cx
        cmp     word ptr ds:[0500h], 0ffffh
        je      short query_a20_restore
        inc     cx
query_a20_restore:
        mov     word ptr es:[0510h], dx
        mov     word ptr ds:[0500h], bx
        xor     ax, ax
        mov     al, cl
        pop     es
        pop     ds
        pop     dx
        pop     cx
        pop     bx
        popf
        ret
query_a20_hardware endp

ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
        include XMSAUTH.INC
else
        include XMSALLOC.INC
endif

xms_move proc near
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp word ptr [bootstrap_stage_entry+2],0
        je staged_move_ready
        push bx
        push dx
        mov ax,8
        call xms_remote_owned
        pop dx
        pop bx
        jc staged_move_forward
        cmp word ptr [bootstrap_stage_entry+2],0
        je staged_move_ready
        xor ax,ax
        mov bl,ERR_GENERAL
        ret
staged_move_forward:
        mov ah,0bh
        call xms_stage_forward
        ret
staged_move_ready:
endif
        push    bx
        push    dx
        push    bp
        push    es
        mov     es, [caller_ds]
        mov     di, [caller_si]
ifdef HIMEM_PROTECTED_COPY_TEST
        mov     word ptr [move_address_classes],0
        cmp     word ptr es:[di+4],0
        jne     short protected_source_handle
        or      word ptr [move_address_classes],1
protected_source_handle:
        cmp     word ptr es:[di+10],0
        jne     short protected_dest_handle
        or      word ptr [move_address_classes],2
protected_dest_handle:
endif
        mov     ax, word ptr es:[di]
        test    al, 1
        jnz     short move_bad_length
        mov     word ptr [move_length], ax
        mov     ax, word ptr es:[di+2]
        mov     word ptr [move_length+2], ax
        or      ax, word ptr [move_length]
        jz      short move_success

        mov     dx, word ptr es:[di+4]
        mov     ax, word ptr es:[di+6]
        mov     bp, word ptr es:[di+8]
        call    resolve_move_address
        jc      short move_bad_source
        mov     word ptr [move_source], ax
        mov     word ptr [move_source+2], dx

        mov     dx, word ptr es:[di+10]
        mov     ax, word ptr es:[di+12]
        mov     bp, word ptr es:[di+14]
        call    resolve_move_address
        jc      short move_bad_dest
        mov     word ptr [move_dest], ax
        mov     word ptr [move_dest+2], dx

move_copy:
        call    copy_move_blocks
        jc      short move_general_failure
move_success:
        pop     es
        pop     bp
        pop     dx
        pop     bx
        jmp     xms_success
move_bad_length:
        mov     bl, ERR_BAD_LENGTH
        jmp     short move_failure
move_bad_source:
        mov     bl, ERR_BAD_SOURCE
        jmp     short move_bad_address
move_bad_dest:
        mov     bl, ERR_BAD_DEST
move_bad_address:
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
        cmp     [move_offset_error],2
        je      short move_general_failure
endif
        cmp     [move_offset_error], 0
        je      short move_failure
        mov     bl, ERR_BAD_LENGTH
        jmp     short move_failure
move_general_failure:
        mov     bl, ERR_GENERAL
move_failure:
        pop     es
        pop     bp
        add     sp, 4
        jmp     xms_failure
xms_move endp

        include XMSUMB.INC

; Resolve an XMS move endpoint. DX is a handle (zero means a packed
; segment:offset conventional address), BP:AX is its offset, and move_length
; is the transfer length. Returns DX:AX=physical address.
resolve_move_address proc near
        push    di
        mov     [move_offset_error], 0
        or      dx, dx
        jnz     short resolve_handle
        mov     dx, bp
        mov     bx, dx
        mov     cl, 12
        shr     dx, cl
        mov     cl, 4
        shl     bx, cl
        add     ax, bx
        adc     dx, 0
        pop     di
        clc
        ret
resolve_handle:
        push    dx
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
ifndef HIMEM_AUTHORITATIVE_LOCAL_LOOKUP
        call    xms_owner_handle
else
        call    validate_handle
endif
else
        call    validate_handle
endif
        pop     dx
        jc      short resolve_bad_handle
        push    bp                     ; retain the start offset's high word
        mov     bx, ax
        add     bx, word ptr [move_length]
        adc     bp, word ptr [move_length+2]
        jc      short resolve_bad_offset
        mov     dx, word ptr [si+HANDLE_LENGTH]
        mov     di, dx
        mov     cl, 6
        shr     dx, cl
        mov     cl, 10
        shl     di, cl
        cmp     bp, dx
        ja      short resolve_bad_offset
        jb      short resolve_offset_valid
        cmp     bx, di
        ja      short resolve_bad_offset
resolve_offset_valid:
        pop     bp                     ; bounds checking used the end offset
        mov     bx, ax
        mov     ax, word ptr [si+HANDLE_BASE]
        call    kb_to_physical
        add     ax, bx
        adc     dx, bp
        pop     di
        clc
        ret
resolve_bad_offset:
        pop     bp
        mov     [move_offset_error], 1
resolve_bad_handle:
        pop     di
        stc
        ret
resolve_move_address endp

copy_move_blocks proc near
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
        cmp     [owner_query_active],0
        je      bootstrap_copy_move
endif
ifdef HIMEM_PROTECTED_COPY_TEST
        push    si
        push    es
        push    bx
        push    cx
        push    dx
ifndef HIMEM_SKIP_COPY_CAPABILITY_TEST
        mov     ax,XCP_QUERY
        int     015h
        cmp     ax,XCP_REPLY
        jne     short protected_copy_unavailable
        cmp     bx,XCP_SIGNATURE
        jne     short protected_copy_unavailable
        cmp     cx,XCP_VERSION
        jne     short protected_copy_unavailable
        and     dx,XCP_REQUIRED
        cmp     dx,XCP_REQUIRED
        jne     short protected_copy_unavailable
endif
        push    cs
        pop     es
        mov     si,offset protected_copy_packet
        mov     ah,087h
        int     015h
        pop     dx
        pop     cx
        pop     bx
        pop     es
        pop     si
        ret
protected_copy_unavailable:
        pop     dx
        pop     cx
        pop     bx
        pop     es
        pop     si
        stc
        ret
else
        HIMEM_BIOS_COPY
endif
copy_move_blocks endp

ifndef HIMEM_AUTHORITATIVE_OWNER_TEST
        HIMEM_BIOS_DESCRIPTOR
endif

; Convert AX kilobytes above the XMS base to DX:AX physical bytes.
kb_to_physical proc near
        mov     dx, ax
        mov     cl, 6
        shr     dx, cl
        add     dx, 0010h
        mov     cl, 10
        shl     ax, cl
        ret
kb_to_physical endp

ifndef HIMEM_AUTHORITATIVE_OWNER_TEST
        HIMEM_BIOS_GDT
        include XMSHANDLE.INC
endif

; Keep variable-capacity XMS handles at the end of the resident image. The
; initialization break includes only /NUMHANDLES= records; the full table is
; still present in the load image for the documented maximum.
ifdef HIMEM_UMB_HANDOFF_TEST
        include XMSUMBFRONT.INC
; After commitment the retired table is temporary peer-registration input,
; never an authoritative low mirror. The preceding word supplies its version.
umb_peer_version dw 1
endif
umb_count       dw      0
umb_blocks      db      MAX_UMB_BLOCKS * UMB_BLOCK_SIZE dup (0)
umb_blocks_end label byte
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
        db (16-(($-device_header) MOD 16)) MOD 16 dup (0)
bootstrap_owner_start label byte
bootstrap_copy_move proc near
        HIMEM_BIOS_COPY
bootstrap_copy_move endp
        HIMEM_BIOS_DESCRIPTOR
        HIMEM_BIOS_GDT
        include XMSALLOC.INC
        include XMSHANDLE.INC
endif
handles         db      MAX_HANDLES * HANDLE_SIZE dup (0)
resident_end label byte
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
HIMEM_PERMANENT_BYTES equ bootstrap_owner_start-device_header
HIMEM_BOOTSTRAP_CODE_BYTES equ handles-bootstrap_owner_start
HIMEM_HANDLES_OFFSET equ handles-device_header
endif

; Record the highest installed physical 64-KiB page for XMS 3 function 88h.
; This is installation-only code and deliberately follows resident_end.
; E801 reports hardware extent independently of memory already reserved from
; the legacy AH=88h pool. DOS 6.22 returns this page number rather than a byte
; address in ECX.
detect_highest_page proc near
        push    ax
        push    bx
        push    cx
        push    dx
        cmp     [cpu_386], 0
        je      short highest_page_done
        ; AT CMOS registers 30h/31h report KiB installed above 1 MiB.
        in      al, 070h
        mov     dl, al
        mov     al, 030h
        out     070h, al
        in      al, 071h
        mov     bl, al
        mov     al, 031h
        out     070h, al
        in      al, 071h
        mov     bh, al
        mov     al, dl
        out     070h, al
        mov     cl, 6
        shr     bx, cl
        add     bx, 16
        dec     bx
        mov     [highest_page], bx

        mov     ax, 0e801h
        int     015h
        jc      short highest_page_done
        or      ax, ax
        jnz     short highest_page_values
        mov     ax, cx
        mov     bx, dx
highest_page_values:
        mov     cl, 6
        shr     ax, cl
        add     bx, ax
        add     bx, 16
        dec     bx
        cmp     bx, [highest_page]
        jbe     short highest_page_done
        mov     [highest_page], bx
highest_page_done:
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
detect_highest_page endp

test_pattern    db      1024 dup (0)
test_verify     db      1024 dup (0)
a20_control     db      1
machine_code    db      1
shadow_ram      db      0
cpu_clock       db      0
eisa_memory     db      0
verbose_mode    db      0
testmem_mode    db      1
option_buffer   db      40 dup (0)
test_address    dd      0
test_remaining dw      0
initialize proc near
ifdef HIMEM_SHIFT_ENTRY_TEST
        mov     [initial_segment],cs
endif
ifdef DEBUG
        mov     al, 'A'
        call    debug_mark
endif
        ; Refuse a second XMS manager.
        mov     ax, 04300h
        int     02fh
        cmp     al, 080h
        je      init_fail
        mov     ax, 0e700h
        int     02fh
        cmp     al, 0ffh
        je      init_fail

        call    parse_options
        jc      init_fail

        ; HIMEM requires an 80286 or newer processor. The move engine below
        ; uses 16-bit word pairs so the published XMS path is 286-safe.
ifdef FORCE_286
        jmp     short init_check_286
else
        call    cpu_is_386
        jc      short init_check_286
        mov     [cpu_386], 1
        jmp     short init_cpu_ok
endif
init_check_286:
        call    cpu_is_286
        jc      init_fail
init_cpu_ok:

ifdef DEBUG
        mov     al, 'B'
        call    debug_mark
endif

        mov     ax, 0352fh
        int     021h
        mov     word ptr [old_int2f], bx
        mov     word ptr [old_int2f+2], es
        mov     ax, 03515h
        int     021h
        mov     word ptr [old_int15], bx
        mov     word ptr [old_int15+2], es
ifdef DEBUG
        mov     al, 'C'
        call    debug_mark
endif

        call    detect_highest_page

        cmp     [eisa_memory], 0
        je      short init_query_88
        mov     ax, 0e801h
        int     015h
        jc      short init_query_88
        or      ax, ax
        jnz     short init_eisa_values
        mov     ax, cx
        mov     bx, dx
init_eisa_values:
        ; AX is KiB between 1 and 16 MiB; BX counts 64-KiB blocks above
        ; 16 MiB.  The XMS 2.00 pool is bounded to 65535 KiB.
        mov     cx, bx
        cmp     cx, 1024
        jae     short init_eisa_saturate
        push    ax
        mov     ax, cx
        mov     cl, 6
        shl     ax, cl
        mov     bx, ax
        pop     ax
        add     ax, bx
        jc      short init_eisa_saturate
        jmp     short init_memory_found
init_eisa_saturate:
        mov     ax, 0ffffh
        jmp     short init_memory_found
init_query_88:
        mov     ah, 088h
        int     015h
init_memory_found:
        sub     ax, [int15_kb]
        jnc     short init_extended_ok
        xor     ax, ax
init_extended_ok:
        mov     [extended_kb], ax
        or      ax, ax
        jz      init_fail
        cmp     [testmem_mode], 0
        je      short init_memory_tested
        call    test_extended_memory
        jnc     short init_memory_tested
        mov     si, offset testmem_failure_message
        call    print_bios_string
        jmp     init_fail
init_memory_tested:
ifdef DEBUG
        mov     al, 'D'
        call    debug_mark
endif

        ; Preserve the machine's incoming A20 state. Querying physical aliasing
        ; avoids assuming that port 92h exists or accurately reports the gate.
        call    query_a20_hardware
        mov     [a20_initial], al
        cmp     al, 0
        je      short init_disable_a20
        cmp     [a20_control], 0
        je      short init_keep_a20
init_disable_a20:
        xor     al, al
        call    set_a20_hardware
        jc      short init_keep_a20
        mov     [a20_initial], 0
init_keep_a20:
        cmp     [verbose_mode], 0
        je      short init_no_verbose
        mov     si, offset verbose_message
        call    print_bios_string
init_no_verbose:

        push    ds
        push    cs
        pop     ds
ifdef DEBUG
        mov     al, 'E'
        call    debug_mark
endif
        mov     dx, offset multiplex_handler
        mov     ax, 0252fh
        int     021h
        mov     dx, offset int15_handler
        mov     ax, 02515h
        int     021h
        pop     ds

        les     bx, cs:[request_ptr]
        xor     ax, ax
        mov     al, byte ptr cs:[handle_limit]
        mov     dl, HANDLE_SIZE
        mul     dl
        add     ax, offset handles
        add     ax, 15
        and     ax, 0fff0h
        mov     word ptr es:[bx+14], ax
        mov     word ptr es:[bx+16], cs
        mov     word ptr es:[bx+3], 00100h
ifdef DEBUG
        mov     al, 'F'
        call    debug_mark
endif
        ret
init_fail:
        les     bx, cs:[request_ptr]
        ; DOS 4 links character-device headers without consulting the INIT
        ; error bit.  Keep the inert request stub resident so the device chain
        ; never points into memory returned to the allocator.
        mov     word ptr es:[bx+14], offset initialize
        mov     word ptr es:[bx+16], cs
        mov     word ptr es:[bx+3], 00100h
        ret
initialize endp

; Parse the documented DOS 6 HIMEM switches implemented by this driver.
; Machine-specific compatibility hints are retained even where the generic,
; verified A20 backends are safer than poking undocumented chipset ports.
parse_options proc near
        les     bx, [request_ptr]
        les     si, dword ptr es:[bx+18]
parse_skip_driver:
        mov     al, es:[si]
        inc     si
        cmp     al, 0
        je      short parse_options_done
        cmp     al, 13
        je      short parse_options_done
        cmp     al, 10
        je      short parse_options_done
        cmp     al, ' '
        je      short parse_next
        cmp     al, 9
        jne     short parse_skip_driver
parse_next:
        mov     al, es:[si]
        cmp     al, ' '
        je      short parse_advance
        cmp     al, 9
        je      short parse_advance
        cmp     al, 0
        je      short parse_options_done
        cmp     al, 13
        je      short parse_options_done
        cmp     al, 10
        je      short parse_options_done
        mov     di, offset option_buffer
        mov     cx, 39
parse_copy_token:
        mov     al, es:[si]
        cmp     al, ' '
        je      short parse_token_done
        cmp     al, 9
        je      short parse_token_done
        cmp     al, 0
        je      short parse_token_done
        cmp     al, 13
        je      short parse_token_done
        cmp     al, 10
        je      short parse_token_done
        or      al, 20h
        cmp     al, 'a'
        jb      short parse_store
        cmp     al, 'z'
        ja      short parse_store
        and     al, 0dfh
parse_store:
        mov     [di], al
        inc     di
        inc     si
        loop    parse_copy_token
        stc
        ret
parse_token_done:
        mov     byte ptr [di], 0
        push    si
        call    parse_one_option
        pop     si
        jc      short parse_options_bad
        jmp     short parse_next
parse_advance:
        inc     si
        jmp     short parse_next
parse_options_done:
        clc
        ret
parse_options_bad:
        stc
        ret
parse_options endp

; Carry clear on an 80386 or newer, carry set on an 80286. In real mode a 286
; clears IOPL and NT when POPF attempts to set them; a 386 retains them.
cpu_is_386 proc near
        push    ax
        pushf
        mov     ax, 07000h
        push    ax
        popf
        pushf
        pop     ax
        and     ax, 07000h
        jz      short cpu_not_386
        popf
        pop     ax
        clc
        ret
cpu_not_386:
        popf
        pop     ax
        stc
        ret
cpu_is_386 endp

; Carry clear on an 80286 or newer, carry set on an 8086/80186. PUSH SP
; stores the pre-decrement value starting with the 286 and the decremented
; value on earlier processors.
cpu_is_286 proc near
        mov     ax, sp
        push    sp
        pop     bx
        cmp     ax, bx
        je      short cpu_is_286_yes
        stc
        ret
cpu_is_286_yes:
        clc
        ret
cpu_is_286 endp

parse_one_option proc near
        mov     si, offset option_buffer
        mov     dx, offset opt_hmamin
        call    match_prefix
        jnc     short option_hmamin
        mov     si, offset option_buffer
        mov     dx, offset opt_numhandles
        call    match_prefix
        jnc     short option_numhandles
        mov     si, offset option_buffer
        mov     dx, offset opt_int15
        call    match_prefix
        jnc     short option_int15
        mov     si, offset option_buffer
        mov     dx, offset opt_machine
        call    match_prefix
        jnc     short option_machine
        mov     si, offset option_buffer
        mov     dx, offset opt_a20control
        call    match_prefix
        jnc     short option_a20
        mov     si, offset option_buffer
        mov     dx, offset opt_shadowram
        call    match_prefix
        jnc     short option_shadow
        mov     si, offset option_buffer
        mov     dx, offset opt_cpuclock
        call    match_prefix
        jnc     short option_cpuclock
        mov     si, offset option_buffer
        mov     dx, offset opt_eisa
        call    string_equal
        jnc     short option_eisa
        mov     si, offset option_buffer
        mov     dx, offset opt_verbose
        call    string_equal
        jnc     short option_verbose
        mov     si, offset option_buffer
        mov     dx, offset opt_testmem
        call    match_prefix
        jnc     short option_testmem
        stc
        ret
option_hmamin:
        call    parse_decimal
        jc      short option_bad
        cmp     ax, 63
        ja      short option_bad
        mov     [hma_min_kb], al
        clc
        ret
option_numhandles:
        call    parse_decimal
        jc      short option_bad
        cmp     ax, 1
        jb      short option_bad
        cmp     ax, MAX_HANDLES
        ja      short option_bad
        mov     byte ptr [handle_limit], al
        clc
        ret
option_int15:
        call    parse_decimal
        jc      short option_bad
        cmp     ax, 64
        jae     short option_int15_store
        xor     ax, ax
option_int15_store:
        mov     [int15_kb], ax
        clc
        ret
option_machine:
        call    parse_machine
        jc      short option_bad
        mov     [machine_code], al
        clc
        ret
option_a20:
        call    parse_on_off
        jc      short option_bad
        mov     [a20_control], al
        clc
        ret
option_shadow:
        call    parse_on_off
        jc      short option_bad
        mov     [shadow_ram], al
        clc
        ret
option_cpuclock:
        call    parse_on_off
        jc      short option_bad
        mov     [cpu_clock], al
        clc
        ret
option_eisa:
        mov     [eisa_memory], 1
        clc
        ret
option_verbose:
        mov     [verbose_mode], 1
        clc
        ret
option_testmem:
        call    parse_on_off
        jc      short option_bad
        mov     [testmem_mode], al
        clc
        ret
option_bad:
        stc
        ret
parse_one_option endp

; Match DS:SI against the NUL-terminated prefix at DS:DX. On success SI is
; positioned at the option value.
match_prefix proc near
        push    bx
        mov     bx, dx
match_prefix_loop:
        mov     al, [bx]
        inc     bx
        or      al, al
        jz      short match_prefix_yes
        cmp     al, [si]
        jne     short match_prefix_no
        inc     si
        jmp     short match_prefix_loop
match_prefix_yes:
        pop     bx
        clc
        ret
match_prefix_no:
        pop     bx
        stc
        ret
match_prefix endp

parse_decimal proc near
        xor     ax, ax
        xor     cx, cx
parse_decimal_loop:
        mov     bl, [si]
        or      bl, bl
        jz      short parse_decimal_done
        cmp     bl, '0'
        jb      short parse_decimal_bad
        cmp     bl, '9'
        ja      short parse_decimal_bad
        mov     dx, 10
        mul     dx
        jc      short parse_decimal_bad
        sub     bl, '0'
        xor     bh, bh
        add     ax, bx
        jc      short parse_decimal_bad
        inc     si
        inc     cx
        jmp     short parse_decimal_loop
parse_decimal_done:
        or      cx, cx
        jz      short parse_decimal_bad
        clc
        ret
parse_decimal_bad:
        stc
        ret
parse_decimal endp

parse_on_off proc near
        mov     dx, offset value_on
        call    string_equal
        jnc     short parse_on
        mov     dx, offset value_off
        call    string_equal
        jc      short parse_on_off_bad
        xor     al, al
        clc
        ret
parse_on:
        mov     al, 1
        clc
        ret
parse_on_off_bad:
        stc
        ret
parse_on_off endp

parse_machine proc near
        push    si
        call    parse_decimal
        pop     si
        jc      short parse_machine_name
        cmp     ax, 1
        jb      short parse_machine_bad
        cmp     ax, 14
        ja      short parse_machine_bad
        clc
        ret
parse_machine_name:
        mov     bx, offset machine_names
        mov     al, 1
parse_machine_loop:
        mov     dx, [bx]
        or      dx, dx
        jz      short parse_machine_bad
        call    string_equal
        jnc     short parse_machine_found
        add     bx, 2
        inc     al
        jmp     short parse_machine_loop
parse_machine_found:
        clc
        ret
parse_machine_bad:
        stc
        ret
parse_machine endp

string_equal proc near
        push    si
        push    bx
        mov     bx, dx
string_equal_loop:
        mov     ah, [bx]
        mov     al, [si]
        inc     bx
        inc     si
        cmp     al, ah
        jne     short string_not_equal
        or      al, al
        jnz     short string_equal_loop
        pop     bx
        pop     si
        clc
        ret
string_not_equal:
        ; DOS 6 documents /V as the abbreviation of /VERBOSE. This mismatch
        ; is the exact point where a NUL after '/V' meets its next 'E'.
        or      al, al
        jnz     short string_really_not_equal
        cmp     bx, offset opt_verbose+3
        je      short string_equal_abbrev
string_really_not_equal:
        pop     bx
        pop     si
        stc
        ret
string_equal_abbrev:
        pop     bx
        pop     si
        clc
        ret
string_equal endp

opt_hmamin      db '/HMAMIN=',0
opt_numhandles  db '/NUMHANDLES=',0
opt_int15       db '/INT15=',0
opt_machine     db '/MACHINE:',0
opt_a20control  db '/A20CONTROL:',0
opt_shadowram   db '/SHADOWRAM:',0
opt_cpuclock    db '/CPUCLOCK:',0
opt_eisa        db '/EISA',0
opt_verbose     db '/VERBOSE',0
opt_testmem     db '/TESTMEM:',0
value_on        db 'ON',0
value_off       db 'OFF',0
machine_names   dw offset machine_at, offset machine_ps2
                dw offset machine_ptl, offset machine_hp, offset machine_att
                dw offset machine_acer, offset machine_toshiba, offset machine_wyse
                dw offset machine_tulip, offset machine_zenith, offset machine_at1
                dw offset machine_at2, offset machine_at3, offset machine_fasthp, 0
machine_at      db 'AT',0
machine_ps2     db 'PS2',0
machine_ptl     db 'PTLCASCADE',0
machine_hp      db 'HPVECTRA',0
machine_att     db 'ATT6300PLUS',0
machine_acer    db 'ACERL100',0
machine_toshiba db 'TOSHIBA',0
machine_wyse    db 'WYSE',0
machine_tulip   db 'TULIP',0
machine_zenith  db 'ZENITH',0
machine_at1     db 'AT1',0
machine_at2     db 'AT2',0
machine_at3     db 'AT3',0
machine_fasthp  db 'FASTHP',0
verbose_message db 13,10,'HIMEM: DOS 6 extended-memory manager installed',13,10,0
testmem_failure_message db 13,10,'HIMEM: Extended-memory test failed',13,10,0

print_bios_string proc near
        push    ax
        push    bx
print_bios_next:
        lodsb
        or      al, al
        jz      short print_bios_done
        mov     ah, 0eh
        mov     bx, 0007h
        int     010h
        jmp     short print_bios_next
print_bios_done:
        pop     bx
        pop     ax
        ret
print_bios_string endp

; Destructively verify every byte of the XMS span before the manager publishes
; it. Each 1-KiB block is written and read back with complementary patterns.
; INT 15h/87h keeps this path 286-safe and reuses the same transfer mechanism
; later exposed through XMS function 0Bh.
test_extended_memory proc near
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    es
        mov     word ptr [test_address], 0
        mov     word ptr [test_address+2], 0010h
        mov     ax, [extended_kb]
        mov     [test_remaining], ax
testmem_block:
        mov     ax, 0aa55h
        call    test_memory_pattern
        jc      short testmem_failed
        mov     ax, 055aah
        call    test_memory_pattern
        jc      short testmem_failed
        add     word ptr [test_address], 1024
        adc     word ptr [test_address+2], 0
        dec     [test_remaining]
        jnz     short testmem_block
        clc
        jmp     short testmem_done
testmem_failed:
        stc
testmem_done:
        pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
test_extended_memory endp

; AX is the word pattern. Write and verify one complete 1-KiB block at the
; physical address in test_address.
test_memory_pattern proc near
        push    ax
        push    cx
        push    si
        push    di
        push    es
        push    ax
        push    cs
        pop     es
        mov     di, offset test_pattern
        mov     cx, 512
        cld
        rep     stosw

        mov     ax, offset test_pattern
        call    conventional_physical
        mov     word ptr [move_source], ax
        mov     word ptr [move_source+2], dx
        mov     ax, word ptr [test_address]
        mov     dx, word ptr [test_address+2]
        mov     word ptr [move_dest], ax
        mov     word ptr [move_dest+2], dx
        mov     word ptr [move_length], 1024
        mov     word ptr [move_length+2], 0
        call    copy_move_blocks
        jc      short test_pattern_bad_pop

        mov     ax, word ptr [test_address]
        mov     dx, word ptr [test_address+2]
        mov     word ptr [move_source], ax
        mov     word ptr [move_source+2], dx
        mov     ax, offset test_verify
        call    conventional_physical
        mov     word ptr [move_dest], ax
        mov     word ptr [move_dest+2], dx
        mov     word ptr [move_length], 1024
        mov     word ptr [move_length+2], 0
        call    copy_move_blocks
        jc      short test_pattern_bad_pop

ifdef TESTMEM_FAULT
        ; Test-only mutation: prove that the readback comparison gates install.
        inc     byte ptr [test_verify]
endif
        pop     ax
        push    ax
        mov     si, offset test_verify
        mov     cx, 512
test_pattern_compare:
        cmp     word ptr [si], ax
        jne     short test_pattern_bad_pop
        add     si, 2
        loop    test_pattern_compare
        pop     ax
        clc
        jmp     short test_pattern_done
test_pattern_bad_pop:
        pop     ax
        stc
test_pattern_done:
        pop     es
        pop     di
        pop     si
        pop     cx
        pop     ax
        ret
test_memory_pattern endp

; Convert CS:AX to a physical DX:AX address.
conventional_physical proc near
        push    bx
        push    cx
        mov     dx, cs
        mov     bx, dx
        mov     cl, 12
        shr     dx, cl
        mov     cl, 4
        shl     bx, cl
        add     ax, bx
        adc     dx, 0
        pop     cx
        pop     bx
        ret
conventional_physical endp
        end
