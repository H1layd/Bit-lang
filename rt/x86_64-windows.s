// ─────────── среда выполнения bit (Windows x64) ───────────
// Внутри bit всё по своему соглашению (rdi, rsi, rdx...), а соглашение Windows
// (rcx, rdx, r8, r9 + 32 байта «теневого» места) спрятано в обёртках _w_* и ядре.
.intel_syntax noprefix
.text

// ── обёртки libc: вход по-нашему (rdi,rsi,rdx,rcx), внутри — Windows ABI ──
_w_getentropy:
    sub rsp, 40
    xor ecx, ecx
    mov rdx, rdi
    mov r8d, esi
    mov r9d, 2
    call BCryptGenRandom
    add rsp, 40
    ret
_w_rename:
    sub rsp, 40
    mov rcx, rdi
    mov rdx, rsi
    // MOVEFILE_REPLACE_EXISTING
    mov r8d, 1
    call MoveFileExA
    test eax, eax
    jnz 1f
    call GetLastError
    mov dword ptr [rsp + 32], eax
    mov rcx, rdi
    mov rdx, rsi
    call strcmp
    test eax, eax
    jnz 2f
    mov rcx, rdi
    call GetFileAttributesA
    cmp eax, -1
    jne 1f
2:  mov eax, dword ptr [rsp + 32]
    // ERROR_NOT_SAME_DEVICE -> EXDEV
    mov ecx, 5
    mov edx, 18
    cmp eax, 17
    cmove ecx, edx
    mov dword ptr [rsp + 32], ecx
    call _errno
    mov ecx, dword ptr [rsp + 32]
    mov dword ptr [rax], ecx
    mov eax, -1
    add rsp, 40
    ret
1:  xor eax, eax
    add rsp, 40
    ret
_w_malloc:
    sub rsp, 40
    mov rcx, rdi
    call malloc
    add rsp, 40
    ret
_w_calloc:
    sub rsp, 40
    mov rcx, rdi
    mov rdx, rsi
    call calloc
    add rsp, 40
    ret
_w_realloc:
    sub rsp, 40
    mov rcx, rdi
    mov rdx, rsi
    call realloc
    add rsp, 40
    ret
_w_free:
    sub rsp, 40
    mov rcx, rdi
    call free
    add rsp, 40
    ret
_w_strlen:
    sub rsp, 40
    mov rcx, rdi
    call strlen
    add rsp, 40
    ret
_w_memcpy:
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call memcpy
    add rsp, 40
    ret
_w_qsort:
    mov r9, rcx
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call qsort
    add rsp, 40
    ret

// ── ядро ──
_bit_alloc:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov rcx, rdi
    call malloc
    add rsp, 32
    pop rbp
    test rax, rax
    jz _bit_oom
    ret

_bit_oom:
    sub rsp, 40
    lea rcx, [rip + Lrt_oom]
    call puts
    mov ecx, 1
    call exit

_bit_rt_ensure:                      # подготовка ключа потока и замка строк
    cmp byte ptr [rip + Lrt_ready], 0
    jne 9f
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    call TlsAlloc
    mov [rip + Lrt_tkey], rax
    lea rcx, [rip + Lrt_slock]
    call InitializeCriticalSection
    mov byte ptr [rip + Lrt_ready], 1
    mov rsp, rbp
    pop rbp
9:  ret

_bit_lock:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    call _bit_rt_ensure
    lea rcx, [rip + Lrt_slock]
    call EnterCriticalSection
    mov rsp, rbp
    pop rbp
    ret

_bit_unlock:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    lea rcx, [rip + Lrt_slock]
    call LeaveCriticalSection
    mov rsp, rbp
    pop rbp
    ret

_bit_tstate:                         # → блок состояния этого потока
    push rbp
    mov rbp, rsp
    push rbx
    and rsp, -16
    sub rsp, 32
    call _bit_rt_ensure
    mov rcx, [rip + Lrt_tkey]
    call TlsGetValue
    test rax, rax
    jnz 9f
    mov edi, 64
    call _bit_alloc
    mov rbx, rax
    xor ecx, ecx
1:  mov qword ptr [rbx + rcx*8], 0
    inc rcx
    cmp rcx, 8
    jl 1b
    mov rcx, [rip + Lrt_tkey]
    mov rdx, rbx
    call TlsSetValue
    mov rax, rbx
9:  lea rsp, [rbp - 8]
    pop rbx
    pop rbp
    ret

_bit_recover_enter:                  # rdi = frame
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    and rsp, -16
    sub rsp, 32
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
    lea rsp, [rbp - 16]
    pop r12
    pop rbx
    pop rbp
    ret

_bit_recover_leave:
    push rbp
    mov rbp, rsp
    push rbx
    and rsp, -16
    sub rsp, 32
    call _bit_tstate
    mov rbx, rax
    mov rax, [rbx]
    mov rax, [rax + 168]
    mov [rbx], rax
    lea rsp, [rbp - 8]
    pop rbx
    pop rbp
    ret

_bit_own_str:                        # rdi = запись со строкой и ссылкой на прежнюю
    push rbp
    mov rbp, rsp
    push rbx
    and rsp, -16
    sub rsp, 32
    mov rbx, rdi
    call _bit_tstate
    mov rcx, [rax + 8]
    mov [rbx + 8], rcx
    mov [rax + 8], rbx
    lea rsp, [rbp - 8]
    pop rbx
    pop rbp
    ret

_bit_drop_owned:
    push rbp
    mov rbp, rsp
    push rbx
    and rsp, -16
    sub rsp, 32
    call _bit_tstate
    mov rbx, rax
    mov rax, [rbx + 8]
    mov rcx, [rax + 8]
    mov [rbx + 8], rcx
    mov rdi, [rax]
    lea rsp, [rbp - 8]
    pop rbx
    pop rbp
    jmp _bit_drop_str

_bit_set_errcode:                    # rdi = код для этого потока
    push rbp
    mov rbp, rsp
    push rbx
    and rsp, -16
    sub rsp, 32
    mov rbx, rdi
    call _bit_tstate
    mov [rax + 32], rbx
    lea rsp, [rbp - 8]
    pop rbx
    pop rbp
    ret

_bit_term_errcode:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    call _bit_tstate
    mov rax, [rax + 32]
    mov rsp, rbp
    pop rbp
    ret

_bit_term_error:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    and rsp, -16
    sub rsp, 32
    call _bit_tstate
    mov rbx, [rax + 16]
    test rbx, rbx
    jnz 1f
    mov edi, 1
    call _bit_alloc
    mov byte ptr [rax], 0
    jmp 2f
1:  mov rdi, rbx
    call _w_strlen
    mov rsi, rax
    mov rdi, rbx
    call _bit_substr
2:  lea rsp, [rbp - 16]
    pop r12
    pop rbx
    pop rbp
    ret

_bit_die:                            # rdi = сообщение, rsi = строка программы
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    and rsp, -16
    sub rsp, 32
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
    lea rsp, [rbp - 24]
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_longjmp
5:  mov r8, r12
    mov rdx, r13
    lea rcx, [rip + Lrt_die]
    call printf
    mov ecx, 1
    call exit

_bit_print:
    sub rsp, 40
    mov rcx, rdi
    call puts
    add rsp, 40
    ret

_bit_drop_str:
    jmp _bit_str_release

_bit_string_str:
    mov rax, rdi
    ret

_bit_dec_fixed:                       # rdi=биты dec, rsi=знаков после точки, rdx=строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    and rsp, -16
    sub rsp, 64
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    js 9f
    cmp r12, 17
    jg 9f
    lea r8, [rsp + 32]
    mov byte ptr [r8], 37
    mov byte ptr [r8 + 1], 46
    mov rax, r12
    cmp rax, 10
    jl 1f
    mov byte ptr [r8 + 2], 49
    sub rax, 10
    add al, 48
    mov byte ptr [r8 + 3], al
    mov byte ptr [r8 + 4], 102
    mov byte ptr [r8 + 5], 0
    jmp 2f
1:  add al, 48
    mov byte ptr [r8 + 2], al
    mov byte ptr [r8 + 3], 102
    mov byte ptr [r8 + 4], 0
2:  mov edi, 512
    call _bit_alloc
    mov r14, rax
    mov rcx, rax
    mov edx, 512
    lea r8, [rsp + 32]
    mov r9, rbx
    movq xmm3, rbx
    mov eax, 1
    call snprintf
    mov rcx, r14
    call strlen
    mov rsi, rax
    mov rdi, r14
    call _bit_substr
    lea rsp, [rbp - 32]
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_efixed_places]
    mov rsi, r13
    lea rsp, [rbp - 32]
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_bool_str:
    lea rax, [rip + Lrt_true]
    test rdi, rdi
    jnz 1f
    lea rax, [rip + Lrt_false]
1:  ret

_bit_num_str:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32
    mov r12, rdi
    mov edi, 32
    call _bit_alloc
    mov rbx, rax
    mov rcx, rax
    mov edx, 32
    lea r8, [rip + Lrt_lld]
    mov r9, r12
    call snprintf
    mov rax, rbx
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

_bit_dec_str:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32
    mov r12, rdi
    mov edi, 48
    call _bit_alloc
    mov rbx, rax
    mov rcx, rax
    mov edx, 48
    lea r8, [rip + Lrt_g]
    mov r9, r12
    movq xmm3, r12
    call snprintf
    mov rcx, rbx
    lea rdx, [rip + Lrt_decch]
    call strpbrk
    test rax, rax
    jnz 1f
    mov rcx, rbx
    lea rdx, [rip + Lrt_dot0]
    call strcat
1:  mov rax, rbx
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

_bit_cat:
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
    mov rcx, rbx
    call strlen
    mov r13, rax
    mov rcx, r12
    call strlen
    mov r14, rax
    lea rdi, [r13 + r14 + 1]
    call _bit_alloc
    mov r15, rax
    mov rcx, r15
    mov rdx, rbx
    mov r8, r13
    call memcpy
    lea rcx, [r15 + r13]
    mov rdx, r12
    lea r8, [r14 + 1]
    call memcpy
    mov rax, r15
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_str_eq:
    sub rsp, 40
    mov rcx, rdi
    mov rdx, rsi
    call strcmp
    add rsp, 40
    test eax, eax
    sete al
    movzx eax, al
    ret

_bit_str_sz:
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

// ── сравнения для сортировки: вход по Windows ABI (rcx, rdx) — их зовёт qsort ──
_bit_cmp_num:
    mov rax, [rcx]
    mov r8, [rdx]
    cmp rax, r8
    setg al
    setl r8b
    movzx eax, al
    movzx r8d, r8b
    sub eax, r8d
    ret
_bit_cmp_dec:
    movsd xmm0, [rcx]
    movsd xmm1, [rdx]
    xor eax, eax
    xor r8d, r8d
    ucomisd xmm0, xmm1
    seta al
    ucomisd xmm1, xmm0
    seta r8b
    movzx r8d, r8b
    sub eax, r8d
    ret
_bit_strptr_cmp:
    mov rax, [rcx]
    mov rdx, [rdx]
    mov rcx, rax
    sub rsp, 40
    call strcmp
    add rsp, 40
    ret

// ── память компьютера (Windows API) ──
_bit_mem_total:
    push rbp
    mov rbp, rsp
    sub rsp, 96
    lea rcx, [rsp + 32]
    mov dword ptr [rsp + 32], 64
    call GlobalMemoryStatusEx
    mov rax, [rsp + 40]
    add rsp, 96
    pop rbp
    ret
_bit_mem_free:
    push rbp
    mov rbp, rsp
    sub rsp, 96
    lea rcx, [rsp + 32]
    mov dword ptr [rsp + 32], 64
    call GlobalMemoryStatusEx
    mov rax, [rsp + 48]
    add rsp, 96
    pop rbp
    ret
_bit_mem_used:
    push rbp
    mov rbp, rsp
    sub rsp, 96
    lea rcx, [rsp + 32]
    mov dword ptr [rsp + 32], 64
    call GlobalMemoryStatusEx
    mov rax, [rsp + 40]
    sub rax, [rsp + 48]
    add rsp, 96
    pop rbp
    ret

_w_fopen:
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call fopen
    add rsp, 40
    ret
_w_fclose:
    mov rcx, rdi
    sub rsp, 40
    call fclose
    add rsp, 40
    ret
_w_fread:
    mov r9, rcx
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call fread
    add rsp, 40
    ret
_w_fwrite:
    mov r9, rcx
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call fwrite
    add rsp, 40
    ret
_w_fseek:
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call fseek
    add rsp, 40
    ret
_w_ftell:
    mov rcx, rdi
    sub rsp, 40
    call ftell
    add rsp, 40
    ret
_w_fseeko:
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call _fseeki64
    add rsp, 40
    ret
_w_fdopen:
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call _fdopen
    add rsp, 40
    ret
_w_close:
    mov rcx, rdi
    sub rsp, 40
    call _close
    add rsp, 40
    ret
_w_ferror:
    mov rcx, rdi
    sub rsp, 40
    call ferror
    add rsp, 40
    ret
_w_fflush:
    mov rcx, rdi
    sub rsp, 40
    call fflush
    add rsp, 40
    ret
_w_fputs:
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call fputs
    add rsp, 40
    ret
_w_strrchr:
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call strrchr
    add rsp, 40
    ret
_w_mkstemp:
    mov rcx, rdi
    sub rsp, 40
    call mkstemp
    add rsp, 40
    ret
_w_strcmp:
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call strcmp
    add rsp, 40
    ret
_w_strtoll:
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call strtoll
    add rsp, 40
    ret
_w_strtod:
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call strtod
    add rsp, 40
    ret
_w_getenv:
    mov rcx, rdi
    sub rsp, 40
    call getenv
    add rsp, 40
    ret
_w_time:
    mov rcx, rdi
    sub rsp, 40
    call time
    add rsp, 40
    ret
_w_unlink:
    mov rcx, rdi
    sub rsp, 40
    call _unlink
    add rsp, 40
    ret
_w_rmdir:
    mov rcx, rdi
    sub rsp, 40
    call _rmdir
    add rsp, 40
    ret
_w_mkdir:
    mov rcx, rdi
    sub rsp, 40
    call _mkdir
    add rsp, 40
    ret
_w_popen:
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call _popen
    add rsp, 40
    ret
_w_pclose:
    mov rcx, rdi
    sub rsp, 40
    call _pclose
    add rsp, 40
    ret
_w_system:
    mov rcx, rdi
    sub rsp, 40
    call system
    add rsp, 40
    ret


_bit_os_clock:                      # monotonic milliseconds since boot
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    call GetTickCount64
    mov rsp, rbp
    pop rbp
    ret


_bit_remove_is_home:                // canonical target -> bool
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    lea rdi, [rip + Lrt_remove_profile]
    call _w_getenv
    test rax, rax
    jz 1f
    mov rsi, rax
    mov rdi, rbx
    call _bit_remove_same_home
    test rax, rax
    jnz 2f
1:  lea rdi, [rip + Lrt_remove_home]
    call _w_getenv
    test rax, rax
    jz 2f
    mov rsi, rax
    mov rdi, rbx
    call _bit_remove_same_home
