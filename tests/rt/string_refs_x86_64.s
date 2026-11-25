.intel_syntax noprefix
.text
.globl MAIN
MAIN:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push rdi
    push rsi
    sub rsp, 40
    xor edi, edi
    call _bit_str_adopt
    test rax, rax
    jnz 9f
    lea rdi, [rip + Lrt_empty]
    mov rsi, rdi
    call _bit_cat
    mov rbx, rax
    mov rdi, rax
    call _bit_str_adopt
    mov rdi, rbx
    call _bit_str_adopt
    mov rdi, rbx
    call _bit_str_find
    test rax, rax
    jz 9f
    cmp qword ptr [rax + 8], 1
    jne 9f
    mov rdi, rbx
    call _bit_str_retain
    mov rdi, rbx
    call _bit_str_retain
    mov rdi, rbx
    call _bit_str_find
    cmp qword ptr [rax + 8], 3
    jne 9f
    mov rdi, rbx
    call _bit_str_release
    mov rdi, rbx
    call _bit_str_release
    mov rdi, rbx
    call _bit_str_find
    test rax, rax
    jz 9f
    cmp qword ptr [rax + 8], 1
    jne 9f
    mov rdi, rbx
    call _bit_str_release
    mov rdi, rbx
    call _bit_str_find
    test rax, rax
    jnz 9f
    lea rbx, [rip + Lrt_empty]
    mov rdi, rbx
    call _bit_str_retain
    cmp rax, rbx
    jne 9f
    mov rdi, rbx
    call _bit_str_release
    mov rdi, rbx
    call STRLEN
    test rax, rax
    jnz 9f
    mov edi, 560000
    call _bit_alloc
    mov r12, rax
    xor r13d, r13d
1:  lea rdi, [rip + Lrt_empty]
    mov rsi, rdi
    call _bit_cat
    mov rdi, rax
    call _bit_str_adopt
    mov [r12 + r13*8], rax
    inc r13
    cmp r13, 70000
    jl 1b
    xor r13d, r13d
2:  mov rdi, [r12 + r13*8]
    call _bit_str_release
    inc r13
    cmp r13, 70000
    jl 2b
    mov rdi, r12
    call FREE
    mov rdx, [rip + Lrt_str_registry]
    mov ecx, 65536
3:  cmp qword ptr [rdx], 0
    jne 9f
    add rdx, 8
    dec ecx
    jnz 3b
    xor eax, eax
    jmp 10f
9:  mov eax, 1
10: add rsp, 40
    pop rsi
    pop rdi
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
