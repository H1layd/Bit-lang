.intel_syntax noprefix
.section __TEXT,__text,regular,pure_instructions

// ─────────── среда выполнения bit (x86_64) ───────────
// аргументы: rdi, rsi, rdx, rcx, r8, r9; результат: rax
.p2align 4
_bit_signal_handler:                 // async-signal-safe: set one aligned flag
    mov dword ptr [rip + Lrt_signalled], 1
    ret

_bit_signalled:
    xor eax, eax
    cmp dword ptr [rip + Lrt_signalled], 0
    setne al
    ret

_bit_signal_init:                    // Darwin sigaction: handler, mask, flags
    push rbp
    mov rbp, rsp
    sub rsp, 16
    lea rax, [rip + _bit_signal_handler]
    mov [rsp], rax
    mov dword ptr [rsp + 8], 0
    mov dword ptr [rsp + 12], 2      // SA_RESTART
    mov edi, 2                       // SIGINT
    mov rsi, rsp
    xor edx, edx
    call _sigaction
    test eax, eax
    jnz 9f
    mov edi, 15                      // SIGTERM
    mov rsi, rsp
    xor edx, edx
    call _sigaction
    test eax, eax
    jnz 9f
    add rsp, 16
    pop rbp
    ret
9:  add rsp, 16
    pop rbp
    lea rdi, [rip + Lrt_esignal]
    xor esi, esi
    jmp _bit_die

_bit_rt_ensure:                     // однократная подготовка ключа потока и замка строк
    cmp byte ptr [rip + Lrt_ready], 0
    jne 9f
    push rbp
    mov rbp, rsp
    sub rsp, 16
    lea rdi, [rip + Lrt_tkey]
    xor esi, esi
    call _pthread_key_create
    lea rdi, [rip + Lrt_slock]
    xor esi, esi
    call _pthread_mutex_init
    mov byte ptr [rip + Lrt_ready], 1
    add rsp, 16
    pop rbp
9:  ret

_bit_lock:
    push rbp
    mov rbp, rsp
    call _bit_rt_ensure
    lea rdi, [rip + Lrt_slock]
    call _pthread_mutex_lock
    pop rbp
    ret

_bit_unlock:
    push rbp
    mov rbp, rsp
    lea rdi, [rip + Lrt_slock]
    call _pthread_mutex_unlock
    pop rbp
    ret

_bit_tstate:                        // → блок состояния этого потока
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    call _bit_rt_ensure
    mov rdi, [rip + Lrt_tkey]
    call _pthread_getspecific
    test rax, rax
    jnz 9f
    mov edi, 64
    call _bit_alloc
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    mov edx, 64
    call _memset
    mov rdi, [rip + Lrt_tkey]
    mov rsi, rbx
    call _pthread_setspecific
    mov rax, rbx
9:  add rsp, 8
    pop rbx
    pop rbp
    ret

_bit_recover_enter:                 // rdi = frame allocated by the compiler
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov r12, rdi
    call _bit_tstate
    mov rbx, rax
    mov rax, [rbx]
    mov [r12 + 168], rax
    mov [rbx], r12
    mov rax, [rbx + 8]
    mov [r12 + 176], rax
    mov qword ptr [rbx + 32], 0
    mov rax, r12
    pop r12
    pop rbx
    pop rbp
    ret

_bit_recover_leave:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    call _bit_tstate
    mov rbx, rax
    mov rax, [rbx]
    mov rax, [rax + 168]
    mov [rbx], rax
    add rsp, 8
    pop rbx
    pop rbp
    ret

_bit_own_str:                       // rdi = stack record with string and previous pointer
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call _bit_tstate
    mov rcx, [rax + 8]
    mov [rbx + 8], rcx
    mov [rax + 8], rbx
    add rsp, 8
    pop rbx
    pop rbp
    ret

_bit_drop_owned:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    call _bit_tstate
    mov rbx, rax
    mov rax, [rbx + 8]
    mov rcx, [rax + 8]
    mov [rbx + 8], rcx
    mov rdi, [rax]
    add rsp, 8
    pop rbx
    pop rbp
    jmp _bit_drop_str

_bit_setjmp:                        // rdi = буфер → 0; сохраняет callee-saved, sp и адрес возврата
    mov [rdi], rbx
    mov [rdi + 8], rbp
    mov [rdi + 16], r12
    mov [rdi + 24], r13
    mov [rdi + 32], r14
    mov [rdi + 40], r15
    lea rdx, [rsp + 8]
    mov [rdi + 48], rdx
    mov rdx, [rsp]
    mov [rdi + 56], rdx
    xor eax, eax
    ret

_bit_longjmp:                       // rdi = буфер, rsi = значение → возврат из _bit_setjmp
    mov rbx, [rdi]
    mov rbp, [rdi + 8]
    mov r12, [rdi + 16]
    mov r13, [rdi + 24]
    mov r14, [rdi + 32]
    mov r15, [rdi + 40]
    mov rsp, [rdi + 48]
    mov rax, rsi
    jmp qword ptr [rdi + 56]

_bit_set_errcode:                   // rdi = код → запомнить для этого потока
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call _bit_tstate
    mov [rax + 32], rbx
    add rsp, 8
    pop rbx
    pop rbp
    ret

_bit_term_errcode:                  // → код последней пойманной ошибки (0 = без кода)
    push rbp
    mov rbp, rsp
    call _bit_tstate
    mov rax, [rax + 32]
    pop rbp
    ret

_bit_errno_map:                     // edi = код ошибки системы → 1 отказ, 2 таймаут, 3 нет маршрута, 0 без кода
    cmp edi, 61                     # ECONNREFUSED (Darwin)
    je 1f
    cmp edi, 60                     # ETIMEDOUT (Darwin)
    je 2f
    cmp edi, 51                     # ENETUNREACH (Darwin)
    je 3f
    cmp edi, 65                     # EHOSTUNREACH (Darwin)
    je 3f
    xor eax, eax
    ret
1:  mov eax, 1
    ret
2:  mov eax, 2
    ret
3:  mov eax, 3
    ret

_bit_errno_code:                    // → код ошибки системы из errno
    push rbp
    mov rbp, rsp
    call ___error
    mov edi, dword ptr [rax]
    pop rbp
    jmp _bit_errno_map

// User locks have process lifetime; aliases refer to the same mutex.
_bit_user_lock_new:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov edi, 80
    call _bit_alloc
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    call _pthread_mutex_init
    test eax, eax
    jnz 1f
    mov rax, rbx
    add rsp, 8
    pop rbx
    pop rbp
    ret
1:  mov rdi, rbx
    call _free
    lea rdi, [rip + Lrt_elock]
    xor esi, esi
    add rsp, 8
    pop rbx
    pop rbp
    jmp _bit_die

_bit_user_lock_enter:                // rdi = lock, rsi = source line
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rsi
    call _pthread_mutex_lock
    test eax, eax
    jnz 1f
    add rsp, 8
    pop rbx
    pop rbp
    ret
1:  lea rdi, [rip + Lrt_elock]
    mov rsi, rbx
    add rsp, 8
    pop rbx
    pop rbp
    jmp _bit_die

_bit_user_lock_leave:                // rdi = lock, rsi = source line
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rsi
    call _pthread_mutex_unlock
    test eax, eax
    jnz 1f
    add rsp, 8
    pop rbx
    pop rbp
    ret
1:  lea rdi, [rip + Lrt_elock]
    mov rsi, rbx
    add rsp, 8
    pop rbx
    pop rbp
    jmp _bit_die

_bit_thread_start:                  // rdi = code -> stable thread token
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    // No bit thread can start before the shared registry and TLS key exist.
    call _bit_rt_ensure
    mov edi, 128
    call _bit_alloc
    mov r12, rax
    mov qword ptr [r12 + 24], 0
    mov qword ptr [r12 + 32], 0
    mov qword ptr [r12 + 120], 0
    lea rdi, [r12 + 40]
    xor esi, esi
    call _pthread_cond_init
    test eax, eax
    jnz 8f
    lea rdi, [r12 + 16]
    xor esi, esi
    lea rdx, [rip + _bit_thread_run]
    mov rcx, rbx
    call _pthread_create
    test eax, eax
    jnz 9f
    call _bit_lock
    mov r13, [rip + Lrt_thread_next]
    lea rax, [r13 + 1]
    mov [rip + Lrt_thread_next], rax
    mov [r12 + 8], r13
    mov rax, [rip + Lrt_thread_list]
    mov [r12], rax
    mov [rip + Lrt_thread_list], r12
    call _bit_unlock
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [r12 + 40]
    call _pthread_cond_destroy
8:  mov rdi, r12
    call _free
    lea rdi, [rip + Lrt_ethread]
    xor esi, esi
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_thread_run:                    // rdi = код потока
    push rbp
    mov rbp, rsp
    call rdi
    // State is optional: do not allocate it just to destroy it.
    mov rdi, [rip + Lrt_tkey]
    call _pthread_getspecific
    test rax, rax
    jz 1f
    mov rdi, rax
    call _free
1:
    xor eax, eax
    pop rbp
    ret

_bit_thread_wait:                   // rdi = stable token; completed tokens are no-ops
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    call _bit_lock
    mov r12, [rip + Lrt_thread_list]
1:  test r12, r12
    jz 8f
    cmp [r12 + 8], rbx
    je 2f
    mov r12, [r12]
    jmp 1b
2:  inc qword ptr [r12 + 24]
    xor r13d, r13d
    cmp qword ptr [r12 + 32], 0
    jne 4f
    mov qword ptr [r12 + 32], 1
    call _bit_unlock
    mov rdi, [r12 + 16]
    xor esi, esi
    call _pthread_join
    mov r13d, eax
    call _bit_lock
    mov [r12 + 120], r13
    mov qword ptr [r12 + 32], 2
    lea rdi, [r12 + 40]
    call _pthread_cond_broadcast
    jmp 6f
4:  cmp qword ptr [r12 + 32], 2
    je 5f
    lea rdi, [r12 + 40]
    lea rsi, [rip + Lrt_slock]
    call _pthread_cond_wait
    test eax, eax
    jz 4b
    mov r13d, eax
    jmp 6f
5:  mov r13, [r12 + 120]
6:  dec qword ptr [r12 + 24]
    jnz 7f
    lea r14, [rip + Lrt_thread_list]
61: mov rax, [r14]
    cmp rax, r12
    je 62f
    mov r14, rax
    jmp 61b
62: mov rax, [r12]
    mov [r14], rax
    call _bit_unlock
    lea rdi, [r12 + 40]
    call _pthread_cond_destroy
    mov rdi, r12
    call _free
    jmp 9f
7:  call _bit_unlock
    jmp 9f
8:  call _bit_unlock
    xor r13d, r13d
9:  test r13, r13
    jnz 10f
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
10: lea rdi, [rip + Lrt_ewait_thread]
    xor esi, esi
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_term_raw:                      // rdi = 1 сырой режим, 0 обычный
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 136
    mov ebx, edi
    xor edi, edi
    lea rsi, [rsp]
    call _tcgetattr
    test eax, eax
    js 9f
    mov eax, [rsp + 24]              # c_lflag (Darwin)
    test ebx, ebx
    jz 1f
    and eax, -265                    # снять ICANON|ECHO (Darwin)
    jmp 2f
1:  or eax, 264                      # вернуть ICANON|ECHO (Darwin)
2:  mov [rsp + 24], eax
    xor edi, edi
    xor esi, esi
    lea rdx, [rsp]
    call _tcsetattr
9:  add rsp, 136
    pop rbx
    pop rbp
    ret

_bit_term_key:                      // → строка из одного символа
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov edi, 8
    call _bit_alloc
    mov rbx, rax
    xor edi, edi
    mov rsi, rbx
    mov edx, 1
    call _read
    cmp eax, 1
    jl 9f
    movzx ecx, byte ptr [rbx]
    mov r13d, 1
    cmp ecx, 0xF0
    jb 1f
    mov r13d, 4
    jmp 3f
1:  cmp ecx, 0xE0
    jb 2f
    mov r13d, 3
    jmp 3f
2:  cmp ecx, 0xC0
    jb 3f
    mov r13d, 2
3:  mov r12d, 1
4:  cmp r12d, r13d
    jge 8f
    xor edi, edi
    lea rsi, [rbx + r12]
    mov edx, 1
    call _read
    cmp eax, 1
    jl 8f
    inc r12d
    jmp 4b
8:  mov byte ptr [rbx + r12], 0
    mov rax, rbx
    jmp 10f
9:  mov byte ptr [rbx], 0
    mov rax, rbx
10: add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_term_error:                    // → копия текста последней пойманной ошибки ("" если не было)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    call _bit_tstate
    mov rbx, [rax + 16]
    test rbx, rbx
    jnz 1f
    mov edi, 1
    call _bit_alloc
    mov byte ptr [rax], 0
    jmp 2f
1:  mov rdi, rbx
    call _strlen
    mov rsi, rax
    mov rdi, rbx
    call _bit_substr
2:  pop r12
    pop rbx
    pop rbp
    ret

_bit_die:                           // rdi = сообщение, rsi = строка программы
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    call _bit_tstate
    mov rbx, rax
    mov rax, [rbx]
    test rax, rax
    jz 5f
    mov [rbx + 16], r12
    mov [rbx + 24], r13
    mov rcx, [rax + 168]
    mov [rbx], rcx
    mov r13, rax
1:  mov rcx, [rbx + 8]
    cmp rcx, [r13 + 176]
    je 2f
    call _bit_drop_owned
    jmp 1b
2:  mov rdi, r13
    mov esi, 1
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_longjmp
5:  xor edi, edi
    call _fflush
    mov rax, [rip + ___stderrp@GOTPCREL]
    mov rdi, [rax]
    lea rsi, [rip + Lrt_die]
    mov rdx, r13
    mov rcx, r12
    xor eax, eax
    call _fprintf
    mov edi, 1
    call _exit

_bit_oom:
    and rsp, -16
    lea rdi, [rip + Lrt_oom]
    xor esi, esi
    call _bit_die

_bit_key_cmp:                       // rdi=a, rsi=b, rdx=вид → eax (-1, 0, 1)
    cmp rdx, 2
    je 1f
    cmp rdi, rsi
    jl 3f
    jg 4f
    xor eax, eax
    ret
1:  movzx eax, byte ptr [rdi]
    movzx ecx, byte ptr [rsi]
    cmp eax, ecx
    jl 3f
    jg 4f
    test eax, eax
    jz 5f
    inc rdi
    inc rsi
    jmp 1b
5:  xor eax, eax
    ret
3:  mov eax, -1
    ret
4:  mov eax, 1
    ret

_bit_mas_sort_by:                   // rdi=значения, rsi=ключи, rdx=вид, rcx=убывание, r8=строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], rdx
    mov [rsp + 8], rcx
    mov r14, [rbx + 8]
    mov rax, [r12 + 8]
    cmp r14, rax
    jle 1f
    mov r14, rax
1:  mov r15, 1
2:  cmp r15, r14
    jge 9f
    mov rax, [rbx]
    mov rdx, [rax + r15*8]
    mov [rsp + 16], rdx
    mov rax, [r12]
    mov rdx, [rax + r15*8]
    mov [rsp + 24], rdx
    mov rcx, r15
3:  test rcx, rcx
    jz 6f
    dec rcx
    mov [rsp + 32], rcx
    mov rax, [r12]
    mov rdi, [rax + rcx*8]
    mov rsi, [rsp + 24]
    mov rdx, [rsp]
    call _bit_key_cmp
    cmp qword ptr [rsp + 8], 0
    je 31f
    neg eax
31: test eax, eax
    jle 7f
    mov rcx, [rsp + 32]
    mov rax, [r12]
    mov rdx, [rax + rcx*8]
    mov [rax + rcx*8 + 8], rdx
    mov rax, [rbx]
    mov rdx, [rax + rcx*8]
    mov [rax + rcx*8 + 8], rdx
    jmp 3b
6:  xor ecx, ecx
    jmp 52f
7:  inc rcx
52: mov rax, [r12]
    mov rdx, [rsp + 24]
    mov [rax + rcx*8], rdx
    mov rax, [rbx]
    mov rdx, [rsp + 16]
    mov [rax + rcx*8], rdx
    inc r15
    jmp 2b
9:  add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_map_keys:                      // rdi=словарь, rsi=строка → mas строк
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r13, rsi
    mov r12, [rbx + 8]
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r14, rax
    xor r15d, r15d
1:  cmp r15, r12
    jge 2f
    mov rax, [rbx]
    mov rax, [rax + r15*8]
    mov rax, [rbx]
    mov rax, [rax + r15*8]
    mov rsi, [rax]
    mov rdi, r14
    mov rdx, r13
    call _bit_mas_add
    inc r15
    jmp 1b
2:  mov rax, r14
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_map_values:                    // rdi=словарь, rsi=вид значения, rdx=строка → mas
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov [rsp], rsi                  # вид значения
    mov r13, rdx
    mov r12, [rbx + 8]
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r14, rax
    xor r15d, r15d
1:  cmp r15, r12
    jge 2f
    mov rax, [rbx]
    mov rax, [rax + r15*8]
    mov rsi, [rax + 8]
    mov [rsp + 8], rsi
3:  mov rdi, r14
    mov rdx, r13
    call _bit_mas_add
    inc r15
    jmp 1b
2:  mov rax, r14
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_map_find:                      // map, key -> index or -1
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, [rdi]
    mov r12, [rdi + 8]
    mov r13, rsi
    xor r14d, r14d
1:  cmp r14, r12
    jge 2f
    mov rdi, [rbx + r14*8]
    mov rdi, [rdi]
    mov rsi, r13
    call _bit_str_eq
    test rax, rax
    jnz 3f
    inc r14
    jmp 1b
2:  mov r14, -1
3:  mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_map_set:                       // map, key, value, source line
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    call _bit_map_find
    test rax, rax
    js 1f
    mov rcx, [rbx]
    mov rcx, [rcx + rax*8]
    mov [rcx + 8], r13
    jmp 2f
1:  mov edi, 16
    call _bit_alloc
    mov [rax], r12
    mov [rax + 8], r13
    mov rdi, rbx
    mov rsi, rax
    mov rdx, r14
    call _bit_mas_add
2:  pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_map_remove:                    // map, key
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    call _bit_map_find
    test rax, rax
    js 1f
    mov rcx, [rbx]
    mov r12, [rcx + rax*8]
    mov rdi, rbx
    mov rsi, rax
    call _bit_mas_remove
    mov rdi, r12
    call _free
1:  pop r12
    pop rbx
    pop rbp
    ret

_bit_random_seed:                   // Hash a UTF-8 seed word with FNV-1a.
    mov rax, 0xcbf29ce484222325
    mov rcx, 0x100000001b3
1:  movzx edx, byte ptr [rdi]
    test edx, edx
    jz 2f
    xor rax, rdx
    imul rax, rcx
    inc rdi
    jmp 1b
2:  mov [rip + Lrt_random_state], rax
    mov qword ptr [rip + Lrt_random_ready], 1
    ret

_bit_random_next:                   // SplitMix64 with unsigned wrapping arithmetic.
    mov rcx, 0x9e3779b97f4a7c15
    add rcx, [rip + Lrt_random_state]
    mov [rip + Lrt_random_state], rcx
    mov rax, rcx
    shr rax, 30
    xor rax, rcx
    mov rcx, 0xbf58476d1ce4e5b9
    imul rax, rcx
    mov rcx, rax
    shr rcx, 27
    xor rax, rcx
    mov rcx, 0x94d049bb133111eb
    imul rax, rcx
    mov rcx, rax
    shr rcx, 31
    xor rax, rcx
    ret

_bit_random_range:                  // Inclusive signed bounds, source line.
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32
    mov rbx, rdi
    mov r13, rdx
    cmp rdi, rsi
    jg 9f
    mov r12, rsi
    sub r12, rdi
    inc r12
    cmp qword ptr [rip + Lrt_random_ready], 0
    jne 2f
    mov rdi, rsp
    mov esi, 16
    call _getentropy
    test eax, eax
    jnz 8f
    xor ecx, ecx
