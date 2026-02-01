section .data
    msg_start       db "ASM-Nano - CTRL+S: Save, CTRL+Q: Quit", 0
    clear_screen    db 27, '[', '2', 'J', 27, '[', 'H', 0
    clear_len       equ $ - clear_screen
    
    status_bar_fmt  db 27, '[', '7', 'm', 0 ; Invert colors
    status_reset    db 27, '[', 'm', 0      ; Reset colors
    
    label_untitled  db "[No Name]", 0
    label_modified  db " (modified)", 0
    label_saved     db " [Saved]", 0
    label_line      db " Line: ", 0
    
    legend_msg      db " ^S = Save | ^Q = Quit", 0
    
    ; Constants
    STDIN           equ 0
    STDOUT          equ 1
    
    ; Syscalls
    SYS_READ        equ 0
    SYS_WRITE       equ 1
    SYS_OPEN        equ 2
    SYS_CLOSE       equ 3
    SYS_IOCTL       equ 16
    SYS_EXIT        equ 60
    
    ; File flags
    O_RDWR          equ 2
    O_CREAT         equ 64
    O_TRUNC         equ 512
    
    ; Termios
    TCGETS          equ 0x5401
    TCSETS          equ 0x5402
    TIOCGWINSZ      equ 0x5413
    
    ICANON          equ 0000002q
    ECHO            equ 0000010q
    ISIG            equ 0000001q
    IEXTEN          equ 0100000q
    ICRNL           equ 0000400q
    IXON            equ 0002000q
    OPOST           equ 0000001q
    CS8             equ 0000060q
    
    OFFSET_C_IFLAG  equ 0
    OFFSET_C_OFLAG  equ 4
    OFFSET_C_CFLAG  equ 8
    OFFSET_C_LFLAG  equ 12

    MAX_BUF_SIZE    equ 1024 * 1024 ; 1MB buffer

section .bss
    orig_termios    resb 60
    raw_termios     resb 60
    input_char      resb 1
    seq_buf         resb 3
    
    winsize:
        ws_row      resw 1
        ws_col      resw 1
        ws_xpixel   resw 1
        ws_ypixel   resw 1
    
    file_buf        resb MAX_BUF_SIZE
    file_len        resq 1
    file_path       resq 1
    is_dirty        resb 1
    
    cursor_idx      resq 1
    actual_row      resq 1
    actual_col      resq 1
    
    render_buf      resb 64

section .text
    global _start

_start:
    mov rdi, [rsp]      ; argc
    cmp rdi, 2
    jl .no_file_arg
    
    mov rsi, [rsp + 16] ; argv[1]
    mov [file_path], rsi
    call file_open

.no_file_arg:
    cld
    call enable_raw_mode
    call update_window_size
    call editor_refresh_screen

main_loop:
    mov rax, SYS_READ
    mov rdi, STDIN
    mov rsi, input_char
    mov rdx, 1
    syscall
    
    cmp rax, 0
    jle .end_loop

    call editor_process_keypress
    call update_window_size
    call editor_refresh_screen
    jmp main_loop

.end_loop:
    call graceful_exit

; ---------------------------------------------
; update_window_size
; ---------------------------------------------
update_window_size:
    mov rax, SYS_IOCTL
    mov rdi, STDOUT
    mov rsi, TIOCGWINSZ
    mov rdx, winsize
    syscall
    ret

; ---------------------------------------------
; editor_process_keypress
; ---------------------------------------------
editor_process_keypress:
    mov al, [input_char]
    
    cmp al, 17  ; CTRL+Q
    je graceful_exit
    cmp al, 19  ; CTRL+S
    je .save_trigger
    
    cmp al, 127 ; Backspace
    je .handle_bksp
    cmp al, 8
    je .handle_bksp
    
    cmp al, 13  ; Enter
    je .handle_enter
    
    cmp al, 27  ; Escape sequence
    je .handle_escape
    
    ; Regular char
    cmp al, 32
    jl .ignore
    
    call editor_insert_char
    mov byte [is_dirty], 1
    ret

.save_trigger:
    call file_save
    mov byte [is_dirty], 0
    ret

.handle_bksp:
    call editor_backspace_char
    mov byte [is_dirty], 1
    ret

.handle_enter:
    mov byte [input_char], 10
    call editor_insert_char
    mov byte [is_dirty], 1
    ret

.handle_escape:
    mov rax, SYS_READ
    mov rdi, STDIN
    mov rsi, seq_buf
    mov rdx, 2
    syscall
    cmp byte [seq_buf], '['
    jne .ignore
    mov al, [seq_buf + 1]
    cmp al, 'C' ; Right
    je .arrow_right
    cmp al, 'D' ; Left
    je .arrow_left
    ret

