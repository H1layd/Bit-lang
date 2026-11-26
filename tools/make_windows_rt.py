#!/usr/bin/env python3
# Делает rt/x86_64-windows.s:
#   - ядро (print, число/строка, склейка, память) — написано под Windows ABI вручную;
#   - массивы, bytes, срезы строк, ФАЙЛЫ, ВВОД, ОС — берутся из System V среды
#     (rt/x86_64.s), а вызовы libc в них подменяются на тонкие обёртки _w_*,
#     прячущие Windows ABI. Пара функций (stat, чтение строки, список папки,
#     число ядер) переписаны под Windows API вручную.
import re
src = open("rt/x86_64.s").read()

def octal(s):
    return '"' + "".join(chr(b) if 32 <= b < 127 and b not in (34, 92) else "\\%03o" % b
                         for b in s.encode()) + '"'

# ── функции из System V «как есть» (оборачиваем только libc-вызовы) ──
NEED = ["_bit_str_find", "_bit_str_retain", "_bit_str_adopt", "_bit_str_release", "_bit_to_str", "_bit_mas_new", "_bit_mas_add", "_bit_mas_insert",
        "_bit_mas_remove", "_bit_mas_str",
        "_bit_mas_slice", "_bit_mas_sum", "_bit_mas_sort",
        "_bit_bytes_new", "_bit_bytes_add", "_bit_bytes_slice", "_bit_bytes_text",
        "_bit_bytes_str", "_bit_bytes_num", "_bit_bytes_put", "_bit_bytes_addr",
        "_bit_bytes_free",
        "_bit_str_slice", "_bit_str_num", "_bit_str_lines",
        "_bit_str_starts", "_bit_str_ends", "_bit_str_trim",
        "_bit_substr", "_bit_str_split", "_bit_str_replace",
        "_bit_mas_join", "_bit_mas_text", "_bit_str_bytes", "_bit_hexval_ptr",
        "_bit_ipow", "_bit_str_find_raw",
        "_bit_setjmp", "_bit_longjmp", "_bit_mas_argv",
        "_bit_term_stderr", "_bit_args",
        "_bit_random_seed", "_bit_random_next", "_bit_random_range",
        "_bit_map_find", "_bit_map_set", "_bit_map_remove",
        "_bit_map_keys", "_bit_map_values", "_bit_key_cmp", "_bit_mas_sort_by",
        "_bit_str_index", "_bit_str_contains", "_bit_str_upper", "_bit_str_lower",
        "_bit_str_code", "_bit_num_char", "_bit_str_pad", "_bit_str_pad_left",
        "_bit_str_pad_do", "_bit_str_repeat", "_bit_num_hex"]
WRAP = ["calloc", "memcpy", "qsort", "realloc", "strlen", "free", "getentropy"]
# сеть: переносим и оборачиваем вызовы Winsock
NET = ["_bit_tcp_connect", "_bit_udp_connect", "_bit_ip_connect", "_bit_tcp_listen", "_bit_tcp_listen_at",
       "_bit_tcp_accept", "_bit_sock_peer", "_bit_sock_send", "_bit_sock_recv", "_bit_sock_recv_timed",
       "_bit_sock_close", "_bit_resolve"]
SOCK = ["accept", "bind", "connect", "getpeername", "gethostbyname", "inet_ntop", "inet_pton",
        "listen", "setsockopt", "recv", "send", "socket", "strlen", "free"]
# файлы, ввод, ОС — переносим с заменой libc на _w_* обёртки.
# (_bit_kind, _bit_dir_list, _bit_os_cpus, _bit_readline — вручную под Windows)
FILES = ["_bit_file_read", "_bit_file_size", "_bit_file_write", "_bit_file_lines",
         "_bit_dir_exists", "_bit_file_exists", "_bit_file_remove", "_bit_dir_remove",
         "_bit_move", "_bit_copy_temp", "_bit_copy", "_bit_dir_make", "_bit_basename",
         "_bit_file_line", "_bit_file_slice", "_bit_file_load", "_bit_file_save",
         "_bit_file_load_at", "_bit_file_save_at", "_bit_dir_walk", "_bit_walk_into",
         "_bit_errpath", "_bit_dir_walk_info", "_bit_remove_error",
         "_bit_input_num", "_bit_input_dec", "_bit_input_str", "_bit_input_bool",
         "_bit_os_host", "_bit_os_user", "_bit_os_now", "_bit_os_procs",
         "_bit_run", "_bit_run_live", "_bit_status",
         "_bit_env", "_bit_str_hex", "_bit_str_num_checked",
         "_bit_fetch", "_bit_http_post", "_bit_download", "_bit_ping"]