1:  movzx eax, byte ptr [rsp + rcx]
    and eax, 15
    add eax, 97
    mov [rsp + rcx], al
    inc ecx
    cmp ecx, 16
    jne 1b
    mov byte ptr [rsp + 16], 0
    mov rdi, rsp
    call _bit_random_seed
2:  test r12, r12
    jz 4f
    // Rejection avoids modulo bias. A zero width denotes the entire num range.
    mov rax, r12
    neg rax
    xor edx, edx
    div r12
    mov r14, rdx
3:  call _bit_random_next
    cmp rax, r14
    jb 3b
    xor edx, edx
    div r12
    mov rax, rdx
    jmp 5f
4:  call _bit_random_next
5:  add rax, rbx
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  lea rdi, [rip + Lrt_random_entropy]
    jmp 7f
9:  lea rdi, [rip + Lrt_random_bounds]
7:  mov rsi, r13
    call _bit_die


// String ownership registry. Unknown pointers (literals and borrowed values) are ignored.
// Node layout: payload, references, next. Ownership adoption is explicit and idempotent.
_bit_str_find_raw:
    xor eax, eax
    cmp rdi, [rip + Lrt_str_low]
    jb 2f
    cmp rdi, [rip + Lrt_str_high]
    ja 2f
    mov rax, [rip + Lrt_str_registry]
    test rax, rax
    jz 2f
    mov rcx, rdi
    shr rcx, 4
    mov rdx, rdi
    shr rdx, 20
    xor rcx, rdx
    and ecx, 1048575
    mov rax, [rax + rcx*8]
1:  test rax, rax
    jz 2f
    cmp [rax], rdi
    je 2f
    mov rax, [rax + 16]
    jmp 1b
2:  ret

_bit_str_find:                      // rdi = указатель → запись реестра или 0 (под замком)
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call _bit_lock
    mov rdi, rbx
    call _bit_str_find_raw
    mov [rsp], rax
    call _bit_unlock
    mov rax, [rsp]
    add rsp, 8
    pop rbx
    pop rbp
    ret

_bit_str_retain:
    mov rax, rdi
    cmp rdi, [rip + Lrt_str_low]
    jb 3f
    cmp rdi, [rip + Lrt_str_high]
    ja 3f
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call _bit_str_find
    test rax, rax
    jz 1f
    mov rdi, rbx
    call _bit_lock
    mov rdi, rbx
    call _bit_str_find_raw
    test rax, rax
    jz 4f
    inc qword ptr [rax + 8]
4:  call _bit_unlock
1:  mov rax, rbx
    add rsp, 8
    pop rbx
    pop rbp
3:  ret

_bit_str_adopt:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    test rdi, rdi
    jz 2f
    call _bit_lock
    mov rdi, rbx
    call _bit_str_find_raw
    test rax, rax
    jnz 3f
    mov r12, [rip + Lrt_str_registry]
    test r12, r12
    jnz 1f
    mov edi, 1048576
    mov esi, 8
    call _calloc
    test rax, rax
    jz _bit_oom
    mov r12, rax
    mov [rip + Lrt_str_registry], rax
1:  mov r13, rbx
    shr r13, 4
    mov rax, rbx
    shr rax, 20
    xor r13, rax
    and r13d, 1048575
    mov edi, 24
    call _bit_alloc
    mov [rax], rbx
    mov qword ptr [rax + 8], 1
    mov rcx, [r12 + r13*8]
    mov [rax + 16], rcx
    mov [r12 + r13*8], rax
    // Conservative bounds never shrink: pointers outside them cannot be owned strings.
    mov rax, [rip + Lrt_str_low]
    cmp rbx, rax
    cmovb rax, rbx
    mov [rip + Lrt_str_low], rax
    mov rax, [rip + Lrt_str_high]
    cmp rbx, rax
    cmova rax, rbx
    mov [rip + Lrt_str_high], rax
3:  call _bit_unlock
2:  mov rax, rbx
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_str_release:
    cmp rdi, [rip + Lrt_str_low]
    jb 3f
    cmp rdi, [rip + Lrt_str_high]
    ja 3f
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    call _bit_lock
    mov r12, [rip + Lrt_str_registry]
    test r12, r12
    jz 2f
    mov rcx, rbx
    shr rcx, 4
    mov rax, rbx
    shr rax, 20
    xor rcx, rax
    and ecx, 1048575
    lea r12, [r12 + rcx*8]
1:  mov rax, [r12]
    test rax, rax
    jz 2f
    cmp [rax], rbx
    je 4f
    lea r12, [rax + 16]
    jmp 1b
4:  dec qword ptr [rax + 8]
    jnz 2f
    mov rcx, [rax + 16]
    mov [r12], rcx
    mov rdi, rax
    call _free
    mov rdi, rbx
    call _free
2:  call _bit_unlock
    pop r12
    pop rbx
    pop rbp
3:  ret

_bit_alloc:                         // rdi = байты → rax = память
    push rbp
    mov rbp, rsp
    call _malloc
    test rax, rax
    jz _bit_oom
    pop rbp
    ret

_bit_print:                         // rdi = строка
    push rbp
    mov rbp, rsp
    call _puts
    pop rbp
    ret

_bit_num_str:                       // rdi = num → строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov edi, 32
    call _bit_alloc
    mov r12, rax
    mov rdi, rax
    mov esi, 32
    lea rdx, [rip + Lrt_lld]
    mov rcx, rbx
    xor eax, eax
    call _snprintf
    mov rax, r12
    pop r12
    pop rbx
    pop rbp
    ret

_bit_dec_str:                       // rdi = биты dec → самая короткая точная запись
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov edi, 48
    call _bit_alloc
    mov r12, rax
    mov r13d, 15
1:  mov rdi, r12
    mov esi, 44
    lea rdx, [rip + Lrt_gp]
    mov ecx, r13d
    movq xmm0, rbx
    mov eax, 1
    call _snprintf
    cmp r13d, 17
    jge 2f
    mov rdi, r12
    xor esi, esi
    call _strtod
    movq rax, xmm0
    cmp rax, rbx
    je 2f
    inc r13d
    jmp 1b
2:  mov rdi, r12
    lea rsi, [rip + Lrt_decch]
    call _strpbrk
    test rax, rax
    jnz 3f
    mov rdi, r12
    lea rsi, [rip + Lrt_dot0]
    call _strcat
3:  mov rax, r12
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_bool_str:                      // rdi = bool → строка
    lea rax, [rip + Lrt_true]
    test rdi, rdi
    jnz 1f
    lea rax, [rip + Lrt_false]
1:  ret

_bit_string_str:
    mov rax, rdi
    ret

_bit_to_str:                        // rdi = значение, rsi = вид (0 num, 1 dec, 2 string, 3 bool)
    cmp rsi, 0
    je _bit_num_str
    cmp rsi, 1
    je _bit_dec_str
    cmp rsi, 3
    je _bit_bool_str
    mov rax, rdi
    ret

_bit_cat:                           // rdi = a, rsi = b → новая строка a+b
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    call _strlen
    mov r13, rax
    mov rdi, r12
    call _strlen
    mov r14, rax
    lea rdi, [r13 + r14 + 1]
    call _bit_alloc
    mov r15, rax
    mov rdi, r15
    mov rsi, rbx
    mov rdx, r13
    call _memcpy
    lea rdi, [r15 + r13]
    mov rsi, r12
    lea rdx, [r14 + 1]
    call _memcpy
    mov rax, r15
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_str_eq:                        // rdi, rsi = строки → 1 если равны
    push rbp
    mov rbp, rsp
    call _strcmp
    test eax, eax
    sete al
    movzx eax, al
    pop rbp
    ret

_bit_str_starts:                    // rdi=строка, rsi=начало → 1/0
1:  movzx eax, byte ptr [rsi]
    test al, al
    jz 2f
    movzx ecx, byte ptr [rdi]
    cmp al, cl
    jne 3f
    inc rdi
    inc rsi
    jmp 1b
2:  mov eax, 1
    ret
3:  xor eax, eax
    ret

_bit_str_ends:                      // rdi=строка, rsi=конец → 1/0
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call _strlen
    mov r13, rax
    mov rdi, rbx
    call _strlen
    cmp r13, rax
    jg 3f
    lea rdi, [rbx + rax]
    sub rdi, r13
    mov rsi, r12
    mov rcx, r13
1:  test rcx, rcx
    jz 2f
    movzx edx, byte ptr [rdi]
    movzx r8d, byte ptr [rsi]
    cmp dl, r8b
    jne 3f
    inc rdi
    inc rsi
    dec rcx
    jmp 1b
2:  mov eax, 1
    jmp 4f
3:  xor eax, eax
4:  pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_str_trim:                      // rdi=строка → новая строка без краёв-пробелов
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
1:  movzx eax, byte ptr [r12]
    cmp al, 0x20
    je 2f
    cmp al, 0x09
    je 2f
    cmp al, 0x0A
    je 2f
    cmp al, 0x0D
    je 2f
    jmp 3f
2:  inc r12
    jmp 1b
3:  mov rdi, r12
    call _strlen
    mov r13, rax
4:  test r13, r13
    jz 6f
    movzx eax, byte ptr [r12 + r13 - 1]
    cmp al, 0x20
    je 5f
    cmp al, 0x09
    je 5f
    cmp al, 0x0A
    je 5f
    cmp al, 0x0D
    je 5f
    jmp 6f
5:  dec r13
    jmp 4b
6:  lea rdi, [r13 + 1]
    call _bit_alloc
    mov r14, rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call _memcpy
    mov byte ptr [r14 + r13], 0
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_substr:                        // rdi=указатель, rsi=длина → новая строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [r12 + 1]
    call _bit_alloc
    mov r13, rax
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r12
    call _memcpy
    mov byte ptr [r13 + r12], 0
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_str_index:                     // rdi=строка, rsi=подстрока → номер символа или -1
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rsi                    # подстрока
    xor r14d, r14d                  # счётчик символов
    movzx eax, byte ptr [r12]
    test eax, eax
    jz 8f                           # пустая подстрока — вхождение с нуля
1:  movzx eax, byte ptr [rdi]
    test eax, eax
    jz 7f                           # конец строки — нет вхождения
    mov rbx, rdi
    mov r13, r12
2:  movzx eax, byte ptr [r13]
    test eax, eax
    jz 6f                           # подстрока кончилась — нашли
    movzx ecx, byte ptr [rbx]
    cmp al, cl
    jne 3f
    inc rbx
    inc r13
    jmp 2b
3:  movzx eax, byte ptr [rdi]
    and eax, 0xC0
    cmp eax, 0x80
    je 4f                           # продолжение символа — не считаем
    inc r14
4:  inc rdi
    jmp 1b
6:  mov rax, r14
    jmp 9f
7:  mov rax, -1
    jmp 9f
8:  xor eax, eax
9:  pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_str_contains:                  // rdi=строка, rsi=подстрока → 1/0
    push rbp
    mov rbp, rsp
    call _bit_str_index
    cmp rax, -1
    jne 1f
    xor eax, eax
    pop rbp
    ret
1:  mov eax, 1
    pop rbp
    ret

_bit_str_upper:                     // rdi=строка → новая строка в верхнем регистре
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    call _strlen
    mov r12, rax
    lea rdi, [r12 + 1]
    call _bit_alloc
    mov r13, rax
    xor r14d, r14d
1:  cmp r14, r12
    jge 3f
    movzx eax, byte ptr [rbx + r14]
    cmp al, 97                      # 'a'
    jb 2f
    cmp al, 122                     # 'z'
    ja 2f
    sub al, 32
2:  mov [r13 + r14], al
    inc r14
    jmp 1b
3:  mov byte ptr [r13 + r12], 0
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_str_lower:                     // rdi=строка → новая строка в нижнем регистре
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    call _strlen
    mov r12, rax
    lea rdi, [r12 + 1]
    call _bit_alloc
    mov r13, rax
    xor r14d, r14d
1:  cmp r14, r12
    jge 3f
    movzx eax, byte ptr [rbx + r14]
    cmp al, 65                      # 'A'
    jb 2f
    cmp al, 90                      # 'Z'
    ja 2f
    add al, 32
2:  mov [r13 + r14], al
    inc r14
    jmp 1b
3:  mov byte ptr [r13 + r12], 0
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_str_code:                      // rdi=строка, rsi=строка программы → код первого символа
    push rbp
    mov rbp, rsp
    push rbx
    mov rbx, rsi
    movzx eax, byte ptr [rdi]
    test eax, eax
    jz 9f
    cmp eax, 0x80
    jae 1f
    pop rbx
    pop rbp
    ret
1:  and eax, 0xE0
    cmp eax, 0xC0
    jne 2f
    movzx eax, byte ptr [rdi]
    and eax, 0x1F
    shl eax, 6
    movzx ecx, byte ptr [rdi + 1]
    and ecx, 0x3F
    or eax, ecx
    pop rbx
    pop rbp
    ret
2:  movzx eax, byte ptr [rdi]
    and eax, 0xF0
    cmp eax, 0xE0
    jne 3f
    movzx eax, byte ptr [rdi]
    and eax, 0x0F
    shl eax, 12
    movzx ecx, byte ptr [rdi + 1]
    and ecx, 0x3F
    shl ecx, 6
    or eax, ecx
    movzx ecx, byte ptr [rdi + 2]
    and ecx, 0x3F
    or eax, ecx
    pop rbx
    pop rbp
    ret
3:  movzx eax, byte ptr [rdi]
    and eax, 0x07
    shl eax, 18
    movzx ecx, byte ptr [rdi + 1]
    and ecx, 0x3F
    shl ecx, 12
    or eax, ecx
    movzx ecx, byte ptr [rdi + 2]
    and ecx, 0x3F
    shl ecx, 6
    or eax, ecx
    movzx ecx, byte ptr [rdi + 3]
    and ecx, 0x3F
    or eax, ecx
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_ecode_empty]
    mov rsi, rbx
    pop rbx
    pop rbp
    jmp _bit_die

_bit_num_char:                      // rdi=код, rsi=строка программы → строка из одного символа
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov r13, rsi
    mov rbx, rdi
    test rbx, rbx
    js 9f
    mov rax, 1114111
    cmp rbx, rax
    jg 9f
    mov edi, 5
    call _bit_alloc
    mov r12, rax
    cmp rbx, 0x80
    jb 1f
    cmp rbx, 0x800
    jb 2f
    cmp rbx, 0x10000
    jb 3f
    mov rax, rbx
    shr rax, 18
    or al, 0xF0
    mov [r12], al
    mov rax, rbx
    shr rax, 12
    and al, 0x3F
    or al, 0x80
    mov [r12 + 1], al
    mov rax, rbx
    shr rax, 6
    and al, 0x3F
    or al, 0x80
    mov [r12 + 2], al
    mov rax, rbx
    and al, 0x3F
    or al, 0x80
    mov [r12 + 3], al
    mov byte ptr [r12 + 4], 0
    jmp 8f
1:  mov [r12], bl
    mov byte ptr [r12 + 1], 0
    jmp 8f
2:  mov rax, rbx
    shr rax, 6
    or al, 0xC0
    mov [r12], al
    mov rax, rbx
    and al, 0x3F
    or al, 0x80
    mov [r12 + 1], al
    mov byte ptr [r12 + 2], 0
    jmp 8f
3:  mov rax, rbx
    shr rax, 12
    or al, 0xE0
    mov [r12], al
    mov rax, rbx
    shr rax, 6
    and al, 0x3F
    or al, 0x80
    mov [r12 + 1], al
    mov rax, rbx
    and al, 0x3F
    or al, 0x80
    mov [r12 + 2], al
    mov byte ptr [r12 + 3], 0
8:  mov rax, r12
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_echar_range]
    mov rsi, r13
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_str_pad:                       // rdi=строка, rsi=ширина, rdx=заполнитель, rcx=строка → строка
    mov r8d, 1
    jmp _bit_str_pad_do

_bit_str_pad_left:                  // rdi=строка, rsi=ширина, rdx=заполнитель, rcx=строка
    xor r8d, r8d
    jmp _bit_str_pad_do

_bit_str_pad_do:                    // rdi=строка, rsi=ширина в символах, rdx=заполнитель, rcx=строка, r8=направление
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov rbx, rdi
    mov r12, rsi
    mov r13, rcx
    mov r14d, r8d
    mov r15, rdx
    test r12, r12
    js 99f
    mov rax, 1000000
    cmp r12, rax
    jg 99f
    mov rdi, rbx
    call _strlen
    mov [rsp], rax
    xor rcx, rcx
    xor rax, rax
1:  cmp rcx, [rsp]
    jge 2f
    movzx edx, byte ptr [rbx + rcx]
    and edx, 0xC0
    cmp edx, 0x80
    je 11f
    inc rax
11: inc rcx
    jmp 1b
2:  mov [rsp + 8], rax
    mov byte ptr [rsp + 32], 32
    mov qword ptr [rsp + 16], 1
    test r15, r15
    jz 5f
    movzx eax, byte ptr [r15]
    test eax, eax
    jz 5f
    mov byte ptr [rsp + 32], al
    mov ecx, 1
    cmp eax, 0xC0
    jb 52f
    and eax, 0xF0
    cmp eax, 0xE0
    je 53f
    cmp eax, 0xF0
    je 54f
    mov ecx, 2
    jmp 52f
53: mov ecx, 3
    jmp 52f
54: mov ecx, 4
52: mov [rsp + 16], rcx
    cmp rcx, 1
    jbe 5f
    mov rdx, 1
55: movzx eax, byte ptr [r15 + rdx]
    mov [rsp + 32 + rdx], al
    inc rdx
    cmp rdx, rcx
    jb 55b
5:  mov rax, [rsp + 8]
    cmp r12, rax
    jg 6f
    mov rdi, rbx
    mov rsi, [rsp]
    call _bit_substr
    jmp 8f
6:  mov rax, r12
    sub rax, [rsp + 8]
    mov [rsp + 48], rax
    imul rax, [rsp + 16]
    add rax, [rsp]
    mov [rsp + 24], rax
    lea rdi, [rax + 1]
    call _bit_alloc
    mov r15, rax
    test r14d, r14d
    jz 20f
    mov rdi, r15
    mov rsi, rbx
    mov rdx, [rsp]
    call _memcpy
    mov r9, [rsp + 48]
    mov r10, [rsp + 16]
    mov r8, [rsp]
    xor r11, r11
10: cmp r11, r9
    jge 30f
    xor rcx, rcx
12: cmp rcx, r10
    jge 13f
    movzx eax, byte ptr [rsp + 32 + rcx]
    mov [r15 + r8], al
    inc r8
    inc rcx
    jmp 12b
13: inc r11
    jmp 10b
20: mov r9, [rsp + 48]
    mov r10, [rsp + 16]
    xor r8, r8
    xor r11, r11
21: cmp r11, r9
    jge 22f
    xor rcx, rcx
23: cmp rcx, r10
    jge 24f
    movzx eax, byte ptr [rsp + 32 + rcx]
    mov [r15 + r8], al
    inc r8
    inc rcx
    jmp 23b
24: inc r11
    jmp 21b
22: mov rdi, r15
    add rdi, r8
    mov rsi, rbx
    mov rdx, [rsp]
    call _memcpy
30: mov rax, [rsp + 24]
    mov byte ptr [r15 + rax], 0
    mov rax, r15
8:  add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
99: lea rdi, [rip + Lrt_epad_width]
    mov rsi, r13
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_str_repeat:                    // rdi=строка, rsi=раз, rdx=строка → строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    js 9f
    mov rax, 100000000
    cmp r12, rax
    jg 9f
    call _strlen
    mov r14, rax
    test r12, r12
    jz 5f
    mov rax, r14
    mul r12
    jc 9f
    mov r15, rax
    cmp r15, 100000000
    jg 9f
    lea rdi, [r15 + 1]
    call _bit_alloc
    mov r8, rax
    xor r9d, r9d
