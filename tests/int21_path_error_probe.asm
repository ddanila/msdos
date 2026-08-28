bits 16
org 100h

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
    push ds
    pop es

    mov dx, test_directory
    mov ah, 39h
    int 21h
    jc setup_failed
    mov dx, test_directory
    mov ah, 39h
    int 21h
    require_error 5, fail_mkdir_exists
    mov dx, missing_child
    mov ah, 39h
    int 21h
    require_error 3, fail_mkdir_path
    mov dx, missing_directory
    mov ah, 3bh
    int 21h
    require_error 3, fail_chdir_path
    mov dx, missing_directory
    mov ah, 3ah
    int 21h
    require_error 3, fail_rmdir_path
    mov dx, test_directory
    mov ah, 3bh
    int 21h
    jc setup_failed
    mov dx, dot_path
    mov ah, 3ah
    int 21h
    require_error 16, fail_rmdir_current
    mov dx, dot_path
    mov di, moved_directory
    mov ah, 56h
    int 21h
    require_error 16, fail_rename_current

    xor cx, cx
    mov dx, local_file
    mov ah, 3ch
    int 21h
    jc setup_failed
    mov bx, ax
    mov ah, 3eh
    int 21h
    jc setup_failed
    xor cx, cx
    mov dx, collision_file
    mov ah, 3ch
    int 21h
    jc setup_failed
    mov bx, ax
    mov ah, 3eh
    int 21h
    jc setup_failed
    mov dx, local_file
    mov di, collision_file
    mov ah, 56h
    int 21h
    require_error 5, fail_rename_access
    mov dx, root_directory
    mov ah, 3bh
    int 21h
    jc setup_failed
    mov dx, test_directory
    mov ah, 3ah
    int 21h
    require_error 5, fail_rmdir_nonempty

    mov ax, 3d00h
    mov dx, test_directory
    int 21h
    require_error 5, fail_open_denied

    mov ax, 4301h
    mov cx, 1
    mov dx, local_file_path
    int 21h
    jc setup_failed
    mov dx, local_file_path
    mov ah, 41h
    int 21h
    require_error 5, fail_delete_denied
    mov ax, 4301h
    xor cx, cx
    mov dx, local_file_path
    int 21h
    jc setup_failed

    mov ax, 4301h
    mov cx, 10h
    mov dx, local_file_path
    int 21h
    require_error 5, fail_attr_denied

    mov ax, 3d01h
    mov dx, local_file_path
    int 21h
    jc setup_failed
    mov bx, ax
    mov cx, 1
    mov dx, io_byte
    mov ah, 3fh
    int 21h
    require_error 5, fail_read_denied
    mov ah, 3eh
    int 21h
    jc setup_failed

    mov ax, 3d00h
    mov dx, local_file_path
    int 21h
    jc setup_failed
    mov bx, ax
    mov cx, 1
    mov dx, io_byte
    mov ah, 40h
    int 21h
    require_error 5, fail_write_denied
    mov ah, 3eh
    int 21h
    jc setup_failed

    mov dx, missing_file
    mov ah, 41h
    int 21h
    require_error 2, fail_delete_file
    mov dx, missing_path_file
    mov ah, 41h
    int 21h
    require_error 3, fail_delete_path
    mov ax, 3d00h
    mov dx, missing_path_file
    int 21h
    require_error 3, fail_open_path

    xor cx, cx
    mov dx, missing_path_file
    mov ah, 3ch
    int 21h
    require_error 3, fail_create_path
    xor cx, cx
    mov dx, wildcard_name
    mov ah, 3ch
    int 21h
    require_error 2, fail_create_file
    mov ax, 4300h
    mov dx, missing_file
    int 21h
    require_error 2, fail_attr_file
    mov ax, 4300h
    mov dx, missing_path_file
    int 21h
    require_error 3, fail_attr_path

    mov dx, missing_file
    mov di, rename_target
    mov ah, 56h
    int 21h
    require_error 2, fail_rename_file
    mov dx, missing_path_file
    mov di, rename_target
    mov ah, 56h
    int 21h
    require_error 3, fail_rename_path

    xor bx, bx
    xor cx, cx
    xor dx, dx
    mov si, local_file_path
    mov ax, 6c00h
    int 21h
    require_error 1, fail_extopen_function
    mov bx, 3
    xor cx, cx
    mov dx, 1
    mov si, local_file_path
    mov ax, 6c00h
    int 21h
    require_error 12, fail_extopen_access_mode
    xor bx, bx
    xor cx, cx
    mov dx, 1
    mov si, missing_file
    mov ax, 6c00h
    int 21h
    require_error 2, fail_extopen_file
    mov si, missing_path_file
    mov ax, 6c00h
    int 21h
    require_error 3, fail_extopen_path
    mov si, test_directory
    mov ax, 6c00h
    int 21h
    require_error 5, fail_extopen_denied
    mov dx, 10h
    mov si, local_file_path
    mov ax, 6c00h
    int 21h
    require_error 80, fail_extopen_exists

    mov dx, dta
    mov ah, 1ah
    int 21h
    xor cx, cx
    mov dx, missing_glob
    mov ah, 4eh
    int 21h
    require_error 18, fail_find_none
    mov dx, missing_path_glob
    mov ah, 4eh
    int 21h
    require_error 3, fail_find_path

    xor cx, cx
    mov dx, wildcard_name
    mov ah, 5bh
    int 21h
    require_error 2, fail_create_new_file
    xor cx, cx
    mov dx, missing_path_file
    mov ah, 5bh
    int 21h
    require_error 3, fail_create_new_path
    xor cx, cx
    mov dx, missing_path_file
    mov ah, 5ah
    int 21h
    require_error 3, fail_create_temp_path

    mov dx, local_file_path
    mov ah, 41h
    int 21h
    jc setup_failed
    mov dx, collision_file_path
    mov ah, 41h
    int 21h
    jc setup_failed
    mov dx, test_directory
    mov ah, 3ah
    int 21h
    jc setup_failed

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

