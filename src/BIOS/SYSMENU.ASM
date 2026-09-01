bits 16
cpu 286
org 0

%define CR 13
%define LF 10
%define TAB 9
%define MAX_ITEMS 9
%define NAME_SIZE 71

; Transient CONFIG.SYS menu preprocessor.
; AX=raw segment, BX=output segment, CX=input size, DX=SYSINIT segment,
; SI=ConfigEnv offset, DI=ConfigEnvUsed offset. Returns output size in AX.
entry:
    mov [cs:raw_seg], ax
    mov [cs:out_seg], bx
    mov [cs:input_count], cx
    mov [cs:sys_seg], dx
    mov [cs:env_off], si
    mov [cs:env_used_off], di
    sub ax, bx
    mov cl, 4
    shl ax, cl
    jnc .limit_ready
    mov ax, 0fffeh
.limit_ready:
    mov [cs:out_limit], ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov ax, [cs:raw_seg]
    mov ds, ax
    call choose_root_menu
    cmp byte [cs:menu_present], 0
    je .copy_all
    call flatten_config
    call set_config_environment
    jmp short .done
.copy_all:
    mov ax, [cs:out_seg]
    mov es, ax
    xor si, si
    xor di, di
    mov cx, [cs:input_count]
    cld
    rep movsb
    mov [cs:out_pos], di
.done:
    mov ax, [cs:out_pos]
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    retf

; Read one raw line and publish its untrimmed/trimmed bounds.
get_line:
    mov si, [cs:scan_pos]
    cmp si, [cs:input_count]
    jae .eof
    mov [cs:line_start], si
    mov bx, si
.find_end:
    cmp bx, [cs:input_count]
    jae .at_end
    cmp byte [bx], LF
    je .have_lf
    inc bx
    jmp short .find_end
.have_lf:
    lea ax, [bx+1]
    mov [cs:next_line], ax
    jmp short .strip_cr
.at_end:
    mov [cs:next_line], bx
.strip_cr:
    mov dx, bx
    cmp dx, si
    jbe .trim
    cmp byte [bx-1], CR
    jne .trim
    dec dx
.trim:
    mov bx, si
.trim_loop:
    cmp bx, dx
    jae .ready
    cmp byte [bx], ' '
    je .trim_one
    cmp byte [bx], TAB
    jne .ready
.trim_one:
    inc bx
    jmp short .trim_loop
.ready:
    mov [cs:trim_start], bx
    mov [cs:line_end], dx
    mov ax, [cs:next_line]
    mov [cs:scan_pos], ax
    clc
    ret
.eof:
    stc
    ret

; Case-insensitive DS:SI prefix match against CS:DI ASCIIZ literal.
match_literal:
    push ax
.loop:
    mov al, [cs:di]
    or al, al
    jz .yes
    mov ah, [si]
    cmp ah, 'a'
    jb .compare
    cmp ah, 'z'
    ja .compare
    sub ah, 20h
.compare:
    cmp ah, al
    jne .no
    inc si
    inc di
    jmp short .loop
.yes:
    pop ax
    clc
    ret
.no:
    pop ax
    stc
    ret

; Case-insensitive equality of DS:SI bracketed section and CS:DI name.
section_equals:
    cmp byte [si], '['
    jne .no
    inc si
.loop:
    mov al, [cs:di]
    or al, al
    jz .end_name
    mov ah, [si]
    cmp ah, 'a'
    jb .raw_ready
    cmp ah, 'z'
    ja .raw_ready
    sub ah, 20h
.raw_ready:
    mov bl, al
    cmp bl, 'a'
    jb .compare
    cmp bl, 'z'
    ja .compare
    sub bl, 20h
.compare:
    cmp ah, bl
    jne .no
    inc si
    inc di
    jmp short .loop
.end_name:
    cmp byte [si], ']'
    jne .no
    clc
    ret
.no:
    stc
    ret

skip_assignment:
.again:
    cmp si, [cs:line_end]
    jae .done
    mov al, [si]
    cmp al, ' '
    je .one
    cmp al, TAB
    je .one
    cmp al, '='
    jne .done
.one:
    inc si
    jmp short .again
.done:
    ret

; Copy name after a directive to CS:DI. Returns byte length in AX.
copy_name:
    call skip_assignment
    xor cx, cx
