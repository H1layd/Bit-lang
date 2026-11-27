@echo off
setlocal
set "BIT_PING_MARKER=%CD%\ping-spawned.txt"
if exist "%BIT_PING_MARKER%" exit /b 2
set "PATH=%CD%"
ping-test.exe 127.0.0.1 > ping-ip4.out
if errorlevel 1 exit /b 3
ping-test.exe localhost > ping-local.out
if errorlevel 1 exit /b 4
ping-test.exe ::1 > ping-ip6.out
if errorlevel 1 exit /b 5
ping-test.exe > ping-empty.out
if errorlevel 1 exit /b 6
ping-threads.exe > ping-threads.out
if errorlevel 1 exit /b 12
if exist "%BIT_PING_MARKER%" exit /b 7
set /p v=<ping-ip4.out
if not "%v%"=="true" exit /b 8
set /p v=<ping-local.out
if not "%v%"=="true" exit /b 9
set /p v=<ping-ip6.out
if not "%v%"=="true" exit /b 10
set /p v=<ping-empty.out
if not "%v%"=="false" exit /b 11
set /p v=<ping-threads.out
if not "%v%"=="64 64 64 64" exit /b 13
echo Windows native IPv4/IPv6 ping passed
exit /b 0
