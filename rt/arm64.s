
// ─────────── среда выполнения bit ───────────
.p2align 2
_bit_signal_handler:                 // async-signal-safe: set one aligned flag
    adrp x9, Lrt_signalled@PAGE
    add x9, x9, Lrt_signalled@PAGEOFF
    mov w10, #1
    stlr w10, [x9]
    ret

_bit_signalled:
    adrp x9, Lrt_signalled@PAGE
    add x9, x9, Lrt_signalled@PAGEOFF
    ldar w0, [x9]
    cmp w0, #0
    cset w0, ne
    ret

_bit_signal_init:                    // Darwin sigaction: handler, mask, flags
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #16
    adrp x9, _bit_signal_handler@PAGE
    add x9, x9, _bit_signal_handler@PAGEOFF
    str x9, [sp]
    str wzr, [sp, #8]
    mov w9, #2                       // SA_RESTART
    str w9, [sp, #12]
    mov w0, #2                       // SIGINT
    mov x1, sp
    mov x2, #0
    bl _sigaction
    cbnz w0, 9f
    mov w0, #15                      // SIGTERM
    mov x1, sp
    mov x2, #0
    bl _sigaction
    cbnz w0, 9f
    add sp, sp, #16
    ldp x29, x30, [sp], #16
    ret
9:  add sp, sp, #16
    ldp x29, x30, [sp], #16
    adrp x0, Lrt_esignal@PAGE
    add x0, x0, Lrt_esignal@PAGEOFF
    mov x1, #0
    b _bit_die

_bit_rt_ensure:                     // однократная подготовка ключа потока и замка строк
    adrp x9, Lrt_ready@PAGE
    ldrb w10, [x9, Lrt_ready@PAGEOFF]
    cbnz w10, 9f
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x0, Lrt_tkey@PAGE
    add x0, x0, Lrt_tkey@PAGEOFF
    mov x1, #0
    bl _pthread_key_create
    adrp x0, Lrt_slock@PAGE
    add x0, x0, Lrt_slock@PAGEOFF
    mov x1, #0
    bl _pthread_mutex_init
    adrp x9, Lrt_ready@PAGE
    mov w10, #1
    strb w10, [x9, Lrt_ready@PAGEOFF]
    ldp x29, x30, [sp], #16
9:  ret

_bit_lock:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _bit_rt_ensure
    adrp x0, Lrt_slock@PAGE
    add x0, x0, Lrt_slock@PAGEOFF
    bl _pthread_mutex_lock
    ldp x29, x30, [sp], #16
    ret

_bit_unlock:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x0, Lrt_slock@PAGE
    add x0, x0, Lrt_slock@PAGEOFF
    bl _pthread_mutex_unlock
    ldp x29, x30, [sp], #16
    ret

_bit_tstate:                        // → блок состояния этого потока
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    bl _bit_rt_ensure
    adrp x0, Lrt_tkey@PAGE
    add x0, x0, Lrt_tkey@PAGEOFF
    ldr x0, [x0]
    bl _pthread_getspecific
    cbnz x0, 9f
    mov x0, #64
    bl _bit_alloc
    mov x19, x0
    mov x0, x19
    mov x1, #0
    mov x2, #64
    bl _memset
    adrp x0, Lrt_tkey@PAGE
    add x0, x0, Lrt_tkey@PAGEOFF
    ldr x0, [x0]
    mov x1, x19
    bl _pthread_setspecific
    mov x0, x19
9:  ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_recover_enter:                 // x0 = frame allocated by the compiler
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    bl _bit_tstate
    mov x20, x0
    ldr x1, [x20]
    str x1, [x19, #168]
    str x19, [x20]
    ldr x1, [x20, #8]
    str x1, [x19, #176]
    str xzr, [x20, #32]
    mov x0, x19
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_recover_leave:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    bl _bit_tstate
    mov x1, x0
    ldr x2, [x1]
    ldr x2, [x2, #168]
    str x2, [x1]
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_own_str:                       // x0 = stack record with string and previous pointer
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    bl _bit_tstate
    ldr x1, [x0, #8]
    str x1, [x19, #8]
    str x19, [x0, #8]
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_drop_owned:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    bl _bit_tstate
    mov x1, x0
    ldr x0, [x1, #8]
    ldr x2, [x0, #8]
    str x2, [x1, #8]
    ldr x0, [x0]
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_drop_str

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

_bit_set_errcode:                   // x0 = код → запомнить для этого потока
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    bl _bit_tstate
    str x19, [x0, #32]
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_term_errcode:                  // → код последней пойманной ошибки (0 = без кода)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _bit_tstate
    ldr x0, [x0, #32]
    ldp x29, x30, [sp], #16
    ret

_bit_errno_map:                     // w0 = код ошибки системы → 1 отказ, 2 таймаут, 3 нет маршрута, 0 без кода
    cmp w0, #61                        // ECONNREFUSED (Darwin)
    b.eq 1f
    cmp w0, #60                        // ETIMEDOUT (Darwin)
    b.eq 2f
    cmp w0, #51                        // ENETUNREACH (Darwin)
    b.eq 3f
    cmp w0, #65                        // EHOSTUNREACH (Darwin)
    b.eq 3f
    mov w0, #0
    ret
1:  mov w0, #1
    ret
2:  mov w0, #2
    ret
3:  mov w0, #3
    ret

_bit_errno_code:                    // → код ошибки системы из errno
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl ___error
    ldr w0, [x0]
    bl _bit_errno_map
    ldp x29, x30, [sp], #16
    ret

// User locks have process lifetime; aliases refer to the same mutex.
_bit_user_lock_new:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x0, #80
    bl _bit_alloc
    mov x19, x0
    mov x1, #0
    bl _pthread_mutex_init
    cbnz w0, 1f
    mov x0, x19
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
1:  mov x0, x19
    bl _free
    adrp x0, Lrt_elock@PAGE
    add x0, x0, Lrt_elock@PAGEOFF
    mov x1, #0
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_die

_bit_user_lock_enter:                // x0 = lock, x1 = source line
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x1
    bl _pthread_mutex_lock
    cbnz w0, 1f
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
1:  adrp x0, Lrt_elock@PAGE
    add x0, x0, Lrt_elock@PAGEOFF
    mov x1, x19
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_die

_bit_user_lock_leave:                // x0 = lock, x1 = source line
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x1
    bl _pthread_mutex_unlock
    cbnz w0, 1f
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
1:  adrp x0, Lrt_elock@PAGE
    add x0, x0, Lrt_elock@PAGEOFF
    mov x1, x19
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_die

_bit_thread_start:                  // x0 = code -> stable thread token
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    // No bit thread can start before the shared registry and TLS key exist.
    bl _bit_rt_ensure
    mov x0, #128
    bl _bit_alloc
    mov x20, x0
    str xzr, [x20, #24]           // waiters
    str xzr, [x20, #32]           // 0 = unjoined, 1 = joining, 2 = joined
    str xzr, [x20, #120]          // pthread_join result
    add x0, x20, #40
    mov x1, #0
    bl _pthread_cond_init
    cbnz w0, 8f
    add x0, x20, #16
    mov x1, #0
    adrp x2, _bit_thread_run@PAGE
    add x2, x2, _bit_thread_run@PAGEOFF
    mov x3, x19
    bl _pthread_create
    cbnz w0, 9f
    bl _bit_lock
    adrp x1, Lrt_thread_next@PAGE
    ldr x21, [x1, Lrt_thread_next@PAGEOFF]
    add x2, x21, #1
    str x2, [x1, Lrt_thread_next@PAGEOFF]
    str x21, [x20, #8]
    adrp x1, Lrt_thread_list@PAGE
    ldr x2, [x1, Lrt_thread_list@PAGEOFF]
    str x2, [x20]
    str x20, [x1, Lrt_thread_list@PAGEOFF]
    bl _bit_unlock
    mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  add x0, x20, #40
    bl _pthread_cond_destroy
8:  mov x0, x20
    bl _free
    adrp x0, Lrt_ethread@PAGE
    add x0, x0, Lrt_ethread@PAGEOFF
    mov x1, #0
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_die

_bit_thread_run:                    // x0 = код потока
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    blr x0
    // State is optional: do not allocate it just to destroy it.
    adrp x0, Lrt_tkey@PAGE
    add x0, x0, Lrt_tkey@PAGEOFF
    ldr x0, [x0]
    bl _pthread_getspecific
    cbz x0, 1f
    bl _free
1:
    mov x0, #0
    ldp x29, x30, [sp], #16
    ret

_bit_thread_wait:                   // x0 = stable token; completed tokens are no-ops
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    bl _bit_lock
    adrp x0, Lrt_thread_list@PAGE
    ldr x20, [x0, Lrt_thread_list@PAGEOFF]
1:  cbz x20, 8f
    ldr x0, [x20, #8]
    cmp x0, x19
    b.eq 2f
    ldr x20, [x20]
    b 1b
2:  ldr x0, [x20, #24]
    add x0, x0, #1
    str x0, [x20, #24]
    mov x21, #0
    ldr x0, [x20, #32]
    cbnz x0, 4f
    mov x0, #1
    str x0, [x20, #32]
    bl _bit_unlock
    ldr x0, [x20, #16]
    mov x1, #0
    bl _pthread_join
    mov x21, x0
    bl _bit_lock
    str x21, [x20, #120]
    mov x0, #2
    str x0, [x20, #32]
    add x0, x20, #40
    bl _pthread_cond_broadcast
    b 6f
4:  ldr x0, [x20, #32]
    cmp x0, #2
    b.eq 5f
    add x0, x20, #40
    adrp x1, Lrt_slock@PAGE
    add x1, x1, Lrt_slock@PAGEOFF
    bl _pthread_cond_wait
    cbz w0, 4b
    mov x21, x0
    b 6f
5:  ldr x21, [x20, #120]
6:  ldr x0, [x20, #24]
    subs x0, x0, #1
    str x0, [x20, #24]
    b.ne 7f
    adrp x22, Lrt_thread_list@PAGE
    add x22, x22, Lrt_thread_list@PAGEOFF
61: ldr x0, [x22]
    cmp x0, x20
    b.eq 62f
    mov x22, x0
    b 61b
62: ldr x0, [x20]
    str x0, [x22]
    bl _bit_unlock
    add x0, x20, #40
    bl _pthread_cond_destroy
    mov x0, x20
    bl _free
    b 9f
7:  bl _bit_unlock
    b 9f
8:  bl _bit_unlock
    mov x21, #0
9:  cbnz x21, 10f
    mov x0, #0
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
10: adrp x0, Lrt_ewait_thread@PAGE
    add x0, x0, Lrt_ewait_thread@PAGEOFF
    mov x1, #0
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_die

_bit_term_raw:                      // x0 = 1 сырой режим, 0 обычный
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    sub sp, sp, #128
    mov w19, w0
    mov x0, #0
    mov x1, sp
    bl _tcgetattr
    tbnz w0, #31, 9f
    ldr w1, [sp, #24]
    cbz w19, 1f
    movn w2, #0x108                  // снять ICANON|ECHO (Darwin)
    and w1, w1, w2
    b 2f
1:  mov w2, #0x108                   // вернуть ICANON|ECHO (Darwin)
    orr w1, w1, w2
2:  str w1, [sp, #24]
    mov x0, #0
    mov x1, #0
    mov x2, sp
    bl _tcsetattr
9:  add sp, sp, #128
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_term_key:                      // → строка из одного символа
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x0, #8
    bl _bit_alloc
    mov x19, x0
    mov x0, #0
    mov x1, x19
    mov x2, #1
    bl _read
    cmp x0, #1
    b.lt 9f
    ldrb w1, [x19]
    mov x20, #1
    cmp w1, #0xF0
    b.lo 1f
    mov x20, #4
    b 3f
1:  cmp w1, #0xE0
    b.lo 2f
    mov x20, #3
    b 3f
2:  cmp w1, #0xC0
    b.lo 3f
    mov x20, #2
3:  mov x21, #1
4:  cmp x21, x20
    b.hs 8f
    mov x0, #0
    add x1, x19, x21
    mov x2, #1
    bl _read
    cmp x0, #1
    b.lt 8f
    add x21, x21, #1
    b 4b
8:  strb wzr, [x19, x21]
    mov x0, x19
    b 10f
9:  strb wzr, [x19]
    mov x0, x19
10: ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_term_error:                    // → копия текста последней пойманной ошибки ("" если не было)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    bl _bit_tstate
    ldr x19, [x0, #16]
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
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x20, x0
    mov x21, x1
    bl _bit_tstate
    mov x19, x0
    ldr x10, [x19]
    cbz x10, 5f
    str x20, [x19, #16]
    str x21, [x19, #24]
    ldr x11, [x10, #168]
    str x11, [x19]
    mov x22, x10
1:  ldr x12, [x19, #8]
    ldr x11, [x22, #176]
    cmp x12, x11
    b.eq 2f
    bl _bit_drop_owned
    b 1b
2:  mov x0, x22
    mov x1, #1
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_longjmp
5:  mov x19, x20
    mov x20, x21
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

_bit_key_cmp:                       // x0=a, x1=b, x2=вид → w0 (-1, 0, 1)
    cmp x2, #2
    b.eq 1f
    cmp x0, x1
    b.lt 3f
    b.gt 4f
    mov w0, #0
    ret
1:  ldrb w2, [x0]
    ldrb w3, [x1]
    cmp w2, w3
    b.lo 3f
    b.hi 4f
    cbz w2, 5f
    add x0, x0, #1
    add x1, x1, #1
    b 1b
5:  mov w0, #0
    ret
3:  mov w0, #-1
    ret
4:  mov w0, #1
    ret

_bit_mas_sort_by:                   // x0=значения, x1=ключи, x2=вид, x3=убывание, x4=строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    sub sp, sp, #64
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x3
    ldr x23, [x19, #8]
    ldr x24, [x20, #8]
    cmp x23, x24
    b.le 1f
    mov x23, x24
1:  mov x24, #1
2:  cmp x24, x23
    b.hs 9f
    ldr x0, [x19]
    ldr x5, [x0, x24, lsl #3]
    str x5, [sp, #16]
    ldr x0, [x20]
    ldr x5, [x0, x24, lsl #3]
    str x5, [sp, #24]
    mov x25, x24
3:  cbz x25, 6f
    sub x25, x25, #1
    str x25, [sp, #32]
    ldr x0, [x20]
    ldr x0, [x0, x25, lsl #3]
    ldr x1, [sp, #24]
    mov x2, x21
    bl _bit_key_cmp
    cbz x22, 31f
    neg w0, w0
31: cmp w0, #0
    b.le 7f
    ldr x25, [sp, #32]
    ldr x0, [x20]
    ldr x5, [x0, x25, lsl #3]
    add x6, x25, #1
    str x5, [x0, x6, lsl #3]
    ldr x0, [x19]
    ldr x5, [x0, x25, lsl #3]
    str x5, [x0, x6, lsl #3]
    b 3b
6:  mov x25, #0
    b 52f
7:  add x25, x25, #1
52: ldr x0, [x20]
    ldr x5, [sp, #24]
    str x5, [x0, x25, lsl #3]
    ldr x0, [x19]
    ldr x5, [sp, #16]
    str x5, [x0, x25, lsl #3]
    add x24, x24, #1
    b 2b
9:  add sp, sp, #64
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_map_keys:                      // x0=словарь, x1=строка → mas строк
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x21, x1
    ldr x20, [x19, #8]
    mov x0, #-1
    mov x1, #0
    bl _bit_mas_new
    mov x22, x0
    mov x23, #0
1:  cmp x23, x20
    b.hs 2f
    ldr x0, [x19]
    ldr x0, [x0, x23, lsl #3]
    ldr x0, [x19]
    ldr x0, [x0, x23, lsl #3]
    ldr x1, [x0]
    mov x0, x22
    mov x2, x21
    bl _bit_mas_add
    add x23, x23, #1
    b 1b
2:  mov x0, x22
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_map_values:                    // x0=словарь, x1=вид значения, x2=строка → mas
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    mov x19, x0
    mov x21, x2
    mov x24, x1
    ldr x20, [x19, #8]
    mov x0, #-1
    mov x1, #0
    bl _bit_mas_new
    mov x22, x0
    mov x23, #0
1:  cmp x23, x20
    b.hs 2f
    ldr x0, [x19]
    ldr x0, [x0, x23, lsl #3]
    ldr x25, [x0, #8]
3:  mov x0, x22
    mov x1, x25
    mov x2, x21
    bl _bit_mas_add
    add x23, x23, #1
    b 1b
2:  mov x0, x22
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_map_find:                      // map, key -> index or -1
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    ldr x19, [x0]
    ldr x20, [x0, #8]
    mov x21, x1
    mov x22, #0
1:  cmp x22, x20
    b.ge 2f
    ldr x0, [x19, x22, lsl #3]
    ldr x0, [x0]
    mov x1, x21
    bl _bit_str_eq
    cbnz x0, 3f
    add x22, x22, #1
    b 1b
2:  mov x22, #-1
3:  mov x0, x22
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_map_set:                       // map, key, value, source line
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x3
    bl _bit_map_find
    tbnz x0, #63, 1f
    ldr x1, [x19]
    ldr x1, [x1, x0, lsl #3]
    str x21, [x1, #8]
    b 2f
1:  mov x0, #16
    bl _bit_alloc
    stp x20, x21, [x0]
    mov x1, x0
    mov x0, x19
    mov x2, x22
    bl _bit_mas_add
2:  ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_map_remove:                    // map, key
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    bl _bit_map_find
    tbnz x0, #63, 1f
    mov x20, x0
    ldr x1, [x19]
    ldr x21, [x1, x20, lsl #3]
    mov x0, x19
    mov x1, x20
    bl _bit_mas_remove
    mov x0, x21
    bl _free
1:  ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_random_seed:                   // Hash a UTF-8 seed word with FNV-1a.
    movz x1, #0x2325
    movk x1, #0x8422, lsl #16
    movk x1, #0x9ce4, lsl #32
    movk x1, #0xcbf2, lsl #48
    movz x2, #0x01b3
    movk x2, #0x0100, lsl #32
1:  ldrb w3, [x0], #1
    cbz w3, 2f
    eor x1, x1, x3
    mul x1, x1, x2
    b 1b
2:  adrp x3, Lrt_random_state@PAGE
    str x1, [x3, Lrt_random_state@PAGEOFF]
    adrp x3, Lrt_random_ready@PAGE
    mov x1, #1
    str x1, [x3, Lrt_random_ready@PAGEOFF]
    ret

_bit_random_next:                   // SplitMix64 with unsigned wrapping arithmetic.
    adrp x1, Lrt_random_state@PAGE
    ldr x0, [x1, Lrt_random_state@PAGEOFF]
    movz x2, #0x7c15
    movk x2, #0x7f4a, lsl #16
    movk x2, #0x79b9, lsl #32
    movk x2, #0x9e37, lsl #48
    add x0, x0, x2
    str x0, [x1, Lrt_random_state@PAGEOFF]
    eor x0, x0, x0, lsr #30
    movz x2, #0xe5b9
    movk x2, #0x1ce4, lsl #16
    movk x2, #0x476d, lsl #32
    movk x2, #0xbf58, lsl #48
    mul x0, x0, x2
    eor x0, x0, x0, lsr #27
    movz x2, #0x11eb
    movk x2, #0x1331, lsl #16
    movk x2, #0x49bb, lsl #32
    movk x2, #0x94d0, lsl #48
    mul x0, x0, x2
    eor x0, x0, x0, lsr #31
    ret

_bit_random_range:                  // Inclusive signed bounds, source line.
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    sub sp, sp, #32
    mov x19, x0
    mov x21, x2
    cmp x0, x1
    b.gt 9f
    sub x20, x1, x0
    add x20, x20, #1
    adrp x3, Lrt_random_ready@PAGE
    ldr x3, [x3, Lrt_random_ready@PAGEOFF]
    cbnz x3, 2f
    mov x0, sp
    mov x1, #16
    bl _getentropy
    cbnz w0, 8f
    mov x3, sp
    mov x4, #16
1:  ldrb w0, [x3]
    and w0, w0, #15
    add w0, w0, #97
    strb w0, [x3], #1
    subs x4, x4, #1
    b.ne 1b
    strb wzr, [x3]
    mov x0, sp
    bl _bit_random_seed
2:  cbz x20, 4f
    // Rejection avoids modulo bias. A zero width denotes the entire num range.
    neg x3, x20
    udiv x4, x3, x20
    msub x22, x4, x20, x3
3:  bl _bit_random_next
    cmp x0, x22
    b.lo 3b
    udiv x3, x0, x20
    msub x0, x3, x20, x0
    b 5f
4:  bl _bit_random_next
5:  add x0, x0, x19
    add sp, sp, #32
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
8:  adrp x0, Lrt_random_entropy@PAGE
    add x0, x0, Lrt_random_entropy@PAGEOFF
    b 7f
9:  adrp x0, Lrt_random_bounds@PAGE
    add x0, x0, Lrt_random_bounds@PAGEOFF
7:  mov x1, x21
    bl _bit_die


// String ownership registry. Unknown pointers (literals and borrowed values) are ignored.
// Node layout: payload, references, next. Ownership adoption is explicit and idempotent.
_bit_str_find_raw:
    adrp x1, Lrt_str_low@PAGE
    ldr x1, [x1, Lrt_str_low@PAGEOFF]
    cmp x0, x1
    b.lo 2f
    adrp x1, Lrt_str_high@PAGE
    ldr x1, [x1, Lrt_str_high@PAGEOFF]
    cmp x0, x1
    b.hi 2f
    adrp x1, Lrt_str_registry@PAGE
    ldr x1, [x1, Lrt_str_registry@PAGEOFF]
    cbz x1, 2f
    lsr x2, x0, #4
    eor x2, x2, x0, lsr #20
    and x2, x2, #1048575
    ldr x1, [x1, x2, lsl #3]
1:  cbz x1, 2f
    ldr x3, [x1]
    cmp x3, x0
    b.eq 3f
    ldr x1, [x1, #16]
    b 1b
2:  mov x0, #0
    ret
3:  mov x0, x1
    ret

_bit_str_find:                      // x0 = указатель → запись реестра или 0 (под замком)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    bl _bit_lock
    mov x0, x19
    bl _bit_str_find_raw
    mov x19, x0
    bl _bit_unlock
    mov x0, x19
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_str_retain:
    adrp x1, Lrt_str_low@PAGE
    ldr x1, [x1, Lrt_str_low@PAGEOFF]
    cmp x0, x1
    b.lo 3f
    adrp x1, Lrt_str_high@PAGE
    ldr x1, [x1, Lrt_str_high@PAGEOFF]
    cmp x0, x1
    b.hi 3f
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    bl _bit_lock
    mov x0, x19
    bl _bit_str_find_raw
    cbz x0, 1f
    ldr x1, [x0, #8]
    add x1, x1, #1
    str x1, [x0, #8]
1:  bl _bit_unlock
    mov x0, x19
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
3:  ret

_bit_str_adopt:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    cbz x0, 2f
    bl _bit_lock
    mov x0, x19
    bl _bit_str_find_raw
    cbnz x0, 3f
    adrp x20, Lrt_str_registry@PAGE
    ldr x20, [x20, Lrt_str_registry@PAGEOFF]
    cbnz x20, 1f
    mov x0, #1048576
    mov x1, #8
    bl _calloc
    cbz x0, _bit_oom
    mov x20, x0
    adrp x1, Lrt_str_registry@PAGE
    str x0, [x1, Lrt_str_registry@PAGEOFF]
1:  lsr x21, x19, #4
    eor x21, x21, x19, lsr #20
    and x21, x21, #1048575
    mov x0, #24
    bl _bit_alloc
    str x19, [x0]
    mov x1, #1
    str x1, [x0, #8]
    ldr x1, [x20, x21, lsl #3]
    str x1, [x0, #16]
    str x0, [x20, x21, lsl #3]
    // Conservative bounds never shrink: pointers outside them cannot be owned strings.
    adrp x1, Lrt_str_low@PAGE
    ldr x2, [x1, Lrt_str_low@PAGEOFF]
    cmp x19, x2
    csel x2, x19, x2, lo
    str x2, [x1, Lrt_str_low@PAGEOFF]
    adrp x1, Lrt_str_high@PAGE
    ldr x2, [x1, Lrt_str_high@PAGEOFF]
    cmp x19, x2
    csel x2, x19, x2, hi
    str x2, [x1, Lrt_str_high@PAGEOFF]
3:  bl _bit_unlock
2:  mov x0, x19
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_str_release:
    adrp x1, Lrt_str_low@PAGE
    ldr x1, [x1, Lrt_str_low@PAGEOFF]
    cmp x0, x1
    b.lo 3f
    adrp x1, Lrt_str_high@PAGE
    ldr x1, [x1, Lrt_str_high@PAGEOFF]
    cmp x0, x1
    b.hi 3f
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    bl _bit_lock
    adrp x20, Lrt_str_registry@PAGE
    ldr x20, [x20, Lrt_str_registry@PAGEOFF]
    cbz x20, 2f
    lsr x1, x19, #4
    eor x1, x1, x19, lsr #20
    and x1, x1, #1048575
    add x20, x20, x1, lsl #3
1:  ldr x0, [x20]
    cbz x0, 2f
    ldr x1, [x0]
    cmp x1, x19
    b.eq 4f
    add x20, x0, #16
    b 1b
4:  ldr x1, [x0, #8]
    subs x1, x1, #1
    str x1, [x0, #8]
    b.ne 2f
    ldr x1, [x0, #16]
    str x1, [x20]
    bl _free
    mov x0, x19
    bl _free
2:  bl _bit_unlock
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
3:  ret

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

_bit_str_index:                     // x0=строка, x1=подстрока → номер символа или -1
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, #0
    ldrb w2, [x20]
    cbz w2, 8f
1:  ldrb w2, [x19]
    cbz w2, 7f
    mov x3, x19
    mov x4, x20
2:  ldrb w2, [x4]
    cbz w2, 6f
    ldrb w5, [x3]
    cmp w2, w5
    b.ne 3f
    add x3, x3, #1
    add x4, x4, #1
    b 2b
3:  ldrb w2, [x19]
    and w5, w2, #0xC0
    cmp w5, #0x80
    b.eq 4f
    add x21, x21, #1
4:  add x19, x19, #1
    b 1b
6:  mov x0, x21
    b 9f
7:  mov x0, #-1
    b 9f
8:  mov x0, #0
9:  ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_str_contains:                  // x0=строка, x1=подстрока → 1/0
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _bit_str_index
    cmn x0, #1
    b.ne 1f
    mov x0, #0
    ldp x29, x30, [sp], #16
    ret
1:  mov x0, #1
    ldp x29, x30, [sp], #16
    ret

_bit_str_upper:                     // x0=строка → новая строка в верхнем регистре
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    bl _strlen
    mov x20, x0
    add x0, x20, #1
    bl _bit_alloc
    mov x21, x0
    mov x22, #0
1:  cmp x22, x20
    b.hs 3f
    ldrb w2, [x19, x22]
    cmp w2, #97
    b.lo 2f
    cmp w2, #122
    b.hi 2f
    sub w2, w2, #32
2:  strb w2, [x21, x22]
    add x22, x22, #1
    b 1b
3:  strb wzr, [x21, x20]
    mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_str_lower:                     // x0=строка → новая строка в нижнем регистре
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    bl _strlen
    mov x20, x0
    add x0, x20, #1
    bl _bit_alloc
    mov x21, x0
    mov x22, #0
1:  cmp x22, x20
    b.hs 3f
    ldrb w2, [x19, x22]
    cmp w2, #65
    b.lo 2f
    cmp w2, #90
    b.hi 2f
    add w2, w2, #32
2:  strb w2, [x21, x22]
    add x22, x22, #1
    b 1b
3:  strb wzr, [x21, x20]
    mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_str_code:                      // x0=строка, x1=строка программы → код первого символа
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x1
    ldrb w2, [x0]
    cbz w2, 9f
    cmp w2, #0x80
    b.hs 1f
    mov x0, x2
    b 8f
1:  and w3, w2, #0xE0
    cmp w3, #0xC0
    b.ne 2f
    and w4, w2, #0x1F
    lsl w4, w4, #6
    ldrb w5, [x0, #1]
    and w5, w5, #0x3F
    orr w0, w4, w5
    b 8f
2:  and w3, w2, #0xF0
    cmp w3, #0xE0
    b.ne 3f
    and w4, w2, #0x0F
    lsl w4, w4, #12
    ldrb w5, [x0, #1]
    and w5, w5, #0x3F
    lsl w5, w5, #6
    orr w4, w4, w5
    ldrb w5, [x0, #2]
    and w5, w5, #0x3F
    orr w0, w4, w5
    b 8f
3:  and w4, w2, #0x07
    lsl w4, w4, #18
    ldrb w5, [x0, #1]
    and w5, w5, #0x3F
    lsl w5, w5, #12
    orr w4, w4, w5
    ldrb w5, [x0, #2]
    and w5, w5, #0x3F
    lsl w5, w5, #6
    orr w4, w4, w5
    ldrb w5, [x0, #3]
    and w5, w5, #0x3F
    orr w0, w4, w5
8:  ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_ecode_empty@PAGE
    add x0, x0, Lrt_ecode_empty@PAGEOFF
    mov x1, x19
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_die

_bit_num_char:                      // x0=код, x1=строка программы → строка из одного символа
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    tbnz x19, #63, 9f
    movz w2, #0xFFFF
    movk w2, #0x0010, lsl #16
    cmp x19, x2
    b.gt 9f
    mov x0, #5
    bl _bit_alloc
    mov x21, x0
    cmp x19, #0x80
    b.lo 1f
    cmp x19, #0x800
    b.lo 2f
    cmp x19, #0x10000
    b.lo 3f
    lsr w2, w19, #18
    orr w2, w2, #0xF0
    strb w2, [x21]
    lsr w2, w19, #12
    and w2, w2, #0x3F
    orr w2, w2, #0x80
    strb w2, [x21, #1]
    lsr w2, w19, #6
    and w2, w2, #0x3F
    orr w2, w2, #0x80
    strb w2, [x21, #2]
    and w2, w19, #0x3F
    orr w2, w2, #0x80
    strb w2, [x21, #3]
    strb wzr, [x21, #4]
    b 8f
1:  strb w19, [x21]
    strb wzr, [x21, #1]
    b 8f
2:  lsr w2, w19, #6
    orr w2, w2, #0xC0
    strb w2, [x21]
    and w2, w19, #0x3F
    orr w2, w2, #0x80
    strb w2, [x21, #1]
    strb wzr, [x21, #2]
    b 8f
3:  lsr w2, w19, #12
    orr w2, w2, #0xE0
    strb w2, [x21]
    lsr w2, w19, #6
    and w2, w2, #0x3F
    orr w2, w2, #0x80
    strb w2, [x21, #1]
    and w2, w19, #0x3F
    orr w2, w2, #0x80
    strb w2, [x21, #2]
    strb wzr, [x21, #3]
8:  mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_echar_range@PAGE
    add x0, x0, Lrt_echar_range@PAGEOFF
    mov x1, x20
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_die

_bit_str_pad:                       // x0=строка, x1=ширина, x2=заполнитель, x3=строка
    mov x4, #1
    b _bit_str_pad_do

_bit_str_pad_left:                  // x0=строка, x1=ширина, x2=заполнитель, x3=строка
    mov x4, #0
    b _bit_str_pad_do

_bit_str_pad_do:                    // x0=строка, x1=ширина в символах, x2=заполнитель, x3=строка, x4=направление
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    sub sp, sp, #96
    mov x19, x0
    mov x20, x1
    mov x21, x3
    mov x22, x4
    mov x23, x2
    tbnz x20, #63, 99f
    movz w1, #0x4240
    movk w1, #0x000F, lsl #16
    cmp x20, x1
    b.gt 99f
    mov x0, x19
    bl _strlen
    str x0, [sp, #32]
    mov x2, #0
    mov x3, #0
1:  cmp x3, x0
    b.hs 2f
    ldrb w4, [x19, x3]
    and w5, w4, #0xC0
    cmp w5, #0x80
    b.eq 11f
    add x2, x2, #1
11: add x3, x3, #1
    b 1b
2:  str x2, [sp, #40]
    mov w4, #32
    strb w4, [sp]
    mov x5, #1
    str x5, [sp, #48]
    cbz x23, 5f
    ldrb w4, [x23]
    cbz w4, 5f
    strb w4, [sp]
    cmp w4, #0xC0
    b.lo 52f
    and w6, w4, #0xF0
    cmp w6, #0xE0
    b.eq 53f
    cmp w6, #0xF0
    b.eq 54f
    mov x5, #2
    b 52f
53: mov x5, #3
    b 52f
54: mov x5, #4
52: str x5, [sp, #48]
    cmp x5, #1
    b.ls 5f
    mov x6, #1
55: ldrb w7, [x23, x6]
    strb w7, [sp, x6]
    add x6, x6, #1
    cmp x6, x5
    b.lo 55b
5:  ldr x2, [sp, #40]
    cmp x20, x2
    b.hi 6f
    mov x0, x19
    ldr x1, [sp, #32]
    bl _bit_substr
    b 8f
6:  sub x2, x20, x2
    str x2, [sp, #56]
    ldr x3, [sp, #48]
    mul x4, x2, x3
    ldr x5, [sp, #32]
    add x4, x4, x5
    str x4, [sp, #64]
    add x0, x4, #1
    bl _bit_alloc
    mov x23, x0
    cbz x22, 20f
    mov x0, x23
    mov x1, x19
    ldr x2, [sp, #32]
    bl _memcpy
    ldr x9, [sp, #56]
    ldr x10, [sp, #48]
    ldr x8, [sp, #32]
    mov x11, #0
10: cmp x11, x9
    b.hs 30f
    mov x12, #0
12: cmp x12, x10
    b.hs 13f
    ldrb w13, [sp, x12]
    strb w13, [x23, x8]
    add x8, x8, #1
    add x12, x12, #1
    b 12b
13: add x11, x11, #1
    b 10b
20: ldr x9, [sp, #56]
    ldr x10, [sp, #48]
    mov x8, #0
    mov x11, #0
21: cmp x11, x9
    b.hs 22f
    mov x12, #0
23: cmp x12, x10
    b.hs 24f
    ldrb w13, [sp, x12]
    strb w13, [x23, x8]
    add x8, x8, #1
    add x12, x12, #1
    b 23b
24: add x11, x11, #1
    b 21b
22: add x0, x23, x8
    mov x1, x19
    ldr x2, [sp, #32]
    bl _memcpy
30: ldr x4, [sp, #64]
    strb wzr, [x23, x4]
    mov x0, x23
8:  add sp, sp, #96
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
99: adrp x0, Lrt_epad_width@PAGE
    add x0, x0, Lrt_epad_width@PAGEOFF
    mov x1, x21
    add sp, sp, #96
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_die

_bit_str_repeat:                    // x0=строка, x1=раз, x2=строка → строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x22, x2
    tbnz x20, #63, 9f
    movz w21, #0xE100
    movk w21, #0x05F5, lsl #16
    cmp x20, x21
    b.gt 9f
    bl _strlen
    mov x24, x0
    cbz x20, 5f
    mul x25, x24, x20
    cmp x25, x21
    b.gt 9f
    add x0, x25, #1
    bl _bit_alloc
    mov x26, x0
    mov x23, #0
1:  cmp x23, x20
    b.hs 3f
    mov x0, x26
    mul x2, x23, x24
    add x0, x0, x2
    mov x1, x19
    mov x2, x24
    bl _memcpy
    add x23, x23, #1
    b 1b
3:  strb wzr, [x26, x25]
    mov x0, x26
    b 8f
5:  mov x0, #1
    bl _bit_alloc
    strb wzr, [x0]
8:  ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_epad_count@PAGE
    add x0, x0, Lrt_epad_count@PAGEOFF
    mov x1, x22
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_die

_bit_num_hex:                       // x0=число, x1=ширина, x2=строка → строка в hex
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    tbnz x20, #63, 9f
    cmp x20, #64
    b.gt 9f
    adrp x22, Lrt_hex@PAGE
    add x22, x22, Lrt_hex@PAGEOFF
    mov x3, x19
    mov x4, #1
1:  lsr x5, x3, #4
    cbz x5, 2f
    mov x3, x5
    add x4, x4, #1
    b 1b
2:  cmp x4, x20
    b.hs 3f
    mov x4, x20
3:  add x0, x4, #1
    mov x23, x4
    bl _bit_alloc
    mov x24, x0
    mov x3, x19
    mov x5, x23
4:  cbz x5, 6f
    sub x5, x5, #1
    and x6, x3, #0x0F
    ldrb w6, [x22, x6]
    strb w6, [x24, x5]
    lsr x3, x3, #4
    b 4b
6:  strb wzr, [x24, x23]
    mov x0, x24
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_ehex_width@PAGE
    add x0, x0, Lrt_ehex_width@PAGEOFF
    mov x1, x21
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_die

_bit_dec_fixed:                     // x0=биты dec, x1=знаков после точки, x2=строка → строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    tbnz x20, #63, 9f
    cmp x20, #17
    b.gt 9f
    mov x0, #512
    bl _bit_alloc
    mov x22, x0
    sub sp, sp, #16
    str x20, [sp]
    str x19, [sp, #8]
    mov x0, x22
    mov x1, #512
    adrp x2, Lrt_fp@PAGE
    add x2, x2, Lrt_fp@PAGEOFF
    bl _snprintf
    add sp, sp, #16
    mov x0, x22
    bl _strlen
    mov x1, x0
    mov x0, x22
    bl _bit_substr
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_efixed_places@PAGE
    add x0, x0, Lrt_efixed_places@PAGEOFF
    mov x1, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_die

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

_bit_move:                          // x0 = from, x1 = to, x2 = source line
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    bl _rename
    cbz w0, 1f
    bl ___error
    ldr w0, [x0]
    cmp w0, #18                      // EXDEV
    b.ne 9f
    mov x0, x19
    mov x1, x20
    mov x2, x21
    bl _bit_copy
    mov x0, x19
    bl _unlink
    cbnz w0, 9f
1:  ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_emv@PAGE
    add x0, x0, Lrt_emv@PAGEOFF
    mov x1, x19
    mov x2, x21
    bl _bit_errpath

_bit_copy_temp:                     // x0 = destination path; returns a sibling template
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov w1, #47
    bl _strrchr
    cbz x0, 1f
    sub x1, x0, x19
    add x1, x1, #1
    b 2f
1:  mov x1, #0
2:  mov x0, x19
    bl _bit_substr
    mov x19, x0
    adrp x1, Lrt_copy_suffix@PAGE
    add x1, x1, Lrt_copy_suffix@PAGEOFF
    bl _bit_cat
    mov x20, x0
    mov x0, x19
    bl _free
    mov x0, x20
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_copy:                          // Copy through a temporary sibling; replace only on success.
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x23, #0
    mov x24, #0
    mov x25, #0
    mov w26, #-1
    adrp x1, Lrt_rb@PAGE
    add x1, x1, Lrt_rb@PAGEOFF
    bl _fopen
    cbz x0, 9f
    mov x22, x0
    mov x0, x19
    mov x1, x20
    bl _strcmp
    cbnz w0, 1f
    mov x0, x22
    bl _fclose
    b 4f
1:  mov x0, #65536
    bl _bit_alloc
    mov x25, x0
    mov x0, x20
    bl _bit_copy_temp
    mov x24, x0
    bl _mkstemp
    tbnz w0, #31, 6f
    mov w26, w0
    adrp x1, Lrt_wb@PAGE
    add x1, x1, Lrt_wb@PAGEOFF
    bl _fdopen
    cbz x0, 5f
    mov x23, x0
    mov w26, #-1
2:  mov x0, x25
    mov x1, #1
    mov x2, #65536
    mov x3, x22
    bl _fread
    cbz x0, 3f
    str x0, [sp, #-16]!
    mov x2, x0
    mov x0, x25
    mov x1, #1
    mov x3, x23
    bl _fwrite
    ldr x1, [sp], #16
    cmp x0, x1
    b.ne 5f
    b 2b
3:  mov x0, x22
    bl _ferror
    cbnz w0, 5f
    mov x0, x23
    mov x23, #0
    bl _fclose
    cbnz w0, 5f
    mov x0, x22
    mov x22, #0
    bl _fclose
    cbnz w0, 5f
    mov x0, x24
    mov x1, x20
    bl _rename
    cbnz w0, 5f
    mov x0, x24
    bl _free
    mov x0, x25
    bl _free
4:  ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
5:  cbz x23, 51f
    mov x0, x23
    bl _fclose
51: tbnz w26, #31, 52f
    mov w0, w26
    bl _close
52: mov x0, x24
    bl _unlink
6:  cbz x22, 7f
    mov x0, x22
    bl _fclose
7:  mov x0, x24
    bl _free
    mov x0, x25
    bl _free
    adrp x0, Lrt_ewrite@PAGE
    add x0, x0, Lrt_ewrite@PAGEOFF
    mov x1, x20
    b 8f
9:  adrp x0, Lrt_eopen@PAGE
    add x0, x0, Lrt_eopen@PAGEOFF
    mov x1, x19
8:  mov x2, x21
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




_bit_remove_is_home:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    adrp x0, Lrt_remove_home@PAGE
    add x0, x0, Lrt_remove_home@PAGEOFF
    bl _getenv
    cbz x0, 7f
    ldrb w1, [x0]
    cbz w1, 7f
    mov x1, #0
    bl _realpath
    cbz x0, 7f
    mov x20, x0
    mov x0, x19
    mov x1, #0
    bl _realpath
    mov x21, x0
    mov x19, #0
    cbz x0, 1f
    mov x2, #0
2:  ldrb w3, [x21, x2]
    cbz w3, 3f
    ldrb w4, [x20, x2]
    cmp w3, w4
    b.ne 1f
    add x2, x2, #1
    b 2b
3:  sub x3, x2, #1
    ldrb w3, [x21, x3]
    cmp w3, #47
    b.eq 4f
    ldrb w3, [x20, x2]
    cbz w3, 4f
    cmp w3, #47
    b.ne 1f
4:  mov x19, #1
1:  mov x0, x20
    bl _free
    mov x0, x21
    bl _free
    mov x0, x19
    b 8f
7:  mov x0, #0
8:  ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_remove_error:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x1
    mov x20, x2
    bl _bit_cat
    str x0, [sp, #-16]!
    mov x0, x19
    bl _free
    ldr x0, [sp], #16
    mov x1, x20
    bl _bit_die

_bit_remove_prefix:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x1
    adrp x1, Lrt_slash@PAGE
    add x1, x1, Lrt_slash@PAGEOFF
    bl _bit_cat
    mov x20, x0
    mov x1, x19
    bl _bit_cat
    mov x21, x0
    mov x0, x20
    bl _free
    mov x0, x19
    bl _free
    mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_dir_remove_all:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x20, x1
    adrp x1, Lrt_empty@PAGE
    add x1, x1, Lrt_empty@PAGEOFF
    bl _bit_cat
    mov x19, x0
    bl _strlen
    cbz x0, 8f
1:  cmp x0, #1
    b.ls 2f
    sub x1, x0, #1
    ldrb w2, [x19, x1]
    cmp w2, #47
    b.ne 2f
    mov x0, x1
    strb wzr, [x19, x1]
    b 1b
2:  ldrb w1, [x19]
    cmp w1, #47
    b.ne 3f
    ldrb w1, [x19, #1]
    cbz w1, 8f
3:  mov x0, x19
    mov x1, #47
    bl _strrchr
    cbnz x0, 4f
    sub x0, x19, #1
4:  add x0, x0, #1
    ldrb w1, [x0]
    cmp w1, #46
    b.ne 5f
    ldrb w1, [x0, #1]
    cbz w1, 8f
    cmp w1, #46
    b.ne 5f
    ldrb w1, [x0, #2]
    cbz w1, 8f
5:  mov x0, x19
    bl _bit_remove_is_home
    cbnz x0, 11f
    mov x0, #-2
    mov x1, x19
    mov x2, x20
    mov x3, #1
    bl _bit_remove_at
    mov x21, x0
    mov x0, x19
    bl _free
    cbnz x21, 9f
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
8:  adrp x0, Lrt_ermroot@PAGE
    add x0, x0, Lrt_ermroot@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_remove_error
11: adrp x0, Lrt_ermhome@PAGE
    add x0, x0, Lrt_ermhome@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_remove_error
9:  adrp x0, Lrt_ermtree@PAGE
    add x0, x0, Lrt_ermtree@PAGEOFF
    mov x1, x21
    mov x2, x20
    bl _bit_remove_error

_bit_remove_at:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    sub sp, sp, #160
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x24, x3
    mov x2, sp
    mov x3, #32
    bl _fstatat
    cbnz w0, 9f
    ldrh w1, [sp, #4]
    and w1, w1, #0xf000
    cmp w1, #0x4000
    b.eq 2f
    cbz x24, 1f
    cmp w1, #0xa000
    b.ne 9f
1:  mov x0, x19
    mov x1, x20
    mov x2, #0
    bl _unlinkat
    cbnz w0, 9f
    b 7f
2:  mov x0, x19
    mov x1, x20
    mov x2, #256
    movk x2, #16, lsl #16
    bl _openat
    tbnz w0, #31, 9f
    mov x23, x0
    bl _fdopendir
    cbz x0, 6f
    mov x22, x0
3:  bl ___error
    str wzr, [x0]
    mov x0, x22
    bl _readdir
    cbz x0, 5f
    add x1, x0, #21
    ldrb w2, [x1]
    cmp w2, #46
    b.ne 4f
    ldrb w2, [x1, #1]
    cbz w2, 3b
    cmp w2, #46
    b.ne 4f
    ldrb w2, [x1, #2]
    cbz w2, 3b
4:  mov x0, x23
    mov x2, x21
    mov x3, #0
    bl _bit_remove_at
    cbnz x0, 8f
    b 3b
5:  bl ___error
    ldr w1, [x0]
    cbnz w1, 11f
    mov x0, x22
    bl _closedir
    cbnz w0, 9f
    mov x0, x19
    mov x1, x20
    mov x2, #128
    bl _unlinkat
    cbnz w0, 9f
    b 7f
6:  mov x0, x23
    bl _close
    b 9f
7:  mov x0, #0
    b 10f
8:  mov x24, x0
    mov x0, x22
    bl _closedir
    mov x0, x20
    mov x1, x24
    bl _bit_remove_prefix
    b 10f
11: mov x0, x22
    bl _closedir
9:  mov x0, x20
    adrp x1, Lrt_empty@PAGE
    add x1, x1, Lrt_empty@PAGEOFF
    bl _bit_cat
10: add sp, sp, #160
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_path_mode:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    sub sp, sp, #160
    mov x19, x0
    mov x20, x1
    mov x1, sp
    bl _stat
    cbnz w0, 9f
    ldrh w0, [sp, #4]
    add sp, sp, #160
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_epermread@PAGE
    add x0, x0, Lrt_epermread@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_mode_set:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x20, x2
    bl _chmod
    cbnz w0, 9f
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_epermwrite@PAGE
    add x0, x0, Lrt_epermwrite@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_permissions_parse:             // text, line -> permission bits
    mov x3, #0
    mov x4, #256
    mov x5, #0
    adrp x6, Lrt_permchars@PAGE
    add x6, x6, Lrt_permchars@PAGEOFF
1:  ldrb w7, [x0, x5]
    cmp w7, #45
    b.eq 2f
    ldrb w8, [x6, x5]
    cmp w7, w8
    b.ne 9f
    orr x3, x3, x4
2:  lsr x4, x4, #1
    add x5, x5, #1
    cmp x5, #9
    b.ne 1b
    ldrb w7, [x0, #9]
    cbnz w7, 9f
    mov x0, x3
    ret
9:  adrp x0, Lrt_epermissions@PAGE
    add x0, x0, Lrt_epermissions@PAGEOFF
    b _bit_die

_bit_permissions_text:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x0, #10
    bl _bit_alloc
    mov x2, #0
    mov x3, #256
    adrp x4, Lrt_permchars@PAGE
    add x4, x4, Lrt_permchars@PAGEOFF
1:  mov w5, #45
    tst x19, x3
    b.eq 2f
    ldrb w5, [x4, x2]
2:  strb w5, [x0, x2]
    lsr x3, x3, #1
    add x2, x2, #1
    cmp x2, #9
    b.ne 1b
    strb wzr, [x0, #9]
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_permissions_get:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _bit_path_mode
    bl _bit_permissions_text
    ldp x29, x30, [sp], #16
    ret

_bit_permissions_set:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x20, x2
    mov x0, x1
    mov x1, x2
    bl _bit_permissions_parse
    mov x1, x0
    mov x0, x19
    mov x2, x20
    bl _bit_mode_set
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_read_only_get:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _bit_path_mode
    mov x1, #146
    tst x0, x1
    cset x0, eq
    ldp x29, x30, [sp], #16
    ret

_bit_read_only_set:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x1, x2
    bl _bit_path_mode
    and x1, x0, #4095
    mov x2, #146
    cbz x20, 1f
    bic x1, x1, x2
    b 2f
1:  orr x1, x1, x2
2:  mov x0, x19
    mov x2, x21
    bl _bit_mode_set
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_lkind:                         // x0 = путь → как _bit_kind, но ссылка — 3 (не заходим по ней)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #160
    mov x1, sp
    bl _lstat
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

_bit_file_mtime:                    // x0 = путь, x1 = строка → время изменения (секунды с 1970)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    sub sp, sp, #160
    mov x19, x0
    mov x20, x1
    mov x1, sp
    bl _stat
    cbnz w0, 9f
    ldr x0, [sp, #48]
    add sp, sp, #160
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:
    adrp x0, Lrt_eread@PAGE
    add x0, x0, Lrt_eread@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_dir_walk:                      // x0 = путь, x1 = строка → mas путей ко всем файлам внутри
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x0, #-1
    mov x1, #0
    bl _bit_mas_new
    mov x21, x0
    mov x0, x19
    mov x1, x21
    mov x2, x20
    bl _bit_walk_into
    mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_walk_into:                     // x0 = путь, x1 = mas, x2 = строка
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x1, x21
    bl _bit_dir_list
    mov x22, x0
    mov x23, #0
1:  ldr x9, [x22, #8]
    cmp x23, x9
    b.ge 5f
    mov x0, x19
    adrp x1, Lrt_slash@PAGE
    add x1, x1, Lrt_slash@PAGEOFF
    bl _bit_cat
    ldr x9, [x22]
    ldr x1, [x9, x23, lsl #3]
    bl _bit_cat
    mov x24, x0
    bl _bit_lkind
    cmp x0, #2
    b.ne 2f
    mov x0, x24
    mov x1, x20
    mov x2, x21
    bl _bit_walk_into
    b 4f
2:  mov x0, x24
    bl _bit_kind
    cmp x0, #1
    b.ne 4f
    mov x0, x20
    mov x1, x24
    mov x2, x21
    bl _bit_mas_add
4:  add x23, x23, #1
    b 1b
5:  ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret


_bit_path_info:                     // path, line -> path, size, modified, kind
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    sub sp, sp, #160
    mov x19, x0
    mov x20, x1
    mov x1, sp
    bl _lstat
    cbnz w0, 9f
    ldrh w1, [sp, #4]
    and w1, w1, #0xf000
    cmp w1, #0xa000
    b.ne 1f
    mov x0, x19
    mov x1, sp
    bl _stat
    cbnz w0, 7f
    ldrh w1, [sp, #4]
    and w1, w1, #0xf000
    cmp w1, #0x8000
    b.ne 7f
1:  mov x21, #1
    cmp w1, #0x8000
    b.eq 2f
    mov x21, #2
    cmp w1, #0x4000
    b.ne 7f
2:  mov x0, #32
    bl _bit_alloc
    str x19, [x0]
    ldr x1, [sp, #96]
    str x1, [x0, #8]
    ldr x1, [sp, #48]
    str x1, [x0, #16]
    str x21, [x0, #24]
    b 8f
7:  mov x0, #0
8:  add sp, sp, #160
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_eread@PAGE
    add x0, x0, Lrt_eread@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_dir_walk_info:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x0, #-1
    mov x1, #0
    bl _bit_mas_new
    mov x21, x0
    mov x0, x19
    mov x1, x21
    mov x2, x20
    bl _bit_walk_info_into
    mov x0, x21
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_walk_info_into:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x1, x21
    bl _bit_dir_list
    mov x22, x0
    mov x23, #0
1:  ldr x9, [x22, #8]
    cmp x23, x9
    b.ge 5f
    mov x0, x19
    adrp x1, Lrt_slash@PAGE
    add x1, x1, Lrt_slash@PAGEOFF
    bl _bit_cat
    mov x25, x0
    ldr x9, [x22]
    ldr x1, [x9, x23, lsl #3]
    bl _bit_cat
    mov x24, x0
    mov x0, x25
    bl _free
    mov x0, x24
    mov x1, x21
    bl _bit_path_info
    cbz x0, 4f
    ldr x9, [x0, #24]
    cmp x9, #2
    b.ne 2f
    mov x25, x0
    mov x0, x24
    mov x1, x20
    mov x2, x21
    bl _bit_walk_info_into
    mov x0, x25
    bl _free
    b 4f
2:  mov x1, x0
    mov x0, x20
    mov x2, x21
    bl _bit_mas_add
    b 3f
4:  mov x0, x24
    bl _free
3:  ldr x9, [x22]
    ldr x0, [x9, x23, lsl #3]
    bl _free
    add x23, x23, #1
    b 1b
5:  ldr x0, [x22]
    bl _free
    mov x0, x22
    bl _free
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// ── proc (macOS): процессы без доступа к их памяти ──
_bit_mac_pname:                     // x0 = pid, x1 = буфер 256 байт → длина имени или 0
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    sub sp, sp, #688
    mov x19, x0
    mov x20, x1
    mov w2, #256
    bl _proc_name
    cmp w0, #0
    b.gt 9f
    // чужие системные процессы: имя через sysctl (как у ps)
    mov w9, #1
    str w9, [sp]
    mov w9, #14
    str w9, [sp, #4]
    mov w9, #1
    str w9, [sp, #8]
    str w19, [sp, #12]
    mov x9, #648
    str x9, [sp, #16]
    mov x0, sp
    mov w1, #4
    add x2, sp, #32
    add x3, sp, #16
    mov x4, #0
    mov x5, #0
    bl _sysctl
    cbnz w0, 0f
    ldr x9, [sp, #16]
    cmp x9, #648
    b.ne 0f
    mov x0, x20
    add x1, sp, #275
    mov x2, #17
    bl _strlcpy
    cmp x0, #0
    b.gt 9f
0:  mov x0, #0
9:  add sp, sp, #688
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_proc_start:                    // x0 = команда, x1 = строка → pid (через /bin/sh -c)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    sub sp, sp, #48
    mov x19, x0
    mov x20, x1
    mov x0, #0
    bl _fflush
    adrp x9, Lrt_msh@PAGE
    add x9, x9, Lrt_msh@PAGEOFF
    str x9, [sp, #8]
    adrp x9, Lrt_mdashc@PAGE
    add x9, x9, Lrt_mdashc@PAGEOFF
    str x9, [sp, #16]
    str x19, [sp, #24]
    str xzr, [sp, #32]
    mov x0, sp
    adrp x1, Lrt_mbinsh@PAGE
    add x1, x1, Lrt_mbinsh@PAGEOFF
    mov x2, #0
    mov x3, #0
    add x4, sp, #8
    adrp x9, _environ@GOTPAGE
    ldr x9, [x9, _environ@GOTPAGEOFF]
    ldr x5, [x9]
    bl _posix_spawn
    cbnz w0, 9f
    ldrsw x0, [sp]
    add sp, sp, #48
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_mespawn@PAGE
    add x0, x0, Lrt_mespawn@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_proc_find:                     // x0 = имя, x1 = строка → pid первого процесса с таким именем или -1
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    sub sp, sp, #256
    mov x19, x0
    mov x20, x1
    mov x0, #262144
    bl _malloc
    cbz x0, 8f
    mov x21, x0
    mov w1, #262144
    bl _proc_listallpids
    sxtw x22, w0
    mov x23, #0
1:  cmp x23, x22
    b.ge 7f
    ldr w0, [x21, x23, lsl #2]
    cmp w0, #0
    b.le 2f
    mov x1, sp
    mov w2, #256
    bl _bit_mac_pname
    cmp w0, #0
    b.le 2f
    mov x0, sp
    mov x1, x19
    bl _strcmp
    cbz w0, 6f
2:  add x23, x23, #1
    b 1b
6:  ldrsw x24, [x21, x23, lsl #2]
    b 5f
7:  mov x24, #-1
5:  mov x0, x21
    bl _free
    mov x0, x24
    b 4f
8:  mov x0, #-1
4:  add sp, sp, #256
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_proc_alive:                    // x0 = pid → 1 если процесс работает (завершённый, но не дождавшийся — нет)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    sub sp, sp, #144
    mov x19, x0
    cmp x0, #0
    b.le 0f
    mov w1, #3
    mov x2, #0
    mov x3, sp
    mov w4, #136
    bl _proc_pidinfo
    cmp w0, #136
    b.ne 3f
    ldr w1, [sp, #4]
    cmp w1, #5
    b.eq 0f
    mov x0, #1
    b 9f
3:  mov x0, x19
    mov w1, #0
    bl _kill
    cbz w0, 1f
    bl ___error
    ldr w1, [x0]
    cmp w1, #1
    b.ne 0f
1:  mov x0, #1
    b 9f
0:  mov x0, #0
9:  add sp, sp, #144
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_proc_name:                     // x0 = pid → имя процесса или ""
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #272
    cmp x0, #0
    b.le 1f
    mov x1, sp
    mov w2, #256
    bl _bit_mac_pname
    cmp w0, #0
    b.le 1f
    mov x0, sp
    adrp x1, Lrt_empty@PAGE
    add x1, x1, Lrt_empty@PAGEOFF
    bl _bit_cat
    b 2f
1:  adrp x0, Lrt_empty@PAGE
    add x0, x0, Lrt_empty@PAGEOFF
    mov x1, x0
    bl _bit_cat
2:  add sp, sp, #272
    ldp x29, x30, [sp], #16
    ret

_bit_proc_wait:                     // x0 = pid → код выхода (-1, если это не наш процесс)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #16
    cmp x0, #0
    b.le 1f
    mov x1, sp
    mov w2, #0
    bl _waitpid
    cmp w0, #0
    b.lt 1f
    ldr w0, [sp]
    bl _bit_wstatus
    b 2f
1:  mov x0, #-1
2:  add sp, sp, #16
    ldp x29, x30, [sp], #16
    ret

_bit_proc_kill:                     // x0 = pid, x1 = строка: просит процесс завершиться (SIGTERM)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    cmp x0, #0
    b.le 9f
    mov w1, #15
    bl _kill
    cbnz w0, 9f
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  mov x0, x19
    bl _bit_num_str
    mov x1, x0
    adrp x0, Lrt_mekill@PAGE
    add x0, x0, Lrt_mekill@PAGEOFF
    mov x2, x20
    bl _bit_errpath
// ── конец proc (macOS) ──

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
    adrp x1, Lrt_empty@PAGE
    add x1, x1, Lrt_empty@PAGEOFF
    bl _bit_cat
    ldp x29, x30, [sp], #16
    ret

_bit_mkdtemp:                      // template, source line -> owned directory path
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x1
    adrp x1, Lrt_empty@PAGE
    add x1, x1, Lrt_empty@PAGEOFF
    bl _bit_cat
    mov x20, x0
    bl _strlen
    cmp x0, #6
    b.lt 9f
    add x9, x20, x0
    sub x9, x9, #6
    mov x10, #0
1:  ldrb w11, [x9, x10]
    cmp w11, #88
    b.ne 9f
    add x10, x10, #1
    cmp x10, #6
    b.lt 1b
    mov x0, x20
    bl _mkdtemp
    cbz x0, 9f
    mov x0, x20
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  mov x0, x20
    bl _free
    adrp x0, Lrt_etmp@PAGE
    add x0, x0, Lrt_etmp@PAGEOFF
    mov x1, x19
    bl _bit_die

_bit_term_folder:                   // x0 = строка программы → текущая папка (новая строка)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x0, #0
    mov x1, #0
    bl _getcwd
    cbz x0, 9f
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_ecwd@PAGE
    add x0, x0, Lrt_ecwd@PAGEOFF
    mov x1, x19
    bl _bit_die

_bit_term_go:                       // x0 = путь, x1 = строка программы
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    bl _chdir
    cbnz w0, 9f
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_ego@PAGE
    add x0, x0, Lrt_ego@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

_bit_env_set:                       // x0 = имя, x1 = значение, x2 = строка программы
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x20, x2
    mov x2, #1
    bl _setenv
    cbnz w0, 9f
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_eenv@PAGE
    add x0, x0, Lrt_eenv@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl _bit_errpath

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

_bit_wait:                          // x0 = milliseconds
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    sub sp, sp, #32                 // timespec request and remainder
    mov x19, x0
    mov x0, #0
    bl _fflush
1:  cmp x19, #0
    b.le 3f
    mov x20, #1000
    cmp x19, x20
    csel x20, x19, x20, lt
    sub x19, x19, x20
    mov x2, #1000
    udiv x3, x20, x2
    msub x4, x3, x2, x20
    str x3, [sp]
    mov x2, #0x4240
    movk x2, #15, lsl #16
    mul x4, x4, x2
    str x4, [sp, #8]
2:  mov x0, sp
    add x1, sp, #16
    bl _nanosleep
    cbz w0, 1b
    bl ___error
    ldr w0, [x0]
    cmp w0, #4                     // EINTR
    b.ne 3f
    ldp x2, x3, [sp, #16]
    stp x2, x3, [sp]
    b 2b
3:  add sp, sp, #32
    ldp x19, x20, [sp], #16
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
    mov x1, #0
    bl _bit_substr
10:
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_file_line:                     // path, index, source line -> independent copy
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x20, x1
    mov x1, x2
    bl _bit_file_read
    mov x19, x0
    mov x21, x0
    tbnz x20, #63, 4f
1:  cbz x20, 2f
    ldrb w2, [x21], #1
    cbz w2, 4f
    cmp w2, #10
    b.ne 1b
    sub x20, x20, #1
    b 1b
2:  mov x22, x21
3:  ldrb w2, [x21]
    cbz w2, 5f
    cmp w2, #10
    b.eq 5f
    add x21, x21, #1
    b 3b
4:  adrp x22, Lrt_empty@PAGE
    add x22, x22, Lrt_empty@PAGEOFF
    mov x21, x22
5:  mov x0, x22
    sub x1, x21, x22
    bl _bit_substr
    mov x23, x0
    mov x0, x19
    bl _free
    mov x0, x23
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
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

_bit_file_load_at:                  // path, offset, count, source line -> bytes
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x3
    tbnz x20, #63, 9f
    tbnz x21, #63, 9f
    mov x0, x21
    bl _bit_bytes_new
    mov x23, x0
    mov x0, x19
    adrp x1, Lrt_rb@PAGE
    add x1, x1, Lrt_rb@PAGEOFF
    bl _fopen
    cbz x0, 8f
    mov x24, x0
    mov x1, x20
    mov w2, #0
    bl _fseeko
    cbnz w0, 7f
    ldr x0, [x23]
    mov x1, #1
    mov x2, x21
    mov x3, x24
    bl _fread
    str x0, [x23, #8]
    mov x0, x24
    bl _ferror
    cbnz w0, 7f
    mov x0, x24
    bl _fclose
    cbnz w0, 8f
    mov x0, x23
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
7:  mov x0, x24
    bl _fclose
8:  mov x0, x23
    bl _bit_bytes_free
    adrp x0, Lrt_eread@PAGE
    add x0, x0, Lrt_eread@PAGEOFF
    mov x1, x19
    mov x2, x22
    bl _bit_errpath
9:  adrp x0, Lrt_echunk@PAGE
    add x0, x0, Lrt_echunk@PAGEOFF
    mov x1, x22
    bl _bit_die

_bit_file_save_at:                  // path, bytes, offset, source line
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x3
    tbnz x21, #63, 9f
    sub sp, sp, #16
    mov w1, #513                    // O_WRONLY | O_CREAT (Darwin)
    mov x2, #438                    // 0666, variadic argument on the Darwin stack
    str x2, [sp]
    bl _open
    add sp, sp, #16
    tbnz w0, #31, 8f
    mov w23, w0
    adrp x1, Lrt_wb@PAGE
    add x1, x1, Lrt_wb@PAGEOFF
    bl _fdopen                      // does not truncate an existing descriptor
    cbz x0, 6f
    mov x23, x0
    mov x1, x21
    mov w2, #0
    bl _fseeko
    cbnz w0, 7f
    ldr x0, [x20]
    mov x1, #1
    ldr x2, [x20, #8]
    mov x3, x23
    bl _fwrite
    ldr x2, [x20, #8]
    cmp x0, x2
    b.ne 7f
    mov x0, x23
    bl _fclose
    cbnz w0, 8f
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
6:  mov w0, w23
    bl _close
    b 8f
7:  mov x0, x23
    bl _fclose
8:  adrp x0, Lrt_ewrite@PAGE
    add x0, x0, Lrt_ewrite@PAGEOFF
    mov x1, x19
    mov x2, x22
    bl _bit_errpath
9:  adrp x0, Lrt_echunk@PAGE
    add x0, x0, Lrt_echunk@PAGEOFF
    mov x1, x22
    bl _bit_die

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

_bit_drop_str:                      // release an adopted string reference
    b _bit_str_release

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
    add x4, sp, #15
    cmp x21, x4
    b.hs 9f
    strb w2, [x21]
    add x19, x19, #1
    add x21, x21, #1
    b 1b
2:  strb wzr, [x21]
    add x19, x19, #1
    mov w3, #0
    ldrb w2, [x19]
    cbz w2, 9f
3:  ldrb w2, [x19]
    cbz w2, 4f
    sub w4, w2, #48
    cmp w4, #9
    b.hi 9f
    mov w5, #6553
    cmp w3, w5
    b.hi 9f
    b.ne 5f
    cmp w4, #5
    b.hi 9f
5:  mov w5, #10
    mul w3, w3, w5
    add w3, w3, w4
    add x19, x19, #1
    b 3b
4:  str xzr, [x22]
    str xzr, [x22, #8]
    mov w2, #0x210                 // Darwin sin_len and AF_INET
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
8:  bl _bit_errno_code
    bl _bit_set_errcode
    mov w0, w19
    bl _close
    b 10f
9:  mov x0, #0
    bl _bit_set_errcode
10: add sp, sp, #112
    adrp x0, Lrt_enet@PAGE
    add x0, x0, Lrt_enet@PAGEOFF
    mov x1, x20
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    bl _bit_die

_bit_tcp_connect_timed:               // x0 = "ip:port", x1 = таймаут мс, x2 = строка -> TCP conn
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    sub sp, sp, #112
    mov x20, x2                       // строка исходника
    mov w21, w1                       // таймаут мс
    tbnz x1, #63, 10f
    mov x4, #2147483647
    cmp x1, x4
    b.gt 10f
    add x22, sp, #0                   // буфер адреса
1:  ldrb w3, [x0]
    cbz w3, 9f                        // пустой адрес
    cmp w3, #58
    b.eq 2f
    add x4, sp, #15
    cmp x22, x4
    b.hs 9f
    strb w3, [x22]
    add x0, x0, #1
    add x22, x22, #1
    b 1b
2:  strb wzr, [x22]
    add x0, x0, #1
    mov w3, #0
    ldrb w4, [x0]
    cbz w4, 9f
3:  ldrb w4, [x0]
    cbz w4, 4f
    sub w5, w4, #48
    cmp w5, #9
    b.hi 9f
    mov w6, #6553
    cmp w3, w6
    b.hi 9f
    b.ne 5f
    cmp w5, #5
    b.hi 9f
5:  mov w6, #10
    mul w3, w3, w6
    add w3, w3, w5
    add x0, x0, #1
    b 3b
4:  str xzr, [sp, #80]
    str xzr, [sp, #88]
    mov w4, #2
    strh w4, [sp, #80]
    lsl w5, w3, #8
    lsr w6, w3, #8
    orr w5, w5, w6
    strh w5, [sp, #82]
    mov w0, #2
    add x1, sp, #0
    add x2, sp, #84
    bl _inet_pton
    cmp w0, #1
    b.ne 9f
    mov w0, #2
    mov w1, #1
    mov w2, #0
    bl _socket
    tbnz w0, #31, 9f
    mov w19, w0                       // сокет
    mov w0, w19
    mov w1, #3                        // F_GETFL
    bl _fcntl
    tbnz w0, #31, 8f
    orr w0, w0, #4               // O_NONBLOCK (Darwin)
    mov w22, w0
    mov w0, w19
    mov w1, #4                        // F_SETFL
    sub sp, sp, #16
    str w22, [sp]                     // Darwin ARM64 variadic argument
    bl _fcntl
    add sp, sp, #16
    tbnz w0, #31, 8f
    mov w0, w19
    add x1, sp, #80
    mov w2, #16
    bl _connect
    cbz w0, 11f                       // подключился сразу
    bl ___error
    ldr w0, [x0]
    cmp w0, #36                       // EINPROGRESS (Darwin)
    b.ne 7f
    str w19, [sp, #32]
    mov w4, #4                        // POLLOUT; revents = 0
    str w4, [sp, #36]
    add x0, sp, #32
    mov w1, #1
    mov w2, w21
    bl _poll
    cbz w0, 6f                        // истёк таймаут
    tbnz w0, #31, 7f                  // ошибка poll
11: mov w0, w19
    mov w1, #65535                    // SOL_SOCKET (Darwin)
    mov w2, #4103                     // SO_ERROR
    add x3, sp, #96
    mov w4, #4
    str w4, [sp, #100]
    add x4, sp, #100
    bl _getsockopt
    tbnz w0, #31, 7f
    ldr w0, [sp, #96]
    cbz w0, 12f                       // ошибки нет — подключён
    bl _bit_errno_map
    bl _bit_set_errcode
    mov w0, w19
    bl _close
    adrp x0, Lrt_enet@PAGE
    add x0, x0, Lrt_enet@PAGEOFF
    b 71f
12: mov w0, w19
    mov w1, #3                        // F_GETFL
    bl _fcntl
    tbnz w0, #31, 8f
    mov w4, #4
    bic w0, w0, w4                    // снять O_NONBLOCK (Darwin)
    mov w22, w0
    mov w0, w19
    mov w1, #4                        // F_SETFL
    sub sp, sp, #16
    str w22, [sp]                     // Darwin ARM64 variadic argument
    bl _fcntl
    add sp, sp, #16
    tbnz w0, #31, 8f
    mov w0, w19
    add sp, sp, #112
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
6:  mov x0, #2
    bl _bit_set_errcode
    mov w0, w19
    bl _close
    adrp x0, Lrt_econn_timeout@PAGE
    add x0, x0, Lrt_econn_timeout@PAGEOFF
    b 71f
7:  bl _bit_errno_code
    bl _bit_set_errcode
    mov w0, w19
    bl _close
    adrp x0, Lrt_enet@PAGE
    add x0, x0, Lrt_enet@PAGEOFF
    b 71f
8:  mov x0, #0
    bl _bit_set_errcode
    mov w0, w19
    bl _close
    adrp x0, Lrt_enet@PAGE
    add x0, x0, Lrt_enet@PAGEOFF
    b 71f
9:  mov x0, #0
    bl _bit_set_errcode
    adrp x0, Lrt_enet@PAGE
    add x0, x0, Lrt_enet@PAGEOFF
    b 71f
10: mov x0, #0
    bl _bit_set_errcode
    adrp x0, Lrt_econn_args@PAGE
    add x0, x0, Lrt_econn_args@PAGEOFF
71: mov x1, x20
    add sp, sp, #112
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _bit_die

_bit_tcp_listen:                    // port, line -> server
    mov x2, x1
    mov x1, #0
    b _bit_tcp_listen_at

_bit_tcp_listen_at:                 // port, IPv4 address or null, line -> server
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    sub sp, sp, #32
    mov x19, x0
    mov x20, x1
    mov x22, x2
    mov x21, #-1
    cmp x19, #0
    b.lt 9f
    mov x3, #65535
    cmp x19, x3
    b.gt 9f
    stp xzr, xzr, [sp]
    mov w3, #0x210                   // Darwin sockaddr_in: length 16, AF_INET 2
    strh w3, [sp]
    rev16 w3, w19
    strh w3, [sp, #2]
    cbz x20, 1f
    mov w0, #2
    mov x1, x20
    add x2, sp, #4
    bl _inet_pton
    cmp w0, #1
    b.ne 8f
1:  mov w0, #2
    mov w1, #1
    mov w2, #0
    bl _socket
    tbnz w0, #31, 9f
    mov w21, w0
    mov w3, #1
    str w3, [sp, #16]
    mov w0, w21
    mov w1, #0xffff                 // Darwin SOL_SOCKET
    mov w2, #4                      // Darwin SO_REUSEADDR
    add x3, sp, #16
    mov w4, #4
    bl _setsockopt
    cbnz w0, 7f
    mov w0, w21
    mov x1, sp
    mov w2, #16
    bl _bind
    cbnz w0, 7f
    mov w0, w21
    mov w1, #16
    bl _listen
    cbnz w0, 7f
    mov w0, w21
    add sp, sp, #32
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
7:  mov w0, w21
    bl _close
9:  adrp x0, Lrt_elisten@PAGE
    add x0, x0, Lrt_elisten@PAGEOFF
    b 6f
8:  adrp x0, Lrt_elisten_addr@PAGE
    add x0, x0, Lrt_elisten_addr@PAGEOFF
6:  mov x1, x22
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

_bit_sock_peer:                     // socket, source line -> owned "IPv4:port"
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    sub sp, sp, #64
    mov x19, x1
    mov w2, #16
    str w2, [sp, #16]
    mov x1, sp
    add x2, sp, #16
    bl _getpeername
    cbnz w0, 9f
    ldrh w21, [sp, #2]
    rev16 w21, w21
    mov w0, #2
    add x1, sp, #4
    add x2, sp, #32
    mov w3, #16
    bl _inet_ntop
    cbz x0, 9f
    add x0, sp, #32
    adrp x1, Lrt_peer_colon@PAGE
    add x1, x1, Lrt_peer_colon@PAGEOFF
    bl _bit_cat
    mov x22, x0
    mov x0, x21
    bl _bit_num_str
    mov x23, x0
    mov x1, x0
    mov x0, x22
    bl _bit_cat
    mov x24, x0
    mov x0, x22
    bl _free
    mov x0, x23
    bl _free
    mov x0, x24
    add sp, sp, #64
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_epeer@PAGE
    add x0, x0, Lrt_epeer@PAGEOFF
    mov x1, x19
    bl _bit_die

_bit_sock_send_bytes:               // socket, bytes, source line
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    sub sp, sp, #16
    mov x19, x0
    ldr x20, [x1]
    ldr x21, [x1, #8]
    mov x22, x2
    mov w9, #1
    str w9, [sp]
    mov w0, w19
    mov w1, #65535
    mov w2, #4130
    mov x3, sp
    mov w4, #4
    bl _setsockopt
    cbnz w0, 9f
1:  mov w0, w19
    mov x1, x20
    mov x2, x21
    mov w3, #0
    bl _send
    cmp x0, #0
    b.gt 2f
    cbz x0, 5f
    bl ___error
    ldr w0, [x0]
    cmp w0, #4
    b.eq 1b
    b 9f
2:  add x20, x20, x0
    sub x21, x21, x0
    cbnz x21, 1b
    b 3f
5:  cbz x21, 3f
    b 9f
3:  add sp, sp, #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_esend@PAGE
    add x0, x0, Lrt_esend@PAGEOFF
    mov x1, x22
    bl _bit_die

_bit_sock_send:                     // x0 = conn, x1 = строка, x2 = строка программы
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    sub sp, sp, #16
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x0, x20
    bl _strlen
    stp x20, x0, [sp]
    mov x0, x19
    mov x1, sp
    mov x2, x21
    bl _bit_sock_send_bytes
    add sp, sp, #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

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
9:  mov x0, x21
    bl _free
    adrp x0, Lrt_erecv@PAGE
    add x0, x0, Lrt_erecv@PAGEOFF
    mov x1, x20
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    bl _bit_die

_bit_sock_recv_timed:               // socket, count, timeout in ms, source line -> string
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    sub sp, sp, #16
    mov x19, x0
    mov x20, x1
    mov x21, x3
    mov w4, #2147483647
    cmp x20, #1
    b.lt 9f
    cmp x20, x4
    b.gt 9f
    tbnz x2, #63, 9f
    cmp x2, x4
    b.gt 9f
    mov x24, x2
    mov x0, x21
    bl _bit_os_clock
    add x23, x0, x24              // absolute deadline
    str w19, [sp]
1:  mov w4, #1                     // POLLIN; clear revents
    str w4, [sp, #4]
    mov x0, sp
    mov w1, #1
    mov x2, x24
    bl _poll
    cbz w0, 8f
    tbz w0, #31, 2f
    bl ___error
    ldr w0, [x0]
    cmp w0, #4                     // EINTR
    b.ne 7f
    mov x0, x21
    bl _bit_os_clock
    subs x24, x23, x0
    b.le 8f
    b 1b
2:
    add x0, x20, #1
    bl _bit_alloc
    mov x22, x0
    mov w0, w19
    mov x1, x22
    mov x2, x20
    mov w3, #0
    bl _recv
    tbnz x0, #63, 6f
    strb wzr, [x22, x0]
    mov x0, x22
    add sp, sp, #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
6:  mov x0, x22
    bl _free
7:  adrp x0, Lrt_erecv@PAGE
    add x0, x0, Lrt_erecv@PAGEOFF
    b 5f
8:  mov x0, #2
    bl _bit_set_errcode
    adrp x0, Lrt_erecv_timeout@PAGE
    add x0, x0, Lrt_erecv_timeout@PAGEOFF
    b 5f
9:  adrp x0, Lrt_erecv_args@PAGE
    add x0, x0, Lrt_erecv_args@PAGEOFF
5:  mov x1, x21
    bl _bit_die

_bit_sock_recv_bytes:               // socket, count, timeout ms, source line -> bytes
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    sub sp, sp, #16
    mov x19, x0
    mov x20, x1
    mov x21, x3
    mov w4, #2147483647
    cmp x20, #1
    b.lt 9f
    cmp x20, x4
    b.gt 9f
    tbnz x2, #63, 9f
    cmp x2, x4
    b.gt 9f
    mov x24, x2
    mov x0, x21
    bl _bit_os_clock
    add x23, x0, x24
    str w19, [sp]
1:  mov w4, #1
    str w4, [sp, #4]
    mov x0, sp
    mov w1, #1
    mov x2, x24
    bl _poll
    cbz w0, 8f
    tbz w0, #31, 2f
    bl ___error
    ldr w0, [x0]
    cmp w0, #4
    b.ne 7f
    mov x0, x21
    bl _bit_os_clock
    subs x24, x23, x0
    b.le 8f
    b 1b
2:  mov x0, x20
    bl _bit_bytes_new
    mov x22, x0
    mov w0, w19
    ldr x1, [x22]
    mov x2, x20
    mov w3, #0
    bl _recv
    cmp x0, #0
    b.lt 6f
    str x0, [x22, #8]
    mov x0, x22
    add sp, sp, #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
6:  mov x0, x22
    bl _bit_bytes_free
7:  adrp x0, Lrt_erecv@PAGE
    add x0, x0, Lrt_erecv@PAGEOFF
    b 5f
8:  mov x0, #2
    bl _bit_set_errcode
    adrp x0, Lrt_erecv_timeout@PAGE
    add x0, x0, Lrt_erecv_timeout@PAGEOFF
    b 5f
9:  adrp x0, Lrt_erecv_args@PAGE
    add x0, x0, Lrt_erecv_args@PAGEOFF
5:  mov x1, x21
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

_bit_compiler_run_direct:                  // argv array -> status, preserving Ctrl+C cleanup
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    sub sp, sp, #16
    ldr x9, [x0, #8]
    cbz x9, 8f
    bl _bit_mas_argv
    mov x20, x0
    mov w0, #2
    mov x1, #1                    // SIG_IGN in the compiler
    bl _signal
    cmn x0, #1
    b.eq 7f
    mov x21, x0
    mov w0, #3
    mov x1, #1
    bl _signal
    cmn x0, #1
    b.eq 6f
    mov x22, x0
    mov x0, #0
    bl _fflush
    bl _fork
    cmp w0, #0
    b.lt 5f
    b.ne 2f
    mov w0, #2
    mov x1, x21
    bl _signal
    mov w0, #3
    mov x1, x22
    bl _signal
    ldr x0, [x20]
    mov x1, x20
    bl _execvp
    mov w0, #127
    bl _exit
2:  sxtw x23, w0
3:  mov x0, x23
    mov x1, sp
    mov x2, #0
    bl _waitpid
    cmp w0, #0
    b.ge 4f
    bl ___error
    ldr w0, [x0]
    cmp w0, #4                    // EINTR
    b.eq 3b
5:  mov w0, #-1
    bl _bit_wstatus
    mov x24, x0
    b 9f
4:  ldr w0, [sp]
    bl _bit_wstatus
    mov x24, x0
9:  mov w0, #3
    mov x1, x22
    bl _signal
    mov w0, #2
    mov x1, x21
    bl _signal
    mov x0, x20
    bl _free
    mov x0, x24
    b 10f
6:  mov w0, #2
    mov x1, x21
    bl _signal
7:  mov x0, x20
    bl _free
8:  mov w0, #-1
    bl _bit_wstatus
10: add sp, sp, #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

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

_bit_ping_clock:                    // monotonic milliseconds, -1 on failure
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #16
    mov w0, #6                      // CLOCK_MONOTONIC on Darwin
    mov x1, sp
    bl _clock_gettime
    cbnz w0, 1f
    ldr x0, [sp]
    mov x1, #1000
    mul x0, x0, x1
    ldr x1, [sp, #8]
    mov x2, #0x4240
    movk x2, #15, lsl #16
    udiv x1, x1, x2
    add x0, x0, x1
    b 2f
1:  mov x0, #-1
2:  add sp, sp, #16
    ldp x29, x30, [sp], #16
    ret

_bit_ping:                          // host -> ICMP echo reply, without a subprocess
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    sub sp, sp, #336
    mov x19, #-1                    // socket
    mov x20, #0                     // addrinfo list
    cbz x0, 9f
    ldrb w9, [x0]
    cbz w9, 9f
    stp xzr, xzr, [sp]
    stp xzr, xzr, [sp, #16]
    stp xzr, xzr, [sp, #32]
    mov w9, #2                      // SOCK_DGRAM, any IP family
    str w9, [sp, #8]
    mov x1, #0
    mov x2, sp
    add x3, sp, #48
    bl _getaddrinfo
    cbnz w0, 9f
    ldr x20, [sp, #48]
    cbz x20, 9f
    mov x21, x20
11: ldr w9, [x21, #4]               // ai_family
    cmp w9, #2
    b.eq 12f
    cmp w9, #30                     // AF_INET6 on Darwin
    b.eq 12f
    ldr x21, [x21, #40]
    cbnz x21, 11b
    b 9f
12: str w9, [sp, #4]                // retain family after freeaddrinfo
    ldr w22, [x21, #16]             // ai_addrlen
    ldr x21, [x21, #32]             // ai_addr on Darwin
    cbz x21, 9f
    mov w0, w9
    mov w1, #2                      // SOCK_DGRAM
    mov w2, #1                      // IPPROTO_ICMP
    cmp w9, #2
    b.eq 13f
    mov w2, #58                     // IPPROTO_ICMPV6
13: bl _socket
    tbnz w0, #31, 9f
    mov w19, w0
    mov x1, x21
    mov w2, w22
    bl _connect
    mov w21, w0
    mov x0, x20
    bl _freeaddrinfo
    mov x20, #0
    cbnz w21, 9f
    // Echo request: type 8, code 0, checksum f135, id 0, sequence 5162,
    // and payload "bit-ping". The OS supplies the socket's ICMP identifier.
    movz x9, #0x0008
    movk x9, #0x35f1, lsl #16
    movk x9, #0x6251, lsl #48
    ldr w10, [sp, #4]
    cmp w10, #2
    b.eq 14f
    movz x9, #0x0080                // ICMPv6 echo, checksum supplied by OS
    movk x9, #0x6251, lsl #48
14: str x9, [sp, #56]
    movz x9, #0x6962
    movk x9, #0x2d74, lsl #16
    movk x9, #0x6970, lsl #32
    movk x9, #0x676e, lsl #48
    str x9, [sp, #64]
    mov w0, w19
    add x1, sp, #56
    mov w2, #16
    mov w3, #0
    bl _send
    cmp x0, #16
    b.ne 9f
    bl _bit_ping_clock
    tbnz x0, #63, 9f
    add x22, x0, #1000              // one-second deadline
    mov x21, #1000
1:  str w19, [sp, #72]
    mov w9, #1                      // POLLIN; clear revents
    str w9, [sp, #76]
    add x0, sp, #72
    mov w1, #1
    mov x2, x21
    bl _poll
    cbz w0, 9f
    tbnz w0, #31, 6f
    mov w0, w19
    add x1, sp, #80
    mov w2, #256
    mov w3, #0
    bl _recv
    tbnz x0, #63, 6f
    cmp x0, #16
    b.lt 7f
    mov x10, #0
    ldrb w9, [sp, #80]
    lsr w11, w9, #4
    cmp w11, #4
    b.ne 2f
    and x10, x9, #15                // Darwin includes IPv4 header
    lsl x10, x10, #2
    cmp x10, #20
    b.lo 7f
2:  add x11, x10, #16
    cmp x0, x11
    b.lo 7f
    add x11, sp, #80
    add x11, x11, x10
    ldrb w9, [x11]
    ldrb w10, [x11, #1]
    cbnz w10, 7f                    // code must be zero
    ldr w10, [sp, #4]
    cmp w10, #2
    b.ne 15f
    cbnz w9, 7f                     // ICMP echo reply type 0
    b 16f
15: cmp w9, #129                    // ICMPv6 echo reply type 129
    b.ne 7f
16: ldrh w9, [x11, #6]
    mov w10, #0x6251                // network bytes 51 62
    cmp w9, w10
    b.ne 7f
    ldr x9, [x11, #8]
    movz x10, #0x6962
    movk x10, #0x2d74, lsl #16
    movk x10, #0x6970, lsl #32
    movk x10, #0x676e, lsl #48
    cmp x9, x10
    b.ne 7f
    mov x21, #1
    b 8f
6:  bl ___error
    ldr w0, [x0]
    cmp w0, #4                      // EINTR
    b.ne 9f
7:  bl _bit_ping_clock
    tbnz x0, #63, 9f
    subs x21, x22, x0
    b.gt 1b
9:  mov x21, #0
8:  cmn w19, #1
    b.eq 3f
    mov w0, w19
    bl _close
3:  cbz x20, 4f
    mov x0, x20
    bl _freeaddrinfo
4:  mov x0, x21
    add sp, sp, #336
    ldp x21, x22, [sp], #16
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

_bit_str_num_checked:               // x0 = string, x1 = source line
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    sub sp, sp, #16
    mov x19, x0
    mov x20, x1
    bl ___error
    mov x21, x0
    str wzr, [x21]
    mov x0, x19
    mov x1, sp
    mov w2, #10
    bl _strtoll
    mov x22, x0
    ldr w0, [x21]
    cbnz w0, 9f
    ldr x1, [sp]
    cmp x1, x19
    b.eq 9f
1:  ldrb w0, [x1], #1
    cbz w0, 2f
    cmp w0, #32
    b.eq 1b
    sub w0, w0, #9
    cmp w0, #4
    b.ls 1b
    b 9f
2:  mov x0, x22
    add sp, sp, #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_badnum@PAGE
    add x0, x0, Lrt_badnum@PAGEOFF
    mov x1, x20
    bl _bit_die

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

_bit_os_clock:                      // x0 = source line -> monotonic milliseconds
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    sub sp, sp, #16
    mov x19, x0
    mov w0, #6                       // CLOCK_MONOTONIC on Darwin
    mov x1, sp
    bl _clock_gettime
    cbnz w0, 9f
    ldr x0, [sp]
    mov x1, #1000
    mul x0, x0, x1
    ldr x1, [sp, #8]
    mov x2, #0x4240
    movk x2, #15, lsl #16
    udiv x1, x1, x2
    add x0, x0, x1
    add sp, sp, #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_eclock@PAGE
    add x0, x0, Lrt_eclock@PAGEOFF
    mov x1, x19
    bl _bit_die

_bit_os_now:                        // -> время (секунды с 1970)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x0, #0
    bl _time
    ldp x29, x30, [sp], #16
    ret

_bit_os_cpus:                       // source line -> online logical processors
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x0, #58                    // Darwin _SC_NPROCESSORS_ONLN
    bl _sysconf
    cmp x0, #1
    b.lt 9f
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  adrp x0, Lrt_ecpus@PAGE
    add x0, x0, Lrt_ecpus@PAGEOFF
    mov x1, x19
    bl _bit_die

_bit_procs_add:                    // array, pid, name, source line
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x3
    mov x0, x20
    bl _bit_num_str
    mov x23, x0
    adrp x1, Lrt_pspc@PAGE
    add x1, x1, Lrt_pspc@PAGEOFF
    bl _bit_cat
    mov x24, x0
    mov x0, x23
    bl _free
    mov x0, x24
    mov x1, x21
    bl _bit_cat
    mov x23, x0
    mov x0, x24
    bl _free
    mov x0, x19
    mov x1, x23
    mov x2, x22
    bl _bit_mas_add
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_procs_finish:                 // array -> joined string; free temporary entries
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    adrp x1, Lrt_pnl@PAGE
    add x1, x1, Lrt_pnl@PAGEOFF
    bl _bit_mas_join
    mov x20, x0
    mov x21, #0
1:  ldr x9, [x19, #8]
    cmp x21, x9
    b.ge 2f
    ldr x9, [x19]
    ldr x0, [x9, x21, lsl #3]
    bl _free
    add x21, x21, #1
    b 1b
2:  ldr x0, [x19]
    bl _free
    mov x0, x19
    bl _free
    mov x0, x20
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_bit_os_procs:                     // source line -> PID and process name per line
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    sub sp, sp, #256
    mov x19, x0
    mov x20, #4096
    mov x0, x20
    bl _bit_alloc
    mov x21, x0
1:  mov x0, x21
    mov x1, x20
    bl _proc_listallpids
    cmp w0, #0
    b.lt 8f
    sxtw x22, w0
    lsl x9, x22, #2
    cmp x9, x20
    b.lt 2f
    mov x9, #16777216
    cmp x20, x9
    b.hs 8f
    lsl x20, x20, #1
    mov x0, x21
    mov x1, x20
    bl _realloc
    cbz x0, _bit_oom
    mov x21, x0
    b 1b
2:  mov x0, #-1
    mov x1, #0
    bl _bit_mas_new
    mov x23, x0
    mov x24, #0
3:  cmp x24, x22
    b.ge 6f
    ldr w25, [x21, x24, lsl #2]
    cbz w25, 5f
    mov x0, x25
    mov x1, sp
    bl _bit_mac_pname
    cmp w0, #0
    b.le 5f
    mov x0, x23
    mov x1, x25
    mov x2, sp
    mov x3, x19
    bl _bit_procs_add
5:  add x24, x24, #1
    b 3b
6:  mov x0, x21
    bl _free
    mov x0, x23
    bl _bit_procs_finish
    add sp, sp, #256
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
8:  mov x0, x21
    bl _free
    adrp x0, Lrt_eprocs@PAGE
    add x0, x0, Lrt_eprocs@PAGEOFF
    mov x1, x19
    bl _bit_die

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
    sub sp, sp, #160
    mov x19, #0
    mov x20, x1
    mov x21, x2
    mov x3, #-1
    stp x3, x3, [sp]
    str x3, [sp, #16]
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
    ldr w0, [sp, #20]
    mov w1, #3                       // F_GETFL
    bl _fcntl
    tbnz w0, #31, 9f
    orr w2, w0, #4                   // O_NONBLOCK on Darwin
    ldr w0, [sp, #20]
    mov w1, #4                       // F_SETFL
    sub sp, sp, #16
    str w2, [sp]                     // Darwin arm64 variadic argument
    bl _fcntl
    add sp, sp, #16
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
    mov x0, x19
    bl _free
    ldr w0, [sp, #4]
    bl _close
    ldr w0, [sp, #12]
    bl _close
    mov w0, #-1
    str w0, [sp, #144]
    mov x0, #2
    str x0, [sp, #104]
    cbz x20, 5f
    ldr w0, [sp, #16]
    bl _close
    mov x0, x20
    bl _strlen
    mov x22, x0
    mov x23, x20
    cbz x22, 6f
    mov x0, #13
    mov x1, #1                       // SIG_IGN
    bl _signal
    str x0, [sp, #112]
    ldr w0, [sp, #20]
    str w0, [sp, #144]
    mov w0, #4                       // POLLOUT
    str w0, [sp, #148]
    mov x0, #3
    str x0, [sp, #104]
    b 5f
6:  ldr w0, [sp, #20]
    bl _close
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
    str w0, [sp, #128]
    mov w1, #1
    str w1, [sp, #132]
    ldr w0, [sp, #8]
    str w0, [sp, #136]
    str w1, [sp, #140]
7:  ldr x1, [sp, #104]
    cbz x1, 8f
    add x0, sp, #128
    mov x1, #3
    mov w2, #-1
    bl _poll
    tbnz w0, #31, 7b
    ldr w0, [sp, #128]
    tbnz w0, #31, 71f
    ldrh w1, [sp, #134]
    cbz w1, 71f
    add x1, sp, #48
    bl _bit_buf_read
    cmp x0, #0
    b.gt 71f
    ldr w0, [sp, #128]
    bl _close
    mov w0, #-1
    str w0, [sp, #128]
    ldr x1, [sp, #104]
    sub x1, x1, #1
    str x1, [sp, #104]
71: ldr w0, [sp, #136]
    tbnz w0, #31, 72f
    ldrh w1, [sp, #142]
    cbz w1, 72f
    add x1, sp, #72
    bl _bit_buf_read
    cmp x0, #0
    b.gt 72f
    ldr w0, [sp, #136]
    bl _close
    mov w0, #-1
    str w0, [sp, #136]
    ldr x1, [sp, #104]
    sub x1, x1, #1
    str x1, [sp, #104]
    b 72f
72: ldr w0, [sp, #144]
    tbnz w0, #31, 7b
    ldrh w1, [sp, #150]
    cbz w1, 7b
    mov x1, x23
    mov x2, #65536
    cmp x22, x2
    csel x2, x22, x2, lo
    bl _write
    cmp x0, #0
    b.gt 73f
    bl ___error
    ldr w0, [x0]
    cmp w0, #4                       // EINTR
    b.eq 7b
    cmp w0, #35                      // EAGAIN on Darwin
    b.eq 7b
    b 74f
73: add x23, x23, x0
    subs x22, x22, x0
    b.ne 7b
74: ldr w0, [sp, #144]
    bl _close
    mov w0, #-1
    str w0, [sp, #144]
    mov x0, #13
    ldr x1, [sp, #112]
    bl _signal
    ldr x1, [sp, #104]
    sub x1, x1, #1
    str x1, [sp, #104]
    b 7b
8:  ldr w0, [sp, #24]
    add x1, sp, #96
    mov w2, #0
    bl _waitpid
    tbnz w0, #31, 81f
    ldr w0, [sp, #96]
    bl _bit_wstatus
    b 82f
81: bl ___error
    ldr w0, [x0]
    cmp w0, #4                       // EINTR
    b.eq 8b
    mov x0, #127
    adrp x1, Lrt_status@PAGE
    str x0, [x1, Lrt_status@PAGEOFF]
82: adrp x1, Lrt_stderr@PAGE
    ldr x0, [x1, Lrt_stderr@PAGEOFF]
    bl _free
    add x0, sp, #72
    bl _bit_buf_finish
    adrp x1, Lrt_stderr@PAGE
    str x0, [x1, Lrt_stderr@PAGEOFF]
    add x0, sp, #48
    bl _bit_buf_finish
    add sp, sp, #160
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
9:  mov x0, x19
    bl _free
    mov x22, #0
91: ldr w0, [sp, x22]
    tbnz w0, #31, 92f
    bl _close
92: add x22, x22, #4
    cmp x22, #24
    b.ne 91b
    adrp x0, Lrt_erun@PAGE
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
Lrt_str_registry: .quad 0
Lrt_str_low: .quad -1
Lrt_str_high: .quad 0
Lrt_argc: .quad 0
Lrt_argv: .quad 0
Lrt_status: .quad 0
Lrt_random_state: .quad 0
Lrt_random_ready: .quad 0
.p2align 2
Lrt_signalled: .long 0
Lrt_ready: .byte 0
.p2align 3
Lrt_tkey: .quad 0
Lrt_thread_list: .quad 0
Lrt_thread_next: .quad 1
.p2align 3
Lrt_slock: .zero 80
Lrt_recover: .quad 0
Lrt_owned: .quad 0
Lrt_errmsg: .quad 0
Lrt_errline: .quad 0
Lrt_errcode: .quad 0
Lrt_stderr: .quad 0
.p2align 4
.section __TEXT,__text,regular,pure_instructions
.p2align 2

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

Lrt_etmp: .asciz "cannot create temporary directory"
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
