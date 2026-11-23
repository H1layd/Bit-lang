.intel_syntax noprefix
.section __TEXT,__text,regular,pure_instructions

// ─────────── среда выполнения bit (x86_64) ───────────
// аргументы: rdi, rsi, rdx, rcx, r8, r9; результат: rax
.p2align 4
_bit_recover_enter:                 // rdi = frame allocated by the compiler
    mov rax, [rip + Lrt_recover]
    mov [rdi + 168], rax
    mov [rip + Lrt_recover], rdi
    mov rax, [rip + Lrt_owned]
    mov [rdi + 176], rax
    mov rax, rdi
    ret

_bit_recover_leave:
    mov rax, [rip + Lrt_recover]
    mov rax, [rax + 168]
    mov [rip + Lrt_recover], rax
    ret

_bit_own_str:                       // rdi = stack record with string and previous pointer
    mov rax, [rip + Lrt_owned]
    mov [rdi + 8], rax
    mov [rip + Lrt_owned], rdi
    ret

_bit_drop_owned:
    mov rax, [rip + Lrt_owned]
    mov rcx, [rax + 8]
    mov [rip + Lrt_owned], rcx
    mov rdi, [rax]
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

_bit_term_error:                    // → копия текста последней пойманной ошибки ("" если не было)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, [rip + Lrt_errmsg]
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
    mov rax, [rip + Lrt_recover]
    test rax, rax
    jz 5f
    mov [rip + Lrt_errmsg], rdi
    mov [rip + Lrt_errline], rsi
    mov rcx, [rax + 168]
    mov [rip + Lrt_recover], rcx
    push rax
1:  mov rcx, [rip + Lrt_owned]
    cmp rcx, [rax + 176]
    je 2f
    call _bit_drop_owned
    mov rax, [rsp]
    jmp 1b
2:  pop rdi
    mov esi, 1
    jmp _bit_longjmp
5:  push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    xor edi, edi
    call _fflush
    mov rax, [rip + ___stderrp@GOTPCREL]
    mov rdi, [rax]
    lea rsi, [rip + Lrt_die]
    mov rdx, r12
    mov rcx, rbx
    xor eax, eax
    call _fprintf
    mov edi, 1
    call _exit

_bit_oom:
    and rsp, -16
    lea rdi, [rip + Lrt_oom]
    xor esi, esi
    call _bit_die

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
1:  pop rbp
    ret

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

_bit_wait:                          // rdi = миллисекунды
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    xor edi, edi
    call _fflush
1:  test rbx, rbx
    jle 3f
    mov r12, 1000
    cmp rbx, r12
    cmovl r12, rbx
    sub rbx, r12
    imul rdi, r12, 1000
    call _usleep
    jmp 1b
3:  pop r12
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
8:  lea rax, [rip + Lrt_empty]
10: pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_file_line:                     // rdi = путь, rsi = номер строки, rdx = строка программы
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rsi
    mov rsi, rdx
    call _bit_file_lines
    test rbx, rbx
    js 1f
    cmp rbx, [rax + 8]
    jge 1f
    mov rax, [rax]
    mov rax, [rax + rbx*8]
    jmp 2f
1:  lea rax, [rip + Lrt_empty]
2:  pop r12
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

_bit_drop_str:                      // rdi = строка (куча) -> освободить
    push rbp
    mov rbp, rsp
    call _free
    pop rbp
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
    mov [rdx], al
    inc rcx
    inc rdx
    jmp 1b
2:  mov byte ptr [rdx], 0
    inc rcx
    xor r8d, r8d
3:  movzx eax, byte ptr [rcx]
    sub eax, 48
    cmp eax, 9
    ja 4f
    imul r8d, r8d, 10
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
    add rsp, 112
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  mov edi, ebx
    call _close
9:  add rsp, 112
    lea rdi, [rip + Lrt_enet]
    mov rsi, r12
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_tcp_listen:                    // rdi = порт, rsi = строка -> server
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 32
    mov r12d, edi
    mov r13, rsi
    mov edi, 2
    mov esi, 1
    xor edx, edx
    call _socket
    test eax, eax
    js 9f
    mov ebx, eax
    xor eax, eax
    mov [rsp], rax
    mov [rsp + 8], rax
    mov word ptr [rsp], 2
    mov eax, r12d
    mov ecx, eax
    shl eax, 8
    shr ecx, 8
    or eax, ecx
    mov [rsp + 2], ax
    mov edi, ebx
    lea rsi, [rsp]
    mov edx, 16
    call _bind
    test eax, eax
    js 9f
    mov edi, ebx
    mov esi, 16
    call _listen
    test eax, eax
    js 9f
    mov eax, ebx
    add rsp, 32
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
9:  add rsp, 32
    lea rdi, [rip + Lrt_elisten]
    mov rsi, r13
    pop r13
    pop r12
    pop rbx
    pop rbp
    jmp _bit_die

_bit_tcp_accept:                    // rdi = server, rsi = строка -> conn
    push rbp
    mov rbp, rsp
    push rbx
    mov rbx, rsi
    xor esi, esi
    xor edx, edx
    call _accept
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
    sub rsp, 24
    mov dword ptr [rsp], edi
    // POLLIN; clear revents
    mov dword ptr [rsp + 4], 1
    mov edx, esi
    mov esi, 1
    mov rdi, rsp
    call _poll
    add rsp, 24
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
8:  lea rdi, [rip + Lrt_erecv_timeout]
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
    mov edi, 256
    call _bit_alloc
    mov rbx, rax
    mov rdi, rbx
    mov esi, 256
    call _gethostname
    mov rax, rbx
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

_bit_os_now:                        // -> время (секунды)
    push rbp
    mov rbp, rsp
    xor edi, edi
    call _time
    pop rbp
    ret

_bit_os_cpus:                       // rdi = строка -> число ядер
    push rbp
    mov rbp, rsp
    mov rsi, rdi
    lea rdi, [rip + Lrt_cpucmd]
    call _bit_run
    mov rdi, rax
    call _bit_str_num
    pop rbp
    ret

_bit_os_procs:                      // rdi = строка -> список процессов
    mov rsi, rdi
    lea rdi, [rip + Lrt_pscmd]
    jmp _bit_run

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
Lrt_argc: .quad 0
Lrt_argv: .quad 0
Lrt_status: .quad 0
Lrt_random_state: .quad 0
Lrt_random_ready: .quad 0
Lrt_recover: .quad 0
Lrt_owned: .quad 0
Lrt_errmsg: .quad 0
Lrt_errline: .quad 0
Lrt_stderr: .quad 0
.p2align 4
.section __TEXT,__cstring,cstring_literals
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
Lrt_cpucmd: .asciz "getconf _NPROCESSORS_ONLN 2>/dev/null"
Lrt_pscmd: .asciz "ps -axo pid=,comm= 2>/dev/null"
Lrt_edns: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\275\320\260\320\271\321\202\320\270 \320\260\320\264\321\200\320\265\321\201 \321\205\320\276\321\201\321\202\320\260"
Lrt_pingcmd: .asciz "ping -c 1 "
Lrt_quiet: .asciz " >/dev/null 2>&1"
Lrt_curlget: .asciz "curl -sS -L -- "
Lrt_curlpost: .asciz "curl -sS -L -d "
Lrt_curlout: .asciz "curl -sS -L -o "
Lrt_dashdash: .asciz " -- "
Lrt_enet: .asciz "\320\275\320\265 \320\274\320\276\320\263\321\203 \320\277\320\276\320\264\320\272\320\273\321\216\321\207\320\270\321\202\321\214\321\201\321\217"
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