1:  cmp r9, r12
    jge 3f
    mov rdi, r8
    mov rax, r9
    imul rax, r14
    add rdi, rax
    mov rsi, rbx
    mov rdx, r14
    push r8
    push r9
    call _memcpy
    pop r9
    pop r8
    inc r9
    jmp 1b
3:  mov byte ptr [r8 + r15], 0
    mov rax, r8
    jmp 8f
5:  mov edi, 1
    call _bit_alloc
    mov byte ptr [rax], 0
8:  add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_epad_count]
    mov rsi, r13
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_num_hex:                       // rdi=число, rsi=ширина, rdx=строка → строка в hex
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    js 9f
    cmp r12, 64
    jg 9f
    lea r14, [rip + Lrt_hex]
    mov rax, rbx
    mov ecx, 1
1:  mov rdx, rax
    shr rdx, 4
    jz 2f
    mov rax, rdx
    inc ecx
    jmp 1b
2:  mov r8, rcx
    cmp r8, r12
    jge 3f
    mov r8, r12
3:  lea rdi, [r8 + 1]
    mov [rsp + 16], r8
    call _bit_alloc
    mov r9, rax
    mov r8, [rsp + 16]
    mov rcx, r8
    mov rax, rbx
4:  test rcx, rcx
    jz 6f
    dec rcx
    mov rdx, rax
    and rdx, 0x0F
    movzx edx, byte ptr [r14 + rdx]
    mov [r9 + rcx], dl
    shr rax, 4
    jmp 4b
6:  mov byte ptr [r9 + r8], 0
    mov rax, r9
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_ehex_width]
    mov rsi, r13
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_dec_fixed:                     // rdi=биты dec, rsi=знаков после точки, rdx=строка → строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    js 9f
    cmp r12, 17
    jg 9f
    mov edi, 512
    call _bit_alloc
    mov r14, rax
    mov rdi, rax
    xor eax, eax
    mov esi, 512
    lea rdx, [rip + Lrt_fp]
    mov ecx, r12d
    movq xmm0, rbx
    mov eax, 1
    call _snprintf
    mov rdi, r14
    call _strlen
    mov rsi, rax
    mov rdi, r14
    call _bit_substr
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_efixed_places]
    mov rsi, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_str_split:                     // rdi=строка, rsi=разделитель → mas строк
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call _strlen
    mov r13, rax
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r14, rax
    test r13, r13
    jnz 10f
    mov rdi, rbx
    call _strlen
    mov rsi, rax
    mov rdi, rbx
    call _bit_substr
    mov rsi, rax
    mov rdi, r14
    xor edx, edx
    call _bit_mas_add
    jmp 9f
10: mov r15, rbx
11: movzx eax, byte ptr [r15]
    test al, al
    jz 15f
    xor ecx, ecx
12: cmp rcx, r13
    jge 16f
    movzx eax, byte ptr [r15 + rcx]
    movzx edx, byte ptr [r12 + rcx]
    cmp al, dl
    jne 17f
    inc rcx
    jmp 12b
17: inc r15
    jmp 11b
16: mov rdi, rbx
    mov rsi, r15
    sub rsi, rbx
    call _bit_substr
    mov rsi, rax
    mov rdi, r14
    xor edx, edx
    call _bit_mas_add
    lea rbx, [r15 + r13]
    jmp 10b
15: mov rdi, rbx
    mov rsi, r15
    sub rsi, rbx
    call _bit_substr
    mov rsi, rax
    mov rdi, r14
    xor edx, edx
    call _bit_mas_add
9:  mov rax, r14
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_str_replace:                   // rdi=строка, rsi=что, rdx=на что → новая строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, r12
    call _strlen
    mov r14, rax
    test r14, r14
    jnz 1f
    mov rdi, rbx
    call _strlen
    mov rsi, rax
    mov rdi, rbx
    call _bit_substr
    jmp 9f
1:  mov rdi, r13
    call _strlen
    mov r15, rax
    mov rdi, rbx
    call _strlen
    mov [rsp], rax
    mov r8, rbx
    xor r9d, r9d
2:  movzx eax, byte ptr [r8]
    test al, al
    jz 5f
    xor ecx, ecx
3:  cmp rcx, r14
    jge 4f
    movzx eax, byte ptr [r8 + rcx]
    movzx edx, byte ptr [r12 + rcx]
    cmp al, dl
    jne 6f
    inc rcx
    jmp 3b
4:  inc r9
    add r8, r14
    jmp 2b
6:  inc r8
    jmp 2b
5:  mov rax, r15
    sub rax, r14
    imul rax, r9
    add rax, [rsp]
    lea rdi, [rax + 1]
    call _bit_alloc
    mov r10, rax
    mov r11, rax
    mov r8, rbx
7:  movzx eax, byte ptr [r8]
    test al, al
    jz 11f
    xor ecx, ecx
8:  cmp rcx, r14
    jge 10f
    movzx eax, byte ptr [r8 + rcx]
    movzx edx, byte ptr [r12 + rcx]
    cmp al, dl
    jne 12f
    inc rcx
    jmp 8b
10: xor ecx, ecx
13: cmp rcx, r15
    jge 14f
    movzx eax, byte ptr [r13 + rcx]
    mov [r11], al
    inc r11
    inc rcx
    jmp 13b
14: add r8, r14
    jmp 7b
12: movzx eax, byte ptr [r8]
    mov [r11], al
    inc r11
    inc r8
    jmp 7b
11: mov byte ptr [r11], 0
    mov rax, r10
9:  add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_str_sz:                        // rdi = строка → сколько символов (UTF-8)
    xor eax, eax
1:  movzx ecx, byte ptr [rdi]
    test ecx, ecx
    jz 2f
    inc rdi
    and ecx, 0xC0
    cmp ecx, 0x80
    je 1b
    inc rax
    jmp 1b
2:  ret

// массив: [0] данные, [8] длина, [16] ёмкость, [24] лимит (-1 = нет)
_bit_mas_new:                       // rdi = лимит, rsi = сколько элементов
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov edi, 32
    call _bit_alloc
    mov r13, rax
    mov r14, 4
    cmp r12, r14
    cmovg r14, r12
    lea rdi, [r14*8]
    call _bit_alloc
    mov [r13], rax
    mov [r13 + 8], r12
    mov [r13 + 16], r14
    mov [r13 + 24], rbx
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_mas_add:                       // rdi = массив, rsi = значение, rdx = строка программы
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rax, [rbx + 24]
    mov rcx, [rbx + 8]
    test rax, rax
    js 1f
    cmp rcx, rax
    jl 1f
    lea rdi, [rip + Lrt_full]
    mov rsi, r13
    call _bit_die
1:  mov rdx, [rbx + 16]
    cmp rcx, rdx
    jl 2f
    shl rdx, 1
    mov [rbx + 16], rdx
    mov rdi, [rbx]
    lea rsi, [rdx*8]
    call _realloc
    test rax, rax
    jz _bit_oom
    mov [rbx], rax
2:  mov rax, [rbx]
    mov rcx, [rbx + 8]
    mov [rax + rcx*8], r12
    inc rcx
    mov [rbx + 8], rcx
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_mas_insert:                    // rdi=массив, rsi=i, rdx=значение, rcx=строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rax, [rbx + 24]
    mov rcx, [rbx + 8]
    test rax, rax
    js 1f
    cmp rcx, rax
    jl 1f
    lea rdi, [rip + Lrt_full]
    mov rsi, r14
    call _bit_die
1:  mov rdx, [rbx + 16]
    cmp rcx, rdx
    jl 2f
    shl rdx, 1
    mov [rbx + 16], rdx
    mov rdi, [rbx]
    lea rsi, [rdx*8]
    call _realloc
    test rax, rax
    jz _bit_oom
    mov [rbx], rax
2:  mov rax, [rbx]
    mov rcx, [rbx + 8]
3:  cmp rcx, r12
    jle 4f
    mov rdx, [rax + rcx*8 - 8]
    mov [rax + rcx*8], rdx
    dec rcx
    jmp 3b
4:  mov [rax + r12*8], r13
    mov rcx, [rbx + 8]
    inc rcx
    mov [rbx + 8], rcx
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_mas_remove:                    // rdi=массив, rsi=i
    mov rax, [rdi]
    mov rcx, rsi
    mov rdx, [rdi + 8]
    dec rdx
1:  cmp rcx, rdx
    jge 2f
    mov r8, [rax + rcx*8 + 8]
    mov [rax + rcx*8], r8
    inc rcx
    jmp 1b
2:  mov rcx, [rdi + 8]
    dec rcx
    mov [rdi + 8], rcx
    ret

_bit_ipow:                          // rdi=основание, rsi=степень → rax (целая степень; отриц. → 0)
    mov rax, 1
    test rsi, rsi
    js 2f
    mov rcx, rsi
1:  test rcx, rcx
    jz 3f
    imul rax, rdi
    dec rcx
    jmp 1b
2:  xor eax, eax
3:  ret

_bit_mas_str:                       // rdi = массив, rsi = вид элементов → "(1, 2, 3)"
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
    lea r14, [rip + Lrt_lpar]
1:  cmp r13, [rbx + 8]
    jge 3f
    test r13, r13
    jz 2f
    mov rdi, r14
    lea rsi, [rip + Lrt_comma]
    call _bit_cat
    mov r14, rax
2:  mov rax, [rbx]
    mov rdi, [rax + r13*8]
    mov rsi, r12
    call _bit_to_str
    mov rsi, rax
    mov rdi, r14
    call _bit_cat
    mov r14, rax
    inc r13
    jmp 1b
3:  mov rdi, r14
    lea rsi, [rip + Lrt_rpar]
    call _bit_cat
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_readline:                      // rdi = строка программы → введённый текст
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 16
    mov rbx, rdi
    xor edi, edi
    call _fflush
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 0
    mov rdi, rsp
    lea rsi, [rsp + 8]
    mov rax, [rip + ___stdinp@GOTPCREL]
    mov rdx, [rax]
    call _getline
    test rax, rax
    js 9f
    mov r12, [rsp]
    lea rcx, [r12 + rax]
1:  cmp rcx, r12
    je 2f
    movzx edx, byte ptr [rcx - 1]
    cmp edx, 10
    je 3f
    cmp edx, 13
    jne 2f
3:  dec rcx
    mov byte ptr [rcx], 0
    jmp 1b
2:  mov rax, r12
    add rsp, 16
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_eof]
    mov rsi, rbx
    call _bit_die

_bit_input_num:                     // rdi = есть границы, rsi = от, rdx = до, rcx = строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
1:  mov rdi, r14
    call _bit_readline
    mov r15, rax
    call ___error
    mov dword ptr [rax], 0
    mov rdi, r15
    mov rsi, rsp
    mov edx, 10
    call _strtoll
    mov [rsp + 8], rax
    mov rcx, [rsp]
    cmp rcx, r15
    je 5f
2:  movzx edx, byte ptr [rcx]
    cmp edx, 32
    jne 3f
    inc rcx
    jmp 2b
3:  test edx, edx
    jnz 5f
    call ___error
    cmp dword ptr [rax], 0
    jne 5f
    mov rax, [rsp + 8]
    test rbx, rbx
    jz 4f
    cmp rax, r12
    jl 5f
    cmp rax, r13
    jg 5f
4:  mov rax, [rsp + 8]
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
5:  test rbx, rbx
    jz 6f
    lea rdi, [rip + Lrt_numr]
    mov rsi, r12
    mov rdx, r13
    xor eax, eax
    call _printf
    jmp 1b
6:  lea rdi, [rip + Lrt_num]
    xor eax, eax
    call _printf
    jmp 1b

_bit_input_dec:                     // rdi = есть границы, rsi = от, rdx = до (биты dec), rcx = строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
1:  mov rdi, r14
    call _bit_readline
    mov r15, rax
    call ___error
    mov dword ptr [rax], 0
    mov rdi, r15
    mov rsi, rsp
    call _strtod
    movq rax, xmm0
    mov [rsp + 8], rax
    mov rcx, [rsp]
    cmp rcx, r15
    je 5f
2:  movzx edx, byte ptr [rcx]
    cmp edx, 32
    jne 3f
    inc rcx
    jmp 2b
3:  test edx, edx
    jnz 5f
    call ___error
    cmp dword ptr [rax], 0
    jne 5f
    movq xmm0, [rsp + 8]
    ucomisd xmm0, xmm0
    jp 5f
    test rbx, rbx
    jz 4f
    movq xmm0, [rsp + 8]
    movq xmm1, r12
    ucomisd xmm0, xmm1
    jb 5f
    movq xmm1, r13
    ucomisd xmm0, xmm1
    ja 5f
4:  mov rax, [rsp + 8]
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
5:  test rbx, rbx
    jz 6f
    lea rdi, [rip + Lrt_decr]
    movq xmm0, r12
    movq xmm1, r13
    mov eax, 2
    call _printf
    jmp 1b
6:  lea rdi, [rip + Lrt_dec]
    xor eax, eax
    call _printf
    jmp 1b

_bit_input_str:                     // rdi = строка программы
    jmp _bit_readline

_bit_input_bool:                    // rdi = строка программы
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
1:  mov rdi, rbx
    call _bit_readline
    mov r12, rax
    mov rdi, r12
    lea rsi, [rip + Lrt_true]
    call _strcmp
    test eax, eax
    jz 2f
    mov rdi, r12
    lea rsi, [rip + Lrt_da]
    call _strcmp
    test eax, eax
    jz 2f
    mov rdi, r12
    lea rsi, [rip + Lrt_1]
    call _strcmp
    test eax, eax
    jz 2f
    mov rdi, r12
    lea rsi, [rip + Lrt_false]
    call _strcmp
    test eax, eax
    jz 3f
    mov rdi, r12
    lea rsi, [rip + Lrt_net]
    call _strcmp
    test eax, eax
    jz 3f
    mov rdi, r12
    lea rsi, [rip + Lrt_0]
    call _strcmp
    test eax, eax
    jz 3f
    lea rdi, [rip + Lrt_boolm]
    xor eax, eax
    call _printf
    jmp 1b
2:  mov eax, 1
    jmp 4f
3:  xor eax, eax
4:  pop r12
    pop rbx
    pop rbp
    ret

_bit_errpath:                       // rdi = текст, rsi = путь, rdx = строка программы
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdx
    call _bit_cat
    mov rdi, rax
    mov rsi, rbx
    call _bit_die

_bit_file_read:                     // rdi = путь, rsi = строка -> весь текст (до конца, размер не нужен)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    lea rsi, [rip + Lrt_rb]
    call _fopen
    test rax, rax
    jz 9f
    mov r13, rax
    mov r15, 4096
    mov rdi, r15
    call _bit_alloc
    mov r14, rax
    mov qword ptr [rsp], 0
1:  mov rax, r15
    sub rax, [rsp]
    jnz 2f
    shl r15, 1
    mov rdi, r14
    mov rsi, r15
    call _realloc
    test rax, rax
    jz _bit_oom
    mov r14, rax
2:  mov rdi, r14
    add rdi, [rsp]
    mov esi, 1
    mov rdx, r15
    sub rdx, [rsp]
    mov rcx, r13
    call _fread
    add [rsp], rax
    test rax, rax
    jnz 1b
    mov rdi, r13
    call _ferror
    test eax, eax
    jnz 8f
    mov rax, [rsp]
    cmp rax, r15
    jne 3f
    mov rdi, r14
    lea rsi, [r15 + 1]
    call _realloc
    test rax, rax
    jz _bit_oom
    mov r14, rax
3:  mov rax, [rsp]
    mov byte ptr [r14 + rax], 0
    mov rdi, r13
    call _fclose
    mov rax, r14
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  lea rdi, [rip + Lrt_eread]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath
9:  lea rdi, [rip + Lrt_eopen]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_file_size:                     // rdi = путь, rsi = строка → байты
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    lea rsi, [rip + Lrt_rb]
    call _fopen
    test rax, rax
    jz 9f
    mov r13, rax
    mov rdi, r13
    xor esi, esi
    mov edx, 2
    call _fseek
    test eax, eax
    jnz 8f
    mov rdi, r13
    call _ftell
    test rax, rax
    js 8f
    mov r14, rax
    mov rdi, r13
    call _fclose
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:
    lea rdi, [rip + Lrt_eread]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath
9:
    lea rdi, [rip + Lrt_eopen]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_file_write:                    // rdi = путь, rsi = текст, rdx = строка, rcx = режим ("w"/"a")
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rsi, rcx
    call _fopen
    test rax, rax
    jz 9f
    mov r14, rax
    mov rdi, r12
    mov rsi, r14
    call _fputs
    cmp eax, -1
    je 9f
    mov rdi, r14
    call _fclose
    test eax, eax
    jnz 9f
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:
    lea rdi, [rip + Lrt_ewrite]
    mov rsi, rbx
    mov rdx, r13
    call _bit_errpath

_bit_file_lines:                    // rdi = путь, rsi = строка → mas из строк
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rsi
    call _bit_file_read
    mov rbx, rax
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r13, rax
    mov r14, rbx
1:  movzx eax, byte ptr [rbx]
    test eax, eax
    jz 3f
    cmp eax, 10
    jne 2f
    mov byte ptr [rbx], 0
    mov rdi, r13
    mov rsi, r14
    mov rdx, r12
    call _bit_mas_add
    inc rbx
    mov r14, rbx
    jmp 1b
2:  inc rbx
    jmp 1b
3:  cmp rbx, r14
    je 4f
    mov rdi, r13
    mov rsi, r14
    mov rdx, r12
    call _bit_mas_add
4:  mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_kind:                          // rdi = путь → 0 нет, 1 файл, 2 папка, 3 другое
    push rbp
    mov rbp, rsp
    sub rsp, 160
    mov rsi, rsp
    call "_stat$INODE64"
    test eax, eax
    jnz 1f
    movzx ecx, word ptr [rsp + 4]
    and ecx, 0xF000
    mov eax, 3
    cmp ecx, 0x8000
    jne 2f
    mov eax, 1
    jmp 3f
2:  cmp ecx, 0x4000
    jne 3f
    mov eax, 2
    jmp 3f
1:  xor eax, eax
3:  mov rsp, rbp
    pop rbp
    ret

_bit_dir_exists:                    // rdi = путь → 1 если это папка
    push rbp
    mov rbp, rsp
    call _bit_kind
    cmp rax, 2
    sete al
    movzx eax, al
    pop rbp
    ret

_bit_file_exists:                   // rdi = путь → 1 если это файл
    push rbp
    mov rbp, rsp
    call _bit_kind
    cmp rax, 1
    sete al
    movzx eax, al
    pop rbp
    ret

_bit_file_remove:                   // rdi = путь, rsi = строка: удаляет только файл
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call _bit_kind
    cmp rax, 1
    jne 8f
    mov rdi, rbx
    call _unlink
    test eax, eax
    jnz 9f
    pop r12
    pop rbx
    pop rbp
    ret
8:
    lea rdi, [rip + Lrt_enotfile]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath
9:
    lea rdi, [rip + Lrt_erm]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_dir_remove:                    // rdi = путь, rsi = строка: удаляет только пустую папку
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call _bit_kind
    cmp rax, 2
    jne 8f
    mov rdi, rbx
    call _rmdir
    test eax, eax
    jnz 9f
    pop r12
    pop rbx
    pop rbp
    ret
8:
    lea rdi, [rip + Lrt_enotdir]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath
9:
    lea rdi, [rip + Lrt_erm]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_move:                          // rdi = from, rsi = to, rdx = source line
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call _rename
    test eax, eax
    jz 1f
    call ___error
    // EXDEV
    cmp dword ptr [rax], 18
    jne 9f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call _bit_copy
    mov rdi, rbx
    call _unlink
    test eax, eax
    jnz 9f
1:  add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_emv]
    mov rsi, rbx
    mov rdx, r13
    call _bit_errpath