2:  pop r12
    pop rbx
    pop rbp
    ret

_bit_remove_canonical:              // path -> owned resolved Windows path or 0
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 56
    mov rcx, rdi
    xor edx, edx
    mov r8d, 7
    xor r9d, r9d
    mov qword ptr [rsp + 32], 3
    mov qword ptr [rsp + 40], 0x02000000
    mov qword ptr [rsp + 48], 0
    call CreateFileA
    cmp rax, -1
    je 7f
    mov rbx, rax
    mov rcx, rax
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call GetFinalPathNameByHandleA
    test eax, eax
    jz 6f
    lea r13d, [eax + 1]
    mov edi, r13d
    call _bit_alloc
    mov r12, rax
    mov rcx, rbx
    mov rdx, r12
    mov r8d, r13d
    xor r9d, r9d
    call GetFinalPathNameByHandleA
    test eax, eax
    jz 5f
    cmp eax, r13d
    jae 5f
    mov rcx, rbx
    call CloseHandle
    mov rax, r12
    jmp 8f
5:  mov rdi, r12
    call _w_free
6:  mov rcx, rbx
    call CloseHandle
7:  xor eax, eax
8:  add rsp, 56
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_remove_same_home:              // target, HOME value -> HOME equals/is inside target
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 48
    mov r14, rsi
    cmp byte ptr [rsi], 0
    je 7f
    call _bit_remove_canonical
    test rax, rax
    jz 7f
    mov rbx, rax
    mov rdi, r14
    call _bit_remove_canonical
    test rax, rax
    jz 6f
    mov r13, rax
    xor r12d, r12d
    mov rcx, rbx
    mov rdx, r13
    call lstrcmpiA
    test eax, eax
    sete r12b
    test r12d, r12d
    jnz 5f
    mov rdi, rbx
    call _w_strlen
    mov [rsp + 32], rax
    mov rdi, r13
    call _w_strlen
    cmp rax, [rsp + 32]
    jbe 5f
    mov rax, [rsp + 32]
    cmp byte ptr [rbx + rax - 1], 92
    je 1f
    cmp byte ptr [r13 + rax], 92
    jne 5f
1:  mov byte ptr [r13 + rax], 0
    mov rcx, rbx
    mov rdx, r13
    call lstrcmpiA
    test eax, eax
    sete r12b
5:  mov rdi, r13
    call _w_free
    mov rdi, rbx
    call _w_free
    mov rax, r12
    jmp 8f
6:  mov rdi, rbx
    call _w_free
7:  xor eax, eax
8:  add rsp, 48
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


_bit_dir_remove_all:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 64
    mov r12, rsi
    lea rsi, [rip + Lrt_empty]
    call _bit_cat
    mov rbx, rax
    mov rdi, rax
    call _w_strlen
    test rax, rax
    jz 8f
1:  cmp rax, 1
    jbe 2f
    cmp rax, 3
    jne 12f
    cmp byte ptr [rbx + 1], 58
    je 2f
12: mov cl, byte ptr [rbx + rax - 1]
    cmp cl, 47
    je 11f
    cmp cl, 92
    jne 2f
11: dec rax
    mov byte ptr [rbx + rax], 0
    jmp 1b
2:  cmp byte ptr [rbx + rax - 1], 58
    je 8f
    cmp byte ptr [rbx + rax - 1], 46
    je 8f
    cmp byte ptr [rbx + rax - 1], 32
    je 8f
    cmp byte ptr [rbx], 92
    jne 24f
    cmp byte ptr [rbx + 1], 92
    jne 24f
    cmp byte ptr [rbx + 2], 63
    je 8f
    cmp byte ptr [rbx + 2], 46
    je 8f
24:
    mov rcx, rbx
    mov rdx, rbx
31: mov al, [rcx]
    test al, al
    jz 32f
    cmp al, 47
    je 33f
    cmp al, 92
    jne 34f
33: lea rdx, [rcx + 1]
34: inc rcx
    jmp 31b
32: cmp byte ptr [rdx], 46
    jne 35f
    cmp byte ptr [rdx + 1], 0
    je 8f
    cmp byte ptr [rdx + 1], 46
    jne 35f
    cmp byte ptr [rdx + 2], 0
    je 8f
35: mov rcx, rbx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call GetFullPathNameA
    test eax, eax
    jz 9f
    mov [rsp + 40], eax
    mov edi, eax
    call _bit_alloc
    mov r13, rax
    mov rcx, rbx
    mov edx, [rsp + 40]
    mov r8, r13
    lea r9, [rsp + 32]
    call GetFullPathNameA
    test eax, eax
    jz 7f
    cmp eax, [rsp + 40]
    jae 7f
    cmp qword ptr [rsp + 32], 0
    je 6f
    cmp byte ptr [r13], 92
    jne 3f
    cmp byte ptr [r13 + 1], 92
    jne 3f
    lea rcx, [r13 + 2]
    xor edx, edx
21: mov al, [rcx]
    test al, al
    jz 22f
    cmp al, 92
    jne 23f
    inc edx
23: inc rcx
    jmp 21b
22: cmp edx, 2
    jb 6f
3:  mov rdi, r13
    call _bit_remove_is_home
    test rax, rax
    jnz 36f
    mov rdi, r13
    mov esi, 1
    call _bit_win_remove_tree
    mov r14, rax
    mov rdi, r13
    call _w_free
    mov rdi, rbx
    call _w_free
    test r14, r14
    jnz 10f
    add rsp, 64
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
6:  mov rdi, r13
    call _w_free
    jmp 8f
7:  mov rdi, r13
    call _w_free
9:  lea rdi, [rip + Lrt_ermtree]
    mov rsi, rbx
    mov rdx, r12
    call _bit_remove_error
10: lea rdi, [rip + Lrt_ermtree]
    mov rsi, r14
    mov rdx, r12
    call _bit_remove_error
36: mov rdi, r13
    call _w_free
    lea rdi, [rip + Lrt_ermhome]
    mov rsi, rbx
    mov rdx, r12
    call _bit_remove_error
8:  lea rdi, [rip + Lrt_ermroot]
    mov rsi, rbx
    mov rdx, r12
    call _bit_remove_error

_bit_win_remove_tree:               // path, require directory -> 0/owned error path
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 408
    mov rbx, rdi
    mov [rsp + 392], rsi
    mov qword ptr [rsp + 400], 0
    mov rcx, rdi
    xor edx, edx
    mov r8d, 3
    xor r9d, r9d
    mov qword ptr [rsp + 32], 3
    mov qword ptr [rsp + 40], 0x02200000
    mov qword ptr [rsp + 48], 0
    call CreateFileA
    cmp rax, -1
    je 9f
    mov r12, rax
    mov rcx, r12
    lea rdx, [rsp + 64]
    call GetFileInformationByHandle
    test eax, eax
    jz 8f
    mov r13d, [rsp + 64]
    cmp qword ptr [rsp + 392], 0
    je 1f
    test r13d, 16
    jz 8f
1:  test r13d, 16
    jz 6f
    test r13d, 0x400
    jnz 6f
    mov rdi, rbx
    lea rsi, [rip + Lrt_star]
    call _bit_cat
    mov r15, rax
    mov rcx, rax
    lea rdx, [rsp + 64]
    call FindFirstFileA
    mov r14, rax
    mov rdi, r15
    call _w_free
    cmp r14, -1
    je 8f
2:  lea rsi, [rsp + 108]
    cmp byte ptr [rsi], 46
    jne 3f
    cmp byte ptr [rsi + 1], 0
    je 4f
    cmp byte ptr [rsi + 1], 46
    jne 3f
    cmp byte ptr [rsi + 2], 0
    je 4f
3:  mov rdi, rbx
    lea rsi, [rip + Lrt_slash]
    call _bit_cat
    mov r15, rax
    mov rdi, rax
    lea rsi, [rsp + 108]
    call _bit_cat
    mov [rsp + 384], rax
    mov rdi, r15
    call _w_free
    mov rdi, [rsp + 384]
    xor esi, esi
    call _bit_win_remove_tree
    mov r15, rax
    mov rdi, [rsp + 384]
    call _w_free
    test r15, r15
    jnz 11f
4:  mov rcx, r14
    lea rdx, [rsp + 64]
    call FindNextFileA
    test eax, eax
    jnz 2b
    call GetLastError
    cmp eax, 18
    jne 7f
    mov rcx, r14
    call FindClose
6:  mov rcx, r12
    call CloseHandle
    mov rcx, rbx
    test r13d, 16
    jz 61f
    call RemoveDirectoryA
    jmp 62f
61: call DeleteFileA
62: test eax, eax
    jz 9f
    xor eax, eax
    jmp 10f
11: mov [rsp + 400], r15
7:  mov rcx, r14
    call FindClose
8:  mov rcx, r12
    call CloseHandle
9:  mov rax, [rsp + 400]
    test rax, rax
    jnz 10f
    mov rdi, rbx
    lea rsi, [rip + Lrt_empty]
    call _bit_cat
10: add rsp, 408
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret




_bit_follow_file_info:              // FileInfo pointer -> pointer/0, only for reparse-point files
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 120
    mov rbx, rdi
    mov rcx, [rdi]
    xor edx, edx
    mov r8d, 7
    xor r9d, r9d
    mov qword ptr [rsp + 32], 3
    mov qword ptr [rsp + 40], 0x02000000
    mov qword ptr [rsp + 48], 0
    call CreateFileA
    cmp rax, -1
    je 8f
    mov r12, rax
    mov rcx, rax
    lea rdx, [rsp + 64]
    call GetFileInformationByHandle
    test eax, eax
    jz 7f
    test dword ptr [rsp + 64], 16
    jnz 7f
    mov eax, [rsp + 96]
    shl rax, 32
    mov edx, [rsp + 100]
    or rax, rdx
    mov [rbx + 8], rax
    mov rax, [rsp + 84]
    xor edx, edx
    mov rcx, 10000000
    div rcx
    mov rcx, 11644473600
    sub rax, rcx
    mov [rbx + 16], rax
    mov rcx, r12
    call CloseHandle
    mov rax, rbx
    jmp 9f
7:  mov rcx, r12
    call CloseHandle
8:  xor eax, eax
9:  add rsp, 120
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_info_cmp:                     // qsort callback uses Win64 ABI
    mov rcx, [rcx]
    mov rdx, [rdx]
    mov rcx, [rcx]
    mov rdx, [rdx]
    sub rsp, 40
    call strcmp
    add rsp, 40
    ret

_bit_dir_entries_info:              // path, line -> sorted entries, metadata from enumeration
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 376
    mov rbx, rdi
    mov r12, rsi
    lea rsi, [rip + Lrt_star]
    call _bit_cat
    mov [rsp + 352], rax
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r14, rax
    mov rcx, [rsp + 352]
    lea rdx, [rsp + 32]
    call FindFirstFileA
    cmp rax, -1
    je 9f
    mov r13, rax
1:  lea rdi, [rsp + 76]
    cmp byte ptr [rdi], 46
    jne 2f
    cmp byte ptr [rdi + 1], 0
    je 5f
    cmp byte ptr [rdi + 1], 46
    jne 2f
    cmp byte ptr [rdi + 2], 0
    je 5f
2:  mov eax, [rsp + 32]
    and eax, 0x410
    cmp eax, 0x410
    je 5f
    mov rdi, rbx
    lea rsi, [rip + Lrt_slash]
    call _bit_cat
    mov [rsp + 360], rax
    mov rdi, rax
    lea rsi, [rsp + 76]
    call _bit_cat
    mov r15, rax
    mov rdi, [rsp + 360]
    call _w_free
    mov edi, 32
    call _bit_alloc
    mov [rsp + 360], rax
    mov [rax], r15
    mov edx, [rsp + 60]
    shl rdx, 32
    mov ecx, [rsp + 64]
    or rdx, rcx
    mov [rax + 8], rdx
    mov rax, [rsp + 52]
    xor edx, edx
    mov rcx, 10000000
    div rcx
    mov rcx, 11644473600
    sub rax, rcx
    mov r15, [rsp + 360]
    mov [r15 + 16], rax
    mov eax, 1
    test dword ptr [rsp + 32], 16
    jz 3f
    mov eax, 2
3:  mov [r15 + 24], rax
    test dword ptr [rsp + 32], 0x400
    jz 4f
    mov rdi, r15
    call _bit_follow_file_info
    test rax, rax
    jnz 4f
    mov rdi, [r15]
    call _w_free
    mov rdi, r15
    call _w_free
    jmp 5f
4:  mov rdi, r14
    mov rsi, r15
    mov rdx, r12
    call _bit_mas_add
5:  mov rcx, r13
    lea rdx, [rsp + 32]
    call FindNextFileA
    test eax, eax
    jnz 1b
    call GetLastError
    cmp eax, 18
    jne 8f
    mov rcx, r13
    call FindClose
    mov rdi, [rsp + 352]
    call _w_free
    mov rdi, [r14]
    mov rsi, [r14 + 8]
    mov edx, 8
    lea rcx, [rip + _bit_info_cmp]
    call _w_qsort
    mov rax, r14
    add rsp, 376
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  mov rcx, r13
    call FindClose
9:  mov rdi, [rsp + 352]
    call _w_free
    lea rdi, [rip + Lrt_edir]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_walk_info_into:                // path, output array, line
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rsi
    mov r13, rdx
    mov rsi, rdx
    call _bit_dir_entries_info
    mov r14, rax
    xor r15d, r15d
1:  cmp r15, [r14 + 8]
    jge 5f
    mov rax, [r14]
    mov rbx, [rax + r15*8]
    cmp qword ptr [rbx + 24], 2
    jne 2f
    mov rdi, [rbx]
    mov rsi, r12
    mov rdx, r13
    call _bit_walk_info_into
    mov rdi, [rbx]
    call _w_free
    mov rdi, rbx
    call _w_free
    jmp 4f
2:  mov rdi, r12
    mov rsi, rbx
    mov rdx, r13
    call _bit_mas_add
4:  inc r15
    jmp 1b
5:  mov rdi, [r14]
    call _w_free
    mov rdi, r14
    call _w_free
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


_bit_read_only_get:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32
    mov rbx, rdi
    mov r12, rsi
    mov rcx, rdi
    call GetFileAttributesA
    cmp eax, -1
    je 9f
    and eax, 1
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_epermread]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_read_only_set:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 40
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rcx, rdi
    call GetFileAttributesA
    cmp eax, -1
    je 9f
    test r12, r12
    jz 1f
    and eax, -129
    or eax, 1
    jmp 2f
1:  and eax, -2
    jnz 2f
    mov eax, 128
2:  mov rcx, rbx
    mov edx, eax
    call SetFileAttributesA
    test eax, eax
    jz 9f
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_epermwrite]
    mov rsi, rbx
    mov rdx, r13
    call _bit_errpath

// system()/pclose() return the exit code itself on Windows, not a POSIX wait status.
_bit_wstatus:
    mov eax, edi
    cmp eax, -1
    jne 1f
    mov eax, 127