# ── подмена libc-вызовов на обёртки _w_* ──
#   символ-в-исходнике : (имя обёртки, настоящая функция libc, число аргументов)
#   настоящая функция None → обёртка уже есть в ядре (realloc/free) или написана вручную.
LIBC = {
    "_fopen":   ("fopen",   "fopen",   2), "_fclose": ("fclose", "fclose", 1),
    "_fread":   ("fread",   "fread",   4), "_fwrite": ("fwrite", "fwrite", 4),
    "_fseek":   ("fseek",   "fseek",   3), "_ftell":  ("ftell",  "ftell",  1),
    "_fseeko":  ("fseeko",  "_fseeki64", 3), "_fdopen": ("fdopen", "_fdopen", 2),
    "_close":   ("close",   "_close", 1),
    "_ferror":  ("ferror",  "ferror",  1), "_fflush": ("fflush", "fflush", 1),
    "_fputs":   ("fputs",   "fputs",   2), "_strrchr":("strrchr","strrchr",2),
    "_rename":  ("rename",  None, None), "_mkstemp": ("mkstemp", "mkstemp", 1), "_strcmp": ("strcmp", "strcmp", 2),
    "_strtoll": ("strtoll", "strtoll", 3), "_strtod": ("strtod", "strtod", 2),
    "_getenv":  ("getenv",  "getenv",  1), "_time":   ("time",   "time",   1),
    "_unlink":  ("unlink",  "_unlink", 1), "_rmdir":  ("rmdir",  "_rmdir", 1),
    "_mkdir":   ("mkdir",   "_mkdir",  1), "_popen":  ("popen",  "_popen", 2),
    "_pclose":  ("pclose",  "_pclose", 1), "_system": ("system", "system", 1),
    "_realloc": ("realloc", None, None),   "_free":   ("free",   None, None),
    "___error": ("errno",   None, None),   "_gethostname": ("gethostname", None, None),
}

def extract_raw(name):
    i = src.index("\n" + name + ":")
    m = re.search(r"\n(_bit_[a-z_0-9]+:|\.section|\.data)", src[i + 1:])
    return src[i + 1: i + 1 + m.start()].rstrip() + "\n"

def wrapcalls(body, names):
    for w in names:
        body = body.replace("call _" + w + "\n", "call _w_" + w + "\n")
        body = body.replace("call _" + w + " ", "call _w_" + w + " ")
    return body

def extract(name):
    body = wrapcalls(extract_raw(name), WRAP)
    # snprintf is C99 and available as such under mingw
    return body.replace("call _snprintf", "call snprintf")

def extract_net(name):
    b = wrapcalls(extract_raw(name), SOCK)
    if name == "_bit_tcp_listen_at":
        b = b.replace("mov word ptr [rsp], 0x210", "mov word ptr [rsp], 2")
    b = b.replace("call _close\n", "call _w_closesocket\n")
    b = b.replace("jmp _close\n", "jmp _w_closesocket\n").replace("jmp _close", "jmp _w_closesocket")
    return b

def extract_file(name):
    b = extract_raw(name)
    for sym, (w, _inner, _n) in LIBC.items():
        b = b.replace("call " + sym + "\n", "call _w_" + w + "\n")
        b = b.replace("call " + sym + " ", "call _w_" + w + " ")
    return b

transformed = "\n".join(extract(n) for n in NEED) + "\n" + "\n".join(extract_net(n) for n in NET)
files_asm = "\n".join(extract_file(n) for n in FILES)

# Also recognize backslashes and drive-relative names on Windows.
prefix = """    mov esi, 47
    call _w_strrchr
    xor esi, esi
    test rax, rax
    jz 1f
    sub rax, rbx
    lea rsi, [rax + 1]
1:  mov rdi, rbx
    call _bit_substr"""
win_prefix = """    mov esi, 47
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
    call _bit_substr"""
assert files_asm.count(prefix) == 1
files_asm = files_asm.replace(prefix, win_prefix)

# ── printf в вводе: System V (al=кол-во xmm) → Windows x64 (аргументы в rcx,rdx,r8) ──
PRINTF_FIX = [
 ("    lea rdi, [rip + Lrt_numr]\n    mov rsi, r12\n    mov rdx, r13\n    xor eax, eax\n    call _printf\n",
  "    lea rcx, [rip + Lrt_numr]\n    mov rdx, r12\n    mov r8, r13\n    sub rsp, 32\n    call printf\n    add rsp, 32\n"),
 ("6:  lea rdi, [rip + Lrt_num]\n    xor eax, eax\n    call _printf\n",
  "6:  lea rcx, [rip + Lrt_num]\n    sub rsp, 32\n    call printf\n    add rsp, 32\n"),
 ("    lea rdi, [rip + Lrt_decr]\n    movq xmm0, r12\n    movq xmm1, r13\n    mov eax, 2\n    call _printf\n",
  "    lea rcx, [rip + Lrt_decr]\n    mov rdx, r12\n    movq xmm1, r12\n    mov r8, r13\n    movq xmm2, r13\n    sub rsp, 32\n    call printf\n    add rsp, 32\n"),
 ("6:  lea rdi, [rip + Lrt_dec]\n    xor eax, eax\n    call _printf\n",
  "6:  lea rcx, [rip + Lrt_dec]\n    sub rsp, 32\n    call printf\n    add rsp, 32\n"),
 ("    lea rdi, [rip + Lrt_boolm]\n    xor eax, eax\n    call _printf\n",
  "    lea rcx, [rip + Lrt_boolm]\n    sub rsp, 32\n    call printf\n    add rsp, 32\n"),
]
for old, new in PRINTF_FIX:
    assert files_asm.count(old) == 1, ("printf fix", old[:40])
    files_asm = files_asm.replace(old, new)