_bit_copy_temp:                     // rdi = destination path; returns a sibling template
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov esi, 47
    call _strrchr
    xor esi, esi
    test rax, rax
    jz 1f
    sub rax, rbx
    lea rsi, [rax + 1]
1:  mov rdi, rbx
    call _bit_substr
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + Lrt_copy_suffix]
    call _bit_cat
    mov r12, rax
    mov rdi, rbx
    call _free
    mov rax, r12
    pop r12
    pop rbx
    pop rbp
    ret

_bit_copy:                          // Copy through a temporary sibling; replace only on success.
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r15d, r15d
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 0
    mov dword ptr [rsp + 16], -1
    lea rsi, [rip + Lrt_rb]
    call _fopen
    test rax, rax
    jz 9f
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    call _strcmp
    test eax, eax
    jnz 1f
    mov rdi, r14
    call _fclose
    jmp 4f
1:  mov edi, 65536
    call _bit_alloc
    mov [rsp + 8], rax
    mov rdi, r12
    call _bit_copy_temp
    mov [rsp], rax
    mov rdi, rax
    call _mkstemp
    test eax, eax
    js 6f
    mov [rsp + 16], eax
    mov edi, eax
    lea rsi, [rip + Lrt_wb]
    call _fdopen
    test rax, rax
    jz 5f
    mov r15, rax
    mov dword ptr [rsp + 16], -1
2:  mov rdi, [rsp + 8]
    mov esi, 1
    mov edx, 65536
    mov rcx, r14
    call _fread
    test rax, rax
    jz 3f
    mov [rsp + 16], rax
    mov rdx, rax
    mov rdi, [rsp + 8]
    mov esi, 1
    mov rcx, r15
    call _fwrite
    cmp rax, [rsp + 16]
    mov dword ptr [rsp + 16], -1
    jne 5f
    jmp 2b
3:  mov rdi, r14
    call _ferror
    test eax, eax
    jnz 5f
    mov rdi, r15
    xor r15d, r15d
    call _fclose
    test eax, eax
    jnz 5f
    mov rdi, r14
    xor r14d, r14d
    call _fclose
    test eax, eax
    jnz 5f
    mov rdi, [rsp]
    mov rsi, r12
    call _rename
    test eax, eax
    jnz 5f
    mov rdi, [rsp]
    call _free
    mov rdi, [rsp + 8]
    call _free
4:  add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
5:  test r15, r15
    jz 51f
    mov rdi, r15
    call _fclose
51: mov edi, [rsp + 16]
    test edi, edi
    js 52f
    call _close
52: mov rdi, [rsp]
    call _unlink
6:  test r14, r14
    jz 7f
    mov rdi, r14
    call _fclose
7:  mov rdi, [rsp]
    call _free
    mov rdi, [rsp + 8]
    call _free
    lea rdi, [rip + Lrt_ewrite]
    mov rsi, r12
    jmp 8f
9:  lea rdi, [rip + Lrt_eopen]
    mov rsi, rbx
8:  mov rdx, r13
    call _bit_errpath

_bit_dir_make:                      // rdi = путь, rsi = строка; создаёт и все папки на пути
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rsi
    lea rsi, [rip + Lrt_empty]
    call _bit_cat
    mov rbx, rax
    mov r13, rax
    cmp byte ptr [r13], 0
    je 3f
    inc r13
1:  movzx eax, byte ptr [r13]
    test eax, eax
    jz 3f
    cmp eax, 47
    jne 2f
    mov byte ptr [r13], 0
    mov rdi, rbx
    mov esi, 493
    call _mkdir
    mov byte ptr [r13], 47
2:  inc r13
    jmp 1b
3:  mov rdi, rbx
    mov esi, 493
    call _mkdir
    test eax, eax
    jz 4f
    mov rdi, rbx
    call _bit_dir_exists
    test rax, rax
    jz 9f
4:  pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_emk]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_strptr_cmp:
    mov rdi, [rdi]
    mov rsi, [rsi]
    jmp _strcmp

_bit_dir_list:                      // rdi = путь, rsi = строка → mas имён по алфавиту
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    call "_opendir$INODE64"
    test rax, rax
    jz 9f
    mov r13, rax
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r14, rax
1:  mov rdi, r13
    call "_readdir$INODE64"
    test rax, rax
    jz 3f
    lea rdi, [rax + 21]
    cmp byte ptr [rdi], 46
    jne 2f
    movzx eax, byte ptr [rdi + 1]
    test eax, eax
    jz 1b
    cmp eax, 46
    jne 2f
    cmp byte ptr [rdi + 2], 0
    je 1b
2:  lea rsi, [rip + Lrt_empty]
    call _bit_cat
    mov rdi, r14
    mov rsi, rax
    mov rdx, r12
    call _bit_mas_add
    jmp 1b
3:  mov rdi, r13
    call _closedir
    mov rdi, [r14]
    mov rsi, [r14 + 8]
    mov edx, 8
    lea rcx, [rip + _bit_strptr_cmp]
    call _qsort
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_edir]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath




_bit_remove_is_home:                // path -> bool, compare canonical HOME paths
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    lea rdi, [rip + Lrt_remove_home]
    call _getenv
    test rax, rax
    jz 7f
    cmp byte ptr [rax], 0
    je 7f
    mov rdi, rax
    xor esi, esi
    call _realpath
    test rax, rax
    jz 7f
    mov r12, rax
    mov rdi, rbx
    xor esi, esi
    call _realpath
    mov r13, rax
    xor ebx, ebx
    test rax, rax
    jz 1f
    xor ecx, ecx
2:  mov al, [r13 + rcx]
    test al, al
    jz 3f
    cmp al, [r12 + rcx]
    jne 1f
    inc rcx
    jmp 2b
3:  cmp byte ptr [r13 + rcx - 1], 47
    je 4f
    cmp byte ptr [r12 + rcx], 0
    je 4f
    cmp byte ptr [r12 + rcx], 47
    jne 1f
4:  mov ebx, 1
1:  mov rdi, r12
    call _free
    mov rdi, r13
    call _free
    mov rax, rbx
    jmp 8f
7:  xor eax, eax
8:  add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_remove_error:                  // message, owned path, line
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rsi
    mov r12, rdx
    call _bit_cat
    push rax
    push rax
    mov rdi, rbx
    call _free
    pop rdi
    pop rax
    mov rsi, r12
    call _bit_die

_bit_remove_prefix:                 // parent name, owned child error path -> owned full path
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rsi
    lea rsi, [rip + Lrt_slash]
    call _bit_cat
    mov r12, rax
    mov rdi, rax
    mov rsi, rbx
    call _bit_cat
    push rax
    push rax
    mov rdi, r12
    call _free
    mov rdi, rbx
    call _free
    pop rax
    pop rcx
    pop r12
    pop rbx
    pop rbp
    ret

_bit_dir_remove_all:                // path, line; never descend through symbolic links
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov r12, rsi
    lea rsi, [rip + Lrt_empty]
    call _bit_cat
    mov rbx, rax
    mov rdi, rax
    call _strlen
    test rax, rax
    jz 8f
1:  cmp rax, 1
    jbe 2f
    cmp byte ptr [rbx + rax - 1], 47
    jne 2f
    dec rax
    mov byte ptr [rbx + rax], 0
    jmp 1b
2:  cmp byte ptr [rbx], 47
    jne 3f
    cmp byte ptr [rbx + 1], 0
    je 8f
3:  mov rdi, rbx
    mov esi, 47
    call _strrchr
    test rax, rax
    jnz 4f
    lea rax, [rbx - 1]
4:  inc rax
    cmp byte ptr [rax], 46
    jne 5f
    cmp byte ptr [rax + 1], 0
    je 8f
    cmp byte ptr [rax + 1], 46
    jne 5f
    cmp byte ptr [rax + 2], 0
    je 8f
5:  mov rdi, rbx
    call _bit_remove_is_home
    test rax, rax
    jnz 11f
    mov rdi, -2
    mov rsi, rbx
    mov rdx, r12
    mov ecx, 1
    call _bit_remove_at
    mov r13, rax
    mov rdi, rbx
    call _free
    test r13, r13
    jnz 9f
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  lea rdi, [rip + Lrt_ermroot]
    mov rsi, rbx
    mov rdx, r12
    call _bit_remove_error
11: lea rdi, [rip + Lrt_ermhome]
    mov rsi, rbx
    mov rdx, r12
    call _bit_remove_error
9:  lea rdi, [rip + Lrt_ermtree]
    mov rsi, r13
    mov rdx, r12
    call _bit_remove_error

_bit_remove_at:                     // parent fd, name, line, require directory -> 0/owned error path
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 184
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp + 160], rcx
    mov rdx, rsp
    mov ecx, 32
    call "_fstatat$INODE64"
    test eax, eax
    jnz 9f
    movzx ecx, word ptr [rsp + 4]
    and ecx, 0xf000
    cmp ecx, 0x4000
    je 2f
    cmp qword ptr [rsp + 160], 0
    je 1f
    cmp ecx, 0xa000
    jne 9f
1:  mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call _unlinkat
    test eax, eax
    jnz 9f
    jmp 7f
2:  mov rdi, rbx
    mov rsi, r12
    mov edx, 0x100100
    xor eax, eax
    call _openat
    test eax, eax
    js 9f
    mov r15d, eax
    mov edi, eax
    call "_fdopendir$INODE64"
    test rax, rax
    jz 6f
    mov r14, rax
3:  call ___error
    mov dword ptr [rax], 0
    mov rdi, r14
    call "_readdir$INODE64"
    test rax, rax
    jz 5f
    lea rsi, [rax + 21]
    cmp byte ptr [rsi], 46
    jne 4f
    cmp byte ptr [rsi + 1], 0
    je 3b
    cmp byte ptr [rsi + 1], 46
    jne 4f
    cmp byte ptr [rsi + 2], 0
    je 3b
4:  mov edi, r15d
    mov rdx, r13
    xor ecx, ecx
    call _bit_remove_at
    test rax, rax
    jnz 8f
    jmp 3b
5:  call ___error
    cmp dword ptr [rax], 0
    jne 11f
    mov rdi, r14
    call _closedir
    test eax, eax
    jnz 9f
    mov rdi, rbx
    mov rsi, r12
    mov edx, 128
    call _unlinkat
    test eax, eax
    jnz 9f
    jmp 7f
6:  mov edi, r15d
    call _close
    jmp 9f
7:  xor eax, eax
    jmp 10f
8:  mov [rsp + 168], rax
    mov rdi, r14
    call _closedir
    mov rdi, r12
    mov rsi, [rsp + 168]
    call _bit_remove_prefix
    jmp 10f
11: mov rdi, r14
    call _closedir
9:  mov rdi, r12
    lea rsi, [rip + Lrt_empty]
    call _bit_cat
10: add rsp, 184
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_path_mode:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 160
    mov rbx, rdi
    mov r12, rsi
    mov rsi, rsp
    call "_stat$INODE64"
    test eax, eax
    jnz 9f
    movzx eax, word ptr [rsp + 4]
    add rsp, 160
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_epermread]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_mode_set:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rdx
    call _chmod
    test eax, eax
    jnz 9f
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_epermwrite]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_permissions_parse:             // text, line -> permission bits
    xor eax, eax
    xor ecx, ecx
    mov r8d, 256
    lea r9, [rip + Lrt_permchars]
1:  movzx edx, byte ptr [rdi + rcx]
    cmp dl, 45
    je 2f
    cmp dl, byte ptr [r9 + rcx]
    jne 9f
    or eax, r8d
2:  shr r8d, 1
    inc ecx
    cmp ecx, 9
    jne 1b
    cmp byte ptr [rdi + 9], 0
    jne 9f
    ret
9:  lea rdi, [rip + Lrt_epermissions]
    jmp _bit_die

_bit_permissions_text:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov edi, 10
    call _bit_alloc
    xor ecx, ecx
    mov edx, 256
    lea r8, [rip + Lrt_permchars]
1:  mov r9b, 45
    test ebx, edx
    jz 2f
    mov r9b, byte ptr [r8 + rcx]
2:  mov byte ptr [rax + rcx], r9b
    shr edx, 1
    inc ecx
    cmp ecx, 9
    jne 1b
    mov byte ptr [rax + 9], 0
    pop r12
    pop rbx
    pop rbp
    ret

_bit_permissions_get:
    push rbp
    mov rbp, rsp
    call _bit_path_mode
    mov rdi, rax
    call _bit_permissions_text
    pop rbp
    ret

_bit_permissions_set:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rdx
    mov rdi, rsi
    mov rsi, rdx
    call _bit_permissions_parse
    mov rdi, rbx
    mov rsi, rax
    mov rdx, r12
    call _bit_mode_set
    pop r12
    pop rbx
    pop rbp
    ret

_bit_read_only_get:
    push rbp
    mov rbp, rsp
    call _bit_path_mode
    test eax, 146
    sete al
    movzx eax, al
    pop rbp
    ret

_bit_read_only_set:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rsi, rdx
    call _bit_path_mode
    and eax, 4095
    test r12, r12
    jz 1f
    and eax, -147
    jmp 2f
1:  or eax, 146
2:  mov rdi, rbx
    mov rsi, rax
    mov rdx, r13
    call _bit_mode_set
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_lkind:                         // rdi = путь → как _bit_kind, но ссылка — 3 (не заходим по ней)
    push rbp
    mov rbp, rsp
    sub rsp, 160
    mov rsi, rsp
    call "_lstat$INODE64"
    test eax, eax
    jnz 1f
    movzx ecx, word ptr [rsp + 4]
    and ecx, 0xF000
    mov eax, 3
    cmp ecx, 0x8000
    jne 2f
    mov eax, 1
    jmp 3f
2:  cmp ecx, 0x4000
    jne 3f
    mov eax, 2
    jmp 3f
1:  xor eax, eax
3:  mov rsp, rbp
    pop rbp
    ret

_bit_file_mtime:                    // rdi = путь, rsi = строка → время изменения (секунды с 1970)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 160
    mov rbx, rdi
    mov r12, rsi
    mov rsi, rsp
    call "_stat$INODE64"
    test eax, eax
    jnz 9f
    mov rax, qword ptr [rsp + 48]       // st_mtime
    add rsp, 160
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_eread]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_dir_walk:                      // rdi = путь, rsi = строка → mas путей ко всем файлам внутри
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    push rax
    push rax
    mov rdi, rbx
    mov rsi, rax
    mov rdx, r12
    call _bit_walk_into
    pop rax
    pop rcx
    pop r12
    pop rbx
    pop rbp
    ret

_bit_walk_into:                     // rdi = путь, rsi = mas, rdx = строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rsi, r13
    call _bit_dir_list
    mov r14, rax
    xor r15d, r15d
1:  cmp r15, [r14 + 8]
    jge 5f
    mov rdi, rbx
    lea rsi, [rip + Lrt_slash]
    call _bit_cat
    mov rdi, rax
    mov rcx, [r14]
    mov rsi, [rcx + r15*8]
    call _bit_cat
    mov [rsp], rax
    mov rdi, rax
    call _bit_lkind
    cmp rax, 2
    jne 2f
    mov rdi, [rsp]
    mov rsi, r12
    mov rdx, r13
    call _bit_walk_into
    jmp 4f
2:  mov rdi, [rsp]
    call _bit_kind
    cmp rax, 1
    jne 4f
    mov rdi, r12
    mov rsi, [rsp]
    mov rdx, r13
    call _bit_mas_add
4:  inc r15
    jmp 1b
5:  add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


_bit_path_info:                     // path, line -> path, size, modified, kind
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 160
    mov rbx, rdi
    mov r12, rsi
    mov rsi, rsp
    call "_lstat$INODE64"
    test eax, eax
    jnz 9f
    movzx ecx, word ptr [rsp + 4]
    and ecx, 0xf000
    cmp ecx, 0xa000
    jne 1f
    mov rdi, rbx
    mov rsi, rsp
    call "_stat$INODE64"
    test eax, eax
    jnz 7f
    movzx ecx, word ptr [rsp + 4]
    and ecx, 0xf000
    cmp ecx, 0x8000
    jne 7f
1:  mov r13d, 1
    cmp ecx, 0x8000
    je 2f
    mov r13d, 2
    cmp ecx, 0x4000
    jne 7f
2:  mov edi, 32
    call _bit_alloc
    mov [rax], rbx
    mov rdx, qword ptr [rsp + 96]
    mov [rax + 8], rdx
    mov rdx, qword ptr [rsp + 48]
    mov [rax + 16], rdx
    mov [rax + 24], r13
    jmp 8f
7:  xor eax, eax
8:  add rsp, 160
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_eread]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_dir_walk_info:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r13, rax
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r12
    call _bit_walk_info_into
    mov rax, r13
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_walk_info_into:                // path, output array, line
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rsi, rdx
    call _bit_dir_list
    mov r14, rax
    xor r15d, r15d
1:  cmp r15, [r14 + 8]
    jge 5f
    mov rdi, rbx
    lea rsi, [rip + Lrt_slash]
    call _bit_cat
    mov [rsp + 8], rax
    mov rdi, rax
    mov rcx, [r14]
    mov rsi, [rcx + r15*8]
    call _bit_cat
    mov [rsp], rax
    mov rdi, [rsp + 8]
    call _free
    mov rdi, [rsp]
    mov rsi, r13
    call _bit_path_info
    test rax, rax
    jz 4f
    cmp qword ptr [rax + 24], 2
    jne 2f
    mov [rsp + 8], rax
    mov rdi, [rsp]
    mov rsi, r12
    mov rdx, r13
    call _bit_walk_info_into
    mov rdi, [rsp + 8]
    call _free
    jmp 4f
2:  mov rdi, r12
    mov rsi, rax
    mov rdx, r13
    call _bit_mas_add
    jmp 3f
4:  mov rdi, [rsp]
    call _free
3:  mov rax, [r14]
    mov rdi, [rax + r15*8]
    call _free
    inc r15
    jmp 1b
5:  mov rdi, [r14]
    call _free
    mov rdi, r14
    call _free
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

// ── proc (macOS): процессы без доступа к их памяти ──
_bit_mac_pname:                     // rdi = pid, rsi = буфер 256 байт → длина имени или 0
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 688
    mov rbx, rdi
    mov r12, rsi
    mov edx, 256
    call _proc_name
    test eax, eax
    jg 9f
    // чужие системные процессы: имя через sysctl (как у ps)
    mov dword ptr [rsp], 1
    mov dword ptr [rsp + 4], 14
    mov dword ptr [rsp + 8], 1
    mov dword ptr [rsp + 12], ebx
    mov qword ptr [rsp + 16], 648
    lea rdi, [rsp]
    mov esi, 4
    lea rdx, [rsp + 32]
    lea rcx, [rsp + 16]
    xor r8d, r8d
    xor r9d, r9d
    call _sysctl
    test eax, eax
    jnz 0f
    cmp qword ptr [rsp + 16], 648
    jne 0f
    mov rdi, r12
    lea rsi, [rsp + 275]
    mov edx, 17
    call _strlcpy
    test eax, eax
    jg 9f
0:  xor eax, eax
9:  add rsp, 688
    pop r12
    pop rbx
    pop rbp
    ret

_bit_proc_start:                    // rdi = команда, rsi = строка → pid (через /bin/sh -c)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 48
    mov rbx, rdi
    mov r12, rsi
    xor edi, edi
    call _fflush
    lea rax, [rip + Lrt_msh]
    mov [rsp + 8], rax
    lea rax, [rip + Lrt_mdashc]
    mov [rsp + 16], rax
    mov [rsp + 24], rbx
    mov qword ptr [rsp + 32], 0
    mov rdi, rsp
    lea rsi, [rip + Lrt_mbinsh]
    xor edx, edx
    xor ecx, ecx
    lea r8, [rsp + 8]
    mov rax, [rip + _environ@GOTPCREL]
    mov r9, [rax]
    call _posix_spawn
    test eax, eax
    jnz 9f
    movsxd rax, dword ptr [rsp]
    add rsp, 48
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_mespawn]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_proc_find:                     // rdi = имя, rsi = строка → pid первого процесса с таким именем или -1
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 264
    mov rbx, rdi
    mov r12, rsi
    mov edi, 262144
    call _malloc
    test rax, rax
    jz 8f
    mov r13, rax
    mov rdi, r13
    mov esi, 262144
    call _proc_listallpids
    movsxd r14, eax
    xor r15d, r15d