1:  mov [rip + Lrt_status], rax
    ret

_bit_term_folder:                   // rdi = строка программы → новая строка с текущей папкой
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 48
    mov rbx, rdi
    xor ecx, ecx
    xor edx, edx
    call GetCurrentDirectoryA
    test eax, eax
    jz 9f
    mov [rsp + 32], eax
    mov edi, eax
    call _bit_alloc
    mov r12, rax
    mov ecx, [rsp + 32]
    mov rdx, r12
    call GetCurrentDirectoryA
    test eax, eax
    jz 8f
    cmp eax, [rsp + 32]
    jae 8f
    mov rax, r12
    add rsp, 48
    pop r12
    pop rbx
    pop rbp
    ret
8:  mov rcx, r12
    call free
9:  lea rdi, [rip + Lrt_ecwd]
    mov rsi, rbx
    call _bit_die

_bit_term_go:                       // rdi = путь, rsi = строка программы
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32
    mov rbx, rdi
    mov r12, rsi
    mov rcx, rdi
    call SetCurrentDirectoryA
    test eax, eax
    jz 9f
    add rsp, 32
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
    push r13
    sub rsp, 40
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp byte ptr [rbx], 0
    je 9f
    mov rax, rbx
1:  movzx ecx, byte ptr [rax]
    test ecx, ecx
    jz 2f
    cmp ecx, 61
    je 9f
    inc rax
    jmp 1b
2:  mov rcx, rbx
    mov rdx, r12
    call _putenv_s
    test eax, eax
    jnz 9f
    mov rcx, rbx
    mov rdx, r12
    call SetEnvironmentVariableA
    test eax, eax
    jz 9f
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_eenv]
    mov rsi, rbx
    mov rdx, r13
    call _bit_errpath

// ── запуск: консоль в UTF-8, как терминал macOS и Linux; при выходе вернуть как было ──
_bit_win_init:
    sub rsp, 40
    call GetConsoleOutputCP
    mov [rip + Lrt_oldocp], rax
    call GetConsoleCP
    mov [rip + Lrt_oldicp], rax
    mov ecx, 65001
    call SetConsoleOutputCP
    mov ecx, 65001
    call SetConsoleCP
    lea rcx, [rip + _bit_win_restore]
    call atexit
    add rsp, 40
    ret
_bit_win_restore:
    sub rsp, 40
    mov rcx, [rip + Lrt_oldocp]
    test ecx, ecx
    jz 1f
    call SetConsoleOutputCP
    mov rcx, [rip + Lrt_oldicp]
    call SetConsoleCP
1:  add rsp, 40
    ret

// ── манифест: системные вызовы *A (пути, команды, аргументы) понимают UTF-8 ──
.section .rsrc,"dr"
.p2align 2
Lrsrc_root:
    .long 0, 0
    .short 0, 0, 0, 1
    .long 24, 0x80000000 + (Lrsrc_name - Lrsrc_root)
Lrsrc_name:
    .long 0, 0
    .short 0, 0, 0, 1
    .long 1, 0x80000000 + (Lrsrc_lang - Lrsrc_root)
Lrsrc_lang:
    .long 0, 0
    .short 0, 0, 0, 1
    .long 0x409, Lrsrc_data - Lrsrc_root
Lrsrc_data:
    .rva Lrsrc_manifest
    .long Lrsrc_end - Lrsrc_manifest
    .long 0, 0
Lrsrc_manifest:
    .ascii "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    .ascii "<assembly manifestVersion=\"1.0\" xmlns=\"urn:schemas-microsoft-com:asm.v1\">\n"
    .ascii "<application xmlns=\"urn:schemas-microsoft-com:asm.v3\"><windowsSettings>\n"
    .ascii "<activeCodePage xmlns=\"http://schemas.microsoft.com/SMI/2019/WindowsSettings\">UTF-8</activeCodePage>\n"
    .ascii "</windowsSettings></application>\n"
    .ascii "</assembly>\n"
Lrsrc_end:
.text

// ── ещё обёртки libc (без аргументов / особые) ──
_w_getchar:
    sub rsp, 40
    call getchar
    add rsp, 40
    ret
_w_errno:
    sub rsp, 40
    call _errno
    add rsp, 40
    ret
_w_gethostname:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call _bit_wsa_init
    mov rcx, rbx
    mov rdx, r12
    sub rsp, 32
    call gethostname
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

// ── чтение строки из консоли (через getchar, без POSIX getline) ──
_bit_readline:                      // rdi = строка программы → введённый текст
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r14, rdi
    xor edi, edi
    call _w_fflush
    mov edi, 16
    call _bit_alloc
    mov rbx, rax
    mov r12, 16
    xor r13, r13
1:  call _w_getchar
    cmp eax, -1
    je 8f
    cmp eax, 13
    je 1b
    cmp eax, 10
    je 3f
    mov r15d, eax
    lea rax, [r13 + 1]
    cmp rax, r12
    jb 2f
    shl r12, 1
    mov rdi, rbx
    mov rsi, r12
    call _w_realloc
    test rax, rax
    jz _bit_oom
    mov rbx, rax
2:  mov byte ptr [rbx + r13], r15b
    inc r13
    jmp 1b
3:  mov byte ptr [rbx + r13], 0
    mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  test r13, r13
    jnz 3b
    lea rdi, [rip + Lrt_eof]
    mov rsi, r14
    call _bit_die

// ── тип пути: 0 нет, 1 файл, 2 папка (через GetFileAttributes) ──
_bit_kind:                          // rdi = путь → 0/1/2
    sub rsp, 40
    mov rcx, rdi
    call GetFileAttributesA
    add rsp, 40
    cmp eax, -1
    je 0f
    test eax, 16
    jnz 2f
    mov eax, 1
    ret
2:  mov eax, 2
    ret
0:  xor eax, eax
    ret

// ── как _bit_kind, но ссылка/точка соединения — 3: обход по ней не заходит ──
_bit_lkind:                         // rdi = путь → 0/1/2/3
    sub rsp, 40
    mov rcx, rdi
    call GetFileAttributesA
    add rsp, 40
    cmp eax, -1
    je 0f
    test eax, 0x400
    jnz 3f
    test eax, 16
    jnz 2f
    mov eax, 1
    ret
2:  mov eax, 2
    ret
3:  mov eax, 3
    ret
0:  xor eax, eax
    ret

// ── время изменения файла (GetFileAttributesEx, FILETIME → секунды с 1970) ──
_bit_file_mtime:                    // rdi = путь, rsi = строка → секунды
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 112
    mov rbx, rdi
    mov r12, rsi
    mov rcx, rdi
    xor edx, edx
    lea r8, [rsp + 32]
    call GetFileAttributesExA
    test eax, eax
    jz 9f
    test dword ptr [rsp + 32], 0x400
    jz 1f
    mov [rsp + 80], rbx
    lea rdi, [rsp + 80]
    call _bit_follow_file_info
    test rax, rax
    jz 9f
    mov rax, [rsp + 96]
    jmp 2f
1:  mov rax, qword ptr [rsp + 52]
    xor edx, edx
    mov rcx, 10000000
    div rcx
    mov rcx, 11644473600
    sub rax, rcx
2:  add rsp, 112
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_eread]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

// ── список папки (через FindFirstFile/FindNextFile) ──
_bit_dir_list:                      // rdi = путь, rsi = строка → mas имён по алфавиту
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 360
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    lea rsi, [rip + Lrt_star]
    call _bit_cat
    mov r15, rax
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r14, rax
    lea rdx, [rsp]
    mov rcx, r15
    sub rsp, 32
    call FindFirstFileA
    add rsp, 32
    cmp rax, -1
    je 9f
    mov r13, rax
1:  lea rdi, [rsp + 44]
    cmp byte ptr [rdi], 46
    jne 2f
    movzx eax, byte ptr [rdi + 1]
    test eax, eax
    jz 5f
    cmp eax, 46
    jne 2f
    cmp byte ptr [rdi + 2], 0
    je 5f
2:  lea rsi, [rip + Lrt_empty]
    call _bit_cat
    mov rdi, r14
    mov rsi, rax
    mov rdx, r12
    call _bit_mas_add
5:  lea rdx, [rsp]
    mov rcx, r13
    sub rsp, 32
    call FindNextFileA
    add rsp, 32
    test eax, eax
    jnz 1b
    mov rcx, r13
    sub rsp, 32
    call FindClose
    add rsp, 32
    mov rdi, [r14]
    mov rsi, [r14 + 8]
    mov rdx, 8
    lea rcx, [rip + _bit_strptr_cmp]
    call _w_qsort
    mov rax, r14
    add rsp, 360
    pop r15
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

// ── число ядер (через GetSystemInfo) ──
_bit_os_cpus:                       // rdi = строка (не нужна) → число ядер
    sub rsp, 88
    lea rcx, [rsp + 32]
    call GetSystemInfo
    mov eax, dword ptr [rsp + 64]
    add rsp, 88
    ret

// ── терминал/процесс (Windows) ──
_bit_clear:                         // очистить экран (ANSI)
    push rbp
    mov rbp, rsp
    sub rsp, 32
    lea rcx, [rip + Lrt_cls]
    call printf
    add rsp, 32
    xor edi, edi
    call _w_fflush
    pop rbp
    ret

_bit_wait:                          // rdi = миллисекунды
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rdi
    xor edi, edi
    call _w_fflush
    mov rcx, rbx
    sub rsp, 32
    call Sleep
    add rsp, 32
    add rsp, 8
    pop rbx
    pop rbp
    ret

_bit_exit:                          // rdi = код выхода
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rdi
    xor edi, edi
    call _w_fflush
    mov rcx, rbx
    sub rsp, 32
    call exit

_bit_eof:                           // → 1 если ввод закончился
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    xor edi, edi
    call _w_fflush
    call _w_getchar
    cmp eax, -1
    je 1f
    mov ebx, eax
    xor ecx, ecx
    sub rsp, 32
    call __acrt_iob_func
    add rsp, 32
    mov rdx, rax
    mov ecx, ebx
    sub rsp, 32
    call ungetc
    add rsp, 32
    xor eax, eax
    jmp 2f
1:  mov eax, 1
2:  add rsp, 8
    pop rbx
    pop rbp
    ret

_bit_self_pid:                      // → pid текущего процесса
    sub rsp, 40
    call GetCurrentProcessId
    add rsp, 40
    mov eax, eax
    ret

// ── аргументы для _spawnvp: CRT склеивает их через пробел без кавычек, поэтому
//    каждый аргумент берём в кавычки сами — по правилам разбора командной строки MSVC ──
_bit_win_quote:                     // rdi = аргумент → rax = он же или копия в кавычках
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    xor ecx, ecx
    xor r8d, r8d
1:  movzx eax, byte ptr [rbx + rcx]
    test al, al
    jz 2f
    cmp al, 32
    je 11f
    cmp al, 9
    je 11f
    cmp al, 10
    je 11f
    cmp al, 11
    je 11f
    cmp al, 34
    jne 12f
11: mov r8d, 1
12: inc rcx
    jmp 1b
2:  test rcx, rcx
    jnz 21f
    mov r8d, 1
21: test r8d, r8d
    jnz 3f
    mov rax, rbx
    jmp 9f
3:  mov r12, rcx
    lea rdi, [rcx*2 + 3]
    call _bit_alloc
    mov r13, rax
    mov r14, rax
    mov byte ptr [r14], 34
    inc r14
    xor ecx, ecx
    xor edx, edx
4:  movzx eax, byte ptr [rbx + rcx]
    test al, al
    jz 6f
    cmp al, 92
    jne 41f
    inc rdx
    inc rcx
    jmp 4b
41: cmp al, 34
    jne 43f
    lea r8, [rdx*2 + 1]
42: test r8, r8
    jz 421f
    mov byte ptr [r14], 92
    inc r14
    dec r8
    jmp 42b
421: mov byte ptr [r14], 34
    inc r14
    xor edx, edx
    inc rcx
    jmp 4b
43: mov r8, rdx
44: test r8, r8
    jz 441f
    mov byte ptr [r14], 92
    inc r14
    dec r8
    jmp 44b
441: mov byte ptr [r14], al
    inc r14
    xor edx, edx
    inc rcx
    jmp 4b
6:  lea r8, [rdx*2]
61: test r8, r8
    jz 62f
    mov byte ptr [r14], 92
    inc r14
    dec r8
    jmp 61b
62: mov byte ptr [r14], 34
    mov byte ptr [r14 + 1], 0
    mov rax, r13
9:  pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_win_quote_argv:                // rdi = argv → rax = новый argv, каждый аргумент в кавычках
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    xor r12d, r12d
1:  cmp qword ptr [rbx + r12*8], 0
    je 2f
    inc r12
    jmp 1b
2:  lea rdi, [r12*8 + 8]
    call _bit_alloc
    mov r13, rax
    xor r14d, r14d
3:  cmp r14, r12
    jge 4f
    mov rdi, [rbx + r14*8]
    call _bit_win_quote
    mov [r13 + r14*8], rax
    inc r14
    jmp 3b
4:  mov qword ptr [r13 + r12*8], 0
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_win_drain:                     // edi = fd, rsi = буфер (ptr, len, cap) → читает до конца и закрывает
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov ebx, edi
    mov r12, rsi
1:  mov rax, [r12 + 8]
    lea rax, [rax + 1]
    cmp rax, [r12 + 16]
    jb 2f
    mov rsi, [r12 + 16]
    shl rsi, 1
    js 4f
    mov [r12 + 16], rsi
    mov rdi, [r12]
    call _w_realloc
    test rax, rax
    jz 4f
    mov [r12], rax
2:  mov ecx, ebx
    mov rdx, [r12]
    add rdx, [r12 + 8]
    mov r8, [r12 + 16]
    sub r8, [r12 + 8]
    dec r8
    mov eax, 65536
    cmp r8, rax
    cmova r8, rax
    sub rsp, 32
    call _read
    add rsp, 32
    test eax, eax
    js 6f
    jz 3f
    movsxd rax, eax
    add [r12 + 8], rax
    jmp 1b
6:  call _w_errno
    cmp dword ptr [rax], 32
    jne 4f
3:  xor r13d, r13d
    jmp 5f
4:  mov r13d, 1
5:  mov ecx, ebx
    sub rsp, 32
    call _close
    add rsp, 32
    mov eax, r13d
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_win_reader:                    // Windows thread entry: fd and buffer pointer.
    push rdi
    push rsi
    sub rsp, 8
    mov edi, [rcx]
    mov rsi, [rcx + 8]
    call _bit_win_drain
    add rsp, 8
    pop rsi
    pop rdi
    ret

_bit_win_reader_start:              // rdi = context -> thread handle (0 on failure)
    sub rsp, 56
    xor ecx, ecx
    xor edx, edx
    lea r8, [rip + _bit_win_reader]
    mov r9, rdi
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    call _beginthreadex
    add rsp, 56
    ret