.arrow_left:
    cmp qword [cursor_idx], 0
    je .ret
    dec qword [cursor_idx]
    ret
.arrow_right:
    mov rbx, [file_len]
    cmp [cursor_idx], rbx
    jge .ret
    inc qword [cursor_idx]
    ret
.ret:
    ret
.ignore:
    ret

; ---------------------------------------------
; editor_insert_char
; ---------------------------------------------
editor_insert_char:
    mov rbx, [cursor_idx]
    mov rcx, [file_len]
    cmp rcx, MAX_BUF_SIZE
    jge .full
    
    mov rsi, file_buf
    add rsi, rcx
    dec rsi
    mov rdi, rsi
    inc rdi
    mov rdx, rcx
    sub rdx, rbx
    cmp rdx, 0
    jle .insert_now
    std
    mov rcx, rdx
    rep movsb
    cld
.insert_now:
    mov al, [input_char]
    lea rdi, [file_buf]
    add rdi, [cursor_idx]
    mov [rdi], al
    inc qword [file_len]
    inc qword [cursor_idx]
.full:
    ret

; ---------------------------------------------
; editor_backspace_char
; ---------------------------------------------
editor_backspace_char:
    mov rbx, [cursor_idx]
    cmp rbx, 0
    je .done
    dec qword [cursor_idx]
    dec qword [file_len]
    mov rbx, [cursor_idx]
    mov rcx, [file_len]
    sub rcx, rbx
    cmp rcx, 0
    jle .done
    lea rdi, [file_buf]
    add rdi, rbx
    lea rsi, [file_buf]
    add rsi, rbx
    inc rsi
    rep movsb
.done:
    ret

; ---------------------------------------------
; editor_refresh_screen
; ---------------------------------------------
editor_refresh_screen:
    ; 1. Clear screen
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, clear_screen
    mov rdx, clear_len
    syscall
    
    ; 2. Render content
    mov rsi, file_buf
    mov rcx, [file_len]
    xor rbx, rbx 
.render_loop:
    cmp rbx, rcx
    jge .render_done
    mov al, [rsi + rbx]
    push rcx
    push rsi
    push rbx
    cmp al, 10
    je .handle_newline
    call .print_one
    jmp .iteration_done
.handle_newline:
    mov al, 13
    call .print_one
    mov al, 10
    call .print_one
.iteration_done:
    pop rbx
    pop rsi
    pop rcx
    inc rbx
    jmp .render_loop
.render_done:

    ; 3. Draw Status Bar
    call editor_draw_status_bar
    
    ; 4. Reset Cursor to writing position
    call cursor_position_update ; this also updates actual_row/col
    ret

.print_one:
    mov [input_char], al
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [input_char]
    mov rdx, 1
    syscall
    ret

; ---------------------------------------------
; editor_draw_status_bar
; ---------------------------------------------
editor_draw_status_bar:
    ; Position cursor at row ws_row-1, col 1
    movzx rax, word [winsize + 0] ; ws_row
    dec rax
    mov r8, rax ; row
    mov r9, 1   ; col
    call set_cursor_pos
    
    ; Invert colors
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, status_bar_fmt
    mov rdx, 5
    syscall
    
    ; Print Filename
    mov rsi, [file_path]
    test rsi, rsi
    jnz .print_filename
    mov rsi, label_untitled
.print_filename:
    call print_string
    
    ; Print modification status
    cmp byte [is_dirty], 1
    jne .not_modified
    mov rsi, label_modified
    call print_string
    jmp .print_line_info
.not_modified:
    ; maybe print [Saved]?
.print_line_info:
    mov rsi, label_line
    call print_string
    
    ; Calculate current line number for display
    call cursor_position_update ; ensure actual_row is fresh
    mov rax, [actual_row]
    inc rax
    lea rdi, [render_buf]
    call int_to_ascii
    mov byte [rdi], 0
    lea rsi, [render_buf]
    call print_string

    ; Fill rest of line with spaces to maintain inverted background?
    ; For now just reset
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, status_reset
    mov rdx, 4
    syscall
    
    ; Position cursor at row ws_row, col 1 for Legend
    movzx rax, word [winsize + 0]
    mov r8, rax
    mov r9, 1
    call set_cursor_pos
    
    mov rsi, legend_msg
    call print_string
    ret

; Helper: Print null-terminated string in RSI
print_string:
    push rsi
    xor rdx, rdx
.count:
    cmp byte [rsi + rdx], 0
    je .done
    inc rdx
    jmp .count