1:  cmp r15, r14
    jge 7f
    mov edi, dword ptr [r13 + r15*4]
    test edi, edi
    jle 2f
    mov rsi, rsp
    mov edx, 256
    call _bit_mac_pname
    test eax, eax
    jle 2f
    mov rdi, rsp
    mov rsi, rbx
    call _strcmp
    test eax, eax
    jz 6f
2:  inc r15
    jmp 1b
6:  movsxd r14, dword ptr [r13 + r15*4]
    jmp 5f
7:  mov r14, -1
5:  mov rdi, r13
    call _free
    mov rax, r14
    jmp 4f
8:  mov rax, -1
4:  add rsp, 264
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_proc_alive:                    // rdi = pid → 1 если процесс работает (завершённый, но не дождавшийся — нет)
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 152
    mov rbx, rdi
    test rdi, rdi
    jle 0f
    mov esi, 3
    xor edx, edx
    mov rcx, rsp
    mov r8d, 136
    call _proc_pidinfo
    cmp eax, 136
    jne 3f
    cmp dword ptr [rsp + 4], 5
    je 0f
    mov eax, 1
    jmp 9f
3:  mov rdi, rbx
    xor esi, esi
    call _kill
    test eax, eax
    jz 1f
    call ___error
    cmp dword ptr [rax], 1
    jne 0f
1:  mov eax, 1
    jmp 9f
0:  xor eax, eax
9:  add rsp, 152
    pop rbx
    pop rbp
    ret

_bit_proc_name:                     // rdi = pid → имя процесса или ""
    push rbp
    mov rbp, rsp
    sub rsp, 272
    test rdi, rdi
    jle 1f
    mov rsi, rsp
    mov edx, 256
    call _bit_mac_pname
    test eax, eax
    jle 1f
    mov rdi, rsp
    lea rsi, [rip + Lrt_empty]
    call _bit_cat
    jmp 2f
1:  lea rdi, [rip + Lrt_empty]
    mov rsi, rdi
    call _bit_cat
2:  mov rsp, rbp
    pop rbp
    ret

_bit_proc_wait:                     // rdi = pid → код выхода (-1, если это не наш процесс)
    push rbp
    mov rbp, rsp
    sub rsp, 16
    test rdi, rdi
    jle 1f
    mov rsi, rsp
    xor edx, edx
    call _waitpid
    test eax, eax
    js 1f
    mov edi, dword ptr [rsp]
    call _bit_wstatus
    jmp 2f
1:  mov rax, -1
2:  mov rsp, rbp
    pop rbp
    ret

_bit_proc_kill:                     // rdi = pid, rsi = строка: просит процесс завершиться (SIGTERM)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    test rdi, rdi
    jle 9f
    mov esi, 15
    call _kill
    test eax, eax
    jnz 9f
    pop r12
    pop rbx
    pop rbp
    ret
9:  mov rdi, rbx
    call _bit_num_str
    lea rdi, [rip + Lrt_mekill]
    mov rsi, rax
    mov rdx, r12
    call _bit_errpath
// ── конец proc (macOS) ──

_bit_basename:                      // rdi = путь → имя после последнего /
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov esi, 47
    call _strrchr
    test rax, rax
    jz 1f
    inc rax
    jmp 2f
1:  mov rax, rbx
2:  pop r12
    pop rbx
    pop rbp
    ret

_bit_wstatus:                       // edi = статус wait → код выхода (сигнал → 128+номер), запоминает его
    mov eax, edi
    cmp eax, -1
    je 2f
    mov ecx, eax
    and ecx, 0x7f
    jnz 1f
    shr eax, 8
    and eax, 0xff
    jmp 3f
1:  lea eax, [rcx + 128]
    jmp 3f
2:  mov eax, 127
3:  mov [rip + Lrt_status], rax
    ret

_bit_status:                        // → код выхода последней команды
    mov rax, [rip + Lrt_status]
    ret

_bit_eof:                           // → 1 если ввод закончился
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    xor edi, edi
    call _fflush
    mov rax, [rip + ___stdinp@GOTPCREL]
    mov rbx, [rax]
    mov rdi, rbx
    call _getc
    cmp eax, -1
    je 1f
    mov edi, eax
    mov rsi, rbx
    call _ungetc
    xor eax, eax
    jmp 2f
1:  mov eax, 1
2:  pop r12
    pop rbx
    pop rbp
    ret

_bit_run_live:                      // rdi = команда: вывод сразу в терминал
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    xor edi, edi
    call _fflush
    mov rdi, rbx
    call _system
    mov edi, eax
    call _bit_wstatus
    pop r12
    pop rbx
    pop rbp
    ret

_bit_run:                           // rdi = команда, rsi = строка → её вывод
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    xor edi, edi
    call _fflush
    mov rdi, rbx
    lea rsi, [rip + Lrt_r]
    call _popen
    test rax, rax
    jz 9f
    mov r13, rax
    mov r14, 4096
    mov rdi, r14
    call _bit_alloc
    mov r15, rax
    mov qword ptr [rsp], 0
1:  mov rax, [rsp]
    lea rdi, [r15 + rax]
    mov esi, 1
    mov rdx, r14
    sub rdx, rax
    dec rdx
    mov rcx, r13
    call _fread
    test rax, rax
    jz 3f
    add [rsp], rax
    mov rax, [rsp]
    lea rdx, [r14 - 1]
    cmp rax, rdx
    jl 1b
    shl r14, 1
    mov rdi, r15
    mov rsi, r14
    call _realloc
    test rax, rax
    jz _bit_oom
    mov r15, rax
    jmp 1b
3:  mov rax, [rsp]
    test rax, rax
    jz 4f
    cmp byte ptr [r15 + rax - 1], 10
    jne 4f
    dec rax
    mov [rsp], rax
4:  mov rax, [rsp]
    mov byte ptr [r15 + rax], 0
    mov rdi, r13
    call _pclose
    mov edi, eax
    call _bit_wstatus
    mov rax, r15
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_erun]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_args:                          // → mas из аргументов командной строки
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov rbx, rax
    mov r12, [rip + Lrt_argc]
    mov r13, [rip + Lrt_argv]
    mov r14, 1
1:  cmp r14, r12
    jge 2f
    mov rdi, rbx
    mov rsi, [r13 + r14*8]
    xor edx, edx
    call _bit_mas_add
    inc r14
    jmp 1b
2:  mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_env:                           // rdi = имя → значение или ""
    push rbp
    mov rbp, rsp
    call _getenv
    test rax, rax
    jnz 1f
    lea rax, [rip + Lrt_empty]
1:  mov rdi, rax
    lea rsi, [rip + Lrt_empty]
    call _bit_cat
    pop rbp
    ret

_bit_term_folder:                   // rdi = строка программы → текущая папка (новая строка)
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rdi
    xor edi, edi
    xor esi, esi
    call _getcwd
    test rax, rax
    jz 9f
    add rsp, 8
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_ecwd]
    mov rsi, rbx
    call _bit_die

_bit_term_go:                       // rdi = путь, rsi = строка программы
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call _chdir
    test eax, eax
    jnz 9f
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_ego]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_env_set:                       // rdi = имя, rsi = значение, rdx = строка программы
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rdx
    mov edx, 1
    call _setenv
    test eax, eax
    jnz 9f
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_eenv]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_clear:
    push rbp
    mov rbp, rsp
    lea rdi, [rip + Lrt_cls]
    xor eax, eax
    call _printf
    xor edi, edi
    call _fflush
    pop rbp
    ret

_bit_wait:                          // rdi = milliseconds
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32                    // timespec request and remainder
    mov rbx, rdi
    xor edi, edi
    call _fflush
1:  test rbx, rbx
    jle 3f
    mov r12, 1000
    cmp rbx, r12
    cmovl r12, rbx
    sub rbx, r12
    mov rax, r12
    xor edx, edx
    mov ecx, 1000
    div rcx
    mov [rsp], rax
    imul rdx, rdx, 1000000
    mov [rsp + 8], rdx
2:  mov rdi, rsp
    lea rsi, [rsp + 16]
    call _nanosleep
    test eax, eax
    jz 1b
    call ___error
    cmp dword ptr [rax], 4         // EINTR
    jne 3f
    mov rax, [rsp + 16]
    mov rdx, [rsp + 24]
    mov [rsp], rax
    mov [rsp + 8], rdx
    jmp 2b
3:  add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

_bit_exit:                          // rdi = код выхода
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    xor edi, edi
    call _fflush
    mov rdi, rbx
    call _exit

_bit_mem_used:                      // → сколько байт памяти программа заняла (пик)
    push rbp
    mov rbp, rsp
    sub rsp, 160
    xor edi, edi
    mov rsi, rsp
    call _getrusage
    mov rax, [rsp + 32]
    mov rsp, rbp
    pop rbp
    ret

_bit_mem_total:                     // → сколько байт памяти в компьютере
    push rbp
    mov rbp, rsp
    sub rsp, 16
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 8
    lea rdi, [rip + Lrt_memsize]
    mov rsi, rsp
    lea rdx, [rsp + 8]
    xor ecx, ecx
    xor r8d, r8d
    call _sysctlbyname
    mov rax, [rsp]
    mov rsp, rbp
    pop rbp
    ret

_bit_str_bytes:                     // rdi = строка → mas из байтов
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    call _strlen
    mov r12, rax
    mov rdi, -1
    mov rsi, r12
    call _bit_mas_new
    mov r13, rax
    mov rdx, [r13]
    xor ecx, ecx
1:  cmp rcx, r12
    jge 2f
    movzx eax, byte ptr [rbx + rcx]
    mov [rdx + rcx*8], rax
    inc rcx
    jmp 1b
2:  mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_mas_text:                      // rdi = mas байтов, rsi = от, rdx = до → строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    xor eax, eax
    test rsi, rsi
    cmovl rsi, rax
    mov rax, [rbx + 8]
    cmp rdx, rax
    cmovg rdx, rax
    cmp rdx, rsi
    cmovl rdx, rsi
    mov r12, rsi
    mov r13, rdx
    sub r13, rsi
    lea rdi, [r13 + 1]
    call _bit_alloc
    mov r14, rax
    mov rdx, [rbx]
    xor ecx, ecx
1:  cmp rcx, r13
    jge 2f
    lea rax, [r12 + rcx]
    mov rax, [rdx + rax*8]
    mov [r14 + rcx], al
    inc rcx
    jmp 1b
2:  mov byte ptr [r14 + r13], 0
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_mas_join:                      // rdi = mas строк, rsi = разделитель → одна строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    call _strlen
    mov r13, rax
    xor r14d, r14d
    xor r15d, r15d
1:  cmp r15, [rbx + 8]
    jge 2f
    mov rax, [rbx]
    mov rdi, [rax + r15*8]
    call _strlen
    add r14, rax
    add r14, r13
    inc r15
    jmp 1b
2:  lea rdi, [r14 + 1]
    call _bit_alloc
    mov [rsp], rax
    mov r14, rax
    xor r15d, r15d
3:  cmp r15, [rbx + 8]
    jge 5f
    test r15, r15
    jz 4f
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call _memcpy
    add r14, r13
4:  mov rax, [rbx]
    mov rdi, [rax + r15*8]
    call _strlen
    mov [rsp + 8], rax
    mov rdx, rax
    mov rax, [rbx]
    mov rsi, [rax + r15*8]
    mov rdi, r14
    call _memcpy
    add r14, [rsp + 8]
    inc r15
    jmp 3b
5:  mov byte ptr [r14], 0
    mov rax, [rsp]
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_mas_slice:                     // rdi = массив, rsi = от, rdx = до (включительно) → новый массив
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    xor eax, eax
    test rsi, rsi
    cmovl rsi, rax
    mov rax, [rbx + 8]
    dec rax
    cmp rdx, rax
    cmovg rdx, rax
    mov r13, rdx
    sub r13, rsi
    inc r13
    xor eax, eax
    test r13, r13
    cmovl r13, rax
    mov r12, rsi
    mov rdi, -1
    mov rsi, r13
    call _bit_mas_new
    mov r14, rax
    mov rdx, [rbx]
    mov r8, [r14]
    xor ecx, ecx
1:  cmp rcx, r13
    jge 2f
    lea rax, [r12 + rcx]
    mov rax, [rdx + rax*8]
    mov [r8 + rcx*8], rax
    inc rcx
    jmp 1b
2:  mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_str_slice:                     // rdi = строка, rsi = от, rdx = до (символы, включительно) → строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    xor eax, eax
    test rsi, rsi
    cmovl rsi, rax
    cmp rdx, rsi
    jl 8f
    mov r12, rdx
    sub r12, rsi
    xor ecx, ecx
1:  cmp rcx, rsi
    jge 2f
    movzx eax, byte ptr [rbx]
    test eax, eax
    jz 2f
    inc rbx
3:  movzx eax, byte ptr [rbx]
    and eax, 0xC0
    cmp eax, 0x80
    jne 4f
    inc rbx
    jmp 3b
4:  inc rcx
    jmp 1b
2:  mov r13, rbx
5:  test r12, r12
    js 6f
    movzx eax, byte ptr [rbx]
    test eax, eax
    jz 6f
    inc rbx
7:  movzx eax, byte ptr [rbx]
    and eax, 0xC0
    cmp eax, 0x80
    jne 9f
    inc rbx
    jmp 7b
9:  dec r12
    jmp 5b
6:  mov r14, rbx
    sub r14, r13
    lea rdi, [r14 + 1]
    call _bit_alloc
    mov r12, rax
    mov rdi, rax
    mov rsi, r13
    mov rdx, r14
    call _memcpy
    mov byte ptr [r12 + r14], 0
    mov rax, r12
    jmp 10f
8:  lea rdi, [rip + Lrt_empty]
    xor esi, esi
    call _bit_substr
10: pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_file_line:                     // path, index, source line -> independent copy
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rsi
    mov rsi, rdx
    call _bit_file_read
    mov rbx, rax
    mov r13, rax
    test r12, r12
    js 4f
1:  test r12, r12
    jz 2f
    movzx eax, byte ptr [r13]
    inc r13
    test al, al
    jz 4f
    cmp al, 10
    jne 1b
    dec r12
    jmp 1b
2:  mov r14, r13
3:  mov al, [r13]
    test al, al
    jz 5f
    cmp al, 10
    je 5f
    inc r13
    jmp 3b
4:  lea r14, [rip + Lrt_empty]
    mov r13, r14
5:  mov rdi, r14
    mov rsi, r13
    sub rsi, r14
    call _bit_substr
    mov r12, rax
    mov rdi, rbx
    call _free
    mov rax, r12
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_file_slice:                    // rdi = путь, rsi = от, rdx = до, rcx = строка программы
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rsi
    mov r12, rdx
    mov rsi, rcx
    call _bit_file_lines
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r12
    call _bit_mas_slice
    pop r12
    pop rbx
    pop rbp
    ret

_bit_mas_sum:                       // rdi = массив, rsi = вид (0 num, 1 dec), rdx = строка программы
    mov r8, [rdi]
    mov r9, [rdi + 8]
    xor ecx, ecx
    cmp rsi, 1
    je 5f
    xor eax, eax
1:  cmp rcx, r9
    jge 8f
    add rax, [r8 + rcx*8]
    jo 9f
    inc rcx
    jmp 1b
5:  xorpd xmm0, xmm0
6:  cmp rcx, r9
    jge 7f
    addsd xmm0, [r8 + rcx*8]
    inc rcx
    jmp 6b
7:  movq rax, xmm0
8:  ret
9:  and rsp, -16
    lea rdi, [rip + Lrt_ovf]
    mov rsi, rdx
    call _bit_die

_bit_cmp_num:
    mov rax, [rdi]
    mov rcx, [rsi]
    cmp rax, rcx
    setg al
    setl cl
    movzx eax, al
    movzx ecx, cl
    sub eax, ecx
    ret

_bit_cmp_dec:
    movsd xmm0, [rdi]
    movsd xmm1, [rsi]
    xor eax, eax
    xor ecx, ecx
    ucomisd xmm0, xmm1
    seta al
    ucomisd xmm1, xmm0
    seta cl
    sub eax, ecx
    ret

_bit_mas_sort:                      // rdi = массив, rsi = вид элементов: сортирует на месте
    push rbp
    mov rbp, rsp
    mov r9, rsi
    mov rsi, [rdi + 8]
    mov rdi, [rdi]
    mov edx, 8
    lea rcx, [rip + _bit_cmp_num]
    cmp r9, 2
    jne 1f
    lea rcx, [rip + _bit_strptr_cmp]
    jmp 2f
1:  cmp r9, 1
    jne 2f
    lea rcx, [rip + _bit_cmp_dec]
2:  call _qsort
    pop rbp
    ret

// bytes: [0] данные, [8] длина, [16] ёмкость, [24] лимит; один байт на элемент
_bit_bytes_new:                     // rdi = сколько байт (нулями) → bytes
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    xor eax, eax
    test rdi, rdi
    cmovl rdi, rax
    mov rbx, rdi
    mov edi, 32
    call _bit_alloc
    mov r12, rax
    mov r13, 16
    cmp rbx, r13
    cmovg r13, rbx
    mov rdi, r13
    mov esi, 1
    call _calloc
    test rax, rax
    jz _bit_oom
    mov [r12], rax
    mov [r12 + 8], rbx
    mov [r12 + 16], r13
    mov qword ptr [r12 + 24], -1
    mov rax, r12
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_bytes_add:                     // rdi = bytes, rsi = значение (младший байт)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rbx + 8]
    mov rcx, [rbx + 16]
    cmp rax, rcx
    jl 1f
    shl rcx, 1
    mov [rbx + 16], rcx
    mov rdi, [rbx]
    mov rsi, rcx
    call _realloc
    test rax, rax
    jz _bit_oom
    mov [rbx], rax
1:  mov rax, [rbx]
    mov rcx, [rbx + 8]
    mov [rax + rcx], r12b
    inc rcx
    mov [rbx + 8], rcx
    pop r12
    pop rbx
    pop rbp
    ret

_bit_bytes_slice:                   // rdi = bytes, rsi = от, rdx = до (включительно) → новые bytes
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    xor eax, eax
    test rsi, rsi
    cmovl rsi, rax
    mov rax, [rbx + 8]
    dec rax
    cmp rdx, rax
    cmovg rdx, rax
    mov r13, rdx
    sub r13, rsi
    inc r13
    xor eax, eax
    test r13, r13
    cmovl r13, rax
    mov r12, rsi
    mov rdi, r13
    call _bit_bytes_new
    mov r14, rax
    mov rdi, [r14]
    mov rsi, [rbx]
    add rsi, r12
    mov rdx, r13
    call _memcpy
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_bytes_text:                    // rdi = bytes → строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, [rbx + 8]
    lea rdi, [r12 + 1]
    call _bit_alloc
    mov r13, rax
    mov rdi, rax
    mov rsi, [rbx]
    mov rdx, r12
    call _memcpy
    mov byte ptr [r13 + r12], 0
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_bytes_str:                     // rdi = bytes → "<01 a0 ff>"
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, [rbx + 8]
    lea rdi, [r12 + r12*2 + 3]
    call _bit_alloc
    mov r13, rax
    mov byte ptr [r13], 60
    mov r14, 1
    xor ecx, ecx
    lea r8, [rip + Lrt_hex]
1:  cmp rcx, r12
    jge 2f
    test rcx, rcx
    jz 3f
    mov byte ptr [r13 + r14], 32
    inc r14