_bit_win_reader_join:               // rdi = handle -> 0 on success, 1 on error
    push rbx
    sub rsp, 48
    mov rbx, rdi
    mov rcx, rbx
    mov edx, -1
    call WaitForSingleObject
    mov dword ptr [rsp + 32], 1
    test eax, eax
    jne 1f
    mov rcx, rbx
    lea rdx, [rsp + 32]
    call GetExitCodeThread
    test eax, eax
    jnz 1f
    mov dword ptr [rsp + 32], 1
1:  mov rcx, rbx
    call CloseHandle
    mov eax, [rsp + 32]
    add rsp, 48
    pop rbx
    ret

_bit_win_finish:                    // rdi = буфер → строка (без последнего перевода строки \r\n)
    mov rax, [rdi + 8]
    mov rdx, [rdi]
    test rax, rax
    jz 1f
    cmp byte ptr [rdx + rax - 1], 10
    jne 1f
    dec rax
    test rax, rax
    jz 1f
    cmp byte ptr [rdx + rax - 1], 13
    jne 1f
    dec rax
1:  mov byte ptr [rdx + rax], 0
    mov rax, rdx
    ret

// mas >> run: каналы с _O_NOINHERIT, чтобы ребёнок не унаследовал наш конец stdin
// (иначе он не увидит конец входа); наследуются только копии на 0/1/2.
// Both readers drain their pipes while the main thread writes stdin.
_bit_exec:                          // rdi = mas строк, rsi = stdin (или 0), rdx = строка → stdout
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 168
    mov r12, rsi
    mov r13, rdx
    cmp qword ptr [rdi + 8], 0
    je 99f
    call _bit_mas_argv
    mov [rsp + 104], rax
    mov rdi, rax
    call _bit_win_quote_argv
    mov rbx, rax
    xor ecx, ecx
    sub rsp, 32
    call fflush
    add rsp, 32
    lea rcx, [rsp]
    mov edx, 1048576
    mov r8d, 0x8080
    sub rsp, 32
    call _pipe
    add rsp, 32
    test eax, eax
    js 99f
    lea rcx, [rsp + 8]
    mov edx, 1048576
    mov r8d, 0x8080
    sub rsp, 32
    call _pipe
    add rsp, 32
    test eax, eax
    js 99f
    test r12, r12
    jz 1f
    lea rcx, [rsp + 16]
    mov edx, 1048576
    mov r8d, 0x8080
    sub rsp, 32
    call _pipe
    add rsp, 32
    test eax, eax
    js 99f
    xor ecx, ecx
    sub rsp, 32
    call _dup
    add rsp, 32
    mov dword ptr [rsp + 24], eax
    mov ecx, dword ptr [rsp + 16]
    xor edx, edx
    sub rsp, 32
    call _dup2
    add rsp, 32
    mov ecx, dword ptr [rsp + 16]
    sub rsp, 32
    call _close
    add rsp, 32
1:  mov ecx, 1
    sub rsp, 32
    call _dup
    add rsp, 32
    mov dword ptr [rsp + 28], eax
    mov ecx, 2
    sub rsp, 32
    call _dup
    add rsp, 32
    mov dword ptr [rsp + 32], eax
    mov ecx, dword ptr [rsp + 4]
    mov edx, 1
    sub rsp, 32
    call _dup2
    add rsp, 32
    mov ecx, dword ptr [rsp + 12]
    mov edx, 2
    sub rsp, 32
    call _dup2
    add rsp, 32
    mov ecx, dword ptr [rsp + 4]
    sub rsp, 32
    call _close
    add rsp, 32
    mov ecx, dword ptr [rsp + 12]
    sub rsp, 32
    call _close
    add rsp, 32
    mov ecx, 1
    mov rax, [rsp + 104]
    mov rdx, [rax]
    mov r8, rbx
    sub rsp, 32
    call _spawnvp
    add rsp, 32
    mov [rsp + 40], rax
    mov rdi, rbx
    call _w_free
    mov rdi, [rsp + 104]
    call _w_free
    mov ecx, dword ptr [rsp + 28]
    mov edx, 1
    sub rsp, 32
    call _dup2
    add rsp, 32
    mov ecx, dword ptr [rsp + 28]
    sub rsp, 32
    call _close
    add rsp, 32
    mov ecx, dword ptr [rsp + 32]
    mov edx, 2
    sub rsp, 32
    call _dup2
    add rsp, 32
    mov ecx, dword ptr [rsp + 32]
    sub rsp, 32
    call _close
    add rsp, 32
    test r12, r12
    jz 2f
    mov ecx, dword ptr [rsp + 24]
    xor edx, edx
    sub rsp, 32
    call _dup2
    add rsp, 32
    mov ecx, dword ptr [rsp + 24]
    sub rsp, 32
    call _close
    add rsp, 32
2:  cmp qword ptr [rsp + 40], -1
    jne 3f
    mov ecx, dword ptr [rsp]
    sub rsp, 32
    call _close
    add rsp, 32
    mov ecx, dword ptr [rsp + 8]
    sub rsp, 32
    call _close
    add rsp, 32
    test r12, r12
    jz 21f
    mov ecx, dword ptr [rsp + 20]
    sub rsp, 32
    call _close
    add rsp, 32
21: mov qword ptr [rip + Lrt_status], 127
    mov rdi, [rip + Lrt_stderr]
    call _w_free
    mov edi, 1
    call _bit_alloc
    mov byte ptr [rax], 0
    mov [rip + Lrt_stderr], rax
    mov edi, 1
    call _bit_alloc
    mov byte ptr [rax], 0
    jmp 98f
3:  mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 72], 0
    mov qword ptr [rsp + 144], 0
    mov qword ptr [rsp + 152], 0
    mov edi, 4096
    call _w_malloc
    test rax, rax
    jz 95f
    mov [rsp + 48], rax
    mov qword ptr [rsp + 56], 0
    mov qword ptr [rsp + 64], 4096
    mov edi, 4096
    call _w_malloc
    test rax, rax
    jz 95f
    mov [rsp + 72], rax
    mov qword ptr [rsp + 80], 0
    mov qword ptr [rsp + 88], 4096
    mov eax, [rsp]
    mov [rsp + 112], eax
    lea rax, [rsp + 48]
    mov [rsp + 120], rax
    mov eax, [rsp + 8]
    mov [rsp + 128], eax
    lea rax, [rsp + 72]
    mov [rsp + 136], rax
    lea rdi, [rsp + 112]
    call _bit_win_reader_start
    mov [rsp + 144], rax
    test rax, rax
    jz 95f
    lea rdi, [rsp + 128]
    call _bit_win_reader_start
    mov [rsp + 152], rax
    test rax, rax
    jz 95f
    test r12, r12
    jz 5f
    mov rdi, r12
    call _w_strlen
    mov r14, rax
    mov r15, r12
4:  test r14, r14
    jz 41f
    mov ecx, dword ptr [rsp + 20]
    mov rdx, r15
    mov r8, r14
    mov eax, 65536
    cmp r8, rax
    cmova r8, rax
    sub rsp, 32
    call _write
    add rsp, 32
    test eax, eax
    jle 41f
    movsxd rax, eax
    add r15, rax
    sub r14, rax
    jmp 4b
41: mov ecx, dword ptr [rsp + 20]
    sub rsp, 32
    call _close
    add rsp, 32
5:  mov rdi, [rsp + 144]
    call _bit_win_reader_join
    mov r14d, eax
    mov rdi, [rsp + 152]
    call _bit_win_reader_join
    or r14d, eax
    mov dword ptr [rsp + 96], 127
    lea rcx, [rsp + 96]
    mov rdx, [rsp + 40]
    xor r8d, r8d
    sub rsp, 32
    call _cwait
    add rsp, 32
    cmp rax, -1
    je 97f
    test r14d, r14d
    jnz 97f
    mov eax, dword ptr [rsp + 96]
    mov [rip + Lrt_status], rax
    mov rdi, [rip + Lrt_stderr]
    call _w_free
    lea rdi, [rsp + 72]
    call _bit_win_finish
    mov [rip + Lrt_stderr], rax
    lea rdi, [rsp + 48]
    call _bit_win_finish
    jmp 98f
95: mov rcx, [rsp + 40]
    mov edx, 1
    sub rsp, 32
    call TerminateProcess
    add rsp, 32
    test r12, r12
    jz 951f
    mov ecx, [rsp + 20]
    sub rsp, 32
    call _close
    add rsp, 32
951: mov rdi, [rsp + 144]
    test rdi, rdi
    jz 952f
    call _bit_win_reader_join
    jmp 953f
952: mov ecx, [rsp]
    sub rsp, 32
    call _close
    add rsp, 32
953: mov rdi, [rsp + 152]
    test rdi, rdi
    jz 954f
    call _bit_win_reader_join
    jmp 955f
954: mov ecx, [rsp + 8]
    sub rsp, 32
    call _close
    add rsp, 32
955: lea rcx, [rsp + 96]
    mov rdx, [rsp + 40]
    xor r8d, r8d
    sub rsp, 32
    call _cwait
    add rsp, 32
97: mov rdi, [rsp + 48]
    call _w_free
    mov rdi, [rsp + 72]
    call _w_free
    jmp 99f
98: add rsp, 168
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
99: lea rdi, [rip + Lrt_erun]
    mov rsi, r13
    call _bit_die

// ── запуск программы напрямую (без шелла): CRT _spawnvp + argv ──
// Как в обычных языках: аргументы передаём массивом, строку команды собирает CRT.
_bit_spawn_capture:                 // rdi = argv (char**), rsi = строка → вывод stdout
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    call _bit_win_quote_argv
    mov [rsp + 40], rax
    xor ecx, ecx
    sub rsp, 32
    call fflush
    add rsp, 32
    lea rcx, [rsp]
    mov edx, 65536
    mov r8d, 0x8000
    sub rsp, 32
    call _pipe
    add rsp, 32
    test eax, eax
    js 9f
    mov ecx, 1
    sub rsp, 32
    call _dup
    add rsp, 32
    mov dword ptr [rsp + 8], eax
    mov ecx, dword ptr [rsp + 4]
    mov edx, 1
    sub rsp, 32
    call _dup2
    add rsp, 32
    mov ecx, dword ptr [rsp + 4]
    sub rsp, 32
    call _close
    add rsp, 32
    mov ecx, 1
    mov rdx, [rbx]
    mov r8, [rsp + 40]
    sub rsp, 32
    call _spawnvp
    add rsp, 32
    mov [rsp + 32], rax
    mov ecx, dword ptr [rsp + 8]
    mov edx, 1
    sub rsp, 32
    call _dup2
    add rsp, 32
    mov ecx, dword ptr [rsp + 8]
    sub rsp, 32
    call _close
    add rsp, 32
    cmp qword ptr [rsp + 32], -1
    je 9f
    mov r13d, dword ptr [rsp]
    mov edi, 4096
    call _bit_alloc
    mov r14, rax
    mov r15, 4096
    mov qword ptr [rsp + 16], 0
3:  mov rax, [rsp + 16]
    lea rax, [rax + 1]
    cmp rax, r15
    jb 4f
    shl r15, 1
    mov rdi, r14
    mov rsi, r15
    call _w_realloc
    test rax, rax
    jz _bit_oom
    mov r14, rax
4:  mov ecx, r13d
    mov rdx, r14
    add rdx, [rsp + 16]
    mov r8, r15
    sub r8, [rsp + 16]
    dec r8
    sub rsp, 32
    call _read
    add rsp, 32
    test eax, eax
    jle 5f
    movsxd rax, eax
    add [rsp + 16], rax
    jmp 3b
5:  mov ecx, r13d
    sub rsp, 32
    call _close
    add rsp, 32
    lea rcx, [rsp + 24]
    mov rdx, [rsp + 32]
    xor r8d, r8d
    sub rsp, 32
    call _cwait
    add rsp, 32
    mov eax, dword ptr [rsp + 24]
    mov [rip + Lrt_status], rax
    mov rax, [rsp + 16]
6:  test rax, rax
    jz 7f
    movzx ecx, byte ptr [r14 + rax - 1]
    cmp ecx, 10
    je 61f
    cmp ecx, 13
    jne 7f
61: dec rax
    jmp 6b
7:  mov [rsp + 16], rax
    mov byte ptr [r14 + rax], 0
    mov rax, r14
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_erun]
    mov rsi, r12
    call _bit_die

_bit_spawn_status:                  // rdi = argv, rsi = тихо(0/1), rdx = строка → код выхода
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rbx
    call _bit_win_quote_argv
    mov [rsp + 16], rax
    xor ecx, ecx
    sub rsp, 32
    call fflush
    add rsp, 32
    test r12, r12
    jz 2f
    mov ecx, 1
    sub rsp, 32
    call _dup
    add rsp, 32
    mov dword ptr [rsp], eax
    mov ecx, 2
    sub rsp, 32
    call _dup
    add rsp, 32
    mov dword ptr [rsp + 4], eax
    lea rcx, [rip + Lrt_nul]
    mov edx, 1
    sub rsp, 32
    call _open
    add rsp, 32
    mov dword ptr [rsp + 8], eax
    mov ecx, eax
    mov edx, 1
    sub rsp, 32
    call _dup2
    add rsp, 32
    mov ecx, dword ptr [rsp + 8]
    mov edx, 2
    sub rsp, 32
    call _dup2
    add rsp, 32
    mov ecx, dword ptr [rsp + 8]
    sub rsp, 32
    call _close
    add rsp, 32
2:  xor ecx, ecx
    mov rdx, [rbx]
    mov r8, [rsp + 16]
    sub rsp, 32
    call _spawnvp
    add rsp, 32
    mov r13, rax
    cmp r13, -1
    jne 22f
    mov r13, 127
22: test r12, r12
    jz 3f
    mov ecx, dword ptr [rsp]
    mov edx, 1
    sub rsp, 32
    call _dup2
    add rsp, 32
    mov ecx, dword ptr [rsp]
    sub rsp, 32
    call _close
    add rsp, 32
    mov ecx, dword ptr [rsp + 4]
    mov edx, 2
    sub rsp, 32
    call _dup2
    add rsp, 32
    mov ecx, dword ptr [rsp + 4]
    sub rsp, 32
    call _close
    add rsp, 32
3:  mov [rip + Lrt_status], r13
    mov rax, r13
    add rsp, 24
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


// ── Winsock: обёртки сокетов (вход по-нашему, внутри Windows ABI + ленивый старт) ──
_bit_wsa_init:
    mov rax, [rip + Lrt_wsa]
    test rax, rax
    jnz 1f
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 448
    mov ecx, 0x0202
    lea rdx, [rsp + 32]
    call WSAStartup
    mov qword ptr [rip + Lrt_wsa], 1
    mov rsp, rbp
    pop rbp
1:  ret

_w_socket:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    and rsp, -16
    sub rsp, 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call _bit_wsa_init
    mov rcx, rbx
    mov rdx, r12
    mov r8, r13
    call socket
    lea rsp, [rbp - 24]
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_w_gethostbyname:
    push rbp
    mov rbp, rsp
    push rbx
    and rsp, -16
    sub rsp, 32
    mov rbx, rdi
    call _bit_wsa_init
    mov rcx, rbx
    call gethostbyname
    lea rsp, [rbp - 8]
    pop rbx
    pop rbp
    ret

