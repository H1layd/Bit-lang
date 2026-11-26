# Делает rt/x86_64-linux.s из rt/x86_64.s: имена и структуры glibc вместо macOS.
import re
src = open("rt/x86_64.s").read()

def func_replace(text, name, body):
    i = text.index("\n" + name + ":")
    m = re.search(r"\n(_bit_[a-z_0-9]+:|\.section|\.data|// bytes)", text[i + 1:])
    j = i + 1 + m.start()
    return text[:i + 1] + body.strip("\n") + "\n\n" + text[j + 1:]

t = src
# процессы macOS (libproc) Linux не нужны: ниже свой блок PROC через /proc
t = re.sub(r"// ── proc \(macOS\).*?// ── конец proc \(macOS\) ──\n", "", t, flags=re.S)
t = t.replace(".section __TEXT,__text,regular,pure_instructions", ".text")
t = t.replace(".section __DATA,__data", ".data")
t = t.replace(".section __TEXT,__cstring,cstring_literals", ".section .rodata")
t = t.replace("___stderrp@GOTPCREL", "stderr@GOTPCREL").replace("___stdinp@GOTPCREL", "stdin@GOTPCREL")
t = t.replace('call "_opendir$INODE64"', "call opendir@PLT").replace('call "_readdir$INODE64"', "call readdir@PLT")
t = t.replace('call "_stat$INODE64"', "call stat@PLT").replace('call "_lstat$INODE64"', "call lstat@PLT")
t = re.sub(r"\b(call|jmp) _(?!bit_|_)([a-z_0-9]+)\b", r"\1 \2@PLT", t)
t = t.replace("call ___error", "call __errno_location@PLT")
t = t.replace('call "_fstatat$INODE64"', "call fstatat@PLT")
t = t.replace('call "_fdopendir$INODE64"', "call fdopendir@PLT")
# Scope ABI substitutions to one runtime function.
def func_transform(text, name, transform):
    start = text.index("\n" + name + ":") + 1
    match = re.search(r"\n(_bit_[a-z_0-9]+:|\.section|\.data)", text[start:])
    end = start + match.start() if match else len(text)
    return text[:start] + transform(text[start:end]) + text[end:]

# CLOCK_MONOTONIC differs between Darwin and Linux.
t = func_transform(t, "_bit_os_clock", lambda body: body.replace(
    "mov edi, 6                       // CLOCK_MONOTONIC on Darwin",
    "mov edi, 1                       # CLOCK_MONOTONIC on Linux"))

# sockaddr_in and socket option constants for Linux.
t = func_transform(t, "_bit_tcp_listen_at", lambda body: body
    .replace("mov word ptr [rsp], 0x210", "mov word ptr [rsp], 2")
    .replace("mov esi, 0xffff", "mov esi, 1")
    .replace("mov edx, 4                      # Darwin SO_REUSEADDR", "mov edx, 2                      # Linux SO_REUSEADDR"))

# AT_FDCWD belongs only to the top-level removal wrapper.
t = func_transform(t, "_bit_dir_remove_all",
                   lambda body: body.replace("mov rdi, -2", "mov rdi, -100"))
t = t.replace("mov ecx, 32" + chr(10) + '    call fstatat@PLT', "mov ecx, 256" + chr(10) + '    call fstatat@PLT')
t = t.replace("mov edx, 0x100100", "mov edx, 0x30000")
t = t.replace("mov edx, 128" + chr(10) + "    call unlinkat@PLT", "mov edx, 512" + chr(10) + "    call unlinkat@PLT")
# POSIX pipe flags and errno values differ from Darwin.
t = t.replace("    // O_NONBLOCK on Darwin\n    or edx, 4", "    // O_NONBLOCK\n    or edx, 2048")
t = t.replace("    // EAGAIN on Darwin\n    cmp eax, 35", "    // EAGAIN\n    cmp eax, 11")
# termios: раскладка и флаги Linux вместо Darwin
t = func_transform(t, "_bit_term_raw", lambda body: body
                   .replace("mov eax, [rsp + 24]", "mov eax, [rsp + 12]")
                   .replace("mov [rsp + 24], eax", "mov [rsp + 12], eax")
                   .replace("and eax, -265", "and eax, -11")
                   .replace("or eax, 264", "or eax, 10")
                   .replace("(Darwin)", "(Linux)"))
