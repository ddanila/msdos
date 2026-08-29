; DOS 5 compatible command history and macro TSR.

HISTORY_SLOTS   EQU 16
HISTORY_WIDTH   EQU 128
MACRO_SLOTS     EQU 16
MACRO_NAME_SIZE EQU 16
MACRO_BODY_SIZE EQU 128

CODE SEGMENT PUBLIC
        ORG     100h
        ASSUME  CS:CODE,DS:CODE,ES:NOTHING,SS:CODE

start:
        cld
        mov     ax,4800h
        int     2fh
        or      al,al
        jz      first_install
        mov     cs:resident_seg,es
        call    process_args
        jmp     exit_with_status

first_install:
        push    cs
        pop     es
        mov     cs:resident_seg,cs
        call    clear_state
        call    process_args
        cmp     cs:exit_code,0
        jne     exit_with_status
        cmp     cs:no_install,0
        jne     exit_with_status

        mov     ax,352fh
        int     21h
        mov     cs:old_2f_off,bx
        mov     cs:old_2f_seg,es

        mov     es,word ptr cs:[2ch]
        mov     ah,49h
        int     21h
        push    cs
        pop     ds
        mov     dx,OFFSET int2f_handler
        mov     ax,252fh
        int     21h
        mov     dx,OFFSET installed_msg
        call    print_dollar
        mov     dx,(resident_end-start+100h+15)/16
        mov     ax,3100h
        int     21h

exit_with_status:
        mov     al,cs:exit_code
        mov     ah,4ch
        int     21h

; ---------------------------------------------------------------------------
; Resident INT 2F interface
; ---------------------------------------------------------------------------
int2f_handler PROC FAR
        cmp     ax,4800h
        je      dk_install_check
        cmp     ax,4810h
        je      dk_buffered_input
        cmp     ax,4812h
        je      dk_command_input
        jmp     dword ptr cs:old_2f_off

dk_install_check:
        mov     ax,0aa02h
        push    cs
        pop     es
        iret

dk_buffered_input:
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        cld
        mov     bp,dx                    ; caller's DOS input buffer
        mov     cs:caller_ds,ds

        cmp     cs:pending_pos,0
        jne     dk_emit_pending

        ; Redirected input must retain DOS handle semantics.  Interactive
        ; console input uses DOSKEY's history-aware editor below.
        mov     ax,4400h
        xor     bx,bx
        int     21h
        test    dx,0080h                ; character device
        jz      dk_read_line
        test    dx,0001h                ; CON input capability (not AUX/file)
        jnz     dk_interactive_line
dk_read_line:
        mov     dx,bp
        mov     ah,0ah
        int     21h
        jmp     short dk_line_ready
dk_interactive_line:
        call    edit_line
dk_line_ready:
        mov     ax,cs:caller_ds           ; DOS does not promise to retain DS
        mov     ds,ax
        call    remember_line
        call    expand_macro
        jmp     short dk_input_done

dk_emit_pending:
        call    emit_pending_line

dk_input_done:
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        xor     ax,ax
        iret

int2f_handler ENDP

; Private COMMAND.COM split-phase adapter.  BX=0 emits a queued $T command
; without reading; BX=1 records and expands a line already read at DS:DX.
dk_command_input:
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        cld
        mov     bp,dx
        mov     cs:service_result,0
        or      bx,bx
        jnz     dk_command_process
        cmp     cs:pending_pos,0
        je      dk_command_prepare
        call    emit_pending_line
        mov     cs:service_result,1
        jmp     short dk_command_done
dk_command_prepare:
        call    preload_template
        cmp     cs:default_insert,0
        je      dk_command_done
        mov     cx,5200h
        mov     ah,05h
        int     16h
        jmp     short dk_command_done
dk_command_process:
        call    remember_line
        call    expand_macro
        mov     cs:service_result,1
dk_command_done:
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        xor     ax,ax
        mov     al,cs:service_result
        iret

; ---------------------------------------------------------------------------
; Interactive line editor.  DOS redirected input continues to use AH=0Ah;
; this path is only selected for a character-device standard input handle.
; ---------------------------------------------------------------------------
edit_line:
        mov     cs:editor_len,0
        mov     cs:editor_pos,0
        mov     cs:editor_drawn,0
        mov     cs:history_nav,0ffh
        mov     cs:f8_active,0
        mov     al,cs:default_insert
        mov     cs:editor_insert_mode,al
editor_key:
        xor     ah,ah
        int     16h
        or      al,al
        jz      editor_extended
        cmp     al,0e0h
        je      editor_extended
        mov     cs:f8_active,0
        cmp     al,0dh
        je      editor_enter
        cmp     al,08h
        je      editor_backspace
        cmp     al,1bh
        je      editor_escape
        cmp     al,20h
        jb      editor_key
        cmp     al,7eh
        ja      editor_key
        mov     dl,ds:[bp]
        dec     dl
        cmp     cs:editor_len,dl
        jae     editor_key
        push    ax
        cmp     cs:editor_insert_mode,0
        je      editor_overwrite
        xor     cx,cx
        mov     cl,cs:editor_len
        sub     cl,cs:editor_pos
        jcxz    editor_overwrite
        mov     si,OFFSET editor_buffer
        xor     bx,bx
        mov     bl,cs:editor_len
        add     si,bx
        dec     si
        mov     di,si
        inc     di
