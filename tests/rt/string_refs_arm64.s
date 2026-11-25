.section __TEXT,__text,regular,pure_instructions
.globl _main
.p2align 2
_main:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x0, #0
    bl _bit_str_adopt
    cbnz x0, 9f
    adrp x0, Lrt_empty@PAGE
    add x0, x0, Lrt_empty@PAGEOFF
    mov x1, x0
    bl _bit_cat
    mov x19, x0
    bl _bit_str_adopt
    mov x0, x19
    bl _bit_str_adopt
    mov x0, x19
    bl _bit_str_find
    cbz x0, 9f
    ldr x1, [x0, #8]
    cmp x1, #1
    b.ne 9f
    mov x0, x19
    bl _bit_str_retain
    mov x0, x19
    bl _bit_str_retain
    mov x0, x19
    bl _bit_str_find
    ldr x1, [x0, #8]
    cmp x1, #3
    b.ne 9f
    mov x0, x19
    bl _bit_str_release
    mov x0, x19
    bl _bit_str_release
    mov x0, x19
    bl _bit_str_find
    cbz x0, 9f
    ldr x1, [x0, #8]
    cmp x1, #1
    b.ne 9f
    mov x0, x19
    bl _bit_str_release
    mov x0, x19
    bl _bit_str_find
    cbnz x0, 9f
    adrp x19, Lrt_empty@PAGE
    add x19, x19, Lrt_empty@PAGEOFF
    mov x0, x19
    bl _bit_str_retain
    cmp x0, x19
    b.ne 9f
    bl _bit_str_release
    mov x0, x19
    bl _strlen
    cbnz x0, 9f
    mov x0, #0x8b80
    movk x0, #8, lsl #16
    bl _bit_alloc
    mov x21, x0
    mov x22, #0
1:  adrp x0, Lrt_empty@PAGE
    add x0, x0, Lrt_empty@PAGEOFF
    mov x1, x0
    bl _bit_cat
    bl _bit_str_adopt
    str x0, [x21, x22, lsl #3]
    add x22, x22, #1
    mov x1, #0x1170
    movk x1, #1, lsl #16
    cmp x22, x1
    b.lt 1b
    mov x22, #0
2:  ldr x0, [x21, x22, lsl #3]
    bl _bit_str_release
    add x22, x22, #1
    mov x1, #0x1170
    movk x1, #1, lsl #16
    cmp x22, x1
    b.lt 2b
    mov x0, x21
    bl _free
    adrp x1, Lrt_str_registry@PAGE
    ldr x1, [x1, Lrt_str_registry@PAGEOFF]
    mov x2, #65536
3:  ldr x3, [x1], #8
    cbnz x3, 9f
    subs x2, x2, #1
    b.ne 3b
    mov x0, #0
    b 10f
9:  mov x0, #1
10: ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