.loop:
    cmp si, [cs:line_end]
    jae .done
    mov al, [si]
    cmp al, ','
    je .done
    cmp al, ' '
    je .done
    cmp al, TAB
    je .done
    cmp cx, NAME_SIZE-1
    jae .done
    mov [cs:di], al
    inc si
    inc di
    inc cx
    jmp short .loop
.done:
    mov byte [cs:di], 0
    mov ax, cx
    ret

; Return carry clear when the section named by CS:probe_name exists. Preserve
; the caller's line scanner so this validation is invisible to menu parsing.
named_section_exists:
    push word [cs:scan_pos]
    push word [cs:line_start]
    push word [cs:trim_start]
    push word [cs:line_end]
    push word [cs:next_line]
    mov word [cs:scan_pos], 0
.scan:
    call get_line
    jc .missing
    mov si, [cs:trim_start]
    cmp si, [cs:line_end]
    jae .scan
    mov di, probe_name
    call section_equals
    jc .scan
    mov byte [cs:section_probe_found], 1
    jmp short .restore
.missing:
    mov byte [cs:section_probe_found], 0
.restore:
    pop word [cs:next_line]
    pop word [cs:line_end]
    pop word [cs:trim_start]
    pop word [cs:line_start]
    pop word [cs:scan_pos]
    cmp byte [cs:section_probe_found], 1
    je .found
    stc
    ret
.found:
    clc
    ret

print_label:
    push ax
    push dx
.loop:
    cmp si, [cs:line_end]
    jae .newline
    mov dl, [si]
    mov ah, 2
    int 21h
    inc si
    jmp short .loop
.newline:
    mov dl, CR
    mov ah, 2
    int 21h
    mov dl, LF
    int 21h
    pop dx
    pop ax
    ret

; BL=0 MENUITEM, BL=1 SUBMENU; SI follows keyword.
add_menu_entry:
    cmp byte [cs:item_count], MAX_ITEMS
    jae .done
    mov [cs:new_type], bl
    xor ax, ax
    mov al, [cs:item_count]
    mov cx, NAME_SIZE
    mul cx
    mov di, entries
    add di, ax
    call copy_name
    or ax, ax
    jz .done
    mov [cs:new_length], al
    mov al, [cs:item_count]
    xor ah, ah
    mov di, entry_lengths
    add di, ax
    mov bl, [cs:new_length]
    mov [cs:di], bl
    mov di, entry_types
    add di, ax
    mov bl, [cs:new_type]
    mov [cs:di], bl
    inc byte [cs:item_count]
.seek_comma:
    cmp si, [cs:line_end]
    jae .use_name
    cmp byte [si], ','
    je .after_comma
    inc si
    jmp short .seek_comma
.after_comma:
    inc si
.skip_space:
    cmp si, [cs:line_end]
    jae .use_name
    cmp byte [si], ' '
    je .one
    cmp byte [si], TAB
    jne .store_raw_label
.one:
    inc si
    jmp short .skip_space
.use_name:
    mov al, [cs:item_count]
    dec al
    xor ah, ah
    mov cx, NAME_SIZE
    mul cx
    mov si, entries
    add si, ax
    mov di, entry_labels
    add di, ax
    mov cx, NAME_SIZE-1
.copy_name_label:
    mov al, [cs:si]
    mov [cs:di], al
    inc si
    inc di
    or al, al
    jz .done
    loop .copy_name_label
    mov byte [cs:di], 0
    jmp short .done
.store_raw_label:
    push si
    mov al, [cs:item_count]
    dec al
    xor ah, ah
    mov cx, NAME_SIZE
    mul cx
    mov di, entry_labels
    add di, ax
    mov cx, NAME_SIZE-1
.copy_raw_label:
    cmp si, [cs:line_end]
    jae .raw_label_done
    mov al, [si]
    mov [cs:di], al
    inc si
    inc di
    loop .copy_raw_label
.raw_label_done:
    mov byte [cs:di], 0
    pop si
.done:
    ret

display_menu_entries:
    mov si, menu_heading
    call print_cs_string
    xor bx, bx
.entry:
    cmp bl, [cs:item_count]
    jae .done
    mov dl, bl
    inc dl
    add dl, '0'
    mov ah, 2
    int 21h
    mov dl, '.'
    int 21h
    mov dl, ' '
    int 21h
    mov ax, bx
    mov cx, NAME_SIZE
    mul cx
    mov si, entry_labels
    add si, ax