_w_connect:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    call connect
    mov rsp, rbp
    pop rbp
    ret
_w_setsockopt:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 48
    mov [rsp + 32], r8
    mov r9, rcx
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    call setsockopt
    mov rsp, rbp
    pop rbp
    ret
_w_getpeername:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    call getpeername
    mov rsp, rbp
    pop rbp
    ret
_w_bind:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    call bind
    mov rsp, rbp
    pop rbp
    ret
_w_listen:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov rdx, rsi
    mov rcx, rdi
    call listen
    mov rsp, rbp
    pop rbp
    ret
_w_accept:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    call accept
    mov rsp, rbp
    pop rbp
    ret
_w_send:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov r9, rcx
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    call send
    mov rsp, rbp
    pop rbp
    ret
_w_recv:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov r9, rcx
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    call recv
    mov rsp, rbp
    pop rbp
    ret
_bit_socket_wait:                   // WSAPOLLFD: SOCKET, events, revents
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 48
    mov [rsp + 32], rdi
    // POLLRDNORM
    mov dword ptr [rsp + 40], 256
    lea rcx, [rsp + 32]
    mov edx, 1
    mov r8d, esi
    call WSAPoll
    mov rsp, rbp
    pop rbp
    ret

_bit_errno_map:                     // edi = код ошибки системы → 1 отказ, 2 таймаут, 3 нет маршрута, 0 без кода
    cmp edi, 10061                  # WSAECONNREFUSED
    je 1f
    cmp edi, 10060                  # WSAETIMEDOUT
    je 2f
    cmp edi, 10051                  # WSAENETUNREACH
    je 3f
    cmp edi, 10065                  # WSAEHOSTUNREACH
    je 3f
    xor eax, eax
    ret
1:  mov eax, 1
    ret
2:  mov eax, 2
    ret
3:  mov eax, 3
    ret

_bit_errno_code:                    // → код ошибки системы из WSAGetLastError
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    call WSAGetLastError
    mov edi, eax
    call _bit_errno_map
    mov rsp, rbp
    pop rbp
    ret

_bit_tcp_connect_timed:               // rdi = "ip:port", rsi = таймаут мс, rdx = строка -> TCP conn
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    and rsp, -16
    sub rsp, 128
    mov r13, rdx                      # строка исходника
    mov r14, rdi                      # адрес
    mov r12d, esi                     # таймаут мс
    test rsi, rsi
    js 10f
    cmp rsi, 2147483647
    jg 10f
    call _bit_wsa_init
    mov rbx, r14                      # обходчик адреса
    lea r14, [rsp + 40]               # буфер адреса
1:  movzx eax, byte ptr [rbx]
    test eax, eax
    jz 9f                             # пустой адрес
    cmp eax, 58
    je 2f
    lea r9, [rsp + 55]
    cmp r14, r9
    jae 9f
    mov [r14], al
    inc rbx
    inc r14
    jmp 1b
2:  mov byte ptr [r14], 0
    inc rbx
    xor r8d, r8d
    cmp byte ptr [rbx], 0
    je 9f
3:  movzx eax, byte ptr [rbx]
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
    inc rbx
    jmp 3b
4:  lea rdx, [rsp + 88]
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
    mov rcx, 2
    lea rdx, [rsp + 40]
    lea r8, [rsp + 92]
    call inet_pton
    cmp eax, 1
    jne 9f
    mov rcx, 2
    mov edx, 1
    xor r8d, r8d
    call socket
    test eax, eax
    js 9f
    mov ebx, eax                      # сокет
    mov eax, r12d
    test eax, eax
    jnz 5f
    mov eax, 1                        # 0 мс значит системный лимит; для мгновенной проверки — 1 мс
5:  mov [rsp + 112], eax
    mov qword ptr [rsp + 32], 4       # optlen = 4 (пятый аргумент setsockopt)
    mov rcx, rbx
    mov edx, 0xFFFF                   # SOL_SOCKET
    mov r8d, 0x3006                   # SO_CONNECT_TIMEOUT
    lea r9, [rsp + 112]
    call setsockopt
    test eax, eax
    jnz 8f
    mov rcx, rbx
    lea rdx, [rsp + 88]
    mov r8d, 16
    call connect
    test eax, eax
    jz 12f                            # подключился
7:  call WSAGetLastError
    mov edi, eax
    mov r14d, eax                     # запомнить код для выбора текста
    call _bit_errno_map
    mov rdi, rax
    call _bit_set_errcode
    mov rcx, rbx
    call closesocket
    cmp r14d, 10060                   # WSAETIMEDOUT
    jne 72f
    lea rdi, [rip + Lrt_econn_timeout]
    jmp 71f
8:  xor edi, edi
    call _bit_set_errcode
    mov rcx, rbx
    call closesocket
72: lea rdi, [rip + Lrt_enet]
    jmp 71f
12: mov rax, rbx
    lea rsp, [rbp - 32]
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  xor edi, edi
    call _bit_set_errcode
    lea rdi, [rip + Lrt_enet]
    jmp 71f
10: xor edi, edi
    call _bit_set_errcode
    lea rdi, [rip + Lrt_econn_args]
71: mov rsi, r13
    lea rsp, [rbp - 32]
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die
# User locks have process lifetime; aliases refer to the same critical section.
_bit_user_lock_new:
    push rbp
    mov rbp, rsp
    push rbx
    and rsp, -16
    sub rsp, 32
    mov edi, 80
    call _bit_alloc
    mov rbx, rax
    mov rcx, rbx
    call InitializeCriticalSection
    mov rax, rbx
    lea rsp, [rbp - 8]
    pop rbx
    pop rbp
    ret

_bit_user_lock_enter:                # rdi = lock
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov rcx, rdi
    call EnterCriticalSection
    mov rsp, rbp
    pop rbp
    ret

_bit_user_lock_leave:                # rdi = lock
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov rcx, rdi
    call LeaveCriticalSection
    mov rsp, rbp
    pop rbp
    ret

_bit_thread_start:                   # rdi = код → rax = поток
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    and rsp, -16
    sub rsp, 64
    mov rbx, rdi
    # Initialize TLS and the registry lock before any bit thread can run.
    call _bit_rt_ensure
    xor ecx, ecx
    xor edx, edx
    lea r8, [rip + _bit_thread_run]
    mov r9, rbx
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    call CreateThread
    lea rsp, [rbp - 16]
    pop r12
    pop rbx
    pop rbp
    ret

_bit_thread_run:                     # rcx = параметр (Win64)
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov rdi, rcx
    call rdi
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

_bit_thread_wait:                    # rdi = поток
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov rcx, rdi
    mov rdx, -1
    call WaitForSingleObject
    mov rsp, rbp
    pop rbp
    ret

_bit_term_raw:                       # rdi = 1 сырой режим, 0 обычный
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 64
    and rsp, -16
    sub rsp, 32
    mov [rsp + 16], rdi
    mov rcx, -10
    call GetStdHandle
    mov rbx, rax
    mov rcx, rbx
    lea rdx, [rsp]
    call GetConsoleMode
    test eax, eax
    jz 9f
    mov eax, [rsp]
    mov rcx, [rsp + 16]
    test ecx, ecx
    jz 1f
    and eax, -7
    jmp 2f
1:  or eax, 6
2:  mov rcx, rbx
    mov edx, eax
    call SetConsoleMode
9:  lea rsp, [rbp - 8]
    pop rbx
    pop rbp
    ret

_bit_term_key:                       # → строка из одного символа
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    and rsp, -16
    sub rsp, 32
    mov edi, 8
    call _bit_alloc
    mov rbx, rax
    xor ecx, ecx
    mov rdx, rbx
    mov r8d, 1
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
    xor ecx, ecx
    lea rdx, [rbx + r12]
    mov r8d, 1
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
10: lea rsp, [rbp - 24]
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_open_update:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov rcx, rdi
    // _O_BINARY | _O_CREAT | _O_WRONLY, _S_IREAD | _S_IWRITE
    mov edx, 33025
    mov r8d, 384
    call _open
    mov rsp, rbp
    pop rbp
    ret
_w_closesocket:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov rcx, rdi
    call closesocket
    mov rsp, rbp
    pop rbp
    ret
_w_inet_pton:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    call inet_pton
    mov rsp, rbp
    pop rbp
    ret
_w_inet_ntop:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov r9, rcx
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    call inet_ntop
    mov rsp, rbp
    pop rbp
    ret


_bit_str_find:                      // rdi = указатель → запись реестра или 0 (под замком)
    push rbp
    mov rbp, rsp
    push rbx
    mov rbx, rdi
    call _bit_lock
    mov rdi, rbx
    call _bit_str_find_raw
    push rax
    call _bit_unlock
    pop rax
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
    call _w_calloc
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
    call _w_free
    mov rdi, rbx
    call _w_free
2:  call _bit_unlock
    pop r12
    pop rbx
    pop rbp
3:  ret

_bit_to_str:                        // rdi = значение, rsi = вид (0 num, 1 dec, 2 string, 3 bool)
    cmp rsi, 0
    je _bit_num_str
    cmp rsi, 1
    je _bit_dec_str
    cmp rsi, 3
    je _bit_bool_str
    mov rax, rdi
    ret

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
    call _w_realloc
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
    call _w_realloc
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
2:  call _w_qsort
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
    call _w_calloc
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
    call _w_realloc
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
    call _w_memcpy
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
    call _w_memcpy
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

_bit_bytes_addr:                    // rdi = bytes → адрес данных
    mov rax, [rdi]
    ret

_bit_bytes_free:                    // rdi = bytes (или 0) -> освободить буфер и описатель
    test rdi, rdi
    jz 1f
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rdi
    mov rdi, [rbx]
    call _w_free
    mov rdi, rbx
    call _w_free
    add rsp, 8
    pop rbx
    pop rbp
1:  ret

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
    call _w_memcpy
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

_bit_str_lines:                     // rdi = строка -> mas строк
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    call _w_strlen
    mov r12, rax
    lea rdi, [rax + 1]
    call _bit_alloc
    mov r13, rax
    mov rdi, rax
    mov rsi, rbx
    lea rdx, [r12 + 1]
    call _w_memcpy
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
    call _w_strlen
    mov r13, rax
    mov rdi, rbx
    call _w_strlen
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
    call _w_strlen
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
    call _w_memcpy
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
    call _w_memcpy
    mov byte ptr [r13 + r12], 0
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

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
    call _w_strlen
    mov r13, rax
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r14, rax
    test r13, r13
    jnz 10f
    mov rdi, rbx
    call _w_strlen
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
    call _w_strlen
    mov r14, rax
    test r14, r14
    jnz 1f
    mov rdi, rbx
    call _w_strlen
    mov rsi, rax
    mov rdi, rbx
    call _bit_substr
    jmp 9f
1:  mov rdi, r13
    call _w_strlen
    mov r15, rax
    mov rdi, rbx
    call _w_strlen
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
    call _w_strlen
    mov r13, rax
    xor r14d, r14d
    xor r15d, r15d
1:  cmp r15, [rbx + 8]
    jge 2f
    mov rax, [rbx]
    mov rdi, [rax + r15*8]
    call _w_strlen
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
    call _w_memcpy
    add r14, r13
4:  mov rax, [rbx]
    mov rdi, [rax + r15*8]
    call _w_strlen
    mov [rsp + 8], rax
    mov rdx, rax
    mov rax, [rbx]
    mov rsi, [rax + r15*8]
    mov rdi, r14
    call _w_memcpy
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

_bit_str_bytes:                     // rdi = строка → mas из байтов
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    call _w_strlen
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
    call _w_strlen
    mov rsi, rax
    mov rdi, rbx
    call _bit_substr
2:  pop r12
    pop rbx
    pop rbp
    ret

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
    call _w_getentropy
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
    call _w_free
1:  pop r12
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
    sub rsp, 64
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
9:  add rsp, 64
    pop r15
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
    call _w_strlen
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
    call _w_strlen
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
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_echar_range]
    mov rsi, r13
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
    sub rsp, 64
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
    call _w_strlen
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
    call _w_memcpy
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
    call _w_memcpy
30: mov rax, [rsp + 24]
    mov byte ptr [r15 + rax], 0
    mov rax, r15
8:  add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
99: lea rdi, [rip + Lrt_epad_width]
    mov rsi, r13
    add rsp, 64
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
    call _w_strlen
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
    sub rsp, 8
    call _w_memcpy
    add rsp, 8
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
    sub rsp, 112
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
    call _w_inet_pton
    cmp eax, 1
    jne 9f
    mov edi, 2
    mov esi, [rsp + 96]
    xor edx, edx
    call _w_socket
    test eax, eax
    js 9f
    mov ebx, eax
    mov edi, ebx
    lea rsi, [rsp + 80]
    mov edx, 16
    call _w_connect
    test eax, eax
    jnz 8f
    mov eax, ebx
    add rsp, 112
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  call _bit_errno_code
    mov rdi, rax
    call _bit_set_errcode
    mov edi, ebx
    call _w_closesocket
    jmp 10f
9:  xor edi, edi
    call _bit_set_errcode
10: add rsp, 112
    lea rdi, [rip + Lrt_enet]
    mov rsi, r12
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
    mov word ptr [rsp], 2       # Darwin sockaddr_in: length 16, AF_INET 2
    mov eax, r12d
    rol ax, 8
    mov [rsp + 2], ax
    test r13, r13
    jz 1f
    mov edi, 2
    mov rsi, r13
    lea rdx, [rsp + 4]
    call _w_inet_pton
    cmp eax, 1
    jne 8f
1:  mov edi, 2
    mov esi, 1
    xor edx, edx
    call _w_socket
    test eax, eax
    js 9f
    mov ebx, eax
    mov dword ptr [rsp + 16], 1
    mov edi, ebx
    mov esi, 0xffff                 # Darwin SOL_SOCKET
    mov edx, 4                      # Darwin SO_REUSEADDR
    lea rcx, [rsp + 16]
    mov r8d, 4
    call _w_setsockopt
    test eax, eax
    jnz 7f
    mov edi, ebx
    mov rsi, rsp
    mov edx, 16
    call _w_bind
    test eax, eax
    jnz 7f
    mov edi, ebx
    mov esi, 16
    call _w_listen
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
    call _w_closesocket
9:  lea rdi, [rip + Lrt_elisten]
    jmp 6f
8:  lea rdi, [rip + Lrt_elisten_addr]
6:  mov rsi, r14
    call _bit_die

_bit_tcp_accept:                    // rdi = server, rsi = строка -> conn
    push rbp
    mov rbp, rsp
    push rbx
    mov rbx, rsi
    xor esi, esi
    xor edx, edx
    call _w_accept
    test eax, eax
    js 9f
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_eaccept]
    mov rsi, rbx
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
    call _w_getpeername
    test eax, eax
    jnz 9f
    movzx ebx, word ptr [rsp + 2]
    rol bx, 8
    mov edi, 2
    lea rsi, [rsp + 4]
    lea rdx, [rsp + 32]
    mov ecx, 16
    call _w_inet_ntop
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
    call _w_free
    mov rdi, r14
    call _w_free
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
    call _w_strlen
    mov r13, rax
