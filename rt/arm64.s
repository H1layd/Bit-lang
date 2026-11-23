
// ─────────── среда выполнения bit ───────────
.p2align 2
_bit_recover_enter:                 // → x0 = буфер перехода; глубину +1
    adrp x1, Lrt_recdepth@PAGE
    ldr x0, [x1, Lrt_recdepth@PAGEOFF]
    mov x2, x0
    lsl x2, x2, #9
    adrp x3, Lrt_recbufs@PAGE
    add x3, x3, Lrt_recbufs@PAGEOFF
    add x3, x3, x2
    add x0, x0, #1
    str x0, [x1, Lrt_recdepth@PAGEOFF]
    mov x0, x3
    ret

_bit_recover_leave:                 // глубину -1
    adrp x1, Lrt_recdepth@PAGE
    ldr x0, [x1, Lrt_recdepth@PAGEOFF]
    sub x0, x0, #1
    str x0, [x1, Lrt_recdepth@PAGEOFF]
    ret

_bit_setjmp:                        // x0 = буфер → 0; сохраняет x19-x30, sp, d8-d15
    stp x19, x20, [x0, #0]
    stp x21, x22, [x0, #16]
    stp x23, x24, [x0, #32]
    stp x25, x26, [x0, #48]
    stp x27, x28, [x0, #64]
    stp x29, x30, [x0, #80]
    mov x1, sp
    str x1, [x0, #96]
    stp d8, d9, [x0, #104]
    stp d10, d11, [x0, #120]
    stp d12, d13, [x0, #136]
    stp d14, d15, [x0, #152]
    mov x0, #0
    ret

_bit_longjmp:                       // x0 = буфер, x1 = значение → возврат из _bit_setjmp
    ldp x19, x20, [x0, #0]
    ldp x21, x22, [x0, #16]
    ldp x23, x24, [x0, #32]
    ldp x25, x26, [x0, #48]
    ldp x27, x28, [x0, #64]
    ldp x29, x30, [x0, #80]
    ldr x2, [x0, #96]
    mov sp, x2
    ldp d8, d9, [x0, #104]
    ldp d10, d11, [x0, #120]
    ldp d12, d13, [x0, #136]
    ldp d14, d15, [x0, #152]
    mov x0, x1
    ret

_bit_term_error:                    // → копия текста последней пойманной ошибки ("" если не было)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    adrp x1, Lrt_errmsg@PAGE
    ldr x19, [x1, Lrt_errmsg@PAGEOFF]
    cbnz x19, 1f
    mov x0, #1
    bl _bit_alloc
    strb wzr, [x0]
    b 2f
1:  mov x0, x19
    bl _strlen
    mov x1, x0
    mov x0, x19
    bl _bit_substr
2:  ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_die:                           // x0 = сообщение, x1 = строка программы
    adrp x9, Lrt_recdepth@PAGE
    ldr x10, [x9, Lrt_recdepth@PAGEOFF]
    cbz x10, 5f
    adrp x12, Lrt_errmsg@PAGE
    str x0, [x12, Lrt_errmsg@PAGEOFF]
    adrp x12, Lrt_errline@PAGE
    str x1, [x12, Lrt_errline@PAGEOFF]
    sub x10, x10, #1
    str x10, [x9, Lrt_recdepth@PAGEOFF]
    lsl x11, x10, #9
    adrp x0, Lrt_recbufs@PAGE
    add x0, x0, Lrt_recbufs@PAGEOFF
    add x0, x0, x11
    mov x1, #1
    b _bit_longjmp
5:  stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x0, #0
    bl _fflush
    sub sp, sp, #16
    str x20, [sp]
    str x19, [sp, #8]
    adrp x0, ___stderrp@GOTPAGE
    ldr x0, [x0, ___stderrp@GOTPAGEOFF]
    ldr x0, [x0]
    adrp x1, Lrt_die@PAGE
    add x1, x1, Lrt_die@PAGEOFF
    bl _fprintf
    mov x0, #1
    bl _exit

_bit_oom:
    adrp x0, Lrt_oom@PAGE
    add x0, x0, Lrt_oom@PAGEOFF
    mov x1, #0
    b _bit_die

_bit_alloc:                         // x0 = байты → x0 = память
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _malloc
    cbz x0, _bit_oom
    ldp x29, x30, [sp], #16
    ret

_bit_print:                         // x0 = строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _puts
    ldp x29, x30, [sp], #16
    ret

_bit_num_str:                       // x0 = num → строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x0, #32
    bl _bit_alloc
    mov x20, x0
    sub sp, sp, #16
    str x19, [sp]
    mov x0, x20
    mov x1, #32
    adrp x2, Lrt_lld@PAGE
    add x2, x2, Lrt_lld@PAGEOFF
    bl _snprintf
    add sp, sp, #16
    mov x0, x20
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_dec_str:                       // x0 = биты dec → самая короткая точная запись
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x0, #48
    bl _bit_alloc
    mov x20, x0
    mov x21, #15
1:  sub sp, sp, #16
    str x21, [sp]
    str x19, [sp, #8]
    mov x0, x20
    mov x1, #44
    adrp x2, Lrt_gp@PAGE
    add x2, x2, Lrt_gp@PAGEOFF
    bl _snprintf
    add sp, sp, #16
    cmp x21, #17
    b.ge 2f
    mov x0, x20
    mov x1, #0
    bl _strtod
    fmov x2, d0
    cmp x2, x19
    b.eq 2f
    add x21, x21, #1
    b 1b
2:  mov x0, x20
    adrp x1, Lrt_decch@PAGE
    add x1, x1, Lrt_decch@PAGEOFF
    bl _strpbrk
    cbnz x0, 3f
    mov x0, x20
    adrp x1, Lrt_dot0@PAGE
    add x1, x1, Lrt_dot0@PAGEOFF
    bl _strcat
3:  mov x0, x20
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_bool_str:                      // x0 = bool → строка
    cbz x0, 1f
    adrp x0, Lrt_true@PAGE
    add x0, x0, Lrt_true@PAGEOFF
    ret
1:
    adrp x0, Lrt_false@PAGE
    add x0, x0, Lrt_false@PAGEOFF
    ret

_bit_string_str:
    ret

_bit_to_str:                        // x0 = значение, x1 = вид (0 num, 1 dec, 2 string, 3 bool)
    cmp x1, #0
    b.eq _bit_num_str
    cmp x1, #1
    b.eq _bit_dec_str
    cmp x1, #3
    b.eq _bit_bool_str
    ret

_bit_cat:                           // x0 = a, x1 = b → новая строка a+b
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    bl _strlen
    mov x21, x0
    mov x0, x20
    bl _strlen
    mov x22, x0
    add x0, x21, x22
    add x0, x0, #1
    bl _bit_alloc
    mov x23, x0
    mov x1, x19
    mov x2, x21
    bl _memcpy
    add x0, x23, x21
    mov x1, x20
    add x2, x22, #1
    bl _memcpy
    mov x0, x23
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_str_eq:                        // x0, x1 = строки → 1 если равны
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _strcmp
    cmp w0, #0
    cset x0, eq
    ldp x29, x30, [sp], #16
    ret

_bit_str_starts:                    // x0=строка, x1=начало → 1/0
1:  ldrb w2, [x1]
    cbz w2, 2f
    ldrb w3, [x0]
    cmp w2, w3
    b.ne 3f
    add x0, x0, #1
    add x1, x1, #1
    b 1b
2:  mov x0, #1
    ret
3:  mov x0, #0
    ret

_bit_str_ends:                      // x0=строка, x1=конец → 1/0
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x0, x1
    bl _strlen
    mov x21, x0
    mov x0, x19
    bl _strlen
    cmp x21, x0
    b.gt 3f
    add x4, x19, x0
    sub x4, x4, x21
    mov x5, x20
    mov x3, x21
1:  cbz x3, 2f
    ldrb w6, [x4]
    ldrb w7, [x5]
    cmp w6, w7
    b.ne 3f
    add x4, x4, #1
    add x5, x5, #1
    sub x3, x3, #1
    b 1b
2:  mov x0, #1
    b 4f
3:  mov x0, #0
4:  ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_str_trim:                      // x0=строка → новая строка без краёв-пробелов
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
1:  ldrb w1, [x19]
    cmp w1, #0x20
    b.eq 2f
    cmp w1, #0x09
    b.eq 2f
    cmp w1, #0x0A
    b.eq 2f
    cmp w1, #0x0D
    b.eq 2f
    b 3f
2:  add x19, x19, #1
    b 1b
3:  mov x0, x19
    bl _strlen
    mov x20, x0
4:  cbz x20, 6f
    sub x1, x20, #1
    ldrb w1, [x19, x1]
    cmp w1, #0x20
    b.eq 5f
    cmp w1, #0x09
    b.eq 5f
    cmp w1, #0x0A
    b.eq 5f
    cmp w1, #0x0D
    b.eq 5f
    b 6f
5:  sub x20, x20, #1
    b 4b
6:  add x0, x20, #1
    bl _bit_alloc
    mov x21, x0
    mov x0, x21
    mov x1, x19
    mov x2, x20
    bl _memcpy
    strb wzr, [x21, x20]
    mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_substr:                        // x0=указатель, x1=длина → новая строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    add x0, x20, #1
    bl _bit_alloc
    mov x21, x0
    mov x0, x21
    mov x1, x19
    mov x2, x20
    bl _memcpy
    strb wzr, [x21, x20]
    mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_str_split:                     // x0=строка, x1=разделитель → mas строк
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x0, x1
    bl _strlen
    mov x21, x0
    mov x0, #-1
    mov x1, #0
    bl _bit_mas_new
    mov x22, x0
    cbnz x21, 10f
    mov x0, x19
    bl _strlen
    mov x1, x0
    mov x0, x19
    bl _bit_substr
    mov x1, x0
    mov x0, x22
    mov x2, #0
    bl _bit_mas_add
    b 9f
10: mov x23, x19
11: ldrb w0, [x23]
    cbz w0, 15f
    mov x2, #0
12: cmp x2, x21
    b.ge 16f
    ldrb w0, [x23, x2]
    ldrb w1, [x20, x2]
    cmp w0, w1
    b.ne 17f
    add x2, x2, #1
    b 12b
17: add x23, x23, #1
    b 11b
16: mov x0, x19
    sub x1, x23, x19
    bl _bit_substr
    mov x1, x0
    mov x0, x22
    mov x2, #0
    bl _bit_mas_add
    add x19, x23, x21
    b 10b
15: mov x0, x19
    sub x1, x23, x19
    bl _bit_substr
    mov x1, x0
    mov x0, x22
    mov x2, #0
    bl _bit_mas_add
9:  mov x0, x22
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_str_replace:                   // x0=строка, x1=что, x2=на что → новая строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x0, x20
    bl _strlen
    mov x22, x0
    cbnz x22, 1f
    mov x0, x19
    bl _strlen
    mov x1, x0
    mov x0, x19
    bl _bit_substr
    b 9f
1:  mov x0, x21
    bl _strlen
    mov x23, x0
    mov x0, x19
    bl _strlen
    mov x24, x0
    mov x9, x19
    mov x10, #0
2:  ldrb w0, [x9]
    cbz w0, 5f
    mov x11, #0
3:  cmp x11, x22
    b.ge 4f
    ldrb w0, [x9, x11]
    ldrb w1, [x20, x11]
    cmp w0, w1
    b.ne 6f
    add x11, x11, #1
    b 3b
4:  add x10, x10, #1
    add x9, x9, x22
    b 2b
6:  add x9, x9, #1
    b 2b
5:  sub x0, x23, x22
    mul x0, x0, x10
    add x0, x0, x24
    add x0, x0, #1
    bl _bit_alloc
    mov x12, x0
    mov x13, x0
    mov x9, x19
7:  ldrb w0, [x9]
    cbz w0, 11f
    mov x11, #0
8:  cmp x11, x22
    b.ge 10f
    ldrb w0, [x9, x11]
    ldrb w1, [x20, x11]
    cmp w0, w1
    b.ne 12f
    add x11, x11, #1
    b 8b
10: mov x11, #0
13: cmp x11, x23
    b.ge 14f
    ldrb w0, [x21, x11]
    strb w0, [x13]
    add x13, x13, #1
    add x11, x11, #1
    b 13b
14: add x9, x9, x22
    b 7b
12: ldrb w0, [x9]
    strb w0, [x13]
    add x13, x13, #1
    add x9, x9, #1
    b 7b
11: strb wzr, [x13]
    mov x0, x12
9:  ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_str_sz:                        // x0 = строка → сколько символов (UTF-8)
    mov x1, #0
1:  ldrb w2, [x0], #1
    cbz w2, 2f
    and w3, w2, #0xC0
    cmp w3, #0x80
    cinc x1, x1, ne
    b 1b
2:  mov x0, x1
    ret

// массив: [0] данные, [8] длина, [16] ёмкость, [24] лимит (-1 = нет)
_bit_mas_new:                       // x0 = лимит, x1 = сколько элементов
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x0, #32
    bl _bit_alloc
    mov x21, x0
    mov x22, #4
    cmp x20, x22
    csel x22, x20, x22, gt
    lsl x0, x22, #3
    bl _bit_alloc
    str x0, [x21]
    str x20, [x21, #8]
    str x22, [x21, #16]
    str x19, [x21, #24]
    mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_mas_add:                       // x0 = массив, x1 = значение, x2 = строка программы
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    ldr x3, [x19, #24]
    ldr x4, [x19, #8]
    tbnz x3, #63, 1f
    cmp x4, x3
    b.lt 1f
    adrp x0, Lrt_full@PAGE
    add x0, x0, Lrt_full@PAGEOFF
    mov x1, x21
    bl _bit_die
1:  ldr x5, [x19, #16]
    cmp x4, x5
    b.lt 2f
    lsl x5, x5, #1
    str x5, [x19, #16]
    ldr x0, [x19]
    lsl x1, x5, #3
    bl _realloc
    cbz x0, _bit_oom
    str x0, [x19]
2:  ldr x0, [x19]
    ldr x4, [x19, #8]
    str x20, [x0, x4, lsl #3]
    add x4, x4, #1
    str x4, [x19, #8]
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_mas_insert:                    // x0=массив, x1=i, x2=значение, x3=строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x3
    ldr x3, [x19, #24]
    ldr x4, [x19, #8]
    tbnz x3, #63, 1f
    cmp x4, x3
    b.lt 1f
    adrp x0, Lrt_full@PAGE
    add x0, x0, Lrt_full@PAGEOFF
    mov x1, x22
    bl _bit_die
1:  ldr x5, [x19, #16]
    cmp x4, x5
    b.lt 2f
    lsl x5, x5, #1
    str x5, [x19, #16]
    ldr x0, [x19]
    lsl x1, x5, #3
    bl _realloc
    cbz x0, _bit_oom
    str x0, [x19]
2:  ldr x3, [x19]
    ldr x4, [x19, #8]
3:  cmp x4, x20
    b.le 4f
    sub x5, x4, #1
    ldr x6, [x3, x5, lsl #3]
    str x6, [x3, x4, lsl #3]
    mov x4, x5
    b 3b
4:  str x21, [x3, x20, lsl #3]
    ldr x4, [x19, #8]
    add x4, x4, #1
    str x4, [x19, #8]
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_mas_remove:                    // x0=массив, x1=i
    ldr x2, [x0]
    mov x3, x1
    ldr x4, [x0, #8]
    sub x4, x4, #1
1:  cmp x3, x4
    b.ge 2f
    add x5, x3, #1
    ldr x6, [x2, x5, lsl #3]
    str x6, [x2, x3, lsl #3]
    mov x3, x5
    b 1b
2:  ldr x3, [x0, #8]
    sub x3, x3, #1
    str x3, [x0, #8]
    ret

_bit_ipow:                          // x0=основание, x1=степень → x0 (целая степень; отриц. → 0)
    mov x2, x0
    mov x0, #1
    tbnz x1, #63, 2f
    mov x3, x1
1:  cbz x3, 3f
    mul x0, x0, x2
    sub x3, x3, #1
    b 1b
2:  mov x0, #0
3:  ret

_bit_mas_str:                       // x0 = массив, x1 = вид элементов → "(1, 2, 3)"
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, #0
    adrp x22, Lrt_lpar@PAGE
    add x22, x22, Lrt_lpar@PAGEOFF
1:  ldr x2, [x19, #8]
    cmp x21, x2
    b.ge 3f
    cbz x21, 2f
    mov x0, x22
    adrp x1, Lrt_comma@PAGE
    add x1, x1, Lrt_comma@PAGEOFF
    bl _bit_cat
    mov x22, x0
2:  ldr x0, [x19]
    ldr x0, [x0, x21, lsl #3]
    mov x1, x20
    bl _bit_to_str
    mov x1, x0
    mov x0, x22
    bl _bit_cat
    mov x22, x0
    add x21, x21, #1
    b 1b
3:  mov x0, x22
    adrp x1, Lrt_rpar@PAGE
    add x1, x1, Lrt_rpar@PAGEOFF
    bl _bit_cat
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_readline:                      // x0 = строка программы → введённый текст
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    sub sp, sp, #16
    mov x19, x0
    mov x0, #0
    bl _fflush
    str xzr, [sp]
    str xzr, [sp, #8]
    mov x0, sp
    add x1, sp, #8
    adrp x2, ___stdinp@GOTPAGE
    ldr x2, [x2, ___stdinp@GOTPAGEOFF]
    ldr x2, [x2]
    bl _getline
    cmp x0, #0
    b.lt 9f
    ldr x20, [sp]
    add x1, x20, x0
1:  cmp x1, x20
    b.eq 2f
    ldrb w2, [x1, #-1]
    cmp w2, #10
    b.eq 3f
    cmp w2, #13
    b.ne 2f
3:  sub x1, x1, #1
    strb wzr, [x1]
    b 1b
2:  mov x0, x20
    add sp, sp, #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:
    adrp x0, Lrt_eof@PAGE
    add x0, x0, Lrt_eof@PAGEOFF
    mov x1, x19
    bl _bit_die

_bit_input_num:                     // x0 = есть границы, x1 = от, x2 = до, x3 = строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    sub sp, sp, #16
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x3
1:  mov x0, x22
    bl _bit_readline
    mov x23, x0
    bl ___error
    str wzr, [x0]
    mov x0, x23
    mov x1, sp
    mov x2, #10
    bl _strtoll
    mov x24, x0
    ldr x1, [sp]
    cmp x1, x23
    b.eq 5f
2:  ldrb w2, [x1]
    cmp w2, #32
    b.ne 3f
    add x1, x1, #1
    b 2b
3:  cbnz w2, 5f
    bl ___error
    ldr w0, [x0]
    cbnz w0, 5f
    cbz x19, 4f
    cmp x24, x20
    b.lt 5f
    cmp x24, x21
    b.gt 5f
4:  mov x0, x24
    add sp, sp, #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
5:  cbz x19, 6f
    sub sp, sp, #16
    str x20, [sp]
    str x21, [sp, #8]
    adrp x0, Lrt_numr@PAGE
    add x0, x0, Lrt_numr@PAGEOFF
    bl _printf
    add sp, sp, #16
    b 1b
6:
    adrp x0, Lrt_num@PAGE
    add x0, x0, Lrt_num@PAGEOFF
    bl _printf
    b 1b

_bit_input_dec:                     // x0 = есть границы, x1 = от, x2 = до (биты dec), x3 = строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    sub sp, sp, #16
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x3
1:  mov x0, x22
    bl _bit_readline
    mov x23, x0
    bl ___error
    str wzr, [x0]
    mov x0, x23
    mov x1, sp
    bl _strtod
    fmov x24, d0
    ldr x1, [sp]
    cmp x1, x23
    b.eq 5f
2:  ldrb w2, [x1]
    cmp w2, #32
    b.ne 3f
    add x1, x1, #1
    b 2b
3:  cbnz w2, 5f
    bl ___error
    ldr w0, [x0]
    cbnz w0, 5f
    fmov d0, x24
    fcmp d0, d0
    b.vs 5f
    cbz x19, 4f
    fmov d0, x24
    fmov d1, x20
    fcmp d0, d1
    b.mi 5f
    fmov d1, x21
    fcmp d0, d1
    b.gt 5f
4:  mov x0, x24
    add sp, sp, #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
5:  cbz x19, 6f
    sub sp, sp, #16
    str x20, [sp]
    str x21, [sp, #8]
    adrp x0, Lrt_decr@PAGE
    add x0, x0, Lrt_decr@PAGEOFF
    bl _printf
    add sp, sp, #16
    b 1b
6:
    adrp x0, Lrt_dec@PAGE
    add x0, x0, Lrt_dec@PAGEOFF
    bl _printf
    b 1b

_bit_input_str:                     // x0 = строка программы
    b _bit_readline

_bit_input_bool:                    // x0 = строка программы
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
1:  mov x0, x19
    bl _bit_readline
    mov x20, x0
    adrp x1, Lrt_true@PAGE
    add x1, x1, Lrt_true@PAGEOFF
    bl _strcmp
    cbz w0, 2f
    mov x0, x20
    adrp x1, Lrt_da@PAGE
    add x1, x1, Lrt_da@PAGEOFF
    bl _strcmp
    cbz w0, 2f
    mov x0, x20
    adrp x1, Lrt_1@PAGE
    add x1, x1, Lrt_1@PAGEOFF
    bl _strcmp
    cbz w0, 2f
    mov x0, x20
    adrp x1, Lrt_false@PAGE
    add x1, x1, Lrt_false@PAGEOFF
    bl _strcmp
    cbz w0, 3f
    mov x0, x20
    adrp x1, Lrt_net@PAGE
    add x1, x1, Lrt_net@PAGEOFF
    bl _strcmp
    cbz w0, 3f
    mov x0, x20
    adrp x1, Lrt_0@PAGE
    add x1, x1, Lrt_0@PAGEOFF
    bl _strcmp
    cbz w0, 3f
    adrp x0, Lrt_boolm@PAGE
    add x0, x0, Lrt_boolm@PAGEOFF
    bl _printf
    b 1b
2:  mov x0, #1
    b 4f
3:  mov x0, #0
4:  ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_errpath:                       // x0 = текст, x1 = путь, x2 = строка программы
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    str x2, [sp, #-16]!
    bl _bit_cat
    ldr x1, [sp], #16
    bl _bit_die

_bit_file_read:                     // x0 = путь, x1 = строка -> весь текст (до конца, размер не нужен)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    adrp x1, Lrt_rb@PAGE
    add x1, x1, Lrt_rb@PAGEOFF
    bl _fopen
    cbz x0, 9f
    mov x21, x0
    mov x23, #4096
    mov x0, x23
    bl _bit_alloc
    mov x22, x0
    mov x24, #0
1:  sub x0, x23, x24
    cbnz x0, 2f
    lsl x23, x23, #1
    mov x0, x22
    mov x1, x23
    bl _realloc
    cbz x0, _bit_oom
    mov x22, x0
2:  add x0, x22, x24
    mov x1, #1
    sub x2, x23, x24
    mov x3, x21
    bl _fread
    add x24, x24, x0
    cbnz x0, 1b
    mov x0, x21
    bl _ferror
    cbnz w0, 8f
    cmp x24, x23
    b.ne 3f
    mov x0, x22
    add x1, x23, #1
    bl _realloc
    cbz x0, _bit_oom
    mov x22, x0
3:  strb wzr, [x22, x24]
    mov x0, x21
    bl _fclose
    mov x0, x22
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
8:  adrp x0, Lrt_eread@PAGE
    add x0, x0, Lrt_eread@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath
9:  adrp x0, Lrt_eopen@PAGE
    add x0, x0, Lrt_eopen@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_file_size:                     // x0 = путь, x1 = строка → байты
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    adrp x1, Lrt_rb@PAGE
    add x1, x1, Lrt_rb@PAGEOFF
    bl _fopen
    cbz x0, 9f
    mov x21, x0
    mov x1, #0
    mov x2, #2
    bl _fseek
    cbnz w0, 8f
    mov x0, x21
    bl _ftell
    tbnz x0, #63, 8f
    mov x22, x0
    mov x0, x21
    bl _fclose
    mov x0, x22
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
8:
    adrp x0, Lrt_eread@PAGE
    add x0, x0, Lrt_eread@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath
9:
    adrp x0, Lrt_eopen@PAGE
    add x0, x0, Lrt_eopen@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_file_write:                    // x0 = путь, x1 = текст, x2 = строка, x3 = режим ("w"/"a")
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x1, x3
    bl _fopen
    cbz x0, 9f
    mov x22, x0
    mov x0, x20
    mov x1, x22
    bl _fputs
    cmn w0, #1
    b.eq 9f
    mov x0, x22
    bl _fclose
    cbnz w0, 9f
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:
    adrp x0, Lrt_ewrite@PAGE
    add x0, x0, Lrt_ewrite@PAGEOFF
    mov x1, x19
    mov x2, x21
    bl _bit_errpath

_bit_file_lines:                    // x0 = путь, x1 = строка → mas из строк
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x20, x1
    bl _bit_file_read
    mov x19, x0
    mov x0, #-1
    mov x1, #0
    bl _bit_mas_new
    mov x21, x0
    mov x22, x19
1:  ldrb w2, [x19]
    cbz w2, 3f
    cmp w2, #10
    b.ne 2f
    strb wzr, [x19]
    mov x0, x21
    mov x1, x22
    mov x2, x20
    bl _bit_mas_add
    add x19, x19, #1
    mov x22, x19
    b 1b
2:  add x19, x19, #1
    b 1b
3:  cmp x19, x22
    b.eq 4f
    mov x0, x21
    mov x1, x22
    mov x2, x20
    bl _bit_mas_add
4:  mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_kind:                          // x0 = путь → 0 нет, 1 файл, 2 папка, 3 другое
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #160
    mov x1, sp
    bl _stat
    cbnz w0, 1f
    ldrh w1, [sp, #4]
    and w1, w1, #0xF000
    mov x0, #3
    cmp w1, #0x8000
    b.ne 2f
    mov x0, #1
    b 3f
2:  cmp w1, #0x4000
    b.ne 3f
    mov x0, #2
    b 3f
1:  mov x0, #0
3:  add sp, sp, #160
    ldp x29, x30, [sp], #16
    ret

_bit_dir_exists:                    // x0 = путь → 1 если это папка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _bit_kind
    cmp x0, #2
    cset x0, eq
    ldp x29, x30, [sp], #16
    ret

_bit_file_exists:                   // x0 = путь → 1 если это файл
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _bit_kind
    cmp x0, #1
    cset x0, eq
    ldp x29, x30, [sp], #16
    ret

_bit_file_remove:                   // x0 = путь, x1 = строка: удаляет только файл
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    bl _bit_kind
    cmp x0, #1
    b.ne 8f
    mov x0, x19
    bl _unlink
    cbnz w0, 9f
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
8:
    adrp x0, Lrt_enotfile@PAGE
    add x0, x0, Lrt_enotfile@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath
9:
    adrp x0, Lrt_erm@PAGE
    add x0, x0, Lrt_erm@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_dir_remove:                    // x0 = путь, x1 = строка: удаляет только пустую папку
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    bl _bit_kind
    cmp x0, #2
    b.ne 8f
    mov x0, x19
    bl _rmdir
    cbnz w0, 9f
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
8:
    adrp x0, Lrt_enotdir@PAGE
    add x0, x0, Lrt_enotdir@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath
9:
    adrp x0, Lrt_erm@PAGE
    add x0, x0, Lrt_erm@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_move:                          // x0 = откуда, x1 = куда, x2 = строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x20, x2
    bl _rename
    cbnz w0, 9f
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:
    adrp x0, Lrt_emv@PAGE
    add x0, x0, Lrt_emv@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_copy:                          // x0 = откуда, x1 = куда, x2 = строка; копирует байты как есть
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    adrp x1, Lrt_rb@PAGE
    add x1, x1, Lrt_rb@PAGEOFF
    bl _fopen
    cbz x0, 9f
    mov x22, x0
    mov x0, x20
    adrp x1, Lrt_wb@PAGE
    add x1, x1, Lrt_wb@PAGEOFF
    bl _fopen
    cbz x0, 7f
    mov x23, x0
    mov x0, #65536
    bl _bit_alloc
    mov x24, x0
1:  mov x0, x24
    mov x1, #1
    mov x2, #65536
    mov x3, x22
    bl _fread
    cbz x0, 2f
    mov x2, x0
    str x2, [sp, #-16]!
    mov x0, x24
    mov x1, #1
    mov x3, x23
    bl _fwrite
    ldr x2, [sp], #16
    cmp x0, x2
    b.ne 7f
    b 1b
2:  mov x0, x22
    bl _ferror
    cbnz w0, 8f
    mov x0, x22
    bl _fclose
    mov x0, x23
    bl _fclose
    cbnz w0, 7f
    mov x0, x24
    bl _free
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
7:
    adrp x0, Lrt_ewrite@PAGE
    add x0, x0, Lrt_ewrite@PAGEOFF
    mov x1, x20
    mov x2, x21
    bl _bit_errpath
8:
    adrp x0, Lrt_eread@PAGE
    add x0, x0, Lrt_eread@PAGEOFF
    mov x1, x19
    mov x2, x21
    bl _bit_errpath
9:
    adrp x0, Lrt_eopen@PAGE
    add x0, x0, Lrt_eopen@PAGEOFF
    mov x1, x19
    mov x2, x21
    bl _bit_errpath

_bit_dir_make:                      // x0 = путь, x1 = строка; создаёт и все папки на пути
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x20, x1
    adrp x1, Lrt_empty@PAGE
    add x1, x1, Lrt_empty@PAGEOFF
    bl _bit_cat
    mov x19, x0
    mov x21, x0
    ldrb w2, [x21]
    cbz w2, 3f
    add x21, x21, #1
1:  ldrb w2, [x21]
    cbz w2, 3f
    cmp w2, #47
    b.ne 2f
    strb wzr, [x21]
    mov x0, x19
    mov x1, #493
    bl _mkdir
    mov w2, #47
    strb w2, [x21]
2:  add x21, x21, #1
    b 1b
3:  mov x0, x19
    mov x1, #493
    bl _mkdir
    cbz w0, 4f
    mov x0, x19
    bl _bit_dir_exists
    cbz x0, 9f
4:
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:
    adrp x0, Lrt_emk@PAGE
    add x0, x0, Lrt_emk@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_strptr_cmp:
    ldr x0, [x0]
    ldr x1, [x1]
    b _strcmp

_bit_dir_list:                      // x0 = путь, x1 = строка → mas имён по алфавиту
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    bl _opendir
    cbz x0, 9f
    mov x21, x0
    mov x0, #-1
    mov x1, #0
    bl _bit_mas_new
    mov x22, x0
1:  mov x0, x21
    bl _readdir
    cbz x0, 3f
    add x1, x0, #21
    ldrb w2, [x1]
    cmp w2, #46
    b.ne 2f
    ldrb w2, [x1, #1]
    cbz w2, 1b
    cmp w2, #46
    b.ne 2f
    ldrb w2, [x1, #2]
    cbz w2, 1b
2:  mov x0, x1
    adrp x1, Lrt_empty@PAGE
    add x1, x1, Lrt_empty@PAGEOFF
    bl _bit_cat
    mov x1, x0
    mov x0, x22
    mov x2, x20
    bl _bit_mas_add
    b 1b
3:  mov x0, x21
    bl _closedir
    ldr x0, [x22]
    ldr x1, [x22, #8]
    mov x2, #8
    adr x3, _bit_strptr_cmp
    bl _qsort
    mov x0, x22
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:
    adrp x0, Lrt_edir@PAGE
    add x0, x0, Lrt_edir@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_basename:                      // x0 = путь → имя после последнего /
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x1, #47
    bl _strrchr
    cbz x0, 1f
    add x0, x0, #1
    b 2f
1:  mov x0, x19
2:  ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_wstatus:                       // w0 = статус wait → код выхода (сигнал → 128+номер), запоминает его
    cmn w0, #1
    b.eq 2f
    and w1, w0, #0x7f
    cbnz w1, 1f
    lsr w0, w0, #8
    and w0, w0, #0xff
    b 3f
1:  add w0, w1, #128
    b 3f
2:  mov w0, #127
3:  adrp x1, Lrt_status@PAGE
    str x0, [x1, Lrt_status@PAGEOFF]
    ret

_bit_status:                        // → код выхода последней команды
    adrp x0, Lrt_status@PAGE
    ldr x0, [x0, Lrt_status@PAGEOFF]
    ret

_bit_eof:                           // → 1 если ввод закончился
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x0, #0
    bl _fflush
    adrp x0, ___stdinp@GOTPAGE
    ldr x0, [x0, ___stdinp@GOTPAGEOFF]
    ldr x19, [x0]
    mov x0, x19
    bl _getc
    cmn w0, #1
    b.eq 1f
    mov x1, x19
    bl _ungetc
    mov x0, #0
    b 2f
1:  mov x0, #1
2:  ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_run_live:                      // x0 = команда: вывод сразу в терминал
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x0, #0
    bl _fflush
    mov x0, x19
    bl _system
    bl _bit_wstatus
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_run:                           // x0 = команда, x1 = строка → её вывод
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x0, #0
    bl _fflush
    mov x0, x19
    adrp x1, Lrt_r@PAGE
    add x1, x1, Lrt_r@PAGEOFF
    bl _popen
    cbz x0, 9f
    mov x21, x0
    mov x22, #4096
    mov x0, x22
    bl _bit_alloc
    mov x23, x0
    mov x24, #0
1:  add x0, x23, x24
    mov x1, #1
    sub x2, x22, x24
    sub x2, x2, #1
    mov x3, x21
    bl _fread
    cbz x0, 3f
    add x24, x24, x0
    sub x2, x22, #1
    cmp x24, x2
    b.lt 1b
    lsl x22, x22, #1
    mov x0, x23
    mov x1, x22
    bl _realloc
    cbz x0, _bit_oom
    mov x23, x0
    b 1b
3:  cbz x24, 4f
    sub x2, x24, #1
    ldrb w3, [x23, x2]
    cmp w3, #10
    b.ne 4f
    mov x24, x2
4:  strb wzr, [x23, x24]
    mov x0, x21
    bl _pclose
    bl _bit_wstatus
    mov x0, x23
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:
    adrp x0, Lrt_erun@PAGE
    add x0, x0, Lrt_erun@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_args:                          // → mas из аргументов командной строки
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x0, #-1
    mov x1, #0
    bl _bit_mas_new
    mov x19, x0
    adrp x2, Lrt_argc@PAGE
    ldr x20, [x2, Lrt_argc@PAGEOFF]
    adrp x2, Lrt_argv@PAGE
    ldr x21, [x2, Lrt_argv@PAGEOFF]
    mov x22, #1
1:  cmp x22, x20
    b.ge 2f
    ldr x1, [x21, x22, lsl #3]
    mov x0, x19
    mov x2, #0
    bl _bit_mas_add
    add x22, x22, #1
    b 1b
2:  mov x0, x19
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_env:                           // x0 = имя → значение или ""
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _getenv
    cbnz x0, 1f
    adrp x0, Lrt_empty@PAGE
    add x0, x0, Lrt_empty@PAGEOFF
1:
    ldp x29, x30, [sp], #16
    ret

_bit_clear:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x0, Lrt_cls@PAGE
    add x0, x0, Lrt_cls@PAGEOFF
    bl _printf
    mov x0, #0
    bl _fflush
    ldp x29, x30, [sp], #16
    ret

_bit_wait:                          // x0 = миллисекунды
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x0, #0
    bl _fflush
1:  cmp x19, #0
    b.le 3f
    mov x20, #1000
    cmp x19, x20
    csel x20, x19, x20, lt
    sub x19, x19, x20
    mov x1, #1000
    mul x0, x20, x1
    bl _usleep
    b 1b
3:  ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_exit:                          // x0 = код выхода
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x0, #0
    bl _fflush
    mov x0, x19
    bl _exit

_bit_mem_used:                      // → сколько байт памяти программа заняла (пик)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #160
    mov x0, #0
    mov x1, sp
    bl _getrusage
    ldr x0, [sp, #32]
    add sp, sp, #160
    ldp x29, x30, [sp], #16
    ret

_bit_str_bytes:                     // x0 = строка → mas из байтов
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    bl _strlen
    mov x20, x0
    mov x1, x0
    mov x0, #-1
    bl _bit_mas_new
    mov x21, x0
    ldr x2, [x21]
    mov x3, #0
1:  cmp x3, x20
    b.ge 2f
    ldrb w4, [x19, x3]
    str x4, [x2, x3, lsl #3]
    add x3, x3, #1
    b 1b
2:  mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_mas_text:                      // x0 = mas байтов, x1 = от, x2 = до → строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    cmp x1, #0
    csel x1, x1, xzr, gt
    ldr x3, [x19, #8]
    cmp x2, x3
    csel x2, x2, x3, lt
    cmp x2, x1
    csel x2, x2, x1, gt
    mov x20, x1
    sub x21, x2, x1
    add x0, x21, #1
    bl _bit_alloc
    mov x22, x0
    ldr x2, [x19]
    mov x3, #0
1:  cmp x3, x21
    b.ge 2f
    add x4, x20, x3
    ldr x5, [x2, x4, lsl #3]
    strb w5, [x22, x3]
    add x3, x3, #1
    b 1b
2:  strb wzr, [x22, x21]
    mov x0, x22
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_mas_join:                      // x0 = mas строк, x1 = разделитель → одна строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x0, x20
    bl _strlen
    mov x21, x0
    mov x22, #0
    mov x23, #0
1:  ldr x2, [x19, #8]
    cmp x23, x2
    b.ge 2f
    ldr x2, [x19]
    ldr x0, [x2, x23, lsl #3]
    bl _strlen
    add x22, x22, x0
    add x22, x22, x21
    add x23, x23, #1
    b 1b
2:  add x0, x22, #1
    bl _bit_alloc
    mov x24, x0
    mov x22, x24
    mov x23, #0
3:  ldr x2, [x19, #8]
    cmp x23, x2
    b.ge 5f
    cbz x23, 4f
    mov x0, x22
    mov x1, x20
    mov x2, x21
    bl _memcpy
    add x22, x22, x21
4:  ldr x2, [x19]
    ldr x0, [x2, x23, lsl #3]
    bl _strlen
    str x0, [sp, #-16]!
    mov x2, x0
    ldr x3, [x19]
    ldr x1, [x3, x23, lsl #3]
    mov x0, x22
    bl _memcpy
    ldr x2, [sp], #16
    add x22, x22, x2
    add x23, x23, #1
    b 3b
5:  strb wzr, [x22]
    mov x0, x24
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_mem_total:                     // → сколько байт памяти в компьютере
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #16
    str xzr, [sp]
    mov x0, #8
    str x0, [sp, #8]
    adrp x0, Lrt_memsize@PAGE
    add x0, x0, Lrt_memsize@PAGEOFF
    mov x1, sp
    add x2, sp, #8
    mov x3, #0
    mov x4, #0
    bl _sysctlbyname
    ldr x0, [sp]
    add sp, sp, #16
    ldp x29, x30, [sp], #16
    ret

_bit_mas_slice:                     // x0 = массив, x1 = от, x2 = до (включительно) → новый массив
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    cmp x1, #0
    csel x1, x1, xzr, gt
    ldr x3, [x19, #8]
    sub x3, x3, #1
    cmp x2, x3
    csel x2, x2, x3, lt
    sub x21, x2, x1
    add x21, x21, #1
    cmp x21, #0
    csel x21, x21, xzr, gt
    mov x20, x1
    mov x0, #-1
    mov x1, x21
    bl _bit_mas_new
    mov x22, x0
    ldr x2, [x19]
    ldr x3, [x22]
    mov x4, #0
1:  cmp x4, x21
    b.ge 2f
    add x5, x20, x4
    ldr x6, [x2, x5, lsl #3]
    str x6, [x3, x4, lsl #3]
    add x4, x4, #1
    b 1b
2:  mov x0, x22
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_str_slice:                     // x0 = строка, x1 = от, x2 = до (символы, включительно) → строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    cmp x1, #0
    csel x1, x1, xzr, gt
    cmp x2, x1
    b.lt 8f
    sub x20, x2, x1
    mov x3, #0
1:  cmp x3, x1
    b.ge 2f
    ldrb w4, [x19]
    cbz w4, 2f
    add x19, x19, #1
3:  ldrb w4, [x19]
    and w5, w4, #0xC0
    cmp w5, #0x80
    b.ne 4f
    add x19, x19, #1
    b 3b
4:  add x3, x3, #1
    b 1b
2:  mov x21, x19
5:  tbnz x20, #63, 6f
    ldrb w4, [x19]
    cbz w4, 6f
    add x19, x19, #1
7:  ldrb w4, [x19]
    and w5, w4, #0xC0
    cmp w5, #0x80
    b.ne 9f
    add x19, x19, #1
    b 7b
9:  sub x20, x20, #1
    b 5b
6:  sub x22, x19, x21
    add x0, x22, #1
    bl _bit_alloc
    mov x20, x0
    mov x1, x21
    mov x2, x22
    bl _memcpy
    strb wzr, [x20, x22]
    mov x0, x20
    b 10f
8:
    adrp x0, Lrt_empty@PAGE
    add x0, x0, Lrt_empty@PAGEOFF
10:
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_file_line:                     // x0 = путь, x1 = номер строки, x2 = строка программы → строка или ""
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x1
    mov x1, x2
    bl _bit_file_lines
    tbnz x19, #63, 1f
    ldr x2, [x0, #8]
    cmp x19, x2
    b.ge 1f
    ldr x2, [x0]
    ldr x0, [x2, x19, lsl #3]
    b 2f
1:
    adrp x0, Lrt_empty@PAGE
    add x0, x0, Lrt_empty@PAGEOFF
2:  ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_file_slice:                    // x0 = путь, x1 = от, x2 = до, x3 = строка программы → mas строк
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x1
    mov x20, x2
    mov x1, x3
    bl _bit_file_lines
    mov x1, x19
    mov x2, x20
    bl _bit_mas_slice
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_mas_sum:                       // x0 = массив, x1 = вид (0 num, 1 dec), x2 = строка программы
    ldr x3, [x0]
    ldr x4, [x0, #8]
    mov x5, #0
    cmp x1, #1
    b.eq 5f
    mov x6, #0
1:  cmp x5, x4
    b.ge 2f
    ldr x7, [x3, x5, lsl #3]
    adds x6, x6, x7
    b.vs 9f
    add x5, x5, #1
    b 1b
2:  mov x0, x6
    ret
5:  fmov d0, xzr
6:  cmp x5, x4
    b.ge 7f
    ldr d1, [x3, x5, lsl #3]
    fadd d0, d0, d1
    add x5, x5, #1
    b 6b
7:  fmov x0, d0
    ret
9:
    adrp x0, Lrt_ovf@PAGE
    add x0, x0, Lrt_ovf@PAGEOFF
    mov x1, x2
    bl _bit_die

_bit_cmp_num:
    ldr x0, [x0]
    ldr x1, [x1]
    cmp x0, x1
    cset w2, gt
    csetm w3, lt
    orr w0, w2, w3
    ret

_bit_cmp_dec:
    ldr d0, [x0]
    ldr d1, [x1]
    fcmp d0, d1
    cset w2, gt
    csetm w3, mi
    orr w0, w2, w3
    ret

_bit_mas_sort:                      // x0 = массив, x1 = вид элементов: сортирует на месте
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x9, x1
    ldr x1, [x0, #8]
    ldr x0, [x0]
    mov x2, #8
    cmp x9, #2
    b.eq 1f
    cmp x9, #1
    b.eq 2f
    adr x3, _bit_cmp_num
    b 3f
1:  adr x3, _bit_strptr_cmp
    b 3f
2:  adr x3, _bit_cmp_dec
3:  bl _qsort
    ldp x29, x30, [sp], #16
    ret

// bytes: [0] данные, [8] длина, [16] ёмкость, [24] лимит; один байт на элемент
_bit_bytes_new:                     // x0 = сколько байт (нулями) → bytes
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    cmp x0, #0
    csel x19, x0, xzr, gt
    mov x0, #32
    bl _bit_alloc
    mov x20, x0
    mov x21, #16
    cmp x19, x21
    csel x21, x19, x21, gt
    mov x0, x21
    mov x1, #1
    bl _calloc
    cbz x0, _bit_oom
    str x0, [x20]
    str x19, [x20, #8]
    str x21, [x20, #16]
    mov x0, #-1
    str x0, [x20, #24]
    mov x0, x20
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_bytes_add:                     // x0 = bytes, x1 = значение (младший байт)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    ldr x4, [x19, #8]
    ldr x5, [x19, #16]
    cmp x4, x5
    b.lt 1f
    lsl x5, x5, #1
    str x5, [x19, #16]
    ldr x0, [x19]
    mov x1, x5
    bl _realloc
    cbz x0, _bit_oom
    str x0, [x19]
1:  ldr x0, [x19]
    ldr x4, [x19, #8]
    strb w20, [x0, x4]
    add x4, x4, #1
    str x4, [x19, #8]
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_bytes_slice:                   // x0 = bytes, x1 = от, x2 = до (включительно) → новые bytes
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    cmp x1, #0
    csel x1, x1, xzr, gt
    ldr x3, [x19, #8]
    sub x3, x3, #1
    cmp x2, x3
    csel x2, x2, x3, lt
    sub x21, x2, x1
    add x21, x21, #1
    cmp x21, #0
    csel x21, x21, xzr, gt
    mov x20, x1
    mov x0, x21
    bl _bit_bytes_new
    mov x22, x0
    ldr x0, [x22]
    ldr x1, [x19]
    add x1, x1, x20
    mov x2, x21
    bl _memcpy
    mov x0, x22
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_bytes_text:                    // x0 = bytes → строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    ldr x20, [x19, #8]
    add x0, x20, #1
    bl _bit_alloc
    mov x21, x0
    ldr x1, [x19]
    mov x2, x20
    bl _memcpy
    strb wzr, [x21, x20]
    mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_bytes_str:                     // x0 = bytes → "<01 a0 ff>"
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    ldr x20, [x19, #8]
    mov x0, #3
    mul x0, x0, x20
    add x0, x0, #3
    bl _bit_alloc
    mov x21, x0
    mov x2, #60
    strb w2, [x21]
    mov x22, #1
    mov x3, #0
    adrp x6, Lrt_hex@PAGE
    add x6, x6, Lrt_hex@PAGEOFF
1:  cmp x3, x20
    b.ge 2f
    cbz x3, 3f
    mov w2, #32
    strb w2, [x21, x22]
    add x22, x22, #1
3:  ldr x4, [x19]
    ldrb w5, [x4, x3]
    lsr w7, w5, #4
    ldrb w7, [x6, x7]
    strb w7, [x21, x22]
    add x22, x22, #1
    and w7, w5, #15
    ldrb w7, [x6, x7]
    strb w7, [x21, x22]
    add x22, x22, #1
    add x3, x3, #1
    b 1b
2:  mov w2, #62
    strb w2, [x21, x22]
    add x22, x22, #1
    strb wzr, [x21, x22]
    mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_file_load:                     // x0 = путь, x1 = строка → bytes (всё содержимое как есть)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    adrp x1, Lrt_rb@PAGE
    add x1, x1, Lrt_rb@PAGEOFF
    bl _fopen
    cbz x0, 9f
    mov x21, x0
    mov x1, #0
    mov x2, #2
    bl _fseek
    cbnz w0, 8f
    mov x0, x21
    bl _ftell
    tbnz x0, #63, 8f
    mov x22, x0
    mov x0, x21
    mov x1, #0
    mov x2, #0
    bl _fseek
    cbnz w0, 8f
    mov x0, x22
    bl _bit_bytes_new
    mov x23, x0
    ldr x0, [x23]
    mov x1, #1
    mov x2, x22
    mov x3, x21
    bl _fread
    cmp x0, x22
    b.ne 8f
    mov x0, x21
    bl _fclose
    mov x0, x23
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
8:
    adrp x0, Lrt_eread@PAGE
    add x0, x0, Lrt_eread@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath
9:
    adrp x0, Lrt_eopen@PAGE
    add x0, x0, Lrt_eopen@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_file_save:                     // x0 = путь, x1 = bytes, x2 = строка: записывает байты как есть
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    adrp x1, Lrt_wb@PAGE
    add x1, x1, Lrt_wb@PAGEOFF
    bl _fopen
    cbz x0, 9f
    mov x22, x0
    ldr x0, [x20]
    mov x1, #1
    ldr x2, [x20, #8]
    mov x3, x22
    bl _fwrite
    ldr x2, [x20, #8]
    cmp x0, x2
    b.ne 9f
    mov x0, x22
    bl _fclose
    cbnz w0, 9f
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:
    adrp x0, Lrt_ewrite@PAGE
    add x0, x0, Lrt_ewrite@PAGEOFF
    mov x1, x19
    mov x2, x21
    bl _bit_errpath

_bit_mem_free:                      // → сколько байт памяти свободно (свободные + неактивные страницы)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    sub sp, sp, #176
    bl _mach_host_self
    mov x1, #4
    mov x2, sp
    mov w3, #38
    str w3, [sp, #168]
    add x3, sp, #168
    bl _host_statistics64
    cbnz w0, 1f
    ldr w19, [sp]
    ldr w20, [sp, #8]
    add x19, x19, x20
    str xzr, [sp, #144]
    mov x0, #8
    str x0, [sp, #152]
    adrp x0, Lrt_vmps@PAGE
    add x0, x0, Lrt_vmps@PAGEOFF
    add x1, sp, #144
    add x2, sp, #152
    mov x3, #0
    mov x4, #0
    bl _sysctlbyname
    ldr w0, [sp, #144]
    mul x0, x19, x0
    b 2f
1:  mov x0, #0
2:  add sp, sp, #176
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_self_pid:                      // → pid текущего процесса
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _getpid
    sxtw x0, w0
    ldp x29, x30, [sp], #16
    ret

_bit_bytes_addr:                    // x0 = bytes → адрес данных
    ldr x0, [x0]
    ret

_bit_bytes_num:                     // x0 = bytes, x1 = номер, x2 = строка -> 8 байт как число
    tbnz x1, #63, 1f
    add x3, x1, #8
    ldr x4, [x0, #8]
    cmp x3, x4
    b.gt 1f
    ldr x0, [x0]
    ldr x0, [x0, x1]
    ret
1:  adrp x0, Lrt_e8@PAGE
    add x0, x0, Lrt_e8@PAGEOFF
    mov x1, x2
    bl _bit_die

_bit_bytes_put:                     // x0 = bytes, x1 = номер, x2 = число, x3 = строка
    tbnz x1, #63, 1f
    add x4, x1, #8
    ldr x5, [x0, #8]
    cmp x4, x5
    b.gt 1f
    ldr x0, [x0]
    str x2, [x0, x1]
    ret
1:  adrp x0, Lrt_e8@PAGE
    add x0, x0, Lrt_e8@PAGEOFF
    mov x1, x3
    bl _bit_die

_bit_hexval_ptr:                    // x0 = указатель -> x0 = число, x1 = конец
    mov x2, x0
    mov x0, #0
1:  ldrb w3, [x2]
    sub w4, w3, #48
    cmp w4, #9
    b.ls 3f
    orr w3, w3, #0x20
    sub w4, w3, #97
    cmp w4, #5
    b.hi 2f
    add w4, w4, #10
3:  lsl x0, x0, #4
    orr x0, x0, x4
    add x2, x2, #1
    b 1b
2:  mov x1, x2
    ret

_bit_str_hex:                       // x0 = строка -> число (hex, можно с 0x)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
1:  ldrb w1, [x0]
    cmp w1, #32
    b.ne 2f
    add x0, x0, #1
    b 1b
2:  ldrb w1, [x0]
    cmp w1, #48
    b.ne 3f
    ldrb w1, [x0, #1]
    orr w1, w1, #0x20
    cmp w1, #120
    b.ne 3f
    add x0, x0, #2
3:  bl _bit_hexval_ptr
    ldp x29, x30, [sp], #16
    ret

_bit_drop_str:                      // x0 = строка (куча) -> освободить
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _free
    ldp x29, x30, [sp], #16
    ret

_bit_bytes_free:                    // x0 = bytes (или 0) -> освободить буфер и описатель
    cbz x0, 1f
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    ldr x0, [x19]
    bl _free
    mov x0, x19
    bl _free
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
1:  ret

_bit_tcp_connect:                   // x0 = "ip:port", x1 = строка -> TCP conn
    mov w2, #1
    b _bit_ip_connect

_bit_udp_connect:                   // x0 = "ip:port", x1 = строка -> UDP conn
    mov w2, #2
    b _bit_ip_connect

_bit_ip_connect:                    // x0 = адрес, x1 = строка, x2 = тип сокета
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    sub sp, sp, #112
    str x2, [sp, #96]
    mov x19, x0
    mov x20, x1
    add x21, sp, #0
    add x22, sp, #80
1:  ldrb w2, [x19]
    cbz w2, 9f
    cmp w2, #58
    b.eq 2f
    strb w2, [x21]
    add x19, x19, #1
    add x21, x21, #1
    b 1b
2:  strb wzr, [x21]
    add x19, x19, #1
    mov w3, #0
3:  ldrb w2, [x19]
    sub w4, w2, #48
    cmp w4, #9
    b.hi 4f
    mov w5, #10
    mul w3, w3, w5
    add w3, w3, w4
    add x19, x19, #1
    b 3b
4:  str xzr, [x22]
    str xzr, [x22, #8]
    mov w2, #2
    strh w2, [x22]
    lsl w4, w3, #8
    lsr w5, w3, #8
    orr w4, w4, w5
    strh w4, [x22, #2]
    mov w0, #2
    add x1, sp, #0
    add x2, sp, #84
    bl _inet_pton
    cmp w0, #1
    b.ne 9f
    mov w0, #2
    ldr w1, [sp, #96]
    mov w2, #0
    bl _socket
    tbnz w0, #31, 9f
    mov w19, w0
    mov w0, w19
    add x1, sp, #80
    mov w2, #16
    bl _connect
    tbnz w0, #31, 8f
    mov w0, w19
    add sp, sp, #112
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
8:  mov w0, w19
    bl _close
9:  add sp, sp, #112
    adrp x0, Lrt_enet@PAGE
    add x0, x0, Lrt_enet@PAGEOFF
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    mov x1, x20
    bl _bit_die

_bit_tcp_listen:                    // x0 = порт, x1 = строка -> server (сокет)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    sub sp, sp, #32
    mov w19, w0
    mov x20, x1
    mov w0, #2
    mov w1, #1
    mov w2, #0
    bl _socket
    tbnz w0, #31, 9f
    mov w21, w0
    str xzr, [sp]
    str xzr, [sp, #8]
    mov w2, #2
    strh w2, [sp]
    lsl w4, w19, #8
    lsr w5, w19, #8
    orr w4, w4, w5
    strh w4, [sp, #2]
    mov w0, w21
    add x1, sp, #0
    mov w2, #16
    bl _bind
    tbnz w0, #31, 9f
    mov w0, w21
    mov w1, #16
    bl _listen
    tbnz w0, #31, 9f
    mov w0, w21
    add sp, sp, #32
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  add sp, sp, #32
    adrp x0, Lrt_elisten@PAGE
    add x0, x0, Lrt_elisten@PAGEOFF
    mov x1, x20
    ldp x19, x20, [sp], #16
    bl _bit_die

_bit_tcp_accept:                    // x0 = server, x1 = строка -> conn
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x20, x1
    mov w1, #0
    mov w2, #0
    bl _accept
    tbnz w0, #31, 9f
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_eaccept@PAGE
    add x0, x0, Lrt_eaccept@PAGEOFF
    mov x1, x20
    ldp x19, x20, [sp], #16
    bl _bit_die

_bit_sock_send:                     // x0 = conn, x1 = строка, x2 = строка программы
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov w19, w0
    mov x20, x1
    mov x22, x2
    mov x0, x20
    bl _strlen
    mov x21, x0
    mov x20, x20
1:  cmp x21, #0
    b.le 3f
    mov w0, w19
    mov x1, x20
    mov x2, x21
    mov w3, #0
    bl _send
    tbnz x0, #63, 9f
    add x20, x20, x0
    sub x21, x21, x0
    b 1b
3:  ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_esend@PAGE
    add x0, x0, Lrt_esend@PAGEOFF
    mov x1, x22
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    bl _bit_die

_bit_sock_recv:                     // x0 = conn, x1 = строка -> строка (то, что пришло)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov w19, w0
    mov x20, x1
    mov x0, #65536
    bl _bit_alloc
    mov x21, x0
    mov w0, w19
    mov x1, x21
    mov x2, #65535
    mov w3, #0
    bl _recv
    tbnz x0, #63, 9f
    strb wzr, [x21, x0]
    mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_erecv@PAGE
    add x0, x0, Lrt_erecv@PAGEOFF
    mov x1, x20
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    bl _bit_die

_bit_sock_close:                    // x0 = conn/server
    b _close

_bit_shquote:                       // x0 = строка -> 'строка' с экранированием для shell
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    bl _strlen
    lsl x1, x0, #2
    add x0, x1, #3
    bl _bit_alloc
    mov x20, x0
    mov x21, x19
    mov x22, x20
    mov w2, #39
    strb w2, [x22], #1
1:  ldrb w2, [x21], #1
    cbz w2, 3f
    cmp w2, #39
    b.ne 2f
    mov w3, #39
    strb w3, [x22], #1
    mov w3, #92
    strb w3, [x22], #1
    mov w3, #39
    strb w3, [x22], #1
    mov w3, #39
    strb w3, [x22], #1
    b 1b
2:  strb w2, [x22], #1
    b 1b
3:  mov w2, #39
    strb w2, [x22], #1
    strb wzr, [x22]
    mov x0, x20
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_spawn_capture:                 // x0 = argv (char**, NULL-терм), x1 = строка -> вывод stdout
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    sub sp, sp, #16
    mov x19, x0
    mov x20, x1
    mov x0, #0
    bl _fflush
    mov x0, sp
    bl _pipe
    cmp w0, #0
    b.lt 9f
    bl _fork
    cmp x0, #0
    b.lt 8f
    b.ne 2f
    ldr w0, [sp, #4]
    mov w1, #1
    bl _dup2
    ldr w0, [sp]
    bl _close
    ldr w0, [sp, #4]
    bl _close
    ldr x0, [x19]
    mov x1, x19
    bl _execvp
    mov w0, #127
    bl _exit
2:  mov x21, x0
    ldr w0, [sp, #4]
    bl _close
    mov x0, #4096
    bl _bit_alloc
    mov x22, x0
    mov x23, #4096
    mov x24, #0
3:  add x0, x24, #1
    cmp x0, x23
    b.lo 4f
    lsl x23, x23, #1
    mov x0, x22
    mov x1, x23
    bl _realloc
    cbz x0, _bit_oom
    mov x22, x0
4:  ldr w0, [sp]
    add x1, x22, x24
    sub x2, x23, x24
    sub x2, x2, #1
    bl _read
    cmp x0, #0
    b.le 5f
    add x24, x24, x0
    b 3b
5:  ldr w0, [sp]
    bl _close
    mov x0, x21
    add x1, sp, #8
    mov x2, #0
    bl _waitpid
    ldr w0, [sp, #8]
    bl _bit_wstatus
    cbz x24, 6f
    sub x0, x24, #1
    ldrb w1, [x22, x0]
    cmp w1, #10
    b.ne 6f
    sub x24, x24, #1
6:  strb wzr, [x22, x24]
    mov x0, x22
    add sp, sp, #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
8:  ldr w0, [sp]
    bl _close
    ldr w0, [sp, #4]
    bl _close
9:  adrp x0, Lrt_erun@PAGE
    add x0, x0, Lrt_erun@PAGEOFF
    mov x1, x20
    bl _bit_die

_bit_spawn_status:                  // x0 = argv, x1 = тихо(0/1), x2 = строка -> код выхода
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    sub sp, sp, #16
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x0, #0
    bl _fflush
    bl _fork
    cmp x0, #0
    b.lt 9f
    b.ne 2f
    cbz x20, 1f
    adrp x0, Lrt_devnull@PAGE
    add x0, x0, Lrt_devnull@PAGEOFF
    mov w1, #1
    mov w2, #0
    bl _open
    cmp w0, #0
    b.lt 1f
    mov x22, x0
    mov x0, x22
    mov w1, #1
    bl _dup2
    mov x0, x22
    mov w1, #2
    bl _dup2
1:  ldr x0, [x19]
    mov x1, x19
    bl _execvp
    mov w0, #127
    bl _exit
2:  mov x1, sp
    mov x2, #0
    bl _waitpid
    ldr w0, [sp]
    bl _bit_wstatus
    add sp, sp, #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_erun@PAGE
    add x0, x0, Lrt_erun@PAGEOFF
    mov x1, x21
    bl _bit_die

_bit_fetch:                         // x0 = url, x1 = строка -> тело ответа
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    sub sp, sp, #48
    mov x19, x1
    mov x20, x0
    adrp x2, Lrt_curl@PAGE
    add x2, x2, Lrt_curl@PAGEOFF
    str x2, [sp]
    adrp x2, Lrt_sS@PAGE
    add x2, x2, Lrt_sS@PAGEOFF
    str x2, [sp, #8]
    adrp x2, Lrt_L@PAGE
    add x2, x2, Lrt_L@PAGEOFF
    str x2, [sp, #16]
    adrp x2, Lrt_ddp@PAGE
    add x2, x2, Lrt_ddp@PAGEOFF
    str x2, [sp, #24]
    str x20, [sp, #32]
    str xzr, [sp, #40]
    mov x0, sp
    mov x1, x19
    bl _bit_spawn_capture
    add sp, sp, #48
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_http_post:                     // x0 = url, x1 = данные, x2 = строка -> ответ
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    sub sp, sp, #64
    mov x19, x0
    mov x20, x1
    mov x21, x2
    adrp x2, Lrt_curl@PAGE
    add x2, x2, Lrt_curl@PAGEOFF
    str x2, [sp]
    adrp x2, Lrt_sS@PAGE
    add x2, x2, Lrt_sS@PAGEOFF
    str x2, [sp, #8]
    adrp x2, Lrt_L@PAGE
    add x2, x2, Lrt_L@PAGEOFF
    str x2, [sp, #16]
    adrp x2, Lrt_d@PAGE
    add x2, x2, Lrt_d@PAGEOFF
    str x2, [sp, #24]
    str x20, [sp, #32]
    adrp x2, Lrt_ddp@PAGE
    add x2, x2, Lrt_ddp@PAGEOFF
    str x2, [sp, #40]
    str x19, [sp, #48]
    str xzr, [sp, #56]
    mov x0, sp
    mov x1, x21
    bl _bit_spawn_capture
    add sp, sp, #64
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_download:                      // x0 = url, x1 = файл, x2 = строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    sub sp, sp, #64
    mov x19, x0
    mov x20, x1
    mov x21, x2
    adrp x2, Lrt_curl@PAGE
    add x2, x2, Lrt_curl@PAGEOFF
    str x2, [sp]
    adrp x2, Lrt_sS@PAGE
    add x2, x2, Lrt_sS@PAGEOFF
    str x2, [sp, #8]
    adrp x2, Lrt_L@PAGE
    add x2, x2, Lrt_L@PAGEOFF
    str x2, [sp, #16]
    adrp x2, Lrt_o@PAGE
    add x2, x2, Lrt_o@PAGEOFF
    str x2, [sp, #24]
    str x20, [sp, #32]
    adrp x2, Lrt_ddp@PAGE
    add x2, x2, Lrt_ddp@PAGEOFF
    str x2, [sp, #40]
    str x19, [sp, #48]
    str xzr, [sp, #56]
    mov x0, sp
    mov x1, #0
    mov x2, x21
    bl _bit_spawn_status
    add sp, sp, #64
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_resolve:                       // x0 = имя хоста, x1 = строка -> IP-адрес строкой
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x20, x1
    bl _gethostbyname
    cbz x0, 9f
    ldr x1, [x0, #24]
    ldr x1, [x1]
    mov x19, x1
    mov x0, #32
    bl _bit_alloc
    mov x2, x0
    mov w0, #2
    mov x1, x19
    mov x3, #32
    bl _inet_ntop
    cbz x0, 9f
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_edns@PAGE
    add x0, x0, Lrt_edns@PAGEOFF
    mov x1, x20
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_die

_bit_ping:                          // x0 = хост -> 1 если отвечает
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    sub sp, sp, #48
    mov x19, x0
    adrp x2, Lrt_pingp@PAGE
    add x2, x2, Lrt_pingp@PAGEOFF
    str x2, [sp]
    adrp x2, Lrt_pingc@PAGE
    add x2, x2, Lrt_pingc@PAGEOFF
    str x2, [sp, #8]
    adrp x2, Lrt_1@PAGE
    add x2, x2, Lrt_1@PAGEOFF
    str x2, [sp, #16]
    str x19, [sp, #24]
    str xzr, [sp, #32]
    mov x0, sp
    mov x1, #1
    mov x2, #0
    bl _bit_spawn_status
    cmp x0, #0
    cset x0, eq
    add sp, sp, #48
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_str_num:                       // x0 = строка -> число (десятичное)
    mov x1, x0
    mov x3, #0
1:  ldrb w2, [x1]
    cmp w2, #32
    b.ne 2f
    add x1, x1, #1
    b 1b
2:  cmp w2, #45
    b.ne 3f
    mov x3, #1
    add x1, x1, #1
3:  mov x0, #0
4:  ldrb w2, [x1]
    sub w4, w2, #48
    cmp w4, #9
    b.hi 5f
    mov x5, #10
    mul x0, x0, x5
    add x0, x0, x4
    add x1, x1, #1
    b 4b
5:  cbz x3, 6f
    neg x0, x0
6:  ret

_bit_str_lines:                     // x0 = строка -> mas строк (по переводу строки)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    bl _strlen
    mov x21, x0
    add x0, x0, #1
    bl _bit_alloc
    mov x20, x0
    mov x0, x20
    mov x1, x19
    add x2, x21, #1
    bl _memcpy
    mov x0, #-1
    mov x1, #0
    bl _bit_mas_new
    mov x22, x0
    mov x19, x20
    mov x21, x20
1:  ldrb w2, [x19]
    cbz w2, 3f
    cmp w2, #10
    b.ne 2f
    strb wzr, [x19]
    mov x0, x22
    mov x1, x21
    mov x2, #0
    bl _bit_mas_add
    add x19, x19, #1
    mov x21, x19
    b 1b
2:  add x19, x19, #1
    b 1b
3:  mov x0, x22
    mov x1, x21
    mov x2, #0
    bl _bit_mas_add
    mov x0, x22
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_os_host:                       // -> имя компьютера
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x0, #256
    bl _bit_alloc
    mov x19, x0
    mov x0, x19
    mov x1, #256
    bl _gethostname
    mov x0, x19
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_os_user:                       // -> имя пользователя
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x0, Lrt_userenv@PAGE
    add x0, x0, Lrt_userenv@PAGEOFF
    bl _getenv
    cbnz x0, 1f
    adrp x0, Lrt_empty@PAGE
    add x0, x0, Lrt_empty@PAGEOFF
1:  ldp x29, x30, [sp], #16
    ret

_bit_os_now:                        // -> время (секунды с 1970)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x0, #0
    bl _time
    ldp x29, x30, [sp], #16
    ret

_bit_os_cpus:                       // x0 = строка -> число ядер
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x1, x0
    adrp x0, Lrt_cpucmd@PAGE
    add x0, x0, Lrt_cpucmd@PAGEOFF
    bl _bit_run
    bl _bit_str_num
    ldp x29, x30, [sp], #16
    ret

_bit_os_procs:                      // x0 = строка -> список процессов (текст)
    mov x1, x0
    adrp x0, Lrt_pscmd@PAGE
    add x0, x0, Lrt_pscmd@PAGEOFF
    b _bit_run

// ── mas >> run: программа напрямую массивом аргументов; stdout и stderr отдельно, stdin ──
_bit_mas_argv:                      // x0 = mas строк → x0 = char** (NULL в конце)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    ldr x0, [x19, #8]
    lsl x0, x0, #3
    add x0, x0, #8
    bl _bit_alloc
    ldr x1, [x19, #8]
    ldr x2, [x19]
    mov x3, #0
1:  cmp x3, x1
    b.ge 2f
    ldr x4, [x2, x3, lsl #3]
    str x4, [x0, x3, lsl #3]
    add x3, x3, #1
    b 1b
2:  str xzr, [x0, x1, lsl #3]
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_buf_read:                      // w0 = fd, x1 = буфер (ptr, len, cap) → x0 = прочитано
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov w19, w0
    mov x20, x1
    ldr x2, [x20, #8]
    add x2, x2, #1
    ldr x3, [x20, #16]
    cmp x2, x3
    b.lo 1f
    lsl x3, x3, #1
    str x3, [x20, #16]
    ldr x0, [x20]
    mov x1, x3
    bl _realloc
    cbz x0, _bit_oom
    str x0, [x20]
1:  mov w0, w19
    ldr x1, [x20]
    ldr x2, [x20, #8]
    add x1, x1, x2
    ldr x3, [x20, #16]
    sub x2, x3, x2
    sub x2, x2, #1
    bl _read
    cmp x0, #0
    b.le 2f
    ldr x1, [x20, #8]
    add x1, x1, x0
    str x1, [x20, #8]
2:  ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_buf_finish:                    // x0 = буфер → строка (без последнего \n)
    ldr x1, [x0, #8]
    ldr x2, [x0]
    cbz x1, 1f
    sub x3, x1, #1
    ldrb w4, [x2, x3]
    cmp w4, #10
    b.ne 1f
    mov x1, x3
1:  strb wzr, [x2, x1]
    mov x0, x2
    ret

_bit_exec:                          // x0 = mas строк, x1 = stdin (или 0), x2 = строка → stdout
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    sub sp, sp, #128
    mov x20, x1
    mov x21, x2
    ldr x3, [x0, #8]
    cbz x3, 9f
    bl _bit_mas_argv
    mov x19, x0
    mov x0, #0
    bl _fflush
    mov x0, sp
    bl _pipe
    tbnz w0, #31, 9f
    add x0, sp, #8
    bl _pipe
    tbnz w0, #31, 9f
    cbz x20, 1f
    add x0, sp, #16
    bl _pipe
    tbnz w0, #31, 9f
1:  bl _fork
    tbnz w0, #31, 9f
    cbnz w0, 3f
    ldr w0, [sp, #4]
    mov w1, #1
    bl _dup2
    ldr w0, [sp, #12]
    mov w1, #2
    bl _dup2
    cbz x20, 2f
    ldr w0, [sp, #16]
    mov w1, #0
    bl _dup2
    ldr w0, [sp, #16]
    bl _close
    ldr w0, [sp, #20]
    bl _close
2:  ldr w0, [sp]
    bl _close
    ldr w0, [sp, #4]
    bl _close
    ldr w0, [sp, #8]
    bl _close
    ldr w0, [sp, #12]
    bl _close
    ldr x0, [x19]
    mov x1, x19
    bl _execvp
    mov w0, #127
    bl _exit
3:  str w0, [sp, #24]
    ldr w0, [sp, #4]
    bl _close
    ldr w0, [sp, #12]
    bl _close
    cbz x20, 5f
    ldr w0, [sp, #16]
    bl _close
    mov x0, #13
    mov x1, #1
    bl _signal
    str x0, [sp, #112]
    mov x0, x20
    bl _strlen
    mov x22, x0
    mov x23, x20
4:  cbz x22, 6f
    ldr w0, [sp, #20]
    mov x1, x23
    mov x2, x22
    bl _write
    cmp x0, #0
    b.le 6f
    add x23, x23, x0
    sub x22, x22, x0
    b 4b
6:  ldr w0, [sp, #20]
    bl _close
    mov x0, #13
    ldr x1, [sp, #112]
    bl _signal
5:  mov x0, #4096
    bl _bit_alloc
    str x0, [sp, #48]
    str xzr, [sp, #56]
    mov x1, #4096
    str x1, [sp, #64]
    mov x0, #4096
    bl _bit_alloc
    str x0, [sp, #72]
    str xzr, [sp, #80]
    mov x1, #4096
    str x1, [sp, #88]
    ldr w0, [sp]
    str w0, [sp, #32]
    mov w1, #1
    str w1, [sp, #36]
    ldr w0, [sp, #8]
    str w0, [sp, #40]
    str w1, [sp, #44]
    mov x1, #2
    str x1, [sp, #104]
7:  ldr x1, [sp, #104]
    cbz x1, 8f
    add x0, sp, #32
    mov x1, #2
    mov w2, #-1
    bl _poll
    ldr w0, [sp, #32]
    tbnz w0, #31, 71f
    ldrh w1, [sp, #38]
    cbz w1, 71f
    add x1, sp, #48
    bl _bit_buf_read
    cmp x0, #0
    b.gt 71f
    ldr w0, [sp, #32]
    bl _close
    mov w0, #-1
    str w0, [sp, #32]
    ldr x1, [sp, #104]
    sub x1, x1, #1
    str x1, [sp, #104]
71: ldr w0, [sp, #40]
    tbnz w0, #31, 7b
    ldrh w1, [sp, #46]
    cbz w1, 7b
    add x1, sp, #72
    bl _bit_buf_read
    cmp x0, #0
    b.gt 7b
    ldr w0, [sp, #40]
    bl _close
    mov w0, #-1
    str w0, [sp, #40]
    ldr x1, [sp, #104]
    sub x1, x1, #1
    str x1, [sp, #104]
    b 7b
8:  ldr w0, [sp, #24]
    add x1, sp, #96
    mov w2, #0
    bl _waitpid
    ldr w0, [sp, #96]
    bl _bit_wstatus
    add x0, sp, #72
    bl _bit_buf_finish
    adrp x1, Lrt_stderr@PAGE
    str x0, [x1, Lrt_stderr@PAGEOFF]
    add x0, sp, #48
    bl _bit_buf_finish
    add sp, sp, #128
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_erun@PAGE
    add x0, x0, Lrt_erun@PAGEOFF
    mov x1, x21
    bl _bit_die

_bit_term_stderr:                   // → копия stderr последнего mas >> run ("" если не было)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    adrp x1, Lrt_stderr@PAGE
    ldr x19, [x1, Lrt_stderr@PAGEOFF]
    cbnz x19, 1f
    mov x0, #1
    bl _bit_alloc
    strb wzr, [x0]
    b 2f
1:  mov x0, x19
    bl _strlen
    mov x1, x0
    mov x0, x19
    bl _bit_substr
2:  ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

.section __DATA,__data
.p2align 3
Lrt_argc: .quad 0
Lrt_argv: .quad 0
Lrt_status: .quad 0
Lrt_recdepth: .quad 0
Lrt_errmsg: .quad 0
Lrt_errline: .quad 0
Lrt_stderr: .quad 0
.p2align 4
Lrt_recbufs: .space 8192
.section __TEXT,__text,regular,pure_instructions
.p2align 2

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
Lrt_wb: .asciz "wb"
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