.label:
    mov dl, [cs:si]
    or dl, dl
    jz .newline
    mov ah, 2
    int 21h
    inc si
    jmp short .label
.newline:
    mov dl, CR
    mov ah, 2
    int 21h
    mov dl, LF
    int 21h
    inc bx
    jmp short .entry
.done:
    mov si, menu_prompt
    call print_cs_string
    call resolve_default
    mov dl, [cs:default_index]
    add dl, '0'
    mov ah, 2
    int 21h
    ret

print_cs_string:
    mov dl, [cs:si]
    or dl, dl
    jz .done
    mov ah, 2
    int 21h
    inc si
    jmp short print_cs_string
.done:
    ret

parse_decimal:
    call skip_assignment
    xor ax, ax
.loop:
    cmp si, [cs:line_end]
    jae .done
    mov cl, [si]
    cmp cl, '0'
    jb .done
    cmp cl, '9'
    ja .done
    sub cl, '0'
    xor ch, ch
    mov bp, cx
    mov bx, 10
    mul bx
    add ax, bp
    inc si
    jmp short .loop
.done:
    ret

take_default:
    mov di, default_name
    call copy_name
    mov [cs:default_length], al
.comma:
    cmp si, [cs:line_end]
    jae .done
    cmp byte [si], ','
    je .seconds
    inc si
    jmp short .comma
.seconds:
    inc si
    mov byte [cs:timeout_present], 1
    call parse_decimal
    cmp ax, 90
    jbe .store
    mov ax, 90
.store:
    mov [cs:timeout_seconds], al
.done:
    ret

take_color:
    mov byte [cs:menu_foreground], 7
    mov byte [cs:menu_background], 0
    call parse_decimal
    cmp ax, 15
    ja .find_comma
    mov [cs:menu_foreground], al
.find_comma:
    cmp si, [cs:line_end]
    jae .done
    cmp byte [si], ','
    je .background
    inc si
    jmp short .find_comma
.background:
    inc si
    call parse_decimal
    cmp ax, 15
    ja .done
    mov [cs:menu_background], al
.done:
    ret

apply_menu_color:
    mov bh, [cs:menu_background]
    mov cl, 4
    shl bh, cl
    or bh, [cs:menu_foreground]
    mov ax, 0600h
    xor cx, cx
    mov dx, 184fh
    int 10h
    mov ax, 0200h
    xor bx, bx
    xor dx, dx
    int 10h
    ret

entry_is_default:
    push si
    push di
    mov si, default_name
.loop:
    mov al, [cs:si]
    mov ah, [cs:di]
    cmp al, 'a'
    jb .left_ready
    cmp al, 'z'
    ja .left_ready
    sub al, 20h
.left_ready:
    cmp ah, 'a'
    jb .right_ready
    cmp ah, 'z'
    ja .right_ready
    sub ah, 20h
.right_ready:
    cmp al, ah
    jne .no
    or al, al
    jz .yes
    inc si
    inc di
    jmp short .loop
.yes:
    pop di
    pop si
    clc
    ret
.no:
    pop di
    pop si
    stc
    ret

resolve_default:
    mov byte [cs:default_index], 1
    cmp byte [cs:default_length], 0
    je .done
    xor bx, bx
.loop:
    cmp bl, [cs:item_count]
    jae .done
    mov ax, bx
    mov cx, NAME_SIZE
    mul cx
    mov di, entries
    add di, ax
    call entry_is_default
    jnc .found
    inc bx
    jmp short .loop
.found:
    inc bl
    mov [cs:default_index], bl
.done:
    ret

read_menu_choice:
    call resolve_default
    mov ah, 0
    int 1ah
    mov [cs:start_tick], dx
.poll:
    mov ah, 1
    int 16h
    jnz .read
    cmp byte [cs:timeout_seconds], 0
    je .poll
    mov ah, 0
    int 1ah
    mov cx, dx
    sub cx, [cs:start_tick]
    xor ax, ax
    mov al, [cs:timeout_seconds]
    mov bx, 18
    mul bx
    cmp cx, ax
    jb .poll
    mov al, [cs:default_index]
    ret
.read:
    mov ah, 0
    int 16h
    cmp al, CR
    je .default
    sub al, '0'
    jb .invalid
    cmp al, 1
    jb .invalid
    cmp al, [cs:item_count]
    jbe .done
.invalid:
    mov ah, 0eh
    mov al, 7
    int 10h
    jmp short .poll
