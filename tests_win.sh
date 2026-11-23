#!/bin/sh
# Тесты bit на настоящей Windows: собирает примеры и тесты под Windows, запускает их по SSH
# и сравнивает вывод с ожидаемым. Запуск: ./tests_win.sh хост   (хост из ~/.ssh/config)
cd "$(dirname "$0")"
H="${1:?укажи хост: ./tests_win.sh хост}"
W="${TMPDIR:-/tmp}/bit_win_tests"
rm -rf "$W"; mkdir -p "$W/got"
bat="$W/all.bat"
printf '@echo off\r\nchcp 65001 >nul\r\n' > "$bat"
# Эти тесты вызывают POSIX-утилиты (sh, printf, mktemp) или пути вида /tmp — на Windows их нет.
SKIP=" err_bad_dir fix_filechunks fix_filesafe fix_fsfix fix_runpipes fix_status "
add() {  # id файл вход ожидаемое с_кодом
    case "$SKIP" in *" $1 "*) return 0;; esac
    ./bitc build "$2" -o "$W/$1.exe" --os windows >/dev/null 2>&1 || return 0
    cp "$3" "$W/$1.in"; cp "$4" "$W/$1.exp"; echo "$5" > "$W/$1.mode"
    printf '%s.exe < %s.in > %s.got 2>&1\r\necho %%ERRORLEVEL%% > %s.code\r\n' "$1" "$1" "$1" "$1" >> "$bat"
}
printf '9\nabc\n2\n' > "$W/ex.in"; : > "$W/null.in"
for f in hello demo ext chains; do add "ex_$f" "examples/$f.bit" "$W/ex.in" "tests/expected/$f.txt" 0; done
for f in examples/errors/*.bit; do n=$(basename "$f" .bit); add "err_$n" "$f" "$W/null.in" "tests/expected/err_$n.txt" 0; done
for f in tests/fixes/*.bit; do
    n="${f%.bit}"; inp="$W/null.in"; [ -f "$n.in" ] && inp="$n.in"
    add "fix_$(basename "$n")" "$f" "$inp" "$n.out" 1
done
ssh "$H" "rmdir /s /q bit-win-tests 2>nul & mkdir bit-win-tests" || exit 1
(cd "$W" && scp -q ./*.exe ./*.in all.bat "$H:bit-win-tests/") || exit 1
ssh "$H" "cd bit-win-tests && all.bat" >/dev/null 2>&1
scp -q "$H:bit-win-tests/*.got" "$H:bit-win-tests/*.code" "$W/got/" || exit 1
ok=0; bad=0
for e in "$W"/*.exp; do
    id=$(basename "$e" .exp)
    got=$(tr -d '\r' < "$W/got/$id.got")
    if [ "$(cat "$W/$id.mode")" = 1 ]; then got="$got
$(tr -d '\r ' < "$W/got/$id.code") "; fi
    if [ "$got" = "$(cat "$e")" ]; then ok=$((ok+1)); else bad=$((bad+1)); echo "НЕ СОВПАЛО: $id"; fi
done
echo "Windows: прошло $ok, упало $bad (вывод в $W/got)"
[ "$bad" = 0 ]
