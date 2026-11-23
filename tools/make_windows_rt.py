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
NEED = ["_bit_to_str", "_bit_mas_new", "_bit_mas_add", "_bit_mas_insert",
        "_bit_mas_remove", "_bit_mas_str",
        "_bit_mas_slice", "_bit_mas_sum", "_bit_mas_sort",
        "_bit_bytes_new", "_bit_bytes_add", "_bit_bytes_slice", "_bit_bytes_text",
        "_bit_bytes_str", "_bit_bytes_num", "_bit_bytes_put", "_bit_bytes_addr",
        "_bit_bytes_free",
        "_bit_str_slice", "_bit_str_num", "_bit_str_lines",
        "_bit_str_starts", "_bit_str_ends", "_bit_str_trim",
        "_bit_substr", "_bit_str_split", "_bit_str_replace",
        "_bit_mas_join", "_bit_mas_text", "_bit_str_bytes", "_bit_hexval_ptr",
        "_bit_ipow", "_bit_recover_enter", "_bit_recover_leave",
        "_bit_setjmp", "_bit_longjmp", "_bit_own_str", "_bit_drop_owned", "_bit_term_error", "_bit_mas_argv",
        "_bit_term_stderr", "_bit_args",
        "_bit_random_seed", "_bit_random_next", "_bit_random_range",
        "_bit_map_find", "_bit_map_set", "_bit_map_remove"]
WRAP = ["calloc", "memcpy", "qsort", "realloc", "strlen", "free", "getentropy"]
# сеть: переносим и оборачиваем вызовы Winsock
NET = ["_bit_tcp_connect", "_bit_udp_connect", "_bit_ip_connect", "_bit_tcp_listen",
       "_bit_tcp_accept", "_bit_sock_send", "_bit_sock_recv", "_bit_sock_recv_timed",
       "_bit_sock_close", "_bit_resolve"]
SOCK = ["accept", "bind", "connect", "gethostbyname", "inet_ntop", "inet_pton",
        "listen", "recv", "send", "socket", "strlen", "free"]
# файлы, ввод, ОС — переносим с заменой libc на _w_* обёртки.
# (_bit_kind, _bit_dir_list, _bit_os_cpus, _bit_readline — вручную под Windows)
FILES = ["_bit_file_read", "_bit_file_size", "_bit_file_write", "_bit_file_lines",
         "_bit_dir_exists", "_bit_file_exists", "_bit_file_remove", "_bit_dir_remove",
         "_bit_move", "_bit_copy_temp", "_bit_copy", "_bit_dir_make", "_bit_basename",
         "_bit_file_line", "_bit_file_slice", "_bit_file_load", "_bit_file_save",
         "_bit_file_load_at", "_bit_file_save_at",
         "_bit_errpath",
         "_bit_input_num", "_bit_input_dec", "_bit_input_str", "_bit_input_bool",
         "_bit_os_host", "_bit_os_user", "_bit_os_now", "_bit_os_procs",
         "_bit_run", "_bit_run_live", "_bit_wstatus", "_bit_status",
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
    return wrapcalls(extract_raw(name), WRAP)

def extract_net(name):
    b = wrapcalls(extract_raw(name), SOCK)
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

_bit_die:
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
    sub rsp, 32
    mov r8, rdi
    mov rdx, rsi
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
    sub rsp, 40
    mov rcx, rdi
    call free
    add rsp, 40
    ret

_bit_string_str:
    mov rax, rdi
    ret

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
    sub rsp, 416
    mov ecx, 0x0202
    lea rdx, [rsp]
    sub rsp, 32
    call WSAStartup
    add rsp, 32
    mov qword ptr [rip + Lrt_wsa], 1
    add rsp, 416
    pop rbp
1:  ret

_w_socket:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call _bit_wsa_init
    mov r8, r13
    mov rdx, r12
    mov rcx, rbx
    sub rsp, 32
    call socket
    add rsp, 32
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_w_gethostbyname:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call _bit_wsa_init
    mov rcx, rbx
    sub rsp, 32
    call gethostbyname
    add rsp, 32
    add rsp, 8
    pop rbx
    pop rbp
    ret

_w_connect:
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call connect
    add rsp, 40
    ret
_w_bind:
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call bind
    add rsp, 40
    ret
_w_listen:
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call listen
    add rsp, 40
    ret
_w_accept:
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call accept
    add rsp, 40
    ret
_w_send:
    mov r9, rcx
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call send
    add rsp, 40
    ret
_w_recv:
    mov r9, rcx
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call recv
    add rsp, 40
    ret
_bit_socket_wait:                   // WSAPOLLFD: SOCKET, events, revents
    sub rsp, 56
    mov [rsp + 32], rdi
    // POLLRDNORM
    mov dword ptr [rsp + 40], 256
    lea rcx, [rsp + 32]
    mov edx, 1
    mov r8d, esi
    call WSAPoll
    add rsp, 56
    ret
_bit_open_update:
    sub rsp, 40
    mov rcx, rdi
    // _O_BINARY | _O_CREAT | _O_WRONLY, _S_IREAD | _S_IWRITE
    mov edx, 33025
    mov r8d, 384
    call _open
    add rsp, 40
    ret
_w_closesocket:
    mov rcx, rdi
    sub rsp, 40
    call closesocket
    add rsp, 40
    ret
_w_inet_pton:
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call inet_pton
    add rsp, 40
    ret
_w_inet_ntop:
    mov r9, rcx
    mov r8, rdx
    mov rdx, rsi
    mov rcx, rdi
    sub rsp, 40
    call inet_ntop
    add rsp, 40
    ret

"""

FOOT_HEAD = r"""
.data
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
Lrt_wsa: .quad 0
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
    "Lrt_enotdir": "eto ne papka: ", "Lrt_erm": "ne mogu udalit: ",
    "Lrt_emv": "ne mogu peremestit: ", "Lrt_emk": "ne mogu sozdat papku: ",
    "Lrt_edir": "ne mogu prochitat papku: ",
    "Lrt_w": "w", "Lrt_a": "a", "Lrt_erun": "ne mogu zapustit komandu: ",
    "Lrt_cls": "\x1b[2J\x1b[H", "Lrt_dashdash": " -- ", "Lrt_gp": "%.*g",
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
FOOT = FOOT_HEAD + "".join("%s: .asciz %s\n" % (k, octal(v)) for k, v in NEWSTR.items()) + ".text\n"

out = CORE + GENW + "\n" + WINEXTRA + NET_WRAPPERS + "\n" + transformed + "\n" + files_asm + FOOT
open("rt/x86_64-windows.s", "w").write(out)

defined = set(re.findall(r"^(_[a-z_0-9]+):", CORE + GENW + WINEXTRA + NET_WRAPPERS + transformed + files_asm, re.M))
left = sorted(set(re.findall(r"call ([a-z_][a-z_0-9]*)", transformed + files_asm)) - defined)
print("перенесено: массивы", len(NEED), "| сеть", len(NET), "| файлы/ввод/ОС", len(FILES))
print("неразрешённые вызовы (должны быть только libc/WinAPI):", left)