.default:
    mov al, [cs:default_index]
.done:
    ret

choose_root_menu:
    mov byte [cs:menu_present], 0
    push ds
    push es
    push cs
    pop ds
    push cs
    pop es
    mov si, root_menu
    mov di, menu_name
    mov cx, 5
    rep movsb
    pop es
    pop ds
.submenu:
    mov byte [cs:item_count], 0
    mov byte [cs:default_length], 0
    mov byte [cs:timeout_seconds], 0
    mov byte [cs:timeout_present], 0
    mov byte [cs:menu_foreground], 7
    mov byte [cs:menu_background], 0
    mov byte [cs:in_menu], 0
    mov word [cs:scan_pos], 0
.line:
    call get_line
    jc .scanned
    mov si, [cs:trim_start]
    cmp si, [cs:line_end]
    jae .line
    cmp byte [si], '['
    jne .directive
    mov di, menu_name
    call section_equals
    jc .other
    mov byte [cs:in_menu], 1
    mov byte [cs:menu_present], 1
    jmp short .line
.other:
    mov byte [cs:in_menu], 0
    jmp short .line
.directive:
    cmp byte [cs:in_menu], 0
    je .line
    push si
    mov di, menuitem_lit
    call match_literal
    pop si
    jc .try_submenu
    mov di, menuitem_lit
    call match_literal
    xor bx, bx
    call add_menu_entry
    jmp .line
.try_submenu:
    push si
    mov di, submenu_lit
    call match_literal
    pop si
    jc .try_default
    mov di, submenu_lit
    call match_literal
    push si
    mov di, probe_name
    call copy_name
    call named_section_exists
    pop si
    jc .line
    mov bl, 1
    call add_menu_entry
    jmp .line
.try_default:
    push si
    mov di, menucolor_lit
    call match_literal
    pop si
    jc .try_menudefault
    mov di, menucolor_lit
    call match_literal
    call take_color
    jmp .line
.try_menudefault:
    mov di, menudefault_lit
    call match_literal
    jc .line
    call take_default
    jmp .line
.scanned:
    cmp byte [cs:item_count], 0
    je .done
    cmp byte [cs:timeout_present], 0
    je .show_menu
    cmp byte [cs:timeout_seconds], 0
    jne .show_menu
    call resolve_default
    mov al, [cs:default_index]
    jmp short .choice_ready
.show_menu:
    call apply_menu_color
    call display_menu_entries
    call read_menu_choice
.choice_ready:
    dec al
    xor ah, ah
    mov bx, ax
    mov si, entry_types
    add si, bx
    mov dl, [cs:si]
    push dx
    mov cx, NAME_SIZE
    mul cx
    pop dx
    mov si, entries
    add si, ax
    cmp dl, 0
    je .selected
    mov di, menu_name
    jmp short .copy
.selected:
    mov di, selected_name
.copy:
    push ds
    push es
    push cs
    pop ds
    push cs
    pop es
    mov cx, NAME_SIZE
    rep movsb
    pop es
    pop ds
    cmp dl, 0
    jne .submenu
.done:
    ret

copy_current_line:
    mov ax, [cs:next_line]
    sub ax, [cs:line_start]
    mov cx, ax
    mov di, [cs:out_pos]
    mov ax, di
    add ax, cx
    jc .truncate
    cmp ax, [cs:out_limit]
    jbe .copy
.truncate:
    mov cx, [cs:out_limit]
    sub cx, di
.copy:
    mov si, [cs:line_start]
    mov ax, [cs:out_seg]
    mov es, ax
    cld
    rep movsb
    mov [cs:out_pos], di
    ret

flatten_config:
    mov word [cs:out_pos], 0
    mov word [cs:scan_pos], 0
    mov byte [cs:section_active], 1
.line:
    call get_line
    jc .done
    mov si, [cs:trim_start]
    cmp si, [cs:line_end]
    jae .maybe_copy
    cmp byte [si], '['
    jne .maybe_include
    push si
    mov di, common_name
    call section_equals
    pop si
    jnc .enable
    mov di, selected_name
    call section_equals
    jnc .enable
    mov byte [cs:section_active], 0
    jmp short .line
.enable:
    mov byte [cs:section_active], 1
    jmp short .line
.maybe_include:
    cmp byte [cs:section_active], 0
    je .line
    push si
    mov di, include_lit
    call match_literal
    pop si
    jc .maybe_copy
    mov di, include_lit
    call match_literal
    call expand_include
    jmp .line