3:  mov rax, [rbx]
    movzx edx, byte ptr [rax + rcx]
    mov eax, edx
    shr eax, 4
    movzx eax, byte ptr [r8 + rax]
    mov [r13 + r14], al
    inc r14
    and edx, 15
    movzx eax, byte ptr [r8 + rdx]
    mov [r13 + r14], al
    inc r14
    inc rcx
    jmp 1b
2:  mov byte ptr [r13 + r14], 62
    mov byte ptr [r13 + r14 + 1], 0
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_file_load:                     // rdi = путь, rsi = строка → bytes (всё содержимое как есть)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    lea rsi, [rip + Lrt_rb]
    call _fopen
    test rax, rax
    jz 9f
    mov r13, rax
    mov rdi, r13
    xor esi, esi
    mov edx, 2
    call _fseek
    test eax, eax
    jnz 8f
    mov rdi, r13
    call _ftell
    test rax, rax
    js 8f
    mov r14, rax
    mov rdi, r13
    xor esi, esi
    xor edx, edx
    call _fseek
    test eax, eax
    jnz 8f
    mov rdi, r14
    call _bit_bytes_new
    mov r15, rax
    mov rdi, [r15]
    mov esi, 1
    mov rdx, r14
    mov rcx, r13
    call _fread
    cmp rax, r14
    jne 8f
    mov rdi, r13
    call _fclose
    mov rax, r15
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  lea rdi, [rip + Lrt_eread]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath
9:  lea rdi, [rip + Lrt_eopen]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_file_save:                     // rdi = путь, rsi = bytes, rdx = строка: записывает байты как есть
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rsi, [rip + Lrt_wb]
    call _fopen
    test rax, rax
    jz 9f
    mov r14, rax
    mov rdi, [r12]
    mov esi, 1
    mov rdx, [r12 + 8]
    mov rcx, r14
    call _fwrite
    cmp rax, [r12 + 8]
    jne 9f
    mov rdi, r14
    call _fclose
    test eax, eax
    jnz 9f
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_ewrite]
    mov rsi, rbx
    mov rdx, r13
    call _bit_errpath

_bit_file_load_at:                  // path, offset, count, source line -> bytes
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rcx
    mov r13, rsi
    mov r14, rdx
    test r13, r13
    js 9f
    test r14, r14
    js 9f
    mov rdi, r14
    call _bit_bytes_new
    mov r15, rax
    mov rdi, rbx
    lea rsi, [rip + Lrt_rb]
    call _fopen
    test rax, rax
    jz 8f
    mov [rsp], rax
    mov rdi, rax
    mov rsi, r13
    xor edx, edx
    call _fseeko
    test eax, eax
    jnz 7f
    mov rdi, [r15]
    mov esi, 1
    mov rdx, r14
    mov rcx, [rsp]
    call _fread
    mov [r15 + 8], rax
    mov rdi, [rsp]
    call _ferror
    test eax, eax
    jnz 7f
    mov rdi, [rsp]
    call _fclose
    test eax, eax
    jnz 8f
    mov rax, r15
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
7:  mov rdi, [rsp]
    call _fclose
8:  mov rdi, r15
    call _bit_bytes_free
    lea rdi, [rip + Lrt_eread]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath
9:  lea rdi, [rip + Lrt_echunk]
    mov rsi, r12
    call _bit_die

_bit_open_update:                   // path -> writable descriptor, creating without truncating
    // O_WRONLY | O_CREAT (Darwin), mode 0666 filtered by umask
    mov esi, 513
    mov edx, 438
    xor eax, eax
    jmp _open

_bit_file_save_at:                  // path, bytes, offset, source line
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    test r13, r13
    js 9f
    call _bit_open_update
    test eax, eax
    js 8f
    mov r15d, eax
    mov edi, eax
    lea rsi, [rip + Lrt_wb]
    // fdopen does not truncate an existing descriptor
    call _fdopen
    test rax, rax
    jz 6f
    mov r15, rax
    mov rdi, rax
    mov rsi, r13
    xor edx, edx
    call _fseeko
    test eax, eax
    jnz 7f
    mov rdi, [r12]
    mov esi, 1
    mov rdx, [r12 + 8]
    mov rcx, r15
    call _fwrite
    cmp rax, [r12 + 8]
    jne 7f
    mov rdi, r15
    call _fclose
    test eax, eax
    jnz 8f
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
6:  mov edi, r15d
    call _close
    jmp 8f
7:  mov rdi, r15
    call _fclose
8:  lea rdi, [rip + Lrt_ewrite]
    mov rsi, rbx
    mov rdx, r14
    call _bit_errpath
9:  lea rdi, [rip + Lrt_echunk]
    mov rsi, r14
    call _bit_die

_bit_mem_free:                      // → сколько байт памяти свободно (свободные + неактивные страницы)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 176
    call _mach_host_self
    mov edi, eax
    mov esi, 4
    mov rdx, rsp
    mov dword ptr [rsp + 168], 38
    lea rcx, [rsp + 168]
    call _host_statistics64
    test eax, eax
    jnz 1f
    mov ebx, dword ptr [rsp]
    mov eax, dword ptr [rsp + 8]
    add rbx, rax
    mov qword ptr [rsp + 144], 0
    mov qword ptr [rsp + 152], 8
    lea rdi, [rip + Lrt_vmps]
    lea rsi, [rsp + 144]
    lea rdx, [rsp + 152]
    xor ecx, ecx
    xor r8d, r8d
    call _sysctlbyname
    mov eax, dword ptr [rsp + 144]
    imul rax, rbx
    jmp 2f
1:  xor eax, eax
2:  lea rsp, [rbp - 16]
    pop r12
    pop rbx
    pop rbp
    ret

_bit_self_pid:                      // → pid текущего процесса
    push rbp
    mov rbp, rsp
    call _getpid
    movsxd rax, eax
    pop rbp
    ret

_bit_bytes_addr:                    // rdi = bytes → адрес данных
    mov rax, [rdi]
    ret

_bit_bytes_num:                     // rdi = bytes, rsi = номер, rdx = строка -> 8 байт как число
    test rsi, rsi
    js 9f
    lea rax, [rsi + 8]
    cmp rax, [rdi + 8]
    jg 9f
    mov rax, [rdi]
    mov rax, [rax + rsi]
    ret
9:  and rsp, -16
    lea rdi, [rip + Lrt_e8]
    mov rsi, rdx
    call _bit_die

_bit_bytes_put:                     // rdi = bytes, rsi = номер, rdx = число, rcx = строка
    test rsi, rsi
    js 9f
    lea rax, [rsi + 8]
    cmp rax, [rdi + 8]
    jg 9f
    mov rax, [rdi]
    mov [rax + rsi], rdx
    ret
9:  and rsp, -16
    lea rdi, [rip + Lrt_e8]
    mov rsi, rcx
    call _bit_die

_bit_hexval_ptr:                    // rdi = указатель -> rax = число, rdx = конец
    xor eax, eax
1:  movzx r8d, byte ptr [rdi]
    lea r9d, [r8 - 48]
    cmp r9d, 9
    jbe 3f
    or r8d, 0x20
    lea r9d, [r8 - 97]
    cmp r9d, 5
    ja 2f
    add r9d, 10
3:  shl rax, 4
    or rax, r9
    inc rdi
    jmp 1b
2:  mov rdx, rdi
    ret

_bit_str_hex:                       // rdi = строка -> число (hex, можно с 0x)
    push rbp
    mov rbp, rsp
1:  movzx eax, byte ptr [rdi]
    cmp eax, 32
    jne 2f
    inc rdi
    jmp 1b
2:  cmp byte ptr [rdi], 48
    jne 3f
    movzx eax, byte ptr [rdi + 1]
    or eax, 0x20
    cmp eax, 120
    jne 3f
    add rdi, 2
3:  call _bit_hexval_ptr
    pop rbp
    ret

_bit_drop_str:                      // release an adopted string reference
    jmp _bit_str_release

_bit_bytes_free:                    // rdi = bytes (или 0) -> освободить буфер и описатель
    test rdi, rdi
    jz 1f
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rdi
    mov rdi, [rbx]
    call _free
    mov rdi, rbx
    call _free
    add rsp, 8
    pop rbx
    pop rbp
1:  ret

_bit_tcp_connect:                   // rdi = "ip:port", rsi = строка -> TCP conn
    mov edx, 1
    jmp _bit_ip_connect

_bit_udp_connect:                   // rdi = "ip:port", rsi = строка -> UDP conn
    mov edx, 2
    jmp _bit_ip_connect

_bit_ip_connect:                    // rdi = адрес, rsi = строка, rdx = тип сокета
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 120
    mov [rsp + 96], rdx
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rsp]
    mov rcx, rbx
    mov rdx, r13
1:  movzx eax, byte ptr [rcx]
    test eax, eax
    jz 9f
    cmp eax, 58
    je 2f
    lea r9, [rsp + 15]
    cmp rdx, r9
    jae 9f
    mov [rdx], al
    inc rcx
    inc rdx
    jmp 1b
2:  mov byte ptr [rdx], 0
    inc rcx
    xor r8d, r8d
    cmp byte ptr [rcx], 0
    je 9f
3:  movzx eax, byte ptr [rcx]
    test eax, eax
    jz 4f
    sub eax, 48
    cmp eax, 9
    ja 9f
    cmp r8d, 6553
    ja 9f
    jne 5f
    cmp eax, 5
    ja 9f
5:  imul r8d, r8d, 10
    add r8d, eax
    inc rcx
    jmp 3b
4:  lea rdx, [rsp + 80]
    xor eax, eax
    mov [rdx], rax
    mov [rdx + 8], rax
    mov word ptr [rdx], 2
    mov eax, r8d
    mov ecx, eax
    shl eax, 8
    shr ecx, 8
    or eax, ecx
    mov [rdx + 2], ax
    mov edi, 2
    lea rsi, [rsp]
    lea rdx, [rsp + 84]
    call _inet_pton
    cmp eax, 1
    jne 9f
    mov edi, 2
    mov esi, [rsp + 96]
    xor edx, edx
    call _socket
    test eax, eax
    js 9f
    mov ebx, eax
    mov edi, ebx
    lea rsi, [rsp + 80]
    mov edx, 16
    call _connect
    test eax, eax
    jnz 8f
    mov eax, ebx
    add rsp, 120
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  call _bit_errno_code
    mov rdi, rax
    call _bit_set_errcode
    mov edi, ebx
    call _close
    jmp 10f
9:  xor edi, edi
    call _bit_set_errcode
10: add rsp, 120
    lea rdi, [rip + Lrt_enet]
    mov rsi, r12
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_tcp_connect_timed:               // rdi = "ip:port", rsi = таймаут мс, rdx = строка -> TCP conn
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 112
    mov r13, rdx                      # строка исходника
    mov r12d, esi                     # таймаут мс
    test rsi, rsi
    js 10f
    cmp rsi, 2147483647
    jg 10f
    mov rcx, rdi
    lea rdx, [rsp]
1:  movzx eax, byte ptr [rcx]
    test eax, eax
    jz 9f                             # пустой адрес
    cmp eax, 58
    je 2f
    lea r9, [rsp + 15]
    cmp rdx, r9
    jae 9f
    mov [rdx], al
    inc rcx
    inc rdx
    jmp 1b
2:  mov byte ptr [rdx], 0
    inc rcx
    xor r8d, r8d
    cmp byte ptr [rcx], 0
    je 9f
3:  movzx eax, byte ptr [rcx]
    test eax, eax
    jz 4f
    sub eax, 48
    cmp eax, 9
    ja 9f
    cmp r8d, 6553
    ja 9f
    jne 5f
    cmp eax, 5
    ja 9f
5:  imul r8d, r8d, 10
    add r8d, eax
    inc rcx
    jmp 3b
4:  lea rdx, [rsp + 80]
    xor eax, eax
    mov [rdx], rax
    mov [rdx + 8], rax
    mov word ptr [rdx], 2
    mov eax, r8d
    mov ecx, eax
    shl eax, 8
    shr ecx, 8
    or eax, ecx
    mov [rdx + 2], ax
    mov edi, 2
    lea rsi, [rsp]
    lea rdx, [rsp + 84]
    call _inet_pton
    cmp eax, 1
    jne 9f
    mov edi, 2
    mov esi, 1
    xor edx, edx
    call _socket
    test eax, eax
    js 9f
    mov ebx, eax
    mov edi, ebx
    mov esi, 3                       # F_GETFL
    call _fcntl
    test eax, eax
    js 8f
    or eax, 4                   # O_NONBLOCK (Darwin)
    mov r14d, eax
    mov edi, ebx
    mov esi, 4                       # F_SETFL
    mov edx, r14d
    call _fcntl
    test eax, eax
    js 8f
    mov edi, ebx
    lea rsi, [rsp + 80]
    mov edx, 16
    call _connect
    test eax, eax
    jz 11f                            # подключился сразу
    call ___error
    mov eax, dword ptr [rax]
    cmp eax, 36                       # EINPROGRESS (Darwin)
    jne 7f
    mov [rsp + 32], ebx
    mov dword ptr [rsp + 36], 4       # POLLOUT; revents = 0
    lea rdi, [rsp + 32]
    mov esi, 1
    mov edx, r12d
    call _poll
    test eax, eax
    jz 6f                             # истёк таймаут
    js 7f                             # ошибка poll
11: mov edi, ebx
    mov esi, 65535                    # SOL_SOCKET (Darwin)
    mov edx, 4103                     # SO_ERROR
    lea rcx, [rsp + 96]
    mov dword ptr [rsp + 100], 4
    lea r8, [rsp + 100]
    call _getsockopt
    test eax, eax
    jnz 7f
    mov edi, dword ptr [rsp + 96]
    test edi, edi
    jz 12f                            # ошибки нет — подключён
    call _bit_errno_map
    mov rdi, rax
    call _bit_set_errcode
    mov edi, ebx
    call _close
    lea rdi, [rip + Lrt_enet]
    jmp 71f
12: mov edi, ebx
    mov esi, 3                       # F_GETFL
    call _fcntl
    test eax, eax
    js 8f
    and eax, -5                  # снять O_NONBLOCK (Darwin)
    mov edi, ebx
    mov esi, 4                       # F_SETFL
    mov edx, eax
    call _fcntl
    test eax, eax
    js 8f
    mov eax, ebx
    add rsp, 112
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
6:  mov edi, 2
    call _bit_set_errcode
    mov edi, ebx
    call _close
    lea rdi, [rip + Lrt_econn_timeout]
    jmp 71f
7:  call _bit_errno_code
    mov rdi, rax
    call _bit_set_errcode
    mov edi, ebx
    call _close
    lea rdi, [rip + Lrt_enet]
    jmp 71f
8:  xor edi, edi
    call _bit_set_errcode
    mov edi, ebx
    call _close
    lea rdi, [rip + Lrt_enet]
    jmp 71f
9:  xor edi, edi
    call _bit_set_errcode
    lea rdi, [rip + Lrt_enet]
    jmp 71f
10: xor edi, edi
    call _bit_set_errcode
    lea rdi, [rip + Lrt_econn_args]
71: mov rsi, r13
    add rsp, 112
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_tcp_listen:                    // port, line -> server
    mov rdx, rsi
    xor esi, esi
    jmp _bit_tcp_listen_at

_bit_tcp_listen_at:                 // port, IPv4 address or null, line -> server
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rbx, -1
    test r12, r12
    js 9f
    cmp r12, 65535
    ja 9f
    xor eax, eax
    mov [rsp], rax
    mov [rsp + 8], rax
    mov word ptr [rsp], 0x210       # Darwin sockaddr_in: length 16, AF_INET 2
    mov eax, r12d
    rol ax, 8
    mov [rsp + 2], ax
    test r13, r13
    jz 1f
    mov edi, 2
    mov rsi, r13
    lea rdx, [rsp + 4]
    call _inet_pton
    cmp eax, 1
    jne 8f
1:  mov edi, 2
    mov esi, 1
    xor edx, edx
    call _socket
    test eax, eax
    js 9f
    mov ebx, eax
    mov dword ptr [rsp + 16], 1
    mov edi, ebx
    mov esi, 0xffff                 # Darwin SOL_SOCKET
    mov edx, 4                      # Darwin SO_REUSEADDR
    lea rcx, [rsp + 16]
    mov r8d, 4
    call _setsockopt
    test eax, eax
    jnz 7f
    mov edi, ebx
    mov rsi, rsp
    mov edx, 16
    call _bind
    test eax, eax
    jnz 7f
    mov edi, ebx
    mov esi, 16
    call _listen
    test eax, eax
    jnz 7f
    mov eax, ebx
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
7:  mov edi, ebx
    call _close
9:  lea rdi, [rip + Lrt_elisten]
    jmp 6f
8:  lea rdi, [rip + Lrt_elisten_addr]
6:  mov rsi, r14
    call _bit_die

_bit_tcp_accept:                    // rdi = server, rsi = строка -> conn
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rsi
    xor esi, esi
    xor edx, edx
    call _accept
    test eax, eax
    js 9f
    add rsp, 8
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_eaccept]
    mov rsi, rbx
    add rsp, 8
    pop rbx
    pop rbp
    jmp _bit_die

_bit_sock_peer:                     // socket, source line -> owned "IPv4:port"
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov r12, rsi
    mov dword ptr [rsp + 16], 16
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call _getpeername
    test eax, eax
    jnz 9f
    movzx ebx, word ptr [rsp + 2]
    rol bx, 8
    mov edi, 2
    lea rsi, [rsp + 4]
    lea rdx, [rsp + 32]
    mov ecx, 16
    call _inet_ntop
    test rax, rax
    jz 9f
    lea rdi, [rsp + 32]
    lea rsi, [rip + Lrt_peer_colon]
    call _bit_cat
    mov r13, rax
    mov edi, ebx
    call _bit_num_str
    mov r14, rax
    mov rdi, r13
    mov rsi, r14
    call _bit_cat
    mov r15, rax
    mov rdi, r13
    call _free
    mov rdi, r14
    call _free
    mov rax, r15
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_epeer]
    mov rsi, r12
    call _bit_die

_bit_sock_send:                     // rdi = conn, rsi = строка, rdx = строка программы
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov ebx, edi
    mov r12, rsi
    mov r14, rdx
    mov rdi, r12
    call _strlen
    mov r13, rax
1:  test r13, r13
    jle 3f
    mov edi, ebx
    mov rsi, r12
    mov rdx, r13
    xor ecx, ecx
    call _send
    test rax, rax
    js 9f
    add r12, rax
    sub r13, rax
    jmp 1b
3:  pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_esend]
    mov rsi, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_sock_recv:                     // rdi = conn, rsi = строка -> строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov ebx, edi
    mov r12, rsi
    mov edi, 65536
    call _bit_alloc
    mov r12, rax
    mov edi, ebx
    mov rsi, r12
    mov edx, 65535
    xor ecx, ecx
    call _recv
    test rax, rax
    js 9f
    mov byte ptr [r12 + rax], 0
    mov rax, r12
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_erecv]
    mov rsi, r12
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_socket_wait:                   // socket, timeout in ms -> poll result
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 16
    mov dword ptr [rsp], edi
    mov r12d, esi
    xor edi, edi
    call _bit_os_clock
    lea r13, [rax + r12]           // absolute deadline
    mov r14, r12
1:  mov dword ptr [rsp + 4], 1     // POLLIN; clear revents
    mov rdi, rsp
    mov esi, 1
    mov edx, r14d
    call _poll
    test eax, eax
    jns 3f
    call ___error
    cmp dword ptr [rax], 4         // EINTR
    jne 2f
    xor edi, edi
    call _bit_os_clock
    mov r14, r13
    sub r14, rax
    jg 1b
    xor eax, eax
    jmp 3f