setup_failed:
    mov dx, fail_setup
fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

test_directory   db 'ERRDIR', 0
missing_directory db 'NOEXIST', 0
missing_child    db 'NOEXIST\CHILD', 0
dot_path         db '.', 0
root_directory   db '\', 0
local_file       db 'LOCAL.TST', 0
collision_file   db 'OTHER.TST', 0
local_file_path  db 'ERRDIR\LOCAL.TST', 0
collision_file_path db 'ERRDIR\OTHER.TST', 0
missing_file     db 'MISSING.TST', 0
missing_path_file db 'NOEXIST\MISSING.TST', 0
missing_glob     db 'NOFILES.*', 0
missing_path_glob db 'NOEXIST\*.*', 0
wildcard_name    db 'BAD*.TMP', 0
moved_directory  db '..\MOVED', 0
rename_target    db 'RENAMED.TST', 0
pass_message     db 'INT21_PATH_ERRORS_PASS', 13, 10, '$'
fail_setup       db 'INT21_PATH_SETUP_FAIL', 13, 10, '$'
fail_mkdir_exists db 'INT21_MKDIR_EXISTS_FAIL', 13, 10, '$'
fail_mkdir_path  db 'INT21_MKDIR_PATH_FAIL', 13, 10, '$'
fail_chdir_path  db 'INT21_CHDIR_PATH_FAIL', 13, 10, '$'
fail_rmdir_current db 'INT21_RMDIR_CURRENT_FAIL', 13, 10, '$'
fail_rmdir_path db 'INT21_RMDIR_PATH_FAIL', 13, 10, '$'
fail_rename_current db 'INT21_RENAME_CURRENT_FAIL', 13, 10, '$'
fail_rmdir_nonempty db 'INT21_RMDIR_NONEMPTY_FAIL', 13, 10, '$'
fail_rename_access db 'INT21_RENAME_ACCESS_FAIL', 13, 10, '$'
fail_rename_file db 'INT21_RENAME_FILE_FAIL', 13, 10, '$'
fail_rename_path db 'INT21_RENAME_PATH_FAIL', 13, 10, '$'
fail_delete_file db 'INT21_DELETE_FILE_FAIL', 13, 10, '$'
fail_delete_path db 'INT21_DELETE_PATH_FAIL', 13, 10, '$'
fail_delete_denied db 'INT21_DELETE_DENIED_FAIL', 13, 10, '$'
fail_open_path   db 'INT21_OPEN_PATH_FAIL', 13, 10, '$'
fail_open_denied db 'INT21_OPEN_DENIED_FAIL', 13, 10, '$'
fail_read_denied db 'INT21_READ_DENIED_FAIL', 13, 10, '$'
fail_write_denied db 'INT21_WRITE_DENIED_FAIL', 13, 10, '$'
fail_create_path db 'INT21_CREATE_PATH_FAIL', 13, 10, '$'
fail_create_file db 'INT21_CREATE_FILE_FAIL', 13, 10, '$'
fail_attr_file   db 'INT21_ATTR_FILE_FAIL', 13, 10, '$'
fail_attr_path   db 'INT21_ATTR_PATH_FAIL', 13, 10, '$'
fail_attr_denied db 'INT21_ATTR_DENIED_FAIL', 13, 10, '$'
fail_extopen_function db 'INT21_EXTOPEN_FUNCTION_FAIL', 13, 10, '$'
fail_extopen_access_mode db 'INT21_EXTOPEN_ACCESS_MODE_FAIL', 13, 10, '$'
fail_extopen_file db 'INT21_EXTOPEN_FILE_FAIL', 13, 10, '$'
fail_extopen_path db 'INT21_EXTOPEN_PATH_FAIL', 13, 10, '$'
fail_extopen_denied db 'INT21_EXTOPEN_DENIED_FAIL', 13, 10, '$'
fail_extopen_exists db 'INT21_EXTOPEN_EXISTS_FAIL', 13, 10, '$'
fail_find_none   db 'INT21_FIND_NONE_FAIL', 13, 10, '$'
fail_find_path   db 'INT21_FIND_PATH_FAIL', 13, 10, '$'
fail_create_new_file db 'INT21_CREATE_NEW_FILE_FAIL', 13, 10, '$'
fail_create_new_path db 'INT21_CREATE_NEW_PATH_FAIL', 13, 10, '$'
fail_create_temp_path db 'INT21_CREATE_TEMP_PATH_FAIL', 13, 10, '$'
io_byte          db 0
dta              times 128 db 0