editor_shift_right:
        mov     al,cs:[si]
        mov     cs:[di],al
        dec     si
        dec     di
        loop    editor_shift_right
editor_overwrite:
        pop     ax
        xor     bx,bx
        mov     bl,cs:editor_pos
        mov     cs:[editor_buffer+bx],al
        inc     cs:editor_pos
        mov     dl,cs:editor_len
        cmp     cs:editor_pos,dl
        jbe     editor_changed
        mov     al,cs:editor_pos
        mov     cs:editor_len,al
        jmp     short editor_changed

editor_backspace:
        cmp     cs:editor_pos,0
        je      editor_key
        dec     cs:editor_pos
        cmp     cs:editor_insert_mode,0
        jne     editor_backspace_delete
        mov     al,cs:editor_pos
        cmp     al,cs:editor_len
        je      editor_backspace_delete
        mov     dl,08h
        call    editor_putc
        dec     cs:editor_screen
        jmp     editor_key
editor_backspace_delete:
        mov     bl,cs:editor_pos
        jmp     short editor_delete_at_bl

editor_delete:
        mov     bl,cs:editor_pos
        cmp     bl,cs:editor_len
        jae     editor_key
editor_delete_at_bl:
        xor     bh,bh
        mov     si,OFFSET editor_buffer
        add     si,bx
        mov     di,si
        inc     si
        xor     cx,cx
        mov     cl,cs:editor_len
        sub     cl,bl
        dec     cx
        jcxz    editor_delete_tail
editor_shift_left:
        mov     al,cs:[si]
        mov     cs:[di],al
        inc     si
        inc     di
        loop    editor_shift_left
editor_delete_tail:
        dec     cs:editor_len
        jmp     short editor_changed

editor_escape:
        mov     cs:editor_len,0
        mov     cs:editor_pos,0
        mov     cs:history_nav,0ffh
editor_changed:
        call    editor_refresh
        jmp     editor_key

editor_extended:
        cmp     ah,48h                  ; Up
        je      editor_up
        cmp     ah,50h                  ; Down
        je      editor_down
        cmp     ah,49h                  ; Page Up
        je      editor_oldest
        cmp     ah,51h                  ; Page Down
        je      editor_newest
        cmp     ah,41h                  ; F7
        je      editor_f7
        cmp     ah,42h                  ; F8
        je      editor_f8
        cmp     ah,43h                  ; F9
        je      editor_f9
        mov     cs:f8_active,0
        cmp     ah,4bh
        je      editor_left
        cmp     ah,4dh
        je      editor_right
        cmp     ah,47h
        je      editor_home
        cmp     ah,4fh
        je      editor_end
        cmp     ah,52h
        je      editor_insert
        cmp     ah,53h
        je      editor_delete
        cmp     ah,73h                  ; Ctrl+Left
        je      editor_word_left
        cmp     ah,74h                  ; Ctrl+Right
        je      editor_word_right
        cmp     ah,75h                  ; Ctrl+End
        je      editor_ctrl_end
        cmp     ah,77h                  ; Ctrl+Home
        je      editor_ctrl_home
        cmp     ah,6eh                  ; Alt+F7
        je      editor_clear_history
        jmp     editor_key

editor_left:
        cmp     cs:editor_pos,0
        je      editor_key
        dec     cs:editor_pos
        mov     dl,08h
        call    editor_putc
        dec     cs:editor_screen
        jmp     editor_key
editor_right:
        mov     bl,cs:editor_pos
        cmp     bl,cs:editor_len
        jae     editor_key
        xor     bh,bh
        mov     dl,cs:[editor_buffer+bx]
        call    editor_putc
        inc     cs:editor_pos
        inc     cs:editor_screen
        jmp     editor_key
editor_home:
        cmp     cs:editor_pos,0
        je      editor_key
        mov     cl,cs:editor_pos
        xor     ch,ch
editor_home_loop:
        mov     dl,08h
        call    editor_putc
        loop    editor_home_loop
        mov     cs:editor_pos,0
        mov     cs:editor_screen,0
        jmp     editor_key
editor_end:
        mov     al,cs:editor_len
        mov     cs:editor_pos,al
        call    editor_refresh
        jmp     editor_key
editor_insert:
        xor     cs:editor_insert_mode,1
        jmp     editor_key

editor_word_left:
        cmp     cs:editor_pos,0
        je      editor_key
        xor     bx,bx
        mov     bl,cs:editor_pos
editor_word_left_spaces:
        or      bl,bl
        jz      editor_word_left_set
        cmp     byte ptr cs:[editor_buffer+bx-1],' '
        jne     editor_word_left_word
        dec     bl
        jmp     editor_word_left_spaces
editor_word_left_word:
        or      bl,bl
        jz      editor_word_left_set
        cmp     byte ptr cs:[editor_buffer+bx-1],' '
        je      editor_word_left_set
        dec     bl
        jmp     editor_word_left_word
editor_word_left_set:
        mov     cs:editor_pos,bl
        call    editor_refresh
        jmp     editor_key

editor_word_right:
        xor     bx,bx
        mov     bl,cs:editor_pos