.done:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    ; rsi already set
    ; rdx now has length
    syscall
    pop rsi
    ret

; Helper: Set cursor pos to row R8, col R9
set_cursor_pos:
    lea rdi, [render_buf]
    mov byte [rdi], 27
    mov byte [rdi+1], '['
    add rdi, 2
    mov rax, r8
    call int_to_ascii
    mov byte [rdi], ';'
    inc rdi
    mov rax, r9
    call int_to_ascii
    mov byte [rdi], 'H'
    inc rdi
    mov byte [rdi], 0
    lea rsi, [render_buf]
    call print_string
    ret

; ---------------------------------------------
; cursor_position_update
; ---------------------------------------------
cursor_position_update:
    xor rcx, rcx
    xor r8, r8   ; row
    xor r9, r9   ; col
    mov rbx, [cursor_idx]
    mov rsi, file_buf
.count_loop:
    cmp rcx, rbx
    jge .calc_done
    mov al, [rsi + rcx]
    cmp al, 10
    je .is_newline
    inc r9
    jmp .next_char
.is_newline:
    inc r8
    xor r9, r9
.next_char:
    inc rcx
    jmp .count_loop
.calc_done:
    mov [actual_row], r8
    mov [actual_col], r9
    inc r8
    inc r9
    call set_cursor_pos
    ret

; Convert RAX to ASCII at RDI, update RDI to end
int_to_ascii:
    push rbx
    push rcx
    push rdx
    mov rbx, 10
    xor rcx, rcx 
.div_loop:
    xor rdx, rdx
    div rbx
    push rdx
    inc rcx
    test rax, rax
    jnz .div_loop
.store_loop:
    pop rax
    add al, '0'
    mov [rdi], al
    inc rdi
    loop .store_loop
    pop rdx
    pop rcx
    pop rbx
    ret

; ---------------------------------------------
; Utils
; ---------------------------------------------
graceful_exit:
    call disable_raw_mode
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, clear_screen
    mov rdx, clear_len
    syscall
    mov rax, SYS_EXIT
    mov rdi, 0
    syscall

file_open:
    mov rax, SYS_OPEN
    mov rdi, [file_path]
    mov rsi, O_RDWR
    mov rdx, 0
    syscall
    cmp rax, 0
    jl .open_failed
    mov rdi, rax
    mov r8, rax ; save fd
    mov rax, SYS_READ
    mov rsi, file_buf
    mov rdx, MAX_BUF_SIZE
    syscall
    mov [file_len], rax
    mov rax, SYS_CLOSE
    mov rdi, r8
    syscall
    ret
.open_failed:
    mov qword [file_len], 0
    ret

file_save:
    mov rdi, [file_path]
    test rdi, rdi
    jz .ret
    mov rax, SYS_OPEN
    mov rsi, 578 ; O_RDWR|O_CREAT|O_TRUNC
    mov rdx, 0644o
    syscall
    cmp rax, 0
    jl .ret
    mov r8, rax ; fd
    mov rdi, rax
    mov rax, SYS_WRITE
    mov rsi, file_buf
    mov rdx, [file_len]
    syscall
    mov rax, SYS_CLOSE
    mov rdi, r8
    syscall
.ret:
    ret

enable_raw_mode:
    mov rax, SYS_IOCTL
    mov rdi, STDIN
    mov rsi, TCGETS
    mov rdx, orig_termios
    syscall
    mov rcx, 60
    mov rsi, orig_termios
    mov rdi, raw_termios
    rep movsb
    mov eax, [raw_termios + OFFSET_C_LFLAG]
    and eax, ~(ECHO | ICANON | ISIG | IEXTEN)
    mov [raw_termios + OFFSET_C_LFLAG], eax
    mov eax, [raw_termios + OFFSET_C_IFLAG]
    and eax, ~(IXON | ICRNL)
    mov [raw_termios + OFFSET_C_IFLAG], eax
    mov eax, [raw_termios + OFFSET_C_OFLAG]
    and eax, ~(OPOST)
    mov [raw_termios + OFFSET_C_OFLAG], eax
    mov eax, [raw_termios + OFFSET_C_CFLAG]
    or eax, CS8
    mov [raw_termios + OFFSET_C_CFLAG], eax
    mov rax, SYS_IOCTL
    mov rdi, STDIN
    mov rsi, TCSETS
    mov rdx, raw_termios
    syscall
    ret

disable_raw_mode:
    mov rax, SYS_IOCTL
    mov rdi, STDIN
    mov rsi, TCSETS
    mov rdx, orig_termios
    syscall
    ret