2:  mov eax, -1
3:  add rsp, 16
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_sock_recv_timed:               // socket, count, timeout in ms, source line -> string
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rcx
    cmp r12, 1
    jl 9f
    cmp r12, 2147483647
    jg 9f
    test rdx, rdx
    js 9f
    cmp rdx, 2147483647
    jg 9f
    mov rsi, rdx
    call _bit_socket_wait
    test eax, eax
    jz 8f
    js 7f
    lea rdi, [r12 + 1]
    call _bit_alloc
    mov r14, rax
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r12
    xor ecx, ecx
    call _recv
    test eax, eax
    js 6f
    mov eax, eax
    mov byte ptr [r14 + rax], 0
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
6:  mov rdi, r14
    call _free
7:  lea rdi, [rip + Lrt_erecv]
    jmp 5f
8:  mov edi, 2
    call _bit_set_errcode
    lea rdi, [rip + Lrt_erecv_timeout]
    jmp 5f
9:  lea rdi, [rip + Lrt_erecv_args]
5:  mov rsi, r13
    call _bit_die

_bit_sock_close:                    // rdi = conn/server
    jmp _close

_bit_shquote:                       // rdi = строка -> 'строка' с экранированием
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    call _strlen
    lea rdi, [rax*4 + 3]
    call _bit_alloc
    mov r12, rax
    mov r13, rbx
    mov r14, rax
    mov byte ptr [r14], 39
    inc r14
1:  movzx eax, byte ptr [r13]
    test eax, eax
    jz 3f
    inc r13
    cmp eax, 39
    jne 2f
    mov byte ptr [r14], 39
    mov byte ptr [r14 + 1], 92
    mov byte ptr [r14 + 2], 39
    mov byte ptr [r14 + 3], 39
    add r14, 4
    jmp 1b
2:  mov [r14], al
    inc r14
    jmp 1b
3:  mov byte ptr [r14], 39
    mov byte ptr [r14 + 1], 0
    mov rax, r12
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_spawn_capture:                 // rdi = argv (char**, NULL-терм), rsi = строка → вывод stdout
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov rbx, rdi
    mov r12, rsi
    xor edi, edi
    call _fflush
    lea rdi, [rsp]
    call _pipe
    test eax, eax
    js 9f
    call _fork
    test eax, eax
    js 8f
    jnz 2f
    mov edi, dword ptr [rsp + 4]
    mov esi, 1
    call _dup2
    mov edi, dword ptr [rsp]
    call _close
    mov edi, dword ptr [rsp + 4]
    call _close
    mov rdi, [rbx]
    mov rsi, rbx
    call _execvp
    mov edi, 127
    call _exit
2:  mov r13d, eax
    mov edi, dword ptr [rsp + 4]
    call _close
    mov edi, 4096
    call _bit_alloc
    mov r14, rax
    mov r15, 4096
    mov qword ptr [rsp + 8], 0
3:  mov rax, [rsp + 8]
    lea rax, [rax + 1]
    cmp rax, r15
    jb 4f
    shl r15, 1
    mov rdi, r14
    mov rsi, r15
    call _realloc
    test rax, rax
    jz _bit_oom
    mov r14, rax
4:  mov edi, dword ptr [rsp]
    mov rsi, r14
    add rsi, [rsp + 8]
    mov rdx, r15
    sub rdx, [rsp + 8]
    dec rdx
    call _read
    test rax, rax
    jle 5f
    add [rsp + 8], rax
    jmp 3b
5:  mov edi, dword ptr [rsp]
    call _close
    mov edi, r13d
    lea rsi, [rsp + 16]
    xor edx, edx
    call _waitpid
    mov edi, dword ptr [rsp + 16]
    call _bit_wstatus
    mov rax, [rsp + 8]
    test rax, rax
    jz 6f
    cmp byte ptr [r14 + rax - 1], 10
    jne 6f
    dec rax
    mov [rsp + 8], rax
6:  mov rax, [rsp + 8]
    mov byte ptr [r14 + rax], 0
    mov rax, r14
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  mov edi, dword ptr [rsp]
    call _close
    mov edi, dword ptr [rsp + 4]
    call _close
9:  lea rdi, [rip + Lrt_erun]
    mov rsi, r12
    call _bit_die

_bit_spawn_status:                  // rdi = argv, rsi = тихо(0/1), rdx = строка → код выхода
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor edi, edi
    call _fflush
    call _fork
    test eax, eax
    js 9f
    jnz 2f
    test r12, r12
    jz 1f
    lea rdi, [rip + Lrt_devnull]
    mov esi, 1
    xor eax, eax
    call _open
    test eax, eax
    js 1f
    mov r12d, eax
    mov edi, r12d
    mov esi, 1
    call _dup2
    mov edi, r12d
    mov esi, 2
    call _dup2
1:  mov rdi, [rbx]
    mov rsi, rbx
    call _execvp
    mov edi, 127
    call _exit
2:  mov edi, eax
    lea rsi, [rsp]
    xor edx, edx
    call _waitpid
    mov edi, dword ptr [rsp]
    call _bit_wstatus
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_erun]
    mov rsi, r13
    call _bit_die

_bit_fetch:                         // rdi = url, rsi = строка -> тело
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

_bit_http_post:                     // rdi = url, rsi = данные, rdx = строка -> ответ
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

_bit_download:                      // rdi = url, rsi = файл, rdx = строка
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

_bit_resolve:                       // rdi = имя хоста, rsi = строка -> IP-адрес строкой
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov r12, rsi
    call _gethostbyname
    test rax, rax
    jz 9f
    mov rcx, [rax + 24]
    mov rbx, [rcx]
    mov edi, 32
    call _bit_alloc
    mov rdx, rax
    mov edi, 2
    mov rsi, rbx
    mov ecx, 32
    call _inet_ntop
    test rax, rax
    jz 9f
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_edns]
    mov rsi, r12
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_ping_clock:                    // monotonic milliseconds, -1 on failure
    sub rsp, 24
    mov edi, 6                      // CLOCK_MONOTONIC on Darwin
    mov rsi, rsp
    call _clock_gettime
    test eax, eax
    jnz 1f
    imul rcx, qword ptr [rsp], 1000
    mov rax, [rsp + 8]
    xor edx, edx
    mov esi, 1000000
    div rsi
    add rax, rcx
    jmp 2f
1:  mov rax, -1
2:  add rsp, 24
    ret

_bit_ping:                          // host -> ICMP echo reply, without a subprocess
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 344
    mov rbx, rdi
    mov r12, -1                    // socket
    xor r13d, r13d                 // addrinfo list
    test rbx, rbx
    jz 9f
    cmp byte ptr [rbx], 0
    je 9f
    pxor xmm0, xmm0
    movdqu [rsp], xmm0
    movdqu [rsp + 16], xmm0
    movdqu [rsp + 32], xmm0
    mov dword ptr [rsp + 8], 2     // SOCK_DGRAM, any IP family
    mov rdi, rbx
    xor esi, esi
    mov rdx, rsp
    lea rcx, [rsp + 48]
    call _getaddrinfo
    test eax, eax
    jnz 9f
    mov r13, [rsp + 48]
    test r13, r13
    jz 9f
    mov r14, r13
11: mov eax, [r14 + 4]            // ai_family
    cmp eax, 2
    je 12f
    cmp eax, 30                   // AF_INET6 on Darwin
    je 12f
    mov r14, [r14 + 40]
    test r14, r14
    jnz 11b
    jmp 9f
12: mov [rsp + 4], eax            // retain family after freeaddrinfo
    mov r15d, [r14 + 16]          // ai_addrlen
    mov r14, [r14 + 32]           // ai_addr on Darwin
    test r14, r14
    jz 9f
    mov edi, eax
    mov esi, 2                    // SOCK_DGRAM
    mov edx, 1                    // IPPROTO_ICMP
    cmp eax, 2
    je 13f
    mov edx, 58                   // IPPROTO_ICMPV6
13: call _socket
    test eax, eax
    js 9f
    mov r12d, eax
    mov edi, eax
    mov rsi, r14
    mov edx, r15d
    call _connect
    mov r14d, eax
    mov rdi, r13
    call _freeaddrinfo
    xor r13d, r13d
    test r14d, r14d
    jnz 9f
    movabs rax, 0x6251000035f10008
    cmp dword ptr [rsp + 4], 2
    je 14f
    movabs rax, 0x6251000000000080 // ICMPv6 echo; OS supplies checksum
14: mov [rsp + 56], rax
    movabs rax, 0x676e69702d746962
    mov [rsp + 64], rax
    mov edi, r12d
    lea rsi, [rsp + 56]
    mov edx, 16
    xor ecx, ecx
    call _send
    cmp rax, 16
    jne 9f
    call _bit_ping_clock
    test rax, rax
    js 9f
    lea r15, [rax + 1000]         // one-second deadline
    mov r14, 1000
1:  mov [rsp + 72], r12d
    mov dword ptr [rsp + 76], 1  // POLLIN; clear revents
    lea rdi, [rsp + 72]
    mov esi, 1
    mov edx, r14d
    call _poll
    test eax, eax
    jz 9f
    js 6f
    mov edi, r12d
    lea rsi, [rsp + 80]
    mov edx, 256
    xor ecx, ecx
    call _recv
    test rax, rax
    js 6f
    cmp rax, 16
    jl 7f
    xor ecx, ecx
    movzx edx, byte ptr [rsp + 80]
    mov r8d, edx
    shr r8d, 4
    cmp r8d, 4
    jne 2f
    and edx, 15                   // Darwin includes IPv4 header
    lea rcx, [rdx * 4]
    cmp rcx, 20
    jb 7f
2:  lea rdx, [rcx + 16]
    cmp rax, rdx
    jb 7f
    lea rdx, [rsp + 80]
    add rdx, rcx
    cmp byte ptr [rdx + 1], 0
    jne 7f
    cmp dword ptr [rsp + 4], 2
    jne 15f
    cmp byte ptr [rdx], 0          // ICMP echo reply
    jne 7f
    jmp 16f
15: cmp byte ptr [rdx], 129        // ICMPv6 echo reply
    jne 7f
16: cmp word ptr [rdx + 6], 0x6251
    jne 7f
    movabs rax, 0x676e69702d746962
    cmp qword ptr [rdx + 8], rax
    jne 7f
    mov r14d, 1
    jmp 8f
6:  call ___error
    cmp dword ptr [rax], 4       // EINTR
    jne 9f
7:  call _bit_ping_clock
    test rax, rax
    js 9f
    mov r14, r15
    sub r14, rax
    jg 1b
9:  xor r14d, r14d
8:  cmp r12, -1
    je 3f
    mov edi, r12d
    call _close
3:  test r13, r13
    jz 4f
    mov rdi, r13
    call _freeaddrinfo
4:  mov rax, r14
    add rsp, 344
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_str_num:                       // rdi = строка -> число
    mov rcx, rdi
    xor r8d, r8d
1:  movzx eax, byte ptr [rcx]
    cmp eax, 32
    jne 2f
    inc rcx
    jmp 1b
2:  cmp eax, 45
    jne 3f
    mov r8d, 1
    inc rcx
3:  xor eax, eax
4:  movzx edx, byte ptr [rcx]
    sub edx, 48
    cmp edx, 9
    ja 5f
    imul rax, rax, 10
    add rax, rdx
    inc rcx
    jmp 4b
5:  test r8d, r8d
    jz 6f
    neg rax
6:  ret

_bit_str_num_checked:               // rdi = string, rsi = source line
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    call ___error
    mov r13, rax
    mov dword ptr [r13], 0
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 10
    call _strtoll
    mov r14, rax
    cmp dword ptr [r13], 0
    jne 9f
    mov rcx, [rsp]
    cmp rcx, rbx
    je 9f
1:  movzx eax, byte ptr [rcx]
    inc rcx
    test eax, eax
    jz 2f
    cmp eax, 32
    je 1b
    sub eax, 9
    cmp eax, 4
    jbe 1b
    jmp 9f
2:  mov rax, r14
    add rsp, 16
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_badnum]
    mov rsi, r12
    call _bit_die

_bit_str_lines:                     // rdi = строка -> mas строк
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    call _strlen
    mov r12, rax
    lea rdi, [rax + 1]
    call _bit_alloc
    mov r13, rax
    mov rdi, rax
    mov rsi, rbx
    lea rdx, [r12 + 1]
    call _memcpy
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r14, rax
    mov rbx, r13
    mov r12, r13
1:  movzx eax, byte ptr [r12]
    test eax, eax
    jz 3f
    cmp eax, 10
    jne 2f
    mov byte ptr [r12], 0
    mov rdi, r14
    mov rsi, rbx
    xor edx, edx
    call _bit_mas_add
    inc r12
    mov rbx, r12
    jmp 1b
2:  inc r12
    jmp 1b
3:  mov rdi, r14
    mov rsi, rbx
    xor edx, edx
    call _bit_mas_add
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_os_host:                       // -> имя компьютера
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov edi, 256
    call _bit_alloc
    mov rbx, rax
    mov rdi, rbx
    mov esi, 256
    call _gethostname
    mov rax, rbx
    add rsp, 8
    pop rbx
    pop rbp
    ret

_bit_os_user:                       // -> имя пользователя
    push rbp
    mov rbp, rsp
    lea rdi, [rip + Lrt_userenv]
    call _getenv
    test rax, rax
    jnz 1f
    lea rax, [rip + Lrt_empty]
1:  pop rbp
    ret

_bit_os_clock:                      // rdi = source line -> monotonic milliseconds
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 24
    mov rbx, rdi
    mov edi, 6                       // CLOCK_MONOTONIC on Darwin
    mov rsi, rsp
    call _clock_gettime
    test eax, eax
    jnz 9f
    imul rcx, qword ptr [rsp], 1000
    mov rax, [rsp + 8]
    xor edx, edx
    mov esi, 1000000
    div rsi
    add rax, rcx
    add rsp, 24
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_eclock]
    mov rsi, rbx
    call _bit_die

_bit_os_now:                        // -> время (секунды)
    push rbp
    mov rbp, rsp
    xor edi, edi
    call _time
    pop rbp
    ret

_bit_os_cpus:                       // source line -> online logical processors
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rdi
    mov edi, 58                    // Darwin _SC_NPROCESSORS_ONLN
    call _sysconf
    cmp rax, 1
    jl 9f
    add rsp, 8
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_ecpus]
    mov rsi, rbx
    call _bit_die

_bit_procs_add:                    // array, pid, name, source line
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, r12
    call _bit_num_str
    mov r15, rax
    mov rdi, rax
    lea rsi, [rip + Lrt_pspc]
    call _bit_cat
    mov r12, rax
    mov rdi, r15
    call _free
    mov rdi, r12
    mov rsi, r13
    call _bit_cat
    mov r15, rax
    mov rdi, r12
    call _free
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r14
    call _bit_mas_add
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_procs_finish:                 // array -> joined string; free temporary entries
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    lea rsi, [rip + Lrt_pnl]
    call _bit_mas_join
    mov r12, rax
    xor r13d, r13d
1:  cmp r13, [rbx + 8]
    jge 2f
    mov rax, [rbx]
    mov rdi, [rax + r13*8]
    call _free
    inc r13
    jmp 1b
2:  mov rdi, [rbx]
    call _free
    mov rdi, rbx
    call _free
    mov rax, r12
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_os_procs:                     // source line -> PID and process name per line
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 280
    mov rbx, rdi
    mov r12d, 4096
    mov rdi, r12
    call _bit_alloc
    mov r13, rax
1:  mov rdi, r13
    mov rsi, r12
    call _proc_listallpids
    test eax, eax
    js 8f
    movsxd r14, eax
    lea rax, [r14*4]
    cmp rax, r12
    jb 2f
    cmp r12, 16777216
    jae 8f
    shl r12, 1
    mov rdi, r13
    mov rsi, r12
    call _realloc
    test rax, rax
    jz _bit_oom
    mov r13, rax
    jmp 1b
2:  mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r15, rax
    mov qword ptr [rsp + 256], 0
3:  mov rax, [rsp + 256]
    cmp rax, r14
    jge 6f
    mov edi, dword ptr [r13 + rax*4]
    test edi, edi
    jz 5f
    mov [rsp + 264], rdi
    mov rsi, rsp
    call _bit_mac_pname
    test eax, eax
    jle 5f
    mov rdi, r15
    mov rsi, [rsp + 264]
    mov rdx, rsp
    mov rcx, rbx
    call _bit_procs_add
5:  inc qword ptr [rsp + 256]
    jmp 3b
6:  mov rdi, r13
    call _free
    mov rdi, r15
    call _bit_procs_finish
    add rsp, 280
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  mov rdi, r13
    call _free
    lea rdi, [rip + Lrt_eprocs]
    mov rsi, rbx
    call _bit_die

// ── mas >> run: программа напрямую массивом аргументов; stdout и stderr отдельно, stdin ──
_bit_mas_argv:                      // rdi = mas строк → rax = char** (NULL в конце)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov rax, [rbx + 8]
    lea rdi, [rax*8 + 8]
    call _bit_alloc
    mov r12, rax
    mov rcx, [rbx + 8]
    mov rdx, [rbx]
    xor r8d, r8d
1:  cmp r8, rcx
    jge 2f
    mov r9, [rdx + r8*8]
    mov [r12 + r8*8], r9
    inc r8
    jmp 1b
2:  mov qword ptr [r12 + rcx*8], 0
    mov rax, r12
    pop r12
    pop rbx
    pop rbp
    ret

_bit_buf_read:                      // edi = fd, rsi = буфер (ptr, len, cap) → rax = прочитано
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov ebx, edi
    mov r12, rsi
    mov rax, [r12 + 8]
    lea rax, [rax + 1]
    cmp rax, [r12 + 16]
    jb 1f
    mov rsi, [r12 + 16]
    shl rsi, 1
    mov [r12 + 16], rsi
    mov rdi, [r12]
    call _realloc
    test rax, rax
    jz _bit_oom
    mov [r12], rax
1:  mov edi, ebx
    mov rsi, [r12]
    add rsi, [r12 + 8]
    mov rdx, [r12 + 16]
    sub rdx, [r12 + 8]
    dec rdx
    call _read
    test rax, rax
    jle 2f
    add [r12 + 8], rax
2:  pop r12
    pop rbx
    pop rbp
    ret

_bit_buf_finish:                    // rdi = буфер → строка (без последнего \n)
    mov rax, [rdi + 8]
    mov rdx, [rdi]
    test rax, rax
    jz 1f
    cmp byte ptr [rdx + rax - 1], 10
    jne 1f
    dec rax
1:  mov byte ptr [rdx + rax], 0
    mov rax, rdx
    ret

_bit_exec:                          // rdi = mas строк, rsi = stdin (или 0), rdx = строка → stdout
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 152
    xor ebx, ebx
    mov r12, rsi
    mov r13, rdx
    mov qword ptr [rsp], -1
    mov qword ptr [rsp + 8], -1
    mov qword ptr [rsp + 16], -1
    cmp qword ptr [rdi + 8], 0
    je 9f
    call _bit_mas_argv
    mov rbx, rax
    xor edi, edi
    call _fflush
    lea rdi, [rsp]
    call _pipe
    test eax, eax
    js 9f
    lea rdi, [rsp + 8]
    call _pipe
    test eax, eax
    js 9f
    test r12, r12
    jz 1f
    lea rdi, [rsp + 16]
    call _pipe
    test eax, eax
    js 9f
    mov edi, dword ptr [rsp + 20]
    // F_GETFL
    mov esi, 3
    xor eax, eax
    call _fcntl
    test eax, eax
    js 9f
    mov edx, eax
    // O_NONBLOCK on Darwin
    or edx, 4
    mov edi, dword ptr [rsp + 20]
    // F_SETFL
    mov esi, 4
    xor eax, eax
    call _fcntl
    test eax, eax
    js 9f