# ── автоматические обёртки libc: вход по-нашему (rdi,rsi,rdx,rcx), внутри Windows ABI ──
def gw(wname, inner, argc):
    mv = []
    if argc >= 4: mv.append("    mov r9, rcx")
    if argc >= 3: mv.append("    mov r8, rdx")
    if argc >= 2: mv.append("    mov rdx, rsi")
    if argc >= 1: mv.append("    mov rcx, rdi")
    body = "\n".join(mv)
    if body:
        body += "\n"
    return "_w_%s:\n%s    sub rsp, 40\n    call %s\n    add rsp, 40\n    ret\n" % (wname, body, inner)

GENW = "".join(gw(w, inner, n) for (w, inner, n) in LIBC.values() if inner is not None)

CORE = r"""// ─────────── среда выполнения bit (Windows x64) ───────────
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

"""

# ── обёртки и функции для файлов/ввода/ОС, написанные под Windows вручную ──
WINEXTRA = r"""
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

"""

NET_WRAPPERS = r"""
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

"""

WINPROC = r"""
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
"""

FOOT_HEAD = r"""
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
Lrt_oom: .asciz "ne hvataet pamyati"
Lrt_die: .asciz "\nOshibka vypolneniya (stroka %lld): %s\n"
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
Lrt_full: .asciz "massiv zapolnen do limita"
Lrt_ovf: .asciz "perepolnenie num"
Lrt_e8: .asciz "v bytes net 8 bajt s etogo nomera"
Lrt_enet: .asciz "ne mogu podklyuchitsya"
Lrt_elisten: .asciz "ne mogu otkryt port"
Lrt_eaccept: .asciz "oshibka priyoma podklyucheniya"
Lrt_esend: .asciz "oshibka otpravki"
Lrt_erecv: .asciz "oshibka priyoma"
Lrt_edns: .asciz "ne mogu najti adres hosta"
"""