editor_word_right_word:
        cmp     bl,cs:editor_len
        jae     editor_word_right_set
        cmp     byte ptr cs:[editor_buffer+bx],' '
        je      editor_word_right_spaces
        inc     bl
        jmp     editor_word_right_word
editor_word_right_spaces:
        cmp     bl,cs:editor_len
        jae     editor_word_right_set
        cmp     byte ptr cs:[editor_buffer+bx],' '
        jne     editor_word_right_set
        inc     bl
        jmp     editor_word_right_spaces
editor_word_right_set:
        mov     cs:editor_pos,bl
        call    editor_refresh
        jmp     editor_key

editor_ctrl_end:
        mov     al,cs:editor_pos
        mov     cs:editor_len,al
        call    editor_refresh
        jmp     editor_key

editor_ctrl_home:
        xor     bx,bx
        mov     bl,cs:editor_pos
        or      bl,bl
        jz      editor_key
        xor     cx,cx
        mov     cl,cs:editor_len
        sub     cl,bl
        mov     si,OFFSET editor_buffer
        add     si,bx
        mov     di,OFFSET editor_buffer
editor_ctrl_home_shift:
        jcxz    editor_ctrl_home_done
        mov     al,cs:[si]
        mov     cs:[di],al
        inc     si
        inc     di
        loop    editor_ctrl_home_shift
editor_ctrl_home_done:
        sub     cs:editor_len,bl
        mov     cs:editor_pos,0
        call    editor_refresh
        jmp     editor_key

editor_clear_history:
        mov     cs:history_count,0
        mov     cs:history_head,0
        mov     cs:history_nav,0ffh
        mov     cs:editor_len,0
        mov     cs:editor_pos,0
        call    editor_refresh
        jmp     editor_key

editor_up:
        cmp     cs:history_count,0
        je      editor_key
        mov     al,cs:history_nav
        cmp     al,0ffh
        jne     editor_up_existing
        mov     al,cs:history_count
        dec     al
        jmp     short editor_load_nav
editor_up_existing:
        or      al,al
        jz      editor_key
        dec     al
        jmp     short editor_load_nav
editor_down:
        mov     al,cs:history_nav
        cmp     al,0ffh
        je      editor_key
        inc     al
        cmp     al,cs:history_count
        jb      editor_load_nav
        mov     cs:history_nav,0ffh
        mov     cs:editor_len,0
        mov     cs:editor_pos,0
        jmp     editor_changed
editor_oldest:
        cmp     cs:history_count,0
        je      editor_key
        xor     al,al
        jmp     short editor_load_nav
editor_newest:
        cmp     cs:history_count,0
        je      editor_key
        mov     al,cs:history_count
        dec     al
editor_load_nav:
        mov     cs:history_nav,al
        call    editor_load_history
        mov     cs:f8_active,0
        jmp     editor_changed

editor_f8:
        cmp     cs:history_count,0
        je      editor_key
        cmp     cs:f8_active,0
        jne     editor_f8_next
        mov     al,cs:editor_len
        mov     cs:f8_prefix_len,al
        xor     bx,bx
        mov     bl,al
editor_f8_save_prefix:
        or      bl,bl
        jz      editor_f8_start
        dec     bl
        mov     al,cs:[editor_buffer+bx]
        mov     cs:[f8_prefix+bx],al
        jmp     editor_f8_save_prefix
editor_f8_start:
        mov     al,cs:history_count
        dec     al
        mov     cs:f8_candidate,al
        mov     cs:f8_active,1
        jmp     short editor_f8_search
editor_f8_next:
        cmp     cs:f8_candidate,0
        jne     editor_f8_previous
        mov     al,cs:history_count
        dec     al
        mov     cs:f8_candidate,al
        jmp     short editor_f8_search
editor_f8_previous:
        dec     cs:f8_candidate
editor_f8_search:
        mov     al,cs:f8_candidate
        call    history_slot_pointer
        xor     cx,cx
        mov     cl,cs:f8_prefix_len
        jcxz    editor_f8_match
        cmp     cs:[si],cl
        jb      editor_f8_miss
        inc     si
        xor     bx,bx
editor_f8_compare:
        mov     dl,cs:[si+bx]
        mov     dh,cs:[f8_prefix+bx]
        cmp     dl,'a'
        jb      editor_f8_fold_prefix
        cmp     dl,'z'
        ja      editor_f8_fold_prefix
        sub     dl,20h
editor_f8_fold_prefix:
        cmp     dh,'a'
        jb      editor_f8_compare_folded
        cmp     dh,'z'
        ja      editor_f8_compare_folded
        sub     dh,20h
editor_f8_compare_folded:
        cmp     dl,dh
        jne     editor_f8_miss
        inc     bx
        loop    editor_f8_compare
editor_f8_match:
        mov     al,cs:f8_candidate
        mov     cs:history_nav,al
        call    editor_load_history
        jmp     editor_changed
editor_f8_miss:
        cmp     cs:f8_candidate,0
        je      editor_key
        dec     cs:f8_candidate
        jmp     editor_f8_search

editor_f7:
        call    editor_newline
        xor     bl,bl
editor_f7_loop:
        cmp     bl,cs:history_count
        jae     editor_f7_done
        mov     al,bl
        inc     al
        call    editor_print_number
        mov     dl,':'
        call    editor_putc
        mov     dl,' '
        call    editor_putc
        mov     al,bl
        call    history_slot_pointer
        xor     cx,cx
        mov     cl,cs:[si]
        inc     si