1:  test r13, r13
    jle 3f
    mov edi, ebx
    mov rsi, r12
    mov rdx, r13
    xor ecx, ecx
    call _w_send
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
    call _w_recv
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
    call _w_recv
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
    call _w_free
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
    jmp _w_closesocket

_bit_resolve:                       // rdi = имя хоста, rsi = строка -> IP-адрес строкой
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov r12, rsi
    call _w_gethostbyname
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
    call _w_inet_ntop
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
    call _w_fopen
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
    call _w_realloc
    test rax, rax
    jz _bit_oom
    mov r14, rax
2:  mov rdi, r14
    add rdi, [rsp]
    mov esi, 1
    mov rdx, r15
    sub rdx, [rsp]
    mov rcx, r13
    call _w_fread
    add [rsp], rax
    test rax, rax
    jnz 1b
    mov rdi, r13
    call _w_ferror
    test eax, eax
    jnz 8f
    mov rax, [rsp]
    cmp rax, r15
    jne 3f
    mov rdi, r14
    lea rsi, [r15 + 1]
    call _w_realloc
    test rax, rax
    jz _bit_oom
    mov r14, rax
3:  mov rax, [rsp]
    mov byte ptr [r14 + rax], 0
    mov rdi, r13
    call _w_fclose
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
    call _w_fopen
    test rax, rax
    jz 9f
    mov r13, rax
    mov rdi, r13
    xor esi, esi
    mov edx, 2
    call _w_fseek
    test eax, eax
    jnz 8f
    mov rdi, r13
    call _w_ftell
    test rax, rax
    js 8f
    mov r14, rax
    mov rdi, r13
    call _w_fclose
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
    call _w_fopen
    test rax, rax
    jz 9f
    mov r14, rax
    mov rdi, r12
    mov rsi, r14
    call _w_fputs
    cmp eax, -1
    je 9f
    mov rdi, r14
    call _w_fclose
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
    call _w_unlink
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
    call _w_rmdir
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
    call _w_rename
    test eax, eax
    jz 1f
    call _w_errno
    // EXDEV
    cmp dword ptr [rax], 18
    jne 9f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call _bit_copy
    mov rdi, rbx
    call _w_unlink
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
    call _w_strrchr
    mov r12, rax
    mov rdi, rbx
    mov esi, 92
    call _w_strrchr
    cmp rax, r12
    cmovb rax, r12
    xor esi, esi
    test rax, rax
    jnz 1f
    cmp byte ptr [rbx], 0
    je 2f
    cmp byte ptr [rbx + 1], 58
    jne 2f
    mov esi, 2
    jmp 2f
1:  sub rax, rbx
    lea rsi, [rax + 1]
2:  mov rdi, rbx
    call _bit_substr
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + Lrt_copy_suffix]
    call _bit_cat
    mov r12, rax
    mov rdi, rbx
    call _w_free
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
    call _w_fopen
    test rax, rax
    jz 9f
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    call _w_strcmp
    test eax, eax
    jnz 1f
    mov rdi, r14
    call _w_fclose
    jmp 4f
1:  mov edi, 65536
    call _bit_alloc
    mov [rsp + 8], rax
    mov rdi, r12
    call _bit_copy_temp
    mov [rsp], rax
    mov rdi, rax
    call _w_mkstemp
    test eax, eax
    js 6f
    mov [rsp + 16], eax
    mov edi, eax
    lea rsi, [rip + Lrt_wb]
    call _w_fdopen
    test rax, rax
    jz 5f
    mov r15, rax
    mov dword ptr [rsp + 16], -1
2:  mov rdi, [rsp + 8]
    mov esi, 1
    mov edx, 65536
    mov rcx, r14
    call _w_fread
    test rax, rax
    jz 3f
    mov [rsp + 16], rax
    mov rdx, rax
    mov rdi, [rsp + 8]
    mov esi, 1
    mov rcx, r15
    call _w_fwrite
    cmp rax, [rsp + 16]
    mov dword ptr [rsp + 16], -1
    jne 5f
    jmp 2b
3:  mov rdi, r14
    call _w_ferror
    test eax, eax
    jnz 5f
    mov rdi, r15
    xor r15d, r15d
    call _w_fclose
    test eax, eax
    jnz 5f
    mov rdi, r14
    xor r14d, r14d
    call _w_fclose
    test eax, eax
    jnz 5f
    mov rdi, [rsp]
    mov rsi, r12
    call _w_rename
    test eax, eax
    jnz 5f
    mov rdi, [rsp]
    call _w_free
    mov rdi, [rsp + 8]
    call _w_free
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
    call _w_fclose
51: mov edi, [rsp + 16]
    test edi, edi
    js 52f
    call _w_close
52: mov rdi, [rsp]
    call _w_unlink
6:  test r14, r14
    jz 7f
    mov rdi, r14
    call _w_fclose
7:  mov rdi, [rsp]
    call _w_free
    mov rdi, [rsp + 8]
    call _w_free
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
    call _w_mkdir
    mov byte ptr [r13], 47
2:  inc r13
    jmp 1b
3:  mov rdi, rbx
    mov esi, 493
    call _w_mkdir
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

_bit_basename:                      // rdi = путь → имя после последнего /
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov esi, 47
    call _w_strrchr
    test rax, rax
    jz 1f
    inc rax
    jmp 2f
1:  mov rax, rbx
2:  pop r12
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
    call _w_free
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
    call _w_fopen
    test rax, rax
    jz 9f
    mov r13, rax
    mov rdi, r13
    xor esi, esi
    mov edx, 2
    call _w_fseek
    test eax, eax
    jnz 8f
    mov rdi, r13
    call _w_ftell
    test rax, rax
    js 8f
    mov r14, rax
    mov rdi, r13
    xor esi, esi
    xor edx, edx
    call _w_fseek
    test eax, eax
    jnz 8f
    mov rdi, r14
    call _bit_bytes_new
    mov r15, rax
    mov rdi, [r15]
    mov esi, 1
    mov rdx, r14
    mov rcx, r13
    call _w_fread
    cmp rax, r14
    jne 8f
    mov rdi, r13
    call _w_fclose
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
    call _w_fopen
    test rax, rax
    jz 9f
    mov r14, rax
    mov rdi, [r12]
    mov esi, 1
    mov rdx, [r12 + 8]
    mov rcx, r14
    call _w_fwrite
    cmp rax, [r12 + 8]
    jne 9f
    mov rdi, r14
    call _w_fclose
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
    call _w_fopen
    test rax, rax
    jz 8f
    mov [rsp], rax
    mov rdi, rax
    mov rsi, r13
    xor edx, edx
    call _w_fseeko
    test eax, eax
    jnz 7f
    mov rdi, [r15]
    mov esi, 1
    mov rdx, r14
    mov rcx, [rsp]
    call _w_fread
    mov [r15 + 8], rax
    mov rdi, [rsp]
    call _w_ferror
    test eax, eax
    jnz 7f
    mov rdi, [rsp]
    call _w_fclose
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
    call _w_fclose
8:  mov rdi, r15
    call _bit_bytes_free
    lea rdi, [rip + Lrt_eread]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath
9:  lea rdi, [rip + Lrt_echunk]
    mov rsi, r12
    call _bit_die

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
    call _w_fdopen
    test rax, rax
    jz 6f
    mov r15, rax
    mov rdi, rax
    mov rsi, r13
    xor edx, edx
    call _w_fseeko
    test eax, eax
    jnz 7f
    mov rdi, [r12]
    mov esi, 1
    mov rdx, [r12 + 8]
    mov rcx, r15
    call _w_fwrite
    cmp rax, [r12 + 8]
    jne 7f
    mov rdi, r15
    call _w_fclose
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
    call _w_close
    jmp 8f
7:  mov rdi, r15
    call _w_fclose
8:  lea rdi, [rip + Lrt_ewrite]
    mov rsi, rbx
    mov rdx, r14
    call _bit_errpath
9:  lea rdi, [rip + Lrt_echunk]
    mov rsi, r14
    call _bit_die

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
    call _w_free
    pop rdi
    pop rax
    mov rsi, r12
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
    call _w_errno
    mov dword ptr [rax], 0
    mov rdi, r15
    mov rsi, rsp
    mov edx, 10
    call _w_strtoll
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
    call _w_errno
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
    lea rcx, [rip + Lrt_numr]
    mov rdx, r12
    mov r8, r13
    sub rsp, 32
    call printf
    add rsp, 32
    jmp 1b
6:  lea rcx, [rip + Lrt_num]
    sub rsp, 32
    call printf
    add rsp, 32
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
    call _w_errno
    mov dword ptr [rax], 0
    mov rdi, r15
    mov rsi, rsp
    call _w_strtod
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
    call _w_errno
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
    lea rcx, [rip + Lrt_decr]
    mov rdx, r12
    movq xmm1, r12
    mov r8, r13
    movq xmm2, r13
    sub rsp, 32
    call printf
    add rsp, 32
    jmp 1b
6:  lea rcx, [rip + Lrt_dec]
    sub rsp, 32
    call printf
    add rsp, 32
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
    call _w_strcmp
    test eax, eax
    jz 2f
    mov rdi, r12
    lea rsi, [rip + Lrt_da]
    call _w_strcmp
    test eax, eax
    jz 2f
    mov rdi, r12
    lea rsi, [rip + Lrt_1]
    call _w_strcmp
    test eax, eax
    jz 2f
    mov rdi, r12
    lea rsi, [rip + Lrt_false]
    call _w_strcmp
    test eax, eax
    jz 3f
    mov rdi, r12
    lea rsi, [rip + Lrt_net]
    call _w_strcmp
    test eax, eax
    jz 3f
    mov rdi, r12
    lea rsi, [rip + Lrt_0]
    call _w_strcmp
    test eax, eax
    jz 3f
    lea rcx, [rip + Lrt_boolm]
    sub rsp, 32
    call printf
    add rsp, 32
    jmp 1b
2:  mov eax, 1
    jmp 4f
3:  xor eax, eax
4:  pop r12
    pop rbx
    pop rbp
    ret

_bit_os_host:                       // -> имя компьютера
    push rbp
    mov rbp, rsp
    push rbx
    mov edi, 256
    call _bit_alloc
    mov rbx, rax
    mov rdi, rbx
    mov esi, 256
    call _w_gethostname
    mov rax, rbx
    pop rbx
    pop rbp
    ret

_bit_os_user:                       // -> имя пользователя
    push rbp
    mov rbp, rsp
    lea rdi, [rip + Lrt_userenv]
    call _w_getenv
    test rax, rax
    jnz 1f
    lea rax, [rip + Lrt_empty]
1:  pop rbp
    ret

_bit_os_now:                        // -> время (секунды)
    push rbp
    mov rbp, rsp
    xor edi, edi
    call _w_time
    pop rbp
    ret

_bit_os_procs:                      // rdi = строка -> список процессов
    mov rsi, rdi
    lea rdi, [rip + Lrt_pscmd]
    jmp _bit_run

// ── mas >> run: программа напрямую массивом аргументов; stdout и stderr отдельно, stdin ──

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
    call _w_fflush
    mov rdi, rbx
    lea rsi, [rip + Lrt_r]
    call _w_popen
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
    call _w_fread
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
    call _w_realloc
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
    call _w_pclose
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

_bit_run_live:                      // rdi = команда: вывод сразу в терминал
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    xor edi, edi
    call _w_fflush
    mov rdi, rbx
    call _w_system
    mov edi, eax
    call _bit_wstatus
    pop r12
    pop rbx
    pop rbp
    ret

_bit_status:                        // → код выхода последней команды
    mov rax, [rip + Lrt_status]
    ret

_bit_env:                           // rdi = имя → значение или ""
    push rbp
    mov rbp, rsp
    call _w_getenv
    test rax, rax
    jnz 1f
    lea rax, [rip + Lrt_empty]
1:  mov rdi, rax
    lea rsi, [rip + Lrt_empty]
    call _bit_cat
    pop rbp
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
    call _w_errno
    mov r13, rax
    mov dword ptr [r13], 0
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 10
    call _w_strtoll
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

_bit_ping:                          // rdi = хост -> 1 если отвечает
    push rbp
    mov rbp, rsp
    sub rsp, 48
    lea rax, [rip + Lrt_pingp]
    mov [rsp], rax
    lea rax, [rip + Lrt_pingc]
    mov [rsp + 8], rax
    lea rax, [rip + Lrt_1]
    mov [rsp + 16], rax
    mov [rsp + 24], rdi
    mov qword ptr [rsp + 32], 0
    mov rdi, rsp
    mov esi, 1
    xor edx, edx
    call _bit_spawn_status
    cmp rax, 0
    sete al
    movzx eax, al
    add rsp, 48
    pop rbp
    ret

// ───── чужие процессы (Windows): WinAPI внутри рантайма, в языке — тот же proc, что на Linux ─────
// Вход — System V (rdi, rsi, rdx, rcx), к WinAPI — Win64 (rcx, rdx, r8, r9, стек) с теневой областью.
// proc — это pid; каждая операция открывает процесс по pid и закрывает его.

_bit_wp_fail:                       // rdi = текст, rsi = pid, rdx = строка программы, rcx = handle или 0
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
    mov r13, rdx
    mov r14, rcx
    call GetLastError
    mov r15d, eax
    test r14, r14
    jz 1f
    mov rcx, r14
    call CloseHandle
1:  mov rdi, r12
    call _bit_num_str
    mov rsi, rax
    mov rdi, rbx
    call _bit_cat
    mov rdi, rax
    lea rsi, [rip + Lrt_wp_code]
    call _bit_cat
    mov rbx, rax
    mov rdi, r15
    call _bit_num_str
    mov rsi, rax
    mov rdi, rbx
    call _bit_cat
    mov rdi, rax
    mov rsi, r13
    call _bit_die

_bit_wp_hex:                        // rdi = куда, rsi = число → rax = конец (шестнадцатерично, без ведущих нулей)
    mov rax, rsi
    mov ecx, 1
1:  shr rax, 4
    jz 2f
    inc ecx
    jmp 1b
2:  lea rax, [rdi + rcx]
    mov r8, rax
3:  dec r8
    mov rdx, rsi
    and edx, 15
    cmp edx, 10
    jb 4f
    add edx, 87
    jmp 5f
4:  add edx, 48
5:  mov byte ptr [r8], dl
    shr rsi, 4
    dec ecx
    jnz 3b
    ret

_bit_wp_mapline:                    // rdi = начало, rsi = конец, edx = защита → "начало-конец rwxp"
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov edi, 48
    call _bit_alloc
    mov rbx, rax
    mov rdi, rbx
    mov rsi, r12
    call _bit_wp_hex
    mov byte ptr [rax], 45
    lea rdi, [rax + 1]
    mov rsi, r13
    call _bit_wp_hex
    mov byte ptr [rax], 32
    mov ecx, r14d
    and ecx, 0xFF
    test r14d, 0x100
    jz 1f
    xor ecx, ecx