NEWSTR = {
    "Lrt_elisten_addr": "listen: неверный IPv4-адрес",
    "Lrt_peer_colon": ":", "Lrt_epeer": "не могу узнать адрес собеседника",
    "Lrt_remove_home": "HOME", "Lrt_remove_profile": "USERPROFILE",
    "Lrt_ermhome": "remove_all: нельзя удалять домашнюю папку: ",
    "Lrt_ermroot": "remove_all: нельзя удалять корень, пустой путь, . или ..: ",
    "Lrt_ermtree": "не могу удалить папку с содержимым: ",
    "Lrt_epermread": "не могу узнать права доступа: ",
    "Lrt_epermwrite": "не могу изменить права доступа: ",
    "Lrt_ecwd": "не могу узнать текущую папку",
    "Lrt_ego": "не могу сменить папку: ",
    "Lrt_eenv": "не могу задать переменную окружения: ",
    "Lrt_wp_exe": ".exe", "Lrt_wp_code": ", код ошибки ",
    "Lrt_wp_eread": "не могу прочитать память процесса ",
    "Lrt_wp_ewrite": "не могу записать в память процесса ",
    "Lrt_wp_ekill": "не могу остановить процесс ", "Lrt_wp_espawn": "не могу запустить: ",
    "Lrt_rb": "rb", "Lrt_wb": "wb", "Lrt_r": "r", "Lrt_star": "\\*",
    "Lrt_userenv": "USERNAME", "Lrt_pscmd": "tasklist",
    "Lrt_eof": "vvod zakonchilsya",
    "Lrt_numr": "nuzhno chislo ot %lld do %lld\n", "Lrt_num": "nuzhno chislo\n",
    "Lrt_decr": "nuzhno drob ot %g do %g\n", "Lrt_dec": "nuzhno drob\n",
    "Lrt_boolm": "napishite da ili net (da/net/1/0)\n",
    "Lrt_da": "да", "Lrt_net": "нет", "Lrt_1": "1", "Lrt_0": "0",
    "Lrt_eopen": "ne mogu otkryt fajl: ", "Lrt_eread": "ne mogu prochitat fajl: ",
    "Lrt_ewrite": "ne mogu zapisat fajl: ", "Lrt_enotfile": "eto ne fajl: ",
    "Lrt_echunk": "smeshenie i razmer dolzhny byt neotricatelnymi",
    "Lrt_erecv_timeout": "isteklo vremya ozhidaniya recv",
    "Lrt_erecv_args": "recv: razmer 1..2147483647, ozhidanie 0..2147483647 ms",
    "Lrt_econn_timeout": "isteklo vremya ozhidaniya podklyucheniya",
    "Lrt_econn_args": "connect: tajmaut ot 0 do 2147483647 ms",
    "Lrt_enotdir": "eto ne papka: ", "Lrt_erm": "ne mogu udalit: ",
    "Lrt_emv": "ne mogu peremestit: ", "Lrt_emk": "ne mogu sozdat papku: ",
    "Lrt_edir": "ne mogu prochitat papku: ", "Lrt_slash": "/",
    "Lrt_w": "wb", "Lrt_a": "ab", "Lrt_erun": "ne mogu zapustit komandu: ",
    "Lrt_cls": "\x1b[2J\x1b[H", "Lrt_dashdash": " -- ", "Lrt_gp": "%.*g",
    "Lrt_fp": "%.*f",
    "Lrt_ecode_empty": "code: пустая строка",
    "Lrt_echar_range": "char: код символа от 0 до 1114111",
    "Lrt_epad_width": "pad: ширина от 0 до 1000000",
    "Lrt_epad_count": "repeat: число от 0 до 100000000",
    "Lrt_ehex_width": "hex: ширина от 0 до 64",
    "Lrt_efixed_places": "fixed: знаков от 0 до 17",
    "Lrt_cpucmd": "", "Lrt_memsize": "", "Lrt_vmps": "",
    "Lrt_curlget": "curl -sS -L -- ", "Lrt_curlout": "curl -sS -L -o ",
    "Lrt_curlpost": "curl -sS -L -d ", "Lrt_pingcmd": "ping -n 1 ",
    "Lrt_quiet": " >nul 2>&1",
    "Lrt_curl": "curl", "Lrt_sS": "-sS", "Lrt_L": "-L", "Lrt_ddp": "--",
    "Lrt_d": "-d", "Lrt_o": "-o", "Lrt_pingp": "ping", "Lrt_pingc": "-n",
    "Lrt_nul": "NUL",
    "Lrt_copy_suffix": ".bit-copy-XXXXXX",
    "Lrt_badnum": "invalid num: expected a decimal integer in range",
    "Lrt_random_bounds": "random: expected minimum <= maximum",
    "Lrt_random_entropy": "random: cannot read system entropy",
}
# Сообщения среды берём из rt/x86_64.s: те же русские тексты, что на macOS и Linux.
def unesc(v):
    out = bytearray(); i = 0
    while i < len(v):
        c = v[i]
        if c == "\\":
            n = v[i + 1]
            if n in "01234567":
                out.append(int(v[i + 1:i + 4], 8)); i += 4; continue
            out += {"n": b"\n", "t": b"\t", "\\": b"\\", '"': b'"'}[n]; i += 2; continue
        out += c.encode(); i += 1
    return out.decode()
MAC = {k: unesc(v) for k, v in re.findall(r'^(Lrt_\w+): \.asciz "((?:[^"\\]|\\.)*)"$', src, re.M)}
def russian(v):
    return any(ord(ch) > 127 for ch in v)
for k in list(NEWSTR):
    if k in MAC and russian(MAC[k]) and not russian(NEWSTR[k]):
        NEWSTR[k] = MAC[k]
def head_line(m):
    k = m.group(1)
    return "%s: .asciz %s" % (k, octal(MAC[k])) if k in MAC and russian(MAC[k]) else m.group(0)
FOOT_HEAD = re.sub(r'^(Lrt_\w+): \.asciz "[^"\n]*"$', head_line, FOOT_HEAD, flags=re.M)
FOOT = FOOT_HEAD + "".join("%s: .asciz %s\n" % (k, octal(v)) for k, v in NEWSTR.items()) + ".text\n"

out = CORE + GENW + "\n" + WINEXTRA + NET_WRAPPERS + "\n" + transformed + "\n" + files_asm + WINPROC + FOOT
open("rt/x86_64-windows.s", "w").write(out)

defined = set(re.findall(r"^(_[a-z_0-9]+):", CORE + GENW + WINEXTRA + NET_WRAPPERS + transformed + files_asm, re.M))
left = sorted(set(re.findall(r"call ([a-z_][a-z_0-9]*)", transformed + files_asm)) - defined)
print("перенесено: массивы", len(NEED), "| сеть", len(NET), "| файлы/ввод/ОС", len(FILES))
print("неразрешённые вызовы (должны быть только libc/WinAPI):", left)