.maybe_copy:
    cmp byte [cs:section_active], 0
    je .line
    call copy_current_line
    jmp short .line
.done:
    ret

; Expand INCLUDE=<section> at its exact source position. Includes nest to
; eight levels; the immutable raw image makes both forward and backward
; references safe.
expand_include:
    cmp byte [cs:include_depth], 8
    jae .return
    xor ax, ax
    mov al, [cs:include_depth]
    mov cx, NAME_SIZE
    mul cx
    mov di, include_names
    add di, ax
    call copy_name
    or ax, ax
    jz .return
    push word [cs:scan_pos]
    push word [cs:line_start]
    push word [cs:trim_start]
    push word [cs:line_end]
    push word [cs:next_line]
    inc byte [cs:include_depth]
    mov byte [cs:include_found], 0
    mov word [cs:scan_pos], 0
.scan:
    call get_line
    jc .done
    mov si, [cs:trim_start]
    cmp si, [cs:line_end]
    jae .copy_line
    cmp byte [si], '['
    jne .inside
    cmp byte [cs:include_found], 0
    jne .done
    xor ax, ax
    mov al, [cs:include_depth]
    dec ax
    mov cx, NAME_SIZE
    mul cx
    mov di, include_names
    add di, ax
    call section_equals
    jc .scan
    mov byte [cs:include_found], 1
    jmp short .scan
.inside:
    cmp byte [cs:include_found], 0
    je .scan
    push si
    mov di, include_lit
    call match_literal
    pop si
    jc .copy_line
    mov di, include_lit
    call match_literal
    call expand_include
    jmp short .scan
.copy_line:
    cmp byte [cs:include_found], 0
    je .scan
    call copy_current_line
    jmp short .scan
.done:
    dec byte [cs:include_depth]
    pop word [cs:next_line]
    pop word [cs:line_end]
    pop word [cs:trim_start]
    pop word [cs:line_start]
    pop word [cs:scan_pos]
.return:
    ret

set_config_environment:
    cmp byte [cs:selected_name], 0
    je .done
    mov ax, [cs:sys_seg]
    mov es, ax
    mov di, [cs:env_off]
    push ds
    push cs
    pop ds
    mov si, config_prefix
.prefix:
    lodsb
    or al, al
    jz .name
    stosb
    jmp short .prefix
.name:
    mov si, selected_name
.name_loop:
    lodsb
    stosb
    or al, al
    jnz .name_loop
    xor al, al
    stosb
    mov bx, di
    sub bx, [cs:env_off]
    mov di, [cs:env_used_off]
    mov [es:di], bx
    pop ds
.done:
    ret

raw_seg          dw 0
out_seg          dw 0
sys_seg          dw 0
env_off          dw 0
env_used_off     dw 0
input_count      dw 0
out_pos          dw 0
out_limit        dw 0
scan_pos         dw 0
line_start       dw 0
trim_start       dw 0
line_end         dw 0
next_line        dw 0
start_tick       dw 0
menu_present     db 0
in_menu          db 0
section_active   db 0
item_count       db 0
default_length   db 0
default_index    db 1
timeout_seconds  db 0
timeout_present  db 0
menu_foreground  db 7
menu_background  db 0
new_type         db 0
new_length       db 0
include_depth    db 0
include_found    db 0
section_probe_found db 0

root_menu       db 'MENU',0
common_name     db 'COMMON',0
menuitem_lit    db 'MENUITEM',0
submenu_lit     db 'SUBMENU',0
menudefault_lit db 'MENUDEFAULT',0
menucolor_lit   db 'MENUCOLOR',0
include_lit     db 'INCLUDE',0
config_prefix   db 'CONFIG=',0
menu_heading    db 'MS-DOS 6.22 Startup Menu',CR,LF
                db '========================',CR,LF,CR,LF,0
menu_prompt     db CR,LF,'Enter a choice: ',0
menu_name       times NAME_SIZE db 0
selected_name   times NAME_SIZE db 0
default_name    times NAME_SIZE db 0
entries         times MAX_ITEMS*NAME_SIZE db 0
entry_lengths   times MAX_ITEMS db 0
entry_types     times MAX_ITEMS db 0
entry_labels    times MAX_ITEMS*NAME_SIZE db 0
include_names   times 8*NAME_SIZE db 0
probe_name      times NAME_SIZE db 0