# errno -> код ошибки: значения Linux вместо Darwin
t = func_transform(t, "_bit_errno_map", lambda body: body
                   .replace("cmp edi, 61", "cmp edi, 111")   # ECONNREFUSED
                   .replace("cmp edi, 60", "cmp edi, 110")   # ETIMEDOUT
                   .replace("cmp edi, 51", "cmp edi, 101")   # ENETUNREACH
                   .replace("cmp edi, 65", "cmp edi, 113")   # EHOSTUNREACH
                   .replace("(Darwin)", "(Linux)"))
# connect(ms): O_NONBLOCK и EINPROGRESS различаются, SOL_SOCKET = 1
t = func_transform(t, "_bit_tcp_connect_timed", lambda body: body
                   .replace("or eax, 4", "or eax, 2048")
                   .replace("mov edx, 4103", "mov edx, 4")       # SO_ERROR
                   .replace("cmp eax, 36", "cmp eax, 115")       # EINPROGRESS
                   .replace("mov esi, 65535", "mov esi, 1")      # SOL_SOCKET
                   .replace("and eax, -5", "and eax, -2049") # снять O_NONBLOCK
                   .replace("(Darwin)", "(Linux)"))
# struct dirent: имя с 19-го байта, struct stat: st_mode с 24-го
t = t.replace("lea rdi, [rax + 21]", "lea rdi, [rax + 19]")
t = t.replace("lea rsi, [rax + 21]", "lea rsi, [rax + 19]")
t = t.replace("movzx ecx, word ptr [rsp + 4]", "mov ecx, dword ptr [rsp + 24]")
t = t.replace("movzx eax, word ptr [rsp + 4]", "mov eax, dword ptr [rsp + 24]")
# stat metadata used by walk("info").
t = t.replace("mov rdx, qword ptr [rsp + 96]", "mov rdx, qword ptr [rsp + 48]")
t = t.replace("mov rdx, qword ptr [rsp + 48]" + chr(10) + "    mov [rax + 16]", "mov rdx, qword ptr [rsp + 88]" + chr(10) + "    mov [rax + 16]")
# struct stat: st_mtime с 88-го байта
t = t.replace("mov rax, qword ptr [rsp + 48]       // st_mtime", "mov rax, qword ptr [rsp + 88]       # st_mtime")

t = func_replace(t, "_bit_open_update", """
_bit_open_update:
    // O_WRONLY | O_CREAT (Linux), mode 0666 filtered by umask
    mov esi, 65
    mov edx, 438
    xor eax, eax
    jmp open@PLT
""")

t = func_replace(t, "_bit_mem_used", """
_bit_mem_used:                      // → пик памяти программы (Linux отдаёт в КБ)
    push rbp
    mov rbp, rsp
    sub rsp, 160
    xor edi, edi
    mov rsi, rsp
    call getrusage@PLT
    mov rax, [rsp + 32]
    shl rax, 10
    mov rsp, rbp
    pop rbp
    ret
""")
t = func_replace(t, "_bit_mem_total", """
_bit_mem_total:                     // → сколько байт памяти в компьютере (sysinfo)
    push rbp
    mov rbp, rsp
    sub rsp, 128
    mov rdi, rsp
    call sysinfo@PLT
    mov rax, [rsp + 32]
    mov ecx, dword ptr [rsp + 104]
    imul rax, rcx
    mov rsp, rbp
    pop rbp
    ret
""")
t = func_replace(t, "_bit_mem_free", """
_bit_mem_free:                      // → свободно + буферы (sysinfo)
    push rbp
    mov rbp, rsp
    sub rsp, 128
    mov rdi, rsp
    call sysinfo@PLT
    mov rax, [rsp + 40]
    add rax, [rsp + 56]
    mov ecx, dword ptr [rsp + 104]
    imul rax, rcx
    mov rsp, rbp
    pop rbp
    ret
""")