editor_f7_text:
        jcxz    editor_f7_eol
        mov     dl,cs:[si]
        call    editor_putc
        inc     si
        loop    editor_f7_text
editor_f7_eol:
        call    editor_newline
        inc     bl
        jmp     editor_f7_loop
editor_f7_done:
        mov     cs:editor_drawn,0
        mov     cs:editor_screen,0
        call    editor_refresh
        jmp     editor_key

editor_f9:
        call    editor_newline
        mov     si,OFFSET line_number_prompt
editor_f9_prompt:
        mov     dl,cs:[si]
        inc     si
        or      dl,dl
        jz      editor_f9_read
        call    editor_putc
        jmp     editor_f9_prompt
editor_f9_read:
        xor     bx,bx
editor_f9_digit:
        xor     ah,ah
        int     16h
        cmp     al,0dh
        je      editor_f9_accept
        cmp     al,'0'
        jb      editor_f9_digit
        cmp     al,'9'
        ja      editor_f9_digit
        mov     dl,al
        call    editor_putc
        sub     al,'0'
        mov     ah,0
        push    ax
        mov     ax,bx
        mov     cx,10
        mul     cx
        mov     bx,ax
        pop     ax
        add     bx,ax
        jmp     editor_f9_digit
editor_f9_accept:
        call    editor_newline
        or      bx,bx
        jz      editor_f7_done
        dec     bx
        cmp     bl,cs:history_count
        jae     editor_f7_done
        mov     al,bl
        jmp     editor_load_nav

editor_enter:
        call    editor_newline
        xor     cx,cx
        mov     cl,cs:editor_len
        mov     ds:[bp+1],cl
        lea     di,[bp+2]
        mov     si,OFFSET editor_buffer
editor_return_copy:
        jcxz    editor_return_cr
        mov     al,cs:[si]
        mov     ds:[di],al
        inc     si
        inc     di
        loop    editor_return_copy
editor_return_cr:
        mov     byte ptr ds:[di],0dh
        ret

; AL is a zero-based chronological history number; returns CS:SI at slot.
history_slot_pointer:
        push    ax
        push    bx
        mov     bl,al
        call    resident_max_slots
        mov     dl,al
        mov     al,cs:history_head
        sub     al,cs:history_count
        jnc     history_oldest_ready
        add     al,dl
history_oldest_ready:
        add     al,bl
        cmp     al,dl
        jb      history_slot_ready
        sub     al,dl
history_slot_ready:
        xor     ah,ah
        mov     si,ax
        mov     cl,7
        shl     si,cl
        add     si,OFFSET history_data
        pop     bx
        pop     ax
        ret

editor_load_history:
        call    history_slot_pointer
        xor     cx,cx
        mov     cl,cs:[si]
        mov     al,ds:[bp]
        dec     al
        cmp     cl,al
        jbe     editor_history_fits
        mov     cl,al
editor_history_fits:
        mov     cs:editor_len,cl
        mov     cs:editor_pos,cl
        inc     si
        mov     di,OFFSET editor_buffer
editor_history_copy:
        jcxz    editor_history_done
        mov     al,cs:[si]
        mov     cs:[di],al
        inc     si
        inc     di
        loop    editor_history_copy
editor_history_done:
        ret

editor_refresh:
        xor     cx,cx
        mov     cl,cs:editor_screen
editor_refresh_back:
        jcxz    editor_refresh_text
        mov     dl,08h
        call    editor_putc
        loop    editor_refresh_back
editor_refresh_text:
        xor     cx,cx
        mov     cl,cs:editor_len
        mov     si,OFFSET editor_buffer
editor_refresh_emit:
        jcxz    editor_refresh_erase
        mov     dl,cs:[si]
        call    editor_putc
        inc     si
        loop    editor_refresh_emit
editor_refresh_erase:
        xor     cx,cx
        mov     cl,cs:editor_drawn
        cmp     cl,cs:editor_len
        jbe     editor_refresh_rewind
        sub     cl,cs:editor_len
editor_refresh_spaces:
        mov     dl,' '
        call    editor_putc
        loop    editor_refresh_spaces
editor_refresh_rewind:
        xor     cx,cx
        mov     cl,cs:editor_drawn
        cmp     cl,cs:editor_len
        jae     editor_refresh_have_max
        mov     cl,cs:editor_len
editor_refresh_have_max:
        jcxz    editor_refresh_forward
editor_refresh_rewind_loop:
        mov     dl,08h
        call    editor_putc
        loop    editor_refresh_rewind_loop
editor_refresh_forward:
        xor     cx,cx
        mov     cl,cs:editor_pos
        mov     si,OFFSET editor_buffer
editor_refresh_forward_loop:
        jcxz    editor_refresh_done
        mov     dl,cs:[si]
        call    editor_putc
        inc     si
        loop    editor_refresh_forward_loop
editor_refresh_done:
        mov     al,cs:editor_len
        mov     cs:editor_drawn,al
        mov     al,cs:editor_pos
        mov     cs:editor_screen,al
        ret

editor_print_number:
        aam
        or      ah,ah
        jz      editor_print_ones
        mov     dl,ah
        add     dl,'0'
        call    editor_putc