1:  mov dl, 45
    test ecx, 0xEE
    jz 2f
    mov dl, 114
2:  mov byte ptr [rax + 1], dl
    mov dl, 45
    test ecx, 0xCC
    jz 3f
    mov dl, 119
3:  mov byte ptr [rax + 2], dl
    mov dl, 45
    test ecx, 0xF0
    jz 4f
    mov dl, 120
4:  mov byte ptr [rax + 3], dl
    mov byte ptr [rax + 4], 112
    mov byte ptr [rax + 5], 0
    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_proc_find:                     // rdi = имя, rsi = строка → pid первого процесса с таким именем (с .exe или без) или -1
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32
    mov rbx, rdi
    lea rsi, [rip + Lrt_wp_exe]
    call _bit_cat
    mov r12, rax
    mov edi, 320
    call _bit_alloc
    mov r13, rax
    mov dword ptr [r13], 304
    mov ecx, 2
    xor edx, edx
    call CreateToolhelp32Snapshot
    cmp rax, -1
    je 8f
    mov r14, rax
    mov rcx, r14
    mov rdx, r13
    call Process32First
1:  test eax, eax
    jz 7f
    lea rcx, [r13 + 44]
    mov rdx, rbx
    call _stricmp
    test eax, eax
    jz 5f
    lea rcx, [r13 + 44]
    mov rdx, r12
    call _stricmp
    test eax, eax
    jz 5f
    mov rcx, r14
    mov rdx, r13
    call Process32Next
    jmp 1b
5:  mov ebx, dword ptr [r13 + 8]
    mov rcx, r14
    call CloseHandle
    mov eax, ebx
    jmp 9f
7:  mov rcx, r14
    call CloseHandle
8:  mov rax, -1
9:  add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_proc_start:                    // rdi = команда, rsi = строка → pid запущенного процесса
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 88
    mov rbx, rdi
    mov r12, rsi
    cmp dword ptr [rbx], 0x63657865
    jne 1f
    cmp byte ptr [rbx + 4], 32
    jne 1f
    add rbx, 5
1:  mov rdi, rbx
    call _w_strlen
    mov rsi, rax
    mov rdi, rbx
    call _bit_substr
    mov r13, rax
    mov edi, 136
    call _bit_alloc
    mov rdx, rax
    xor ecx, ecx
2:  mov qword ptr [rdx + rcx*8], 0
    inc rcx
    cmp rcx, 17
    jl 2b
    mov dword ptr [rdx], 104
    mov [rsp + 80], rdx
    mov [rsp + 64], rdx
    lea rax, [rdx + 104]
    mov [rsp + 72], rax
    xor ecx, ecx
    mov rdx, r13
    xor r8d, r8d
    xor r9d, r9d
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 56], 0
    call CreateProcessA
    test eax, eax
    jz 9f
    mov rdx, [rsp + 80]
    mov rcx, [rdx + 112]
    call CloseHandle
    mov rdx, [rsp + 80]
    mov eax, dword ptr [rdx + 120]
    add rsp, 88
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_wp_espawn]
    mov rsi, rbx
    mov rdx, r12
    call _bit_errpath

_bit_proc_alive:                    // rdi = pid → 1, если процесс работает
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 40
    mov ecx, 0x1000
    xor edx, edx
    mov r8d, edi
    call OpenProcess
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rcx, rax
    lea rdx, [rsp + 32]
    call GetExitCodeProcess
    test eax, eax
    jz 7f
    mov rcx, rbx
    call CloseHandle
    xor eax, eax
    cmp dword ptr [rsp + 32], 259
    sete al
    jmp 9f
7:  mov rcx, rbx
    call CloseHandle
8:  xor eax, eax
9:  add rsp, 40
    pop rbx
    pop rbp
    ret

_bit_proc_name:                     // rdi = pid → имя файла без .exe или ""
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 40
    mov r12d, edi
    mov edi, 300
    call _bit_alloc
    mov r13, rax
    mov byte ptr [r13], 0
    mov ecx, 0x1000
    xor edx, edx
    mov r8d, r12d
    call OpenProcess
    test rax, rax
    jz 9f
    mov rbx, rax
    mov dword ptr [rsp + 32], 290
    mov rcx, rbx
    xor edx, edx
    mov r8, r13
    lea r9, [rsp + 32]
    call QueryFullProcessImageNameA
    mov r12d, eax
    mov rcx, rbx
    call CloseHandle
    test r12d, r12d
    jnz 1f
    mov byte ptr [r13], 0
    jmp 9f
1:  mov rax, r13
    mov rcx, r13
2:  movzx edx, byte ptr [rcx]
    test dl, dl
    jz 4f
    cmp dl, 92
    je 3f
    cmp dl, 47
    jne 31f
3:  lea rax, [rcx + 1]
31: inc rcx
    jmp 2b
4:  mov rdx, rcx
    sub rdx, rax
    cmp rdx, 4
    jl 6f
    mov r8d, dword ptr [rcx - 4]
    or r8d, 0x20202020
    cmp r8d, 0x6578652e
    jne 6f
    mov byte ptr [rcx - 4], 0
6:  mov rcx, r13
7:  movzx edx, byte ptr [rax]
    mov byte ptr [rcx], dl
    inc rax
    inc rcx
    test dl, dl
    jnz 7b
9:  mov rax, r13
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_proc_wait:                     // rdi = pid → код выхода (ждёт завершения), -1 если процесс не открыть
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 40
    mov ecx, 0x101000
    xor edx, edx
    mov r8d, edi
    call OpenProcess
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rcx, rbx
    mov edx, -1
    call WaitForSingleObject
    mov rcx, rbx
    lea rdx, [rsp + 32]
    call GetExitCodeProcess
    mov rcx, rbx
    call CloseHandle
    mov eax, dword ptr [rsp + 32]
    mov [rip + Lrt_status], rax
    jmp 9f
8:  mov rax, -1
9:  add rsp, 40
    pop rbx
    pop rbp
    ret

_bit_proc_kill:                     // rdi = pid, rsi = строка: завершить процесс (код 143, как SIGTERM на Linux)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 40
    mov r12, rdi
    mov r13, rsi
    mov ecx, 1
    xor edx, edx
    mov r8d, r12d
    call OpenProcess
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rcx, rbx
    mov edx, 143
    call TerminateProcess
    test eax, eax
    jz 7f
    mov rcx, rbx
    call CloseHandle
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
7:  lea rdi, [rip + Lrt_wp_ekill]
    mov rsi, r12
    mov rdx, r13
    mov rcx, rbx
    call _bit_wp_fail
8:  lea rdi, [rip + Lrt_wp_ekill]
    mov rsi, r12
    mov rdx, r13
    xor ecx, ecx
    call _bit_wp_fail

_bit_proc_read:                     // rdi = pid, rsi = адрес, rdx = сколько байт, rcx = строка → bytes
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rdi, r14
    call _bit_bytes_new
    mov rbx, rax
    mov ecx, 0x10
    xor edx, edx
    mov r8d, r12d
    call OpenProcess
    test rax, rax
    jz 8f
    mov [rsp + 48], rax
    mov rcx, rax
    mov rdx, r13
    mov r8, [rbx]
    mov r9, [rbx + 8]
    lea rax, [rsp + 40]
    mov [rsp + 32], rax
    call ReadProcessMemory
    test eax, eax
    jz 7f
    mov rcx, [rsp + 48]
    call CloseHandle
    mov rax, rbx
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
7:  lea rdi, [rip + Lrt_wp_eread]
    mov rsi, r12
    mov rdx, r15
    mov rcx, [rsp + 48]
    call _bit_wp_fail
8:  lea rdi, [rip + Lrt_wp_eread]
    mov rsi, r12
    mov rdx, r15
    xor ecx, ecx
    call _bit_wp_fail

_bit_proc_write:                    // rdi = pid, rsi = адрес, rdx = bytes, rcx = строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov ecx, 0x28
    xor edx, edx
    mov r8d, r12d
    call OpenProcess
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rcx, rbx
    mov rdx, r13
    mov r8, [r14]
    mov r9, [r14 + 8]
    lea rax, [rsp + 40]
    mov [rsp + 32], rax
    call WriteProcessMemory
    test eax, eax
    jz 7f
    mov rcx, rbx
    call CloseHandle
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
7:  lea rdi, [rip + Lrt_wp_ewrite]
    mov rsi, r12
    mov rdx, r15
    mov rcx, rbx
    call _bit_wp_fail
8:  lea rdi, [rip + Lrt_wp_ewrite]
    mov rsi, r12
    mov rdx, r15
    xor ecx, ecx
    call _bit_wp_fail

_bit_proc_read_num:                 // rdi = pid, rsi = адрес, rdx = строка → число (8 байт)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 64
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov ecx, 0x10
    xor edx, edx
    mov r8d, r12d
    call OpenProcess
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rcx, rbx
    mov rdx, r13
    lea r8, [rsp + 48]
    mov r9d, 8
    lea rax, [rsp + 40]
    mov [rsp + 32], rax
    call ReadProcessMemory
    test eax, eax
    jz 7f
    mov rcx, rbx
    call CloseHandle
    mov rax, [rsp + 48]
    add rsp, 64
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
7:  lea rdi, [rip + Lrt_wp_eread]
    mov rsi, r12
    mov rdx, r14
    mov rcx, rbx
    call _bit_wp_fail
8:  lea rdi, [rip + Lrt_wp_eread]
    mov rsi, r12
    mov rdx, r14
    xor ecx, ecx
    call _bit_wp_fail

_bit_proc_write_num:                // rdi = pid, rsi = адрес, rdx = число, rcx = строка
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56
    mov r12, rdi
    mov r13, rsi
    mov [rsp + 48], rdx
    mov r15, rcx
    mov ecx, 0x28
    xor edx, edx
    mov r8d, r12d
    call OpenProcess
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rcx, rbx
    mov rdx, r13
    lea r8, [rsp + 48]
    mov r9d, 8
    lea rax, [rsp + 40]
    mov [rsp + 32], rax
    call WriteProcessMemory
    test eax, eax
    jz 7f
    mov rcx, rbx
    call CloseHandle
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
7:  lea rdi, [rip + Lrt_wp_ewrite]
    mov rsi, r12
    mov rdx, r15
    mov rcx, rbx
    call _bit_wp_fail
8:  lea rdi, [rip + Lrt_wp_ewrite]
    mov rsi, r12
    mov rdx, r15
    xor ecx, ecx
    call _bit_wp_fail

_bit_proc_maps:                     // rdi = pid, rsi = строка → mas строк "начало-конец rwxp" (выделенные регионы)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 120
    mov r12, rdi
    mov r13, rsi
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r14, rax
    mov ecx, 0x410
    xor edx, edx
    mov r8d, r12d
    call OpenProcess
    test rax, rax
    jz 8f
    mov rbx, rax
    xor r15d, r15d
1:  mov rcx, rbx
    mov rdx, r15
    lea r8, [rsp + 48]
    mov r9d, 48
    call VirtualQueryEx
    test rax, rax
    jz 9f
    cmp dword ptr [rsp + 80], 0x1000
    jne 5f
    mov rdi, [rsp + 48]
    mov rsi, rdi
    add rsi, [rsp + 72]
    mov edx, dword ptr [rsp + 84]
    call _bit_wp_mapline
    mov rsi, rax
    mov rdi, r14
    mov rdx, r13
    call _bit_mas_add
5:  mov rax, [rsp + 48]
    add rax, [rsp + 72]
    cmp rax, r15
    jbe 9f
    mov r15, rax
    jmp 1b
9:  mov rcx, rbx
    call CloseHandle
    mov rax, r14
    add rsp, 120
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  lea rdi, [rip + Lrt_wp_eread]
    mov rsi, r12
    mov rdx, r13
    xor ecx, ecx
    call _bit_wp_fail

_bit_proc_scan:                     // rdi = pid, rsi = число, rdx = строка → mas адресов, где лежит это 8-байтное число
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 120
    mov [rsp + 104], rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r14, rax
    mov edi, 1048584
    call _bit_alloc
    mov [rsp + 96], rax
    mov ecx, 0x410
    xor edx, edx
    mov r8d, dword ptr [rsp + 104]
    call OpenProcess
    test rax, rax
    jz 8f
    mov rbx, rax
    xor r15d, r15d
1:  mov rcx, rbx
    mov rdx, r15
    lea r8, [rsp + 48]
    mov r9d, 48
    call VirtualQueryEx
    test rax, rax
    jz 9f
    mov rax, [rsp + 48]
    add rax, [rsp + 72]
    cmp rax, r15
    jbe 9f
    mov [rsp + 112], rax
    cmp dword ptr [rsp + 80], 0x1000
    jne 6f
    mov eax, dword ptr [rsp + 84]
    test eax, 0x100
    jnz 6f
    test eax, 0xEE
    jz 6f
    mov r15, [rsp + 48]
2:  mov rax, [rsp + 112]
    sub rax, r15
    jbe 6f
    cmp rax, 1048576
    jbe 21f
    mov rax, 1048576
21: mov [rsp + 56], rax
    mov rcx, rbx
    mov rdx, r15
    mov r8, [rsp + 96]
    mov r9, rax
    lea rax, [rsp + 40]
    mov [rsp + 32], rax
    call ReadProcessMemory
    test eax, eax
    jz 5f
    mov r9, [rsp + 40]
    cmp r9, 8
    jb 5f
    sub r9, 8
    mov r8, [rsp + 96]
    xor r10d, r10d
3:  cmp r10, r9
    ja 5f
    mov rax, [r8 + r10]
    cmp rax, r12
    jne 4f
    mov [rsp + 64], r10
    mov [rsp + 72], r9
    mov rsi, r15
    add rsi, r10
    mov rdi, r14
    mov rdx, r13
    call _bit_mas_add
    mov r10, [rsp + 64]
    mov r9, [rsp + 72]
    mov r8, [rsp + 96]
4:  inc r10
    jmp 3b
5:  mov rax, [rsp + 56]
    mov rcx, r15
    add rcx, rax
    cmp rcx, [rsp + 112]
    jae 6f
    cmp rax, 8
    jbe 51f
    sub rax, 7
51: add r15, rax
    jmp 2b
6:  mov r15, [rsp + 112]
    jmp 1b
9:  mov rcx, rbx
    call CloseHandle
    mov rax, r14
    add rsp, 120
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  lea rdi, [rip + Lrt_wp_eread]
    mov rsi, [rsp + 104]
    mov rdx, r13
    xor ecx, ecx
    call _bit_wp_fail

.data
.p2align 3
Lrt_str_registry: .quad 0
Lrt_str_low: .quad -1
Lrt_str_high: .quad 0
Lrt_argc: .quad 0
Lrt_argv: .quad 0
Lrt_status: .quad 0
Lrt_random_state: .quad 0
Lrt_random_ready: .quad 0
Lrt_ready: .byte 0
.p2align 3
Lrt_tkey: .quad 0
.p2align 3
Lrt_slock: .zero 80
Lrt_recover: .quad 0
Lrt_owned: .quad 0
Lrt_errmsg: .quad 0
Lrt_errline: .quad 0
Lrt_errcode: .quad 0
Lrt_stderr: .quad 0
Lrt_wsa: .quad 0
Lrt_oldocp: .quad 0
Lrt_oldicp: .quad 0
.p2align 4
.p2align 3