PROC = r"""
// ───── чужие процессы (Linux): /proc/<pid>/mem ─────
_bit_proc_path:                     // rdi = pid, rsi = формат → строка "/proc/<pid>/..."
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov edi, 64
    call _bit_alloc
    push rax
    push rax
    mov rdi, rax
    mov esi, 64
    mov rdx, r12
    mov rcx, rbx
    xor eax, eax
    call snprintf@PLT
    pop rax
    pop rax
    pop r12
    pop rbx
    pop rbp
    ret

_bit_proc_fail:                     // rdi = текст, rsi = путь, rdx = строка программы: текст + путь + причина
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call __errno_location@PLT
    mov edi, dword ptr [rax]
    call strerror@PLT
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    call _bit_cat
    mov rdi, rax
    lea rsi, [rip + Lrt_colon]
    call _bit_cat
    mov rdi, rax
    mov rsi, r14
    call _bit_cat
    mov rdi, rax
    mov rsi, r13
    call _bit_die

_bit_proc_start:                    // rdi = команда, rsi = строка → pid запущенного процесса (наш ребёнок)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 48
    mov rbx, rdi
    mov r12, rsi
    xor edi, edi
    call fflush@PLT
    lea rax, [rip + Lrt_sh]
    mov [rsp + 8], rax
    lea rax, [rip + Lrt_dashc]
    mov [rsp + 16], rax
    mov [rsp + 24], rbx
    mov qword ptr [rsp + 32], 0
    mov rdi, rsp
    lea rsi, [rip + Lrt_binsh]
    xor edx, edx
    xor ecx, ecx
    lea r8, [rsp + 8]
    mov rax, [rip + environ@GOTPCREL]
    mov r9, [rax]
    call posix_spawn@PLT
    test eax, eax
    jnz 9f
    movsxd rax, dword ptr [rsp]
    add rsp, 48
    pop r12
    pop rbx
    pop rbp
    ret
9:  lea rdi, [rip + Lrt_espawn]
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
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + Lrt_procdir]
    call opendir@PLT
    test rax, rax
    jz 8f
    mov r13, rax
1:  mov rdi, r13
    call readdir@PLT
    test rax, rax
    jz 7f
    lea r14, [rax + 19]
    movzx eax, byte ptr [r14]
    sub eax, 48
    cmp eax, 9
    ja 1b
    mov rdi, r14
    xor esi, esi
    mov edx, 10
    call strtoll@PLT
    mov r15, rax
    mov rdi, r15
    lea rsi, [rip + Lrt_fcomm]
    call _bit_proc_path
    mov rdi, rax
    lea rsi, [rip + Lrt_rb]
    call fopen@PLT
    test rax, rax
    jz 1b
    mov r14, rax
    mov edi, 64
    call _bit_alloc
    mov [rsp], rax
    mov rdi, rax
    mov esi, 64
    mov rdx, r14
    call fgets@PLT
    mov rdi, r14
    call fclose@PLT
    mov rdi, [rsp]
    lea rsi, [rip + Lrt_nl]
    call strcspn@PLT
    mov rdi, [rsp]
    mov byte ptr [rdi + rax], 0
    mov rsi, rbx
    call strcmp@PLT
    test eax, eax
    jnz 1b
    mov rdi, r13
    call closedir@PLT
    mov rax, r15
    jmp 9f
7:  mov rdi, r13
    call closedir@PLT
8:  mov rax, -1
9:  add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_proc_alive:                    // rdi = pid → 1 если процесс есть
    push rbp
    mov rbp, rsp
    test rdi, rdi
    jle 2f
    xor esi, esi
    call kill@PLT
    test eax, eax
    jz 1f
    call __errno_location@PLT
    cmp dword ptr [rax], 1
    je 1f
2:  xor eax, eax
    pop rbp
    ret
1:  mov eax, 1
    pop rbp
    ret

_bit_proc_name:                     // rdi = pid → имя процесса или ""
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    lea rsi, [rip + Lrt_fcomm]
    call _bit_proc_path
    mov rbx, rax
    mov rdi, rax
    call _bit_file_exists
    test rax, rax
    jz 1f
    mov rdi, rbx
    xor esi, esi
    call _bit_file_read
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + Lrt_nl]
    call strcspn@PLT
    mov byte ptr [rbx + rax], 0
    mov rax, rbx
    jmp 2f
1:  lea rax, [rip + Lrt_empty]
2:  pop r12
    pop rbx
    pop rbp
    ret

_bit_proc_maps:                     // rdi = pid, rsi = строка → mas строк /proc/<pid>/maps
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov r12, rsi
    lea rsi, [rip + Lrt_fmaps]
    call _bit_proc_path
    mov rdi, rax
    mov rsi, r12
    call _bit_file_lines
    pop r12
    pop rbx
    pop rbp
    ret

_bit_proc_read:                     // rdi = pid, rsi = адрес, rdx = сколько байт, rcx = строка → bytes
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
    mov r14, rcx
    lea rsi, [rip + Lrt_fmem]
    call _bit_proc_path
    mov rbx, rax
    mov rdi, r13
    call _bit_bytes_new
    mov r15, rax
    mov rdi, rbx
    xor esi, esi
    xor eax, eax
    call open@PLT
    test eax, eax
    js 9f
    mov [rsp], rax
    mov edi, eax
    mov rsi, [r15]
    mov rdx, r13
    mov rcx, r12
    call pread@PLT
    cmp rax, r13
    jne 8f
    mov edi, dword ptr [rsp]
    call close@PLT
    mov rax, r15
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  mov edi, dword ptr [rsp]
    call close@PLT
9:  lea rdi, [rip + Lrt_epread]
    mov rsi, rbx
    mov rdx, r14
    call _bit_proc_fail

_bit_proc_write:                    // rdi = pid, rsi = адрес, rdx = bytes, rcx = строка
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
    mov r14, rcx
    lea rsi, [rip + Lrt_fmem]
    call _bit_proc_path
    mov rbx, rax
    mov rdi, rbx
    mov esi, 2
    xor eax, eax
    call open@PLT
    test eax, eax
    js 9f
    mov r15, rax
    mov edi, eax
    mov rsi, [r13]
    mov rdx, [r13 + 8]
    mov rcx, r12
    call pwrite@PLT
    cmp rax, [r13 + 8]
    jne 8f
    mov edi, r15d
    call close@PLT
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
8:  mov edi, r15d
    call close@PLT
9:  lea rdi, [rip + Lrt_epwrite]
    mov rsi, rbx
    mov rdx, r14
    call _bit_proc_fail

_bit_proc_kill:                     // rdi = pid, rsi = строка: просит процесс завершиться (SIGTERM)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    // pid <= 0 у kill значит «группа» или «все процессы» — не трогаем
    test rdi, rdi
    jle 8f
    mov esi, 15
    call kill@PLT
    test eax, eax
    jnz 9f
    pop r12
    pop rbx
    pop rbp
    ret
8:  mov rdi, rbx
    call _bit_num_str
    lea rdi, [rip + Lrt_mekill]
    mov rsi, rax
    mov rdx, r12
    call _bit_errpath
9:  mov rdi, rbx
    lea rsi, [rip + Lrt_fpid]
    call _bit_proc_path
    lea rdi, [rip + Lrt_ekill]
    mov rsi, rax
    mov rdx, r12
    call _bit_proc_fail

_bit_proc_wait:                     // rdi = pid → код выхода
    push rbp
    mov rbp, rsp
    sub rsp, 16
    // pid <= 0 у waitpid значит «любой ребёнок» — это не наш процесс
    test rdi, rdi
    jle 1f
    mov rsi, rsp
    xor edx, edx
    call waitpid@PLT
    test eax, eax
    js 1f
    mov edi, dword ptr [rsp]
    call _bit_wstatus
    jmp 2f
1:  mov rax, -1
2:  mov rsp, rbp
    pop rbp
    ret

_bit_proc_read_num:                 // rdi = pid, rsi = адрес, rdx = строка -> число (8 байт)
    push rbp
    mov rbp, rsp
    mov rcx, rdx
    mov edx, 8
    call _bit_proc_read
    mov rax, [rax]
    mov rax, [rax]
    pop rbp
    ret

_bit_proc_write_num:                // rdi = pid, rsi = адрес, rdx = число, rcx = строка
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
    mov edi, 8
    call _bit_bytes_new
    mov rcx, [rax]
    mov [rcx], r13
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    mov rcx, r14
    call _bit_proc_write
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_proc_try:                      // rdi=pid, rsi=адрес, rdx=сколько -> bytes или 0 (без ошибки)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rsi
    mov r13, rdx
    lea rsi, [rip + Lrt_fmem]
    call _bit_proc_path
    mov rbx, rax
    mov rdi, r13
    call _bit_bytes_new
    mov r14, rax
    mov rdi, rbx
    xor esi, esi
    xor eax, eax
    call open@PLT
    test eax, eax
    js 8f
    mov ebx, eax
    mov edi, ebx
    mov rsi, [r14]
    mov rdx, r13
    mov rcx, r12
    call pread@PLT
    cmp rax, r13
    jne 7f
    mov edi, ebx
    call close@PLT
    mov rax, r14
    jmp 9f
7:  mov edi, ebx
    call close@PLT
8:  xor eax, eax
9:  pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_bit_proc_scan:                     // rdi=pid, rsi=число, rdx=строка -> mas:num адресов
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
    mov r13, rdx
    mov rdi, rbx
    mov rsi, r13
    call _bit_proc_maps
    mov r15, rax
    mov rdi, -1
    xor esi, esi
    call _bit_mas_new
    mov r14, rax
    mov qword ptr [rbp - 48], 0
.Ls_loop:
    mov rax, [rbp - 48]
    cmp rax, [r15 + 8]
    jge .Ls_done
    mov rcx, [r15]
    mov rdi, [rcx + rax*8]
    call _bit_hexval_ptr
    mov [rbp - 56], rax
    cmp byte ptr [rdx], 45
    jne .Ls_next
    lea rdi, [rdx + 1]
    call _bit_hexval_ptr
    mov [rbp - 64], rax
    mov rdi, rdx
.Ls_sp:
    movzx eax, byte ptr [rdi]
    test eax, eax
    je .Ls_next
    cmp eax, 32
    je .Ls_perm
    inc rdi
    jmp .Ls_sp
.Ls_perm:
    inc rdi
    cmp byte ptr [rdi], 114
    jne .Ls_next
    mov rax, [rbp - 64]
    sub rax, [rbp - 56]
    test rax, rax
    jle .Ls_next
    mov rcx, 0x10000000
    cmp rax, rcx
    ja .Ls_next
    mov [rbp - 72], rax
    mov rdi, rbx
    mov rsi, [rbp - 56]
    mov rdx, [rbp - 72]
    call _bit_proc_try
    test rax, rax
    jz .Ls_next
    mov [rbp - 104], rax
    mov rcx, [rax]
    mov [rbp - 80], rcx
    mov qword ptr [rbp - 88], 0
    mov rax, [rbp - 72]
    sub rax, 8
    mov [rbp - 96], rax
.Ls_scan:
    mov r10, [rbp - 88]
    cmp r10, [rbp - 96]
    jg .Ls_region
    mov r8, [rbp - 80]
    mov rax, [r8 + r10]
    cmp rax, r12
    jne .Ls_sn
    mov rsi, [rbp - 56]
    add rsi, r10
    mov rdi, r14
    mov rdx, r13
    call _bit_mas_add
.Ls_sn:
    mov r10, [rbp - 88]
    inc r10
    mov [rbp - 88], r10
    jmp .Ls_scan
.Ls_region:
    mov rdi, [rbp - 80]
    call free@PLT
    mov rdi, [rbp - 104]
    call free@PLT
.Ls_next:
    mov rax, [rbp - 48]
    inc rax
    mov [rbp - 48], rax
    jmp .Ls_loop
.Ls_done:
    mov rax, r14
    lea rsp, [rbp - 40]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
"""
i = t.index("\n.data")
t = t[:i] + "\n" + PROC + t[i:]

