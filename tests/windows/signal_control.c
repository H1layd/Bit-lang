/* Isolated console-control integration test. Run next to signal-child.exe and
   signal-default.exe in an empty directory. No signals are sent to the caller. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

/* mode: 0 = default disposition, 1 = interrupted input, 2 = worker thread. */
static int run_case(const char *label, const char *exe, DWORD event, int mode) {
    SECURITY_ATTRIBUTES sa = { sizeof(sa), NULL, TRUE };
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    HANDLE in_read = NULL, in_write = NULL, output = INVALID_HANDLE_VALUE;
    char ready[128], logname[128], command[512], output_text[256];
    DWORD received = 0, exit_code = 0, n = 0;
    int result = 1;
    snprintf(ready, sizeof(ready), "%s.ready", label);
    snprintf(logname, sizeof(logname), "%s.output", label);
    snprintf(command, sizeof(command), "%s %s", exe, ready);
    if (GetFileAttributesA(ready) != INVALID_FILE_ATTRIBUTES) {
        fprintf(stderr, "%s already exists; use an empty directory\n", ready);
        goto cleanup;
    }
    if (!CreatePipe(&in_read, &in_write, &sa, 0) ||
        !SetHandleInformation(in_write, HANDLE_FLAG_INHERIT, 0)) goto cleanup;
    output = CreateFileA(logname, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                         &sa, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if (output == INVALID_HANDLE_VALUE) goto cleanup;
    ZeroMemory(&si, sizeof(si));
    ZeroMemory(&pi, sizeof(pi));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    si.hStdInput = in_read;
    si.hStdOutput = output;
    si.hStdError = output;
    if (!CreateProcessA(NULL, command, NULL, NULL, TRUE,
                        CREATE_NEW_CONSOLE | CREATE_NEW_PROCESS_GROUP,
                        NULL, NULL, &si, &pi)) goto cleanup;
    CloseHandle(pi.hThread);
    CloseHandle(in_read); in_read = NULL;
    CloseHandle(output); output = INVALID_HANDLE_VALUE;
    for (int i = 0; i < 1000; ++i) {
        if (GetFileAttributesA(ready) != INVALID_FILE_ATTRIBUTES) break;
        if (WaitForSingleObject(pi.hProcess, 0) != WAIT_TIMEOUT) goto child_cleanup;
        Sleep(10);
    }
    if (GetFileAttributesA(ready) == INVALID_FILE_ATTRIBUTES) goto child_cleanup;
    Sleep(200); /* let the child reach its blocking read */
    FreeConsole();
    if (!AttachConsole(pi.dwProcessId)) goto child_cleanup;
    if (event == CTRL_CLOSE_EVENT) {
        HWND window = GetConsoleWindow();
        FreeConsole();
        if (!window || !PostMessageA(window, WM_CLOSE, 0, 0)) goto child_cleanup;
    } else {
        if (!SetConsoleCtrlHandler(NULL, TRUE)) goto child_cleanup;
        if (!GenerateConsoleCtrlEvent(event, event == CTRL_C_EVENT ? 0 : pi.dwProcessId)) goto child_cleanup;
        Sleep(200);
        FreeConsole();
    }
    if (mode == 1) {
        Sleep(100);
        if (!WriteFile(in_write, "x", 1, &n, NULL) || n != 1) goto child_cleanup;
    }
    if (WaitForSingleObject(pi.hProcess, 10000) != WAIT_OBJECT_0) goto child_cleanup;
    if (!GetExitCodeProcess(pi.hProcess, &exit_code)) goto child_cleanup;
    if (mode != 0) {
        if (exit_code != 0) goto child_cleanup;
        HANDLE file = CreateFileA(logname, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                  NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (file == INVALID_HANDLE_VALUE) goto child_cleanup;
        if (!ReadFile(file, output_text, sizeof(output_text) - 1, &received, NULL)) {
            CloseHandle(file); goto child_cleanup;
        }
        CloseHandle(file);
        output_text[received] = 0;
        const char *expected_crlf = mode == 2 ? "true\r\n" : "true x true\r\n";
        const char *expected_lf = mode == 2 ? "true\n" : "true x true\n";
        if (strcmp(output_text, expected_crlf) != 0 && strcmp(output_text, expected_lf) != 0) {
            fprintf(stderr, "%s output: %s\n", label, output_text);
            goto child_cleanup;
        }
    } else if (exit_code == 0) goto child_cleanup;
    printf("%s passed\n", label);
    result = 0;
child_cleanup:
    if (result) {
        DWORD err = GetLastError();
        fprintf(stderr, "%s failed, windows error=%lu exit=%lu\n", label, (unsigned long)err, (unsigned long)exit_code);
        if (WaitForSingleObject(pi.hProcess, 0) == WAIT_TIMEOUT) TerminateProcess(pi.hProcess, 1);
    }
    CloseHandle(pi.hProcess);
cleanup:
    if (in_read) CloseHandle(in_read);
    if (in_write) CloseHandle(in_write);
    if (output != INVALID_HANDLE_VALUE) CloseHandle(output);
    return result;
}

int main(void) {
    if (run_case("ctrl-c", "signal-child.exe", CTRL_C_EVENT, 1)) return 1;
    if (run_case("ctrl-break", "signal-child.exe", CTRL_BREAK_EVENT, 1)) return 1;
    if (run_case("generic-ctrl-c", "signal-generic.exe", CTRL_C_EVENT, 1)) return 1;
    if (run_case("thread-ctrl-c", "signal-thread.exe", CTRL_C_EVENT, 2)) return 1;
    if (run_case("thread-ctrl-break", "signal-thread.exe", CTRL_BREAK_EVENT, 2)) return 1;
    if (run_case("default-break", "signal-default.exe", CTRL_BREAK_EVENT, 0)) return 1;
    if (run_case("ctrl-close", "signal-child.exe", CTRL_CLOSE_EVENT, 1)) return 1;
    return 0;
}