editor_print_ones:
        mov     dl,al
        add     dl,'0'
        call    editor_putc
        ret

editor_newline:
        mov     dl,0dh
        call    editor_putc
        mov     dl,0ah
editor_putc:
        push    ax
        push    bx
        mov     ah,02h
        int     21h
        pop     bx
        pop     ax
        ret

preload_template:
        cmp     cs:history_count,0
        je      no_template
        call    resident_max_slots
        mov     cs:resident_max,al
        xor     ax,ax
        mov     al,cs:history_head
        or      al,al
        jnz     template_index
        mov     al,cs:resident_max
template_index:
        dec     ax
        mov     si,ax
        mov     cl,7
        shl     si,cl
        add     si,OFFSET history_data
        xor     cx,cx
        mov     cl,cs:[si]
        cmp     cl,ds:[bp]
        jb      template_fits
        mov     cl,ds:[bp]
        dec     cl
template_fits:
        mov     ds:[bp+1],cl
        inc     si
        lea     di,[bp+2]
        push    ds
        push    cs
        pop     ds
        pop     es
        rep     movsb
        mov     al,0dh
        stosb
        push    es
        pop     ds
        ret
no_template:
        mov     byte ptr ds:[bp+1],0
        ret

remember_line:
        xor     cx,cx
        mov     cl,ds:[bp+1]
        jcxz    remember_done
        cmp     cl,HISTORY_WIDTH-2
        jbe     remember_length_ok
        mov     cl,HISTORY_WIDTH-2
remember_length_ok:
        xor     ax,ax
        mov     al,cs:history_head
        mov     di,ax
        mov     bl,7
        mov     cl,bl
        shl     di,cl
        add     di,OFFSET history_data
        xor     cx,cx
        mov     cl,ds:[bp+1]
        cmp     cl,HISTORY_WIDTH-2
        jbe     remember_copy_len
        mov     cl,HISTORY_WIDTH-2
remember_copy_len:
        push    cx
        mov     ax,cx
        mov     cs:[di],al
        inc     di
        lea     si,[bp+2]
        push    es
        push    cs
        pop     es
        rep     movsb
        pop     es
        pop     cx
        inc     cs:history_head
        call    resident_max_slots
        cmp     cs:history_head,al
        jb      remember_count
        mov     cs:history_head,0
remember_count:
        cmp     cs:history_count,al
        jae     remember_done
        inc     cs:history_count
remember_done:
        ret

resident_max_slots:
        mov     ax,cs:history_limit
        mov     cl,7
        shr     ax,cl
        or      al,al
        jnz     max_slots_nonzero
        mov     al,1
max_slots_nonzero:
        cmp     al,HISTORY_SLOTS
        jbe     max_slots_done
        mov     al,HISTORY_SLOTS
max_slots_done:
        ret

; Expand a matching macro into pending_buffer, then return its first line.
expand_macro:
        mov     si,bp
        add     si,2
        cmp     byte ptr ds:[si],' '
        je      expand_done               ; leading space bypasses macros
        mov     di,si
find_word_end:
        mov     al,ds:[di]
        cmp     al,' '
        je      have_word
        cmp     al,0dh
        je      have_word
        inc     di
        jmp     short find_word_end
have_word:
        mov     cs:macro_name_end,di
        mov     cs:argument_off,di
        cmp     byte ptr ds:[di],' '
        jne     argument_ready
        inc     cs:argument_off
argument_ready:
        mov     bx,OFFSET macro_names
        xor     dx,dx
macro_search:
        cmp     dx,MACRO_SLOTS
        jae     expand_done
        cmp     byte ptr cs:[bx],0
        je      macro_next
        push    si
        push    di
        push    bx
macro_name_cmp:
        cmp     si,cs:macro_name_end
        jae     macro_input_end
        mov     al,ds:[si]
        call    upper_al
        cmp     al,cs:[bx]
        jne     macro_no_match
        inc     si
        inc     bx
        jmp     short macro_name_cmp
macro_input_end:
        cmp     byte ptr cs:[bx],0
        jne     macro_no_match
        pop     bx
        pop     di
        pop     si
        jmp     short macro_found
macro_no_match:
        pop     bx
        pop     di
        pop     si
macro_next:
        add     bx,MACRO_NAME_SIZE
        inc     dx
        jmp     short macro_search

macro_found:
        mov     ax,dx
        mov     cl,7
        shl     ax,cl
        add     ax,OFFSET macro_bodies
        mov     si,ax
        mov     di,OFFSET pending_buffer
        mov     cs:pending_length,0
macro_expand_loop:
        mov     al,cs:[si]
        inc     si
        or      al,al
        jz      macro_expanded
        cmp     al,'$'
        jne     macro_put
        mov     al,cs:[si]
        inc     si
        call    upper_al
        cmp     al,'$'
        je      macro_dollar
        cmp     al,'G'
        je      macro_greater
        cmp     al,'L'
        je      macro_less
        cmp     al,'B'
        je      macro_pipe
        cmp     al,'T'
        je      macro_separator
        cmp     al,'*'
        je      macro_all_args
        cmp     al,'1'
        jb      macro_literal_pair
        cmp     al,'9'
        ja      macro_literal_pair
        sub     al,'0'
        call    copy_argument_number
        jmp     short macro_expand_loop