.section .rdata
Lrt_oom: .asciz "\320\275\320\265 \321\205\320\262\320\260\321\202\320\260\320\265\321\202 \320\277\320\260\320\274\321\217\321\202\320\270"
Lrt_die: .asciz "\012\320\236\321\210\320\270\320\261\320\272\320\260 \320\262\321\213\320\277\320\276\320\273\320\275\320\265\320\275\320\270\321\217 (\321\201\321\202\321\200\320\276\320\272\320\260 %lld): %s\012"
Lrt_lld: .asciz "%lld"
Lrt_g: .asciz "%.17g"
Lrt_decch: .asciz ".eni"
Lrt_dot0: .asciz ".0"
Lrt_true: .asciz "true"
Lrt_false: .asciz "false"
Lrt_lpar: .asciz "("
Lrt_rpar: .asciz ")"
Lrt_comma: .asciz ", "
Lrt_hex: .asciz "0123456789abcdef"
Lrt_empty: .asciz ""
Lrt_full: .asciz "\320\274\320\260\321\201\321\201\320\270\320\262 \320\267\320\260\320\277\320\276\320\273\320\275\320\265\320\275 \342\200\224 \321\215\320\273\320\265\320\274\320\265\320\275\321\202\320\276\320\262 \321\203\320\266\320\265 \321\201\321\202\320\276\320\273\321\214\320\272\320\276, \321\201\320\272\320\276\320\273\321\214\320\272\320\276 \320\273\320\270\320\274\320\270\321\202"
Lrt_ovf: .asciz "\320\277\320\265\321\200\320\265\320\277\320\276\320\273\320\275\320\265\320\275\320\270\320\265 num \342\200\224 \321\207\320\270\321\201\320\273\320\276 \320\275\320\265 \320\262\320\273\320\265\320\267\320\273\320\276"
Lrt_e8: .asciz "\320\262 bytes \320\275\320\265\321\202 8 \320\261\320\260\320\271\321\202 \321\201 \321\215\321\202\320\276\320\263\320\276 \320\275\320\276\320\274\320\265\321\200\320\260"
Lrt_enet: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\277\320\276\320\264\320\272\320\273\321\216\321\207\320\270\321\202\321\214\321\201\321\217"
Lrt_elisten: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\276\321\202\320\272\321\200\321\213\321\202\321\214 \320\277\320\276\321\200\321\202"
Lrt_eaccept: .asciz "\320\276\321\210\320\270\320\261\320\272\320\260 \320\277\321\200\320\270\321\221\320\274\320\260 \320\277\320\276\320\264\320\272\320\273\321\216\321\207\320\265\320\275\320\270\321\217"
Lrt_esend: .asciz "\320\276\321\210\320\270\320\261\320\272\320\260 \320\276\321\202\320\277\321\200\320\260\320\262\320\272\320\270"
Lrt_erecv: .asciz "\320\276\321\210\320\270\320\261\320\272\320\260 \320\277\321\200\320\270\321\221\320\274\320\260"
Lrt_edns: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\275\320\260\320\271\321\202\320\270 \320\260\320\264\321\200\320\265\321\201 \321\205\320\276\321\201\321\202\320\260"
Lrt_elisten_addr: .asciz "listen: \320\275\320\265\320\262\320\265\321\200\320\275\321\213\320\271 IPv4-\320\260\320\264\321\200\320\265\321\201"
Lrt_peer_colon: .asciz ":"
Lrt_epeer: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \321\203\320\267\320\275\320\260\321\202\321\214 \320\260\320\264\321\200\320\265\321\201 \321\201\320\276\320\261\320\265\321\201\320\265\320\264\320\275\320\270\320\272\320\260"
Lrt_remove_home: .asciz "HOME"
Lrt_remove_profile: .asciz "USERPROFILE"
Lrt_ermhome: .asciz "remove_all: \320\275\320\265\320\273\321\214\320\267\321\217 \321\203\320\264\320\260\320\273\321\217\321\202\321\214 \320\264\320\276\320\274\320\260\321\210\320\275\321\216\321\216 \320\277\320\260\320\277\320\272\321\203: "
Lrt_ermroot: .asciz "remove_all: \320\275\320\265\320\273\321\214\320\267\321\217 \321\203\320\264\320\260\320\273\321\217\321\202\321\214 \320\272\320\276\321\200\320\265\320\275\321\214, \320\277\321\203\321\201\321\202\320\276\320\271 \320\277\321\203\321\202\321\214, . \320\270\320\273\320\270 ..: "
Lrt_ermtree: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \321\203\320\264\320\260\320\273\320\270\321\202\321\214 \320\277\320\260\320\277\320\272\321\203 \321\201 \321\201\320\276\320\264\320\265\321\200\320\266\320\270\320\274\321\213\320\274: "
Lrt_epermread: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \321\203\320\267\320\275\320\260\321\202\321\214 \320\277\321\200\320\260\320\262\320\260 \320\264\320\276\321\201\321\202\321\203\320\277\320\260: "
Lrt_epermwrite: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\270\320\267\320\274\320\265\320\275\320\270\321\202\321\214 \320\277\321\200\320\260\320\262\320\260 \320\264\320\276\321\201\321\202\321\203\320\277\320\260: "
Lrt_ecwd: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \321\203\320\267\320\275\320\260\321\202\321\214 \321\202\320\265\320\272\321\203\321\211\321\203\321\216 \320\277\320\260\320\277\320\272\321\203"
Lrt_ego: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \321\201\320\274\320\265\320\275\320\270\321\202\321\214 \320\277\320\260\320\277\320\272\321\203: "
Lrt_eenv: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\267\320\260\320\264\320\260\321\202\321\214 \320\277\320\265\321\200\320\265\320\274\320\265\320\275\320\275\321\203\321\216 \320\276\320\272\321\200\321\203\320\266\320\265\320\275\320\270\321\217: "
Lrt_wp_exe: .asciz ".exe"
Lrt_wp_code: .asciz ", \320\272\320\276\320\264 \320\276\321\210\320\270\320\261\320\272\320\270 "
Lrt_wp_eread: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\277\321\200\320\276\321\207\320\270\321\202\320\260\321\202\321\214 \320\277\320\260\320\274\321\217\321\202\321\214 \320\277\321\200\320\276\321\206\320\265\321\201\321\201\320\260 "
Lrt_wp_ewrite: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\267\320\260\320\277\320\270\321\201\320\260\321\202\321\214 \320\262 \320\277\320\260\320\274\321\217\321\202\321\214 \320\277\321\200\320\276\321\206\320\265\321\201\321\201\320\260 "
Lrt_wp_ekill: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\276\321\201\321\202\320\260\320\275\320\276\320\262\320\270\321\202\321\214 \320\277\321\200\320\276\321\206\320\265\321\201\321\201 "
Lrt_wp_espawn: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\267\320\260\320\277\321\203\321\201\321\202\320\270\321\202\321\214: "
Lrt_rb: .asciz "rb"
Lrt_wb: .asciz "wb"
Lrt_r: .asciz "r"
Lrt_star: .asciz "\134*"
Lrt_userenv: .asciz "USERNAME"
Lrt_pscmd: .asciz "tasklist"
Lrt_eof: .asciz "\320\262\320\262\320\276\320\264 \320\267\320\260\320\272\320\276\320\275\321\207\320\270\320\273\321\201\321\217, \320\260 \320\277\321\200\320\276\320\263\321\200\320\260\320\274\320\274\320\260 \320\266\320\264\320\260\320\273\320\260 \320\267\320\275\320\260\321\207\320\265\320\275\320\270\320\265"
Lrt_numr: .asciz "\320\275\321\203\320\266\320\275\320\276 \321\206\320\265\320\273\320\276\320\265 \321\207\320\270\321\201\320\273\320\276 \320\276\321\202 %lld \320\264\320\276 %lld, \320\277\320\276\320\277\321\200\320\276\320\261\321\203\320\271 \320\265\321\211\321\221 \321\200\320\260\320\267: "
Lrt_num: .asciz "\320\275\321\203\320\266\320\275\320\276 \321\206\320\265\320\273\320\276\320\265 \321\207\320\270\321\201\320\273\320\276, \320\277\320\276\320\277\321\200\320\276\320\261\321\203\320\271 \320\265\321\211\321\221 \321\200\320\260\320\267: "
Lrt_decr: .asciz "\320\275\321\203\320\266\320\275\320\276 \321\207\320\270\321\201\320\273\320\276 \320\276\321\202 %g \320\264\320\276 %g, \320\277\320\276\320\277\321\200\320\276\320\261\321\203\320\271 \320\265\321\211\321\221 \321\200\320\260\320\267: "
Lrt_dec: .asciz "\320\275\321\203\320\266\320\275\320\276 \321\207\320\270\321\201\320\273\320\276, \320\277\320\276\320\277\321\200\320\276\320\261\321\203\320\271 \320\265\321\211\321\221 \321\200\320\260\320\267: "
Lrt_boolm: .asciz "\320\275\321\203\320\266\320\275\320\276 true \320\270\320\273\320\270 false (\320\264\320\260/\320\275\320\265\321\202), \320\277\320\276\320\277\321\200\320\276\320\261\321\203\320\271 \320\265\321\211\321\221 \321\200\320\260\320\267: "
Lrt_da: .asciz "\320\264\320\260"
Lrt_net: .asciz "\320\275\320\265\321\202"
Lrt_1: .asciz "1"
Lrt_0: .asciz "0"
Lrt_eopen: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\276\321\202\320\272\321\200\321\213\321\202\321\214 \321\204\320\260\320\271\320\273: "
Lrt_eread: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\277\321\200\320\276\321\207\320\270\321\202\320\260\321\202\321\214 \321\204\320\260\320\271\320\273: "
Lrt_ewrite: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\267\320\260\320\277\320\270\321\201\320\260\321\202\321\214 \320\262 \321\204\320\260\320\271\320\273: "
Lrt_enotfile: .asciz "\321\215\321\202\320\276 \320\275\320\265 \321\204\320\260\320\271\320\273: "
Lrt_echunk: .asciz "\321\201\320\274\320\265\321\211\320\265\320\275\320\270\320\265 \320\270 \321\200\320\260\320\267\320\274\320\265\321\200 \320\264\320\276\320\273\320\266\320\275\321\213 \320\261\321\213\321\202\321\214 \320\275\320\265\320\276\321\202\321\200\320\270\321\206\320\260\321\202\320\265\320\273\321\214\320\275\321\213\320\274\320\270"
Lrt_erecv_timeout: .asciz "\320\270\321\201\321\202\320\265\320\272\320\273\320\276 \320\262\321\200\320\265\320\274\321\217 \320\276\320\266\320\270\320\264\320\260\320\275\320\270\321\217 recv"
Lrt_erecv_args: .asciz "recv: \321\200\320\260\320\267\320\274\320\265\321\200 1..2147483647, \320\276\320\266\320\270\320\264\320\260\320\275\320\270\320\265 0..2147483647 \320\274\321\201"
Lrt_econn_timeout: .asciz "\320\270\321\201\321\202\320\265\320\272\320\273\320\276 \320\262\321\200\320\265\320\274\321\217 \320\276\320\266\320\270\320\264\320\260\320\275\320\270\321\217 \320\277\320\276\320\264\320\272\320\273\321\216\321\207\320\265\320\275\320\270\321\217"
Lrt_econn_args: .asciz "connect: \321\202\320\260\320\271\320\274\320\260\321\203\321\202 \320\276\321\202 0 \320\264\320\276 2147483647 \320\274\321\201"
Lrt_enotdir: .asciz "\321\215\321\202\320\276 \320\275\320\265 \320\277\320\260\320\277\320\272\320\260: "
Lrt_erm: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \321\203\320\264\320\260\320\273\320\270\321\202\321\214: "
Lrt_emv: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\277\320\265\321\200\320\265\320\274\320\265\321\201\321\202\320\270\321\202\321\214: "
Lrt_emk: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \321\201\320\276\320\267\320\264\320\260\321\202\321\214 \320\277\320\260\320\277\320\272\321\203: "
Lrt_edir: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\276\321\202\320\272\321\200\321\213\321\202\321\214 \320\277\320\260\320\277\320\272\321\203: "
Lrt_slash: .asciz "/"
Lrt_w: .asciz "wb"
Lrt_a: .asciz "ab"
Lrt_erun: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\267\320\260\320\277\321\203\321\201\321\202\320\270\321\202\321\214 \320\272\320\276\320\274\320\260\320\275\320\264\321\203: "
Lrt_cls: .asciz "\033[2J\033[H"
Lrt_dashdash: .asciz " -- "
Lrt_gp: .asciz "%.*g"
Lrt_fp: .asciz "%.*f"
Lrt_ecode_empty: .asciz "code: \320\277\321\203\321\201\321\202\320\260\321\217 \321\201\321\202\321\200\320\276\320\272\320\260"
Lrt_echar_range: .asciz "char: \320\272\320\276\320\264 \321\201\320\270\320\274\320\262\320\276\320\273\320\260 \320\276\321\202 0 \320\264\320\276 1114111"
Lrt_epad_width: .asciz "pad: \321\210\320\270\321\200\320\270\320\275\320\260 \320\276\321\202 0 \320\264\320\276 1000000"
Lrt_epad_count: .asciz "repeat: \321\207\320\270\321\201\320\273\320\276 \320\276\321\202 0 \320\264\320\276 100000000"
Lrt_ehex_width: .asciz "hex: \321\210\320\270\321\200\320\270\320\275\320\260 \320\276\321\202 0 \320\264\320\276 64"
Lrt_efixed_places: .asciz "fixed: \320\267\320\275\320\260\320\272\320\276\320\262 \320\276\321\202 0 \320\264\320\276 17"
Lrt_cpucmd: .asciz ""
Lrt_memsize: .asciz ""
Lrt_vmps: .asciz ""
Lrt_curlget: .asciz "curl -sS -L -- "
Lrt_curlout: .asciz "curl -sS -L -o "
Lrt_curlpost: .asciz "curl -sS -L -d "
Lrt_pingcmd: .asciz "ping -n 1 "
Lrt_quiet: .asciz " >nul 2>&1"
Lrt_curl: .asciz "curl"
Lrt_sS: .asciz "-sS"
Lrt_L: .asciz "-L"
Lrt_ddp: .asciz "--"
Lrt_d: .asciz "-d"
Lrt_o: .asciz "-o"
Lrt_pingp: .asciz "ping"
Lrt_pingc: .asciz "-n"
Lrt_nul: .asciz "NUL"
Lrt_copy_suffix: .asciz ".bit-copy-XXXXXX"
Lrt_badnum: .asciz "invalid num: expected a decimal integer in range"
Lrt_random_bounds: .asciz "random: expected minimum <= maximum"
Lrt_random_entropy: .asciz "random: cannot read system entropy"
.text
