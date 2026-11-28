_bit_fetch:                         # rdi = url, rsi = строка -> тело
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 56
    mov rbx, rsi
    lea rax, [rip + Lrt_curl]
    mov [rsp], rax
    lea rax, [rip + Lrt_sS]
    mov [rsp + 8], rax
    lea rax, [rip + Lrt_L]
    mov [rsp + 16], rax
    lea rax, [rip + Lrt_ddp]
    mov [rsp + 24], rax
    mov [rsp + 32], rdi
    mov qword ptr [rsp + 40], 0
    mov rdi, rsp
    mov rsi, rbx
    call _bit_spawn_capture
    add rsp, 56
    pop rbx
    pop rbp
    ret

_bit_http_post:                     # rdi = url, rsi = данные, rdx = строка -> ответ
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 64
    mov rbx, rdx
    mov r12, rdi
    lea rax, [rip + Lrt_curl]
    mov [rsp], rax
    lea rax, [rip + Lrt_sS]
    mov [rsp + 8], rax
    lea rax, [rip + Lrt_L]
    mov [rsp + 16], rax
    lea rax, [rip + Lrt_d]
    mov [rsp + 24], rax
    mov [rsp + 32], rsi
    lea rax, [rip + Lrt_ddp]
    mov [rsp + 40], rax
    mov [rsp + 48], r12
    mov qword ptr [rsp + 56], 0
    mov rdi, rsp
    mov rsi, rbx
    call _bit_spawn_capture
    add rsp, 64
    pop r12
    pop rbx
    pop rbp
    ret

_bit_download:                      # rdi = url, rsi = файл, rdx = строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 64
    mov rbx, rdx
    mov r12, rdi
    lea rax, [rip + Lrt_curl]
    mov [rsp], rax
    lea rax, [rip + Lrt_sS]
    mov [rsp + 8], rax
    lea rax, [rip + Lrt_L]
    mov [rsp + 16], rax
    lea rax, [rip + Lrt_o]
    mov [rsp + 24], rax
    mov [rsp + 32], rsi
    lea rax, [rip + Lrt_ddp]
    mov [rsp + 40], rax
    mov [rsp + 48], r12
    mov qword ptr [rsp + 56], 0
    mov rdi, rsp
    xor esi, esi
    mov rdx, rbx
    call _bit_spawn_status
    add rsp, 64
    pop r12
    pop rbx
    pop rbp
    ret