macro_literal_pair:
        mov     ah,al
        mov     al,'$'
        call    pending_put
        mov     al,ah
        jmp     short macro_put
macro_dollar:
        mov     al,'$'
        jmp     short macro_put
macro_greater:
        mov     al,'>'
        jmp     short macro_put
macro_less:
        mov     al,'<'
        jmp     short macro_put
macro_pipe:
        mov     al,'|'
        jmp     short macro_put
macro_separator:
        mov     al,0dh
        jmp     short macro_put
macro_all_args:
        mov     bx,cs:argument_off
macro_all_loop:
        mov     al,ds:[bx]
        cmp     al,0dh
        je      macro_expand_loop
        inc     bx
        call    pending_put
        jmp     short macro_all_loop
macro_put:
        call    pending_put
        jmp     macro_expand_loop
macro_expanded:
        mov     al,0dh
        call    pending_put
        mov     cs:pending_pos,1
        call    emit_pending_line
expand_done:
        ret

; AL is the 1-based argument number.
copy_argument_number:
        push    si
        push    bx
        push    dx
        mov     dl,al
        mov     bx,cs:argument_off
arg_skip_spaces:
        cmp     byte ptr ds:[bx],' '
        jne     arg_at_token
        inc     bx
        jmp     short arg_skip_spaces
arg_at_token:
        cmp     byte ptr ds:[bx],0dh
        je      arg_copy_done
        dec     dl
        jz      arg_copy
arg_skip_token:
        mov     al,ds:[bx]
        cmp     al,' '
        je      arg_skip_spaces
        cmp     al,0dh
        je      arg_copy_done
        inc     bx
        jmp     short arg_skip_token
arg_copy:
        mov     al,ds:[bx]
        cmp     al,' '
        je      arg_copy_done
        cmp     al,0dh
        je      arg_copy_done
        inc     bx
        call    pending_put
        jmp     short arg_copy
arg_copy_done:
        pop     dx
        pop     bx
        pop     si
        ret

pending_put:
        cmp     cs:pending_length,254
        jae     pending_full
        mov     cs:[di],al
        inc     di
        inc     cs:pending_length
pending_full:
        ret

emit_pending_line:
        push    ds
        push    cs
        pop     ds
        xor     si,si
        mov     si,cs:pending_pos
        dec     si
        add     si,OFFSET pending_buffer
        xor     cx,cx
emit_count:
        cmp     si,OFFSET pending_buffer+255
        jae     emit_have_count
        cmp     byte ptr cs:[si],0dh
        je      emit_have_count
        inc     si
        inc     cx
        jmp     short emit_count
emit_have_count:
        pop     ds
        mov     al,ds:[bp]
        dec     al
        xor     ah,ah
        cmp     cx,ax
        jbe     emit_fits
        mov     cx,ax
emit_fits:
        mov     ds:[bp+1],cl
        push    ds
        pop     es
        lea     di,[bp+2]
        push    ds
        push    cs
        pop     ds
        mov     si,cs:pending_pos
        dec     si
        add     si,OFFSET pending_buffer
        rep     movsb
        mov     al,0dh
        stosb
        mov     ax,si
        sub     ax,OFFSET pending_buffer
        inc     ax                      ; next byte after the separator
        cmp     ax,cs:pending_length
        jae     emit_no_more
        inc     ax                      ; encode offset as offset+1
        jmp     short emit_more
emit_no_more:
        xor     ax,ax
emit_more:
        mov     cs:pending_pos,ax
        pop     ds
        ret

upper_al:
        cmp     al,'a'
        jb      upper_done
        cmp     al,'z'
        ja      upper_done
        sub     al,20h
upper_done:
        ret

; ---------------------------------------------------------------------------
; Transient command parser and resident-state editor
; ---------------------------------------------------------------------------
process_args:
        mov     cs:exit_code,0
        call    trim_command_tail
        cmp     byte ptr cs:[command_tail],0
        je      args_done
        mov     si,OFFSET command_tail
        cmp     byte ptr [si],'/'
        jne     define_macro
        call    option_help
        jc      show_help
        call    option_reinstall
        jc      do_reinstall
        call    option_macros
        jc      do_list_macros
        call    option_history
        jc      do_list_history
        call    option_insert
        jc      do_insert
        call    option_overstrike
        jc      do_overstrike
        call    option_bufsize
        jc      do_bufsize
        jmp     syntax_error
args_done:
        ret
show_help:
        mov     cs:no_install,1
        mov     dx,OFFSET help_msg
        call    print_dollar
        ret
do_reinstall:
        mov     es,cs:resident_seg
        call    clear_state
        mov     dx,OFFSET reinstalled_msg
        call    print_dollar
        ret
do_insert:
        mov     es,cs:resident_seg
        mov     byte ptr es:default_insert,1
        ret
do_overstrike:
        mov     es,cs:resident_seg
        mov     byte ptr es:default_insert,0
        ret
do_bufsize:
        call    parse_bufsize_value
        jc      syntax_error
        mov     es,cs:resident_seg
        mov     es:history_limit,ax
        mov     byte ptr es:history_count,0
        mov     byte ptr es:history_head,0
        ret
do_list_macros:
        call    list_macros
        ret
do_list_history:
        call    list_history
        ret

define_macro:
        mov     di,si