1:  call _fork
    test eax, eax
    js 9f
    jnz 3f
    mov edi, dword ptr [rsp + 4]
    mov esi, 1
    call _dup2
    mov edi, dword ptr [rsp + 12]
    mov esi, 2
    call _dup2
    test r12, r12
    jz 2f
    mov edi, dword ptr [rsp + 16]
    xor esi, esi
    call _dup2
    mov edi, dword ptr [rsp + 16]
    call _close
    mov edi, dword ptr [rsp + 20]
    call _close
2:  mov edi, dword ptr [rsp]
    call _close
    mov edi, dword ptr [rsp + 4]
    call _close
    mov edi, dword ptr [rsp + 8]
    call _close
    mov edi, dword ptr [rsp + 12]
    call _close
    mov rdi, [rbx]
    mov rsi, rbx
    call _execvp
    mov edi, 127
    call _exit
3:  mov dword ptr [rsp + 24], eax
    mov rdi, rbx
    call _free
    mov edi, dword ptr [rsp + 4]
    call _close
    mov edi, dword ptr [rsp + 12]
    call _close
    mov dword ptr [rsp + 144], -1
    mov qword ptr [rsp + 104], 2
    test r12, r12
    jz 5f
    mov edi, dword ptr [rsp + 16]
    call _close
    mov rdi, r12
    call _strlen
    mov r14, rax
    mov r15, r12
    test r14, r14
    jz 6f
    mov edi, 13
    // SIG_IGN
    mov esi, 1
    call _signal
    mov [rsp + 112], rax
    mov eax, dword ptr [rsp + 20]
    mov dword ptr [rsp + 144], eax
    // POLLOUT
    mov dword ptr [rsp + 148], 4
    mov qword ptr [rsp + 104], 3
    jmp 5f
6:  mov edi, dword ptr [rsp + 20]
    call _close
5:  mov edi, 4096
    call _bit_alloc
    mov [rsp + 48], rax
    mov qword ptr [rsp + 56], 0
    mov qword ptr [rsp + 64], 4096
    mov edi, 4096
    call _bit_alloc
    mov [rsp + 72], rax
    mov qword ptr [rsp + 80], 0
    mov qword ptr [rsp + 88], 4096
    mov eax, dword ptr [rsp]
    mov dword ptr [rsp + 128], eax
    mov dword ptr [rsp + 132], 1
    mov eax, dword ptr [rsp + 8]
    mov dword ptr [rsp + 136], eax
    mov dword ptr [rsp + 140], 1
7:  cmp qword ptr [rsp + 104], 0
    je 8f
    lea rdi, [rsp + 128]
    mov esi, 3
    mov edx, -1
    call _poll
    test eax, eax
    js 7b
    mov eax, dword ptr [rsp + 128]
    test eax, eax
    js 71f
    movzx ecx, word ptr [rsp + 134]
    test ecx, ecx
    jz 71f
    mov edi, eax
    lea rsi, [rsp + 48]
    call _bit_buf_read
    test rax, rax
    jg 71f
    mov edi, dword ptr [rsp + 128]
    call _close
    mov dword ptr [rsp + 128], -1
    dec qword ptr [rsp + 104]
71: mov eax, dword ptr [rsp + 136]
    test eax, eax
    js 72f
    movzx ecx, word ptr [rsp + 142]
    test ecx, ecx
    jz 72f
    mov edi, eax
    lea rsi, [rsp + 72]
    call _bit_buf_read
    test rax, rax
    jg 72f
    mov edi, dword ptr [rsp + 136]
    call _close
    mov dword ptr [rsp + 136], -1
    dec qword ptr [rsp + 104]
    jmp 72f
72: mov edi, dword ptr [rsp + 144]
    test edi, edi
    js 7b
    cmp word ptr [rsp + 150], 0
    je 7b
    mov rsi, r15
    mov edx, 65536
    cmp r14, rdx
    cmovb rdx, r14
    call _write
    test rax, rax
    jg 73f
    call ___error
    mov eax, dword ptr [rax]
    // EINTR
    cmp eax, 4
    je 7b
    // EAGAIN on Darwin
    cmp eax, 35
    je 7b
    jmp 74f
73: add r15, rax
    sub r14, rax
    jnz 7b
74: mov edi, dword ptr [rsp + 144]
    call _close
    mov dword ptr [rsp + 144], -1
    mov edi, 13
    mov rsi, [rsp + 112]
    call _signal
    dec qword ptr [rsp + 104]
    jmp 7b
8:  mov edi, dword ptr [rsp + 24]
    lea rsi, [rsp + 96]
    xor edx, edx
    call _waitpid
    test eax, eax
    js 81f
    mov edi, dword ptr [rsp + 96]
    call _bit_wstatus
    jmp 82f
81: call ___error
    // EINTR
    cmp dword ptr [rax], 4
    je 8b
    mov qword ptr [rip + Lrt_status], 127
82: mov rdi, [rip + Lrt_stderr]
    call _free
    lea rdi, [rsp + 72]
    call _bit_buf_finish
    mov [rip + Lrt_stderr], rax
    lea rdi, [rsp + 48]
    call _bit_buf_finish
    add rsp, 152
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  mov rdi, rbx
    call _free
    xor r14d, r14d
91: mov edi, dword ptr [rsp + r14]
    test edi, edi
    js 92f
    call _close
92: add r14, 4
    cmp r14, 24
    jne 91b
    lea rdi, [rip + Lrt_erun]
    mov rsi, r13
    call _bit_die

_bit_term_stderr:                   // → копия stderr последнего mas >> run ("" если не было)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, [rip + Lrt_stderr]
    test rbx, rbx
    jnz 1f
    mov edi, 1
    call _bit_alloc
    mov byte ptr [rax], 0
    jmp 2f
1:  mov rdi, rbx
    call _strlen
    mov rsi, rax
    mov rdi, rbx
    call _bit_substr
2:  pop r12
    pop rbx
    pop rbp
    ret

.section __DATA,__data
.p2align 3
Lrt_str_registry: .quad 0
Lrt_str_low: .quad -1
Lrt_str_high: .quad 0
Lrt_argc: .quad 0
Lrt_argv: .quad 0
Lrt_status: .quad 0
Lrt_random_state: .quad 0
Lrt_random_ready: .quad 0
Lrt_recover: .quad 0
Lrt_owned: .quad 0
Lrt_errmsg: .quad 0
Lrt_errline: .quad 0
.p2align 2
Lrt_signalled: .long 0
Lrt_ready: .byte 0
.p2align 3
Lrt_tkey: .quad 0
Lrt_thread_list: .quad 0
Lrt_thread_next: .quad 1
Lrt_slock: .zero 80
.p2align 3
Lrt_stderr: .quad 0
.p2align 4
.section __TEXT,__cstring,cstring_literals
Lrt_eclock: .asciz "не могу узнать монотонное время"
Lrt_elisten_addr: .asciz "listen: неверный IPv4-адрес"
Lrt_peer_colon: .asciz ":"
Lrt_epeer: .asciz "не могу узнать адрес собеседника"
Lrt_curl: .asciz "curl"
Lrt_sS: .asciz "-sS"
Lrt_L: .asciz "-L"
Lrt_ddp: .asciz "--"
Lrt_d: .asciz "-d"
Lrt_o: .asciz "-o"
Lrt_pingp: .asciz "ping"
Lrt_pingc: .asciz "-c"
Lrt_devnull: .asciz "/dev/null"
Lrt_userenv: .asciz "USER"
Lrt_ecpus: .asciz "os >> cpus: cannot determine processor count"
Lrt_pspc: .asciz " "
Lrt_pnl: .asciz "\012"
Lrt_eprocs: .asciz "os >> procs: cannot list processes"
Lrt_edns: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\275\320\260\320\271\321\202\320\270 \320\260\320\264\321\200\320\265\321\201 \321\205\320\276\321\201\321\202\320\260"
Lrt_pingcmd: .asciz "ping -c 1 "
Lrt_quiet: .asciz " >/dev/null 2>&1"
Lrt_curlget: .asciz "curl -sS -L -- "
Lrt_curlpost: .asciz "curl -sS -L -d "
Lrt_curlout: .asciz "curl -sS -L -o "
Lrt_dashdash: .asciz " -- "
Lrt_enet: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\277\320\276\320\264\320\272\320\273\321\216\321\207\320\270\321\202\321\214\321\201\321\217"
Lrt_econn_timeout: .asciz "\320\270\321\201\321\202\320\265\320\272\320\273\320\276 \320\262\321\200\320\265\320\274\321\217 \320\276\320\266\320\270\320\264\320\260\320\275\320\270\321\217 \320\277\320\276\320\264\320\272\320\273\321\216\321\207\320\265\320\275\320\270\321\217"
Lrt_econn_args: .asciz "connect: \321\202\320\260\320\271\320\274\320\260\321\203\321\202 \320\276\321\202 0 \320\264\320\276 2147483647 \320\274\321\201"
Lrt_elisten: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\276\321\202\320\272\321\200\321\213\321\202\321\214 \320\277\320\276\321\200\321\202"
Lrt_eaccept: .asciz "\320\276\321\210\320\270\320\261\320\272\320\260 \320\277\321\200\320\270\321\221\320\274\320\260 \320\277\320\276\320\264\320\272\320\273\321\216\321\207\320\265\320\275\320\270\321\217"
Lrt_esend: .asciz "\320\276\321\210\320\270\320\261\320\272\320\260 \320\276\321\202\320\277\321\200\320\260\320\262\320\272\320\270"
Lrt_erecv: .asciz "\320\276\321\210\320\270\320\261\320\272\320\260 \320\277\321\200\320\270\321\221\320\274\320\260"
Lrt_e8: .asciz "\320\262 bytes \320\275\320\265\321\202 8 \320\261\320\260\320\271\321\202 \321\201 \321\215\321\202\320\276\320\263\320\276 \320\275\320\276\320\274\320\265\321\200\320\260"
Lrt_vmps: .asciz "vm.pagesize"
Lrt_hex: .asciz "0123456789abcdef"
Lrt_ovf: .asciz "\320\277\320\265\321\200\320\265\320\277\320\276\320\273\320\275\320\265\320\275\320\270\320\265 num \342\200\224 \321\207\320\270\321\201\320\273\320\276 \320\275\320\265 \320\262\320\273\320\265\320\267\320\273\320\276"
Lrt_echunk: .asciz "\321\201\320\274\320\265\321\211\320\265\320\275\320\270\320\265\040\320\270\040\321\200\320\260\320\267\320\274\320\265\321\200\040\320\264\320\276\320\273\320\266\320\275\321\213\040\320\261\321\213\321\202\321\214\040\320\275\320\265\320\276\321\202\321\200\320\270\321\206\320\260\321\202\320\265\320\273\321\214\320\275\321\213\320\274\320\270"
Lrt_erecv_timeout: .asciz "\320\270\321\201\321\202\320\265\320\272\320\273\320\276\040\320\262\321\200\320\265\320\274\321\217\040\320\276\320\266\320\270\320\264\320\260\320\275\320\270\321\217\040\162\145\143\166"
Lrt_erecv_args: .asciz "\162\145\143\166\072\040\321\200\320\260\320\267\320\274\320\265\321\200\040\061\056\056\062\061\064\067\064\070\063\066\064\067\054\040\320\276\320\266\320\270\320\264\320\260\320\275\320\270\320\265\040\060\056\056\062\061\064\067\064\070\063\066\064\067\040\320\274\321\201"
Lrt_wb: .asciz "wb"
Lrt_copy_suffix: .asciz ".bit-copy-XXXXXX"
Lrt_badnum: .asciz "invalid num: expected a decimal integer in range"
Lrt_random_bounds: .asciz "random: expected minimum <= maximum"
Lrt_random_entropy: .asciz "random: cannot read system entropy"
Lrt_gp: .asciz "%.*g"
Lrt_fp: .asciz "%.*f"
Lrt_ecode_empty: .asciz "\320\272\320\276\320\264: \320\277\321\203\321\201\321\202\320\260\321\217 \321\201\321\202\321\200\320\276\320\272\320\260"
Lrt_echar_range: .asciz "char: \320\272\320\276\320\264 \321\201\320\270\320\274\320\262\320\276\320\273\320\260 \320\276\321\202 0 \320\264\320\276 1114111"
Lrt_elock: .asciz "lock operation failed"
Lrt_ewait_thread: .asciz "thread wait failed"
Lrt_esignal: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \321\203\321\201\321\202\320\260\320\275\320\276\320\262\320\270\321\202\321\214 \320\276\320\261\321\200\320\260\320\261\320\276\321\202\321\207\320\270\320\272 \321\201\320\270\320\263\320\275\320\260\320\273\320\276\320\262"
Lrt_ethread: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \321\201\320\276\320\267\320\264\320\260\321\202\321\214 \320\277\320\276\321\202\320\276\320\272"
Lrt_epad_width: .asciz "pad: \321\210\320\270\321\200\320\270\320\275\320\260 \320\276\321\202 0 \320\264\320\276 1000000"
Lrt_epad_count: .asciz "repeat: \321\207\320\270\321\201\320\273\320\276 \320\276\321\202 0 \320\264\320\276 100000000"
Lrt_ehex_width: .asciz "hex: \321\210\320\270\321\200\320\270\320\275\320\260 \320\276\321\202 0 \320\264\320\276 64"
Lrt_efixed_places: .asciz "fixed: \320\267\320\275\320\260\320\272\320\276\320\262 \320\276\321\202 0 \320\264\320\276 17"
Lrt_eread: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\277\321\200\320\276\321\207\320\270\321\202\320\260\321\202\321\214 \321\204\320\260\320\271\320\273: "
Lrt_enotfile: .asciz "\321\215\321\202\320\276 \320\275\320\265 \321\204\320\260\320\271\320\273: "
Lrt_enotdir: .asciz "\321\215\321\202\320\276 \320\275\320\265 \320\277\320\260\320\277\320\272\320\260: "
Lrt_die: .asciz "\012\320\236\321\210\320\270\320\261\320\272\320\260 \320\262\321\213\320\277\320\276\320\273\320\275\320\265\320\275\320\270\321\217 (\321\201\321\202\321\200\320\276\320\272\320\260 %lld): %s\012"
Lrt_oom: .asciz "\320\275\320\265 \321\205\320\262\320\260\321\202\320\260\320\265\321\202 \320\277\320\260\320\274\321\217\321\202\320\270"
Lrt_full: .asciz "\320\274\320\260\321\201\321\201\320\270\320\262 \320\267\320\260\320\277\320\276\320\273\320\275\320\265\320\275 \342\200\224 \321\215\320\273\320\265\320\274\320\265\320\275\321\202\320\276\320\262 \321\203\320\266\320\265 \321\201\321\202\320\276\320\273\321\214\320\272\320\276, \321\201\320\272\320\276\320\273\321\214\320\272\320\276 \320\273\320\270\320\274\320\270\321\202"
Lrt_eof: .asciz "\320\262\320\262\320\276\320\264 \320\267\320\260\320\272\320\276\320\275\321\207\320\270\320\273\321\201\321\217, \320\260 \320\277\321\200\320\276\320\263\321\200\320\260\320\274\320\274\320\260 \320\266\320\264\320\260\320\273\320\260 \320\267\320\275\320\260\321\207\320\265\320\275\320\270\320\265"
Lrt_lld: .asciz "%lld"
Lrt_g: .asciz "%.15g"
Lrt_decch: .asciz ".eni"
Lrt_dot0: .asciz ".0"
Lrt_true: .asciz "true"
Lrt_false: .asciz "false"
Lrt_da: .asciz "\320\264\320\260"
Lrt_net: .asciz "\320\275\320\265\321\202"
Lrt_1: .asciz "1"
Lrt_0: .asciz "0"
Lrt_lpar: .asciz "("
Lrt_rpar: .asciz ")"
Lrt_comma: .asciz ", "
Lrt_numr: .asciz "\320\275\321\203\320\266\320\275\320\276 \321\206\320\265\320\273\320\276\320\265 \321\207\320\270\321\201\320\273\320\276 \320\276\321\202 %lld \320\264\320\276 %lld, \320\277\320\276\320\277\321\200\320\276\320\261\321\203\320\271 \320\265\321\211\321\221 \321\200\320\260\320\267: "
Lrt_num: .asciz "\320\275\321\203\320\266\320\275\320\276 \321\206\320\265\320\273\320\276\320\265 \321\207\320\270\321\201\320\273\320\276, \320\277\320\276\320\277\321\200\320\276\320\261\321\203\320\271 \320\265\321\211\321\221 \321\200\320\260\320\267: "
Lrt_decr: .asciz "\320\275\321\203\320\266\320\275\320\276 \321\207\320\270\321\201\320\273\320\276 \320\276\321\202 %g \320\264\320\276 %g, \320\277\320\276\320\277\321\200\320\276\320\261\321\203\320\271 \320\265\321\211\321\221 \321\200\320\260\320\267: "
Lrt_dec: .asciz "\320\275\321\203\320\266\320\275\320\276 \321\207\320\270\321\201\320\273\320\276, \320\277\320\276\320\277\321\200\320\276\320\261\321\203\320\271 \320\265\321\211\321\221 \321\200\320\260\320\267: "
Lrt_boolm: .asciz "\320\275\321\203\320\266\320\275\320\276 true \320\270\320\273\320\270 false (\320\264\320\260/\320\275\320\265\321\202), \320\277\320\276\320\277\321\200\320\276\320\261\321\203\320\271 \320\265\321\211\321\221 \321\200\320\260\320\267: "
Lrt_rb: .asciz "rb"
Lrt_w: .asciz "w"
Lrt_a: .asciz "a"
Lrt_r: .asciz "r"
Lrt_empty: .asciz ""

Lrt_ermroot: .asciz "remove_all: нельзя удалять корень, пустой путь, . или ..: "
Lrt_ermtree: .asciz "не могу удалить папку с содержимым: "
Lrt_remove_home: .asciz "HOME"
Lrt_ermhome: .asciz "remove_all: нельзя удалять домашнюю папку: "
Lrt_permchars: .asciz "rwxrwxrwx"
Lrt_epermissions: .asciz "permissions: нужны ровно 9 символов rwx на своих местах или -"
Lrt_epermread: .asciz "не могу узнать права доступа: "
Lrt_epermwrite: .asciz "не могу изменить права доступа: "

Lrt_ecwd: .asciz "не могу узнать текущую папку"
Lrt_ego: .asciz "не могу сменить папку: "
Lrt_eenv: .asciz "не могу задать переменную окружения: "
Lrt_slash: .asciz "/"
Lrt_msh: .asciz "sh"
Lrt_mdashc: .asciz "-c"
Lrt_mbinsh: .asciz "/bin/sh"
Lrt_mespawn: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\267\320\260\320\277\321\203\321\201\321\202\320\270\321\202\321\214: "
Lrt_mekill: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\276\321\201\321\202\320\260\320\275\320\276\320\262\320\270\321\202\321\214 \320\277\321\200\320\276\321\206\320\265\321\201\321\201 "
Lrt_cls: .asciz "\033[2J\033[H"
Lrt_memsize: .asciz "hw.memsize"
Lrt_eopen: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\276\321\202\320\272\321\200\321\213\321\202\321\214 \321\204\320\260\320\271\320\273: "
Lrt_ewrite: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\267\320\260\320\277\320\270\321\201\320\260\321\202\321\214 \320\262 \321\204\320\260\320\271\320\273: "
Lrt_erm: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \321\203\320\264\320\260\320\273\320\270\321\202\321\214: "
Lrt_emv: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\277\320\265\321\200\320\265\320\274\320\265\321\201\321\202\320\270\321\202\321\214: "
Lrt_emk: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \321\201\320\276\320\267\320\264\320\260\321\202\321\214 \320\277\320\260\320\277\320\272\321\203: "
Lrt_edir: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\276\321\202\320\272\321\200\321\213\321\202\321\214 \320\277\320\260\320\277\320\272\321\203: "
Lrt_erun: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\267\320\260\320\277\321\203\321\201\321\202\320\270\321\202\321\214 \320\272\320\276\320\274\320\260\320\275\320\264\321\203: "
.section __TEXT,__text,regular,pure_instructions