def octal(s):
    return '"' + "".join(chr(b) if 32 <= b < 127 and b not in (34, 92) else "\\%03o" % b for b in s.encode()) + '"'
strs = {"Lrt_colon": ": ", "Lrt_sh": "sh", "Lrt_dashc": "-c", "Lrt_binsh": "/bin/sh", "Lrt_procdir": "/proc",
        "Lrt_fcomm": "/proc/%lld/comm", "Lrt_fmaps": "/proc/%lld/maps", "Lrt_fmem": "/proc/%lld/mem",
        "Lrt_fpid": "/proc/%lld", "Lrt_nl": "\n",
        "Lrt_espawn": "не могу запустить: ", "Lrt_epread": "не могу прочитать память ",
        "Lrt_epwrite": "не могу записать в память ", "Lrt_ekill": "не могу остановить "}
t = t.replace(".section .rodata\n", ".section .rodata\n" + "".join(f"{k}: .asciz {octal(v)}\n" for k, v in strs.items()), 1)
t += '\n.section .note.GNU-stack,"",@progbits\n'
open("rt/x86_64-linux.s", "w").write(t)
left = sorted(set(re.findall(r"call (_[a-z][a-z_0-9]*)", t)) - set(re.findall(r"^(_bit_[a-z_0-9]+):", t, re.M)))
print("ok; неразрешённые вызовы:", left)