find_equals:
        mov     al,[di]
        or      al,al
        jz      syntax_error
        cmp     al,'='
        je      have_equals
        cmp     al,' '
        je      syntax_error
        inc     di
        jmp     short find_equals
have_equals:
        mov     byte ptr [di],0
        inc     di
        call    set_macro
        jc      macro_error
        ret

syntax_error:
        mov     dx,OFFSET syntax_msg
        jmp     short command_error
macro_error:
        mov     dx,OFFSET macro_full_msg
command_error:
        call    print_dollar
        mov     cs:exit_code,1
        ret

clear_state:
        push    ax
        push    cx
        push    di
        mov     di,OFFSET state_start
        mov     cx,state_end-state_start
        xor     al,al
        rep     stosb
        mov     word ptr es:history_limit,512
        pop     di
        pop     cx
        pop     ax
        ret

set_macro:
        ; DS:SI name, DS:DI body, ES resident.
        push    di
        mov     bx,OFFSET macro_names
        xor     dx,dx
set_find_slot:
        cmp     dx,MACRO_SLOTS
        jae     set_no_slot
        cmp     byte ptr es:[bx],0
        je      set_empty_slot
        push    si
        push    bx
set_name_cmp:
        mov     al,[si]
        call    upper_al
        cmp     al,es:[bx]
        jne     set_name_diff
        inc     si
        inc     bx
        or      al,al
        jne     set_name_cmp
        pop     bx
        pop     si
        jmp     short set_slot_found
set_name_diff:
        pop     bx
        pop     si
set_next_slot:
        add     bx,MACRO_NAME_SIZE
        inc     dx
        jmp     short set_find_slot
set_empty_slot:
        cmp     byte ptr [di],0
        je      set_success               ; deleting absent macro
set_slot_found:
        cmp     byte ptr [di],0
        jne     set_copy
        mov     byte ptr es:[bx],0
        jmp     short set_success
set_copy:
        push    di
        mov     cx,MACRO_NAME_SIZE-1
set_copy_name:
        lodsb
        call    upper_al
        mov     es:[bx],al
        inc     bx
        or      al,al
        jz      set_name_done
        loop    set_copy_name
        mov     byte ptr es:[bx],0
set_name_done:
        pop     si                       ; body pointer
        mov     ax,dx
        mov     cl,7
        shl     ax,cl
        add     ax,OFFSET macro_bodies
        mov     bx,ax
        mov     cx,MACRO_BODY_SIZE-1
set_copy_body:
        lodsb
        mov     es:[bx],al
        inc     bx
        or      al,al
        jz      set_success
        loop    set_copy_body
        mov     byte ptr es:[bx],0
set_success:
        pop     di
        clc
        ret
set_no_slot:
        pop     di
        stc
        ret

list_macros:
        mov     es,cs:resident_seg
        mov     bx,OFFSET macro_names
        xor     bp,bp
list_macro_next:
        cmp     bp,MACRO_SLOTS
        jae     list_done
        cmp     byte ptr es:[bx],0
        je      list_macro_skip
        mov     si,bx
        call    print_es_string
        mov     dl,'='
        call    put_char
        mov     ax,bp
        mov     cl,7
        shl     ax,cl
        add     ax,OFFSET macro_bodies
        mov     si,ax
        call    print_es_string
        call    print_crlf
list_macro_skip:
        add     bx,MACRO_NAME_SIZE
        inc     bp
        jmp     short list_macro_next

list_history:
        mov     es,cs:resident_seg
        mov     ax,es:history_limit
        mov     cl,7
        shr     ax,cl
        or      al,al
        jnz     list_max_nonzero
        mov     al,1
list_max_nonzero:
        cmp     al,HISTORY_SLOTS
        jbe     list_max_ready
        mov     al,HISTORY_SLOTS
list_max_ready:
        mov     cs:list_max_slots,al
        xor     bx,bx
        mov     bl,es:history_count
        or      bx,bx
        jz      list_done
        xor     ax,ax
        mov     al,es:history_head
        sub     ax,bx
        jnc     history_start_ok
        xor     dx,dx
        mov     dl,cs:list_max_slots
        add     ax,dx
history_start_ok:
        mov     bp,bx
history_next:
        mov     si,ax
        mov     cl,7
        shl     si,cl
        add     si,OFFSET history_data+1
        push    ax
        call    print_es_string_len
        call    print_crlf
        pop     ax
        inc     ax
        xor     dx,dx
        mov     dl,cs:list_max_slots
        cmp     ax,dx
        jb      history_index_ok
        xor     ax,ax
history_index_ok:
        dec     bp
        jnz     history_next
list_done:
        ret

print_es_string_len:
        mov     cl,es:[si-1]
        xor     ch,ch
print_es_len_loop:
        jcxz    print_es_done
        mov     dl,es:[si]
        call    put_char
        inc     si
        loop    print_es_len_loop
print_es_done:
        ret
print_es_string:
        mov     dl,es:[si]
        or      dl,dl
        jz      print_es_done
        call    put_char
        inc     si
        jmp     short print_es_string

trim_command_tail:
        push    es
        push    cs
        pop     es
        xor     ax,ax
        mov     al,byte ptr ds:[80h]
        mov     si,81h
        mov     di,OFFSET command_tail
trim_leading:
        or      ax,ax
        jz      trim_done
        cmp     byte ptr [si],' '
        jne     trim_copy
        inc     si
        dec     ax
        jmp     short trim_leading
trim_copy:
        cmp     ax,126
        jbe     trim_count_ok
        mov     ax,126
trim_count_ok:
        mov     cx,ax
        rep     movsb
        mov     byte ptr [di],0
trim_trailing:
        cmp     di,OFFSET command_tail
        jbe     trim_done
        cmp     byte ptr [di-1],' '
        jne     trim_done
        dec     di
        mov     byte ptr [di],0
        jmp     short trim_trailing
trim_done:
        mov     byte ptr [di],0
        pop     es
        ret

option_help:
        mov     di,OFFSET opt_help
        jmp     short option_compare
option_reinstall:
        mov     di,OFFSET opt_reinstall
        jmp     short option_compare
option_macros:
        mov     di,OFFSET opt_macros
        jmp     short option_compare
option_history:
        mov     di,OFFSET opt_history
        jmp     short option_compare
option_insert:
        mov     di,OFFSET opt_insert
        jmp     short option_compare
option_overstrike:
        mov     di,OFFSET opt_overstrike
option_compare:
        push    si
option_loop:
        mov     al,[si]
        call    upper_al
        cmp     al,[di]
        jne     option_no
        inc     si
        inc     di
        or      al,al
        jne     option_loop
        pop     si
        stc
        ret
option_no:
        pop     si
        clc
        ret

option_bufsize:
        push    si
        mov     di,OFFSET opt_bufsize
buf_opt_loop:
        mov     al,[si]
        call    upper_al
        cmp     al,[di]
        jne     buf_opt_no
        inc     si
        inc     di
        cmp     byte ptr [di],0
        jne     buf_opt_loop
        mov     cs:number_arg,si
        pop     si
        stc
        ret
buf_opt_no:
        pop     si
        clc
        ret

parse_bufsize_value:
        mov     si,cs:number_arg
        xor     ax,ax
        xor     cx,cx
buf_digit:
        mov     dl,[si]
        or      dl,dl
        jz      buf_value_done
        cmp     dl,'0'
        jb      buf_bad
        cmp     dl,'9'
        ja      buf_bad
        sub     dl,'0'
        xor     dh,dh
        push    dx
        mov     bx,10
        mul     bx
        pop     bx
        or      dx,dx
        jnz     buf_bad
        add     ax,bx
        jc      buf_bad
        inc     si
        inc     cx
        jmp     short buf_digit
buf_value_done:
        jcxz    buf_bad
        cmp     ax,128
        jb      buf_bad
        cmp     ax,HISTORY_SLOTS*HISTORY_WIDTH
        ja      buf_bad
        clc
        ret
buf_bad:
        stc
        ret

put_char:
        mov     ah,02h
        int     21h
        ret
print_crlf:
        mov     dx,OFFSET crlf
print_dollar:
        mov     ah,09h
        int     21h
        ret

resident_seg    dw 0
number_arg      dw 0
exit_code       db 0
no_install      db 0
list_max_slots  db 0
command_tail    db 128 dup(0)
opt_help        db '/?',0
opt_reinstall   db '/REINSTALL',0
opt_macros      db '/MACROS',0
opt_history     db '/HISTORY',0
opt_insert      db '/INSERT',0
opt_overstrike  db '/OVERSTRIKE',0
opt_bufsize     db '/BUFSIZE:',0
crlf            db 13,10,'$'
installed_msg   db 'DOSKEY installed.',13,10,'$'
reinstalled_msg db 'DOSKEY reinstalled; history and macros cleared.',13,10,'$'
syntax_msg      db 'Invalid syntax. Use DOSKEY /? for help.',13,10,'$'
macro_full_msg  db 'Macro table is full.',13,10,'$'
help_msg        db 'DOSKEY [/REINSTALL] [/BUFSIZE:size] [/MACROS] [/HISTORY]',13,10
                db '       [/INSERT | /OVERSTRIKE] [macroname=[text]]',13,10,'$'

; Everything below remains resident and is also accessed at the same offsets
; by later DOSKEY invocations after AX=4800h returns ES.
old_2f_off      dw 0
old_2f_seg      dw 0
caller_ds       dw 0
service_result  db 0
argument_off    dw 0
macro_name_end  dw 0
state_start LABEL BYTE
history_count   db 0
history_head    db 0
history_limit   dw 512
default_insert  db 0
resident_max    db 0
pending_pos     dw 0
pending_length  dw 0
editor_len      db 0
editor_pos      db 0
editor_drawn    db 0
editor_screen   db 0
editor_insert_mode db 0
history_nav     db 0ffh
f8_active       db 0
f8_prefix_len   db 0
f8_candidate    db 0
line_number_prompt db 'Line number: ',0
editor_buffer   db HISTORY_WIDTH dup(0)
f8_prefix       db HISTORY_WIDTH dup(0)
history_data    db HISTORY_SLOTS*HISTORY_WIDTH dup(0)
macro_names     db MACRO_SLOTS*MACRO_NAME_SIZE dup(0)
macro_bodies    db MACRO_SLOTS*MACRO_BODY_SIZE dup(0)
pending_buffer  db 256 dup(0)
state_end LABEL BYTE
resident_end LABEL BYTE

CODE ENDS
        END start
