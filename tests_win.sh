#!/bin/sh
# Тесты bit на настоящей Windows: собирает примеры и тесты под Windows, запускает их по SSH
# и сравнивает вывод с ожидаемым. Запуск: ./tests_win.sh хост   (хост из ~/.ssh/config)
# Без запуска на Windows: ./tests_win.sh --build-only
# --stack-check перед именем хоста добавляет проверку RSP перед каждым вызовом.
cd "$(dirname "$0")"
stack_check=0
if [ "${1:-}" = --stack-check ]; then stack_check=1; shift; fi
H="${1:?укажи хост: ./tests_win.sh хост (или --build-only)}"
build_only=0
[ "$H" != --build-only ] || build_only=1
W="${TMPDIR:-/tmp}/bit_win_tests"
rm -rf "$W"; mkdir -p "$W/got"
bat="$W/all.bat"
printf '@echo off\r\nchcp 65001 >nul\r\n' > "$bat"
# Проверка запрета записи в корень зависит от прав и устройства ОС.
SKIP=" err_bad_dir "
compile_only=0
add() {  # id файл вход ожидаемое с_кодом
    case "$SKIP" in *" $1 "*) return 0;; esac
    if [ "$stack_check" = 1 ]; then
        python3 tools/build_windows_stack_checked.py "$2" "$W/$1.exe" >"$W/$1.build" 2>&1
    else
        ./bitc build "$2" -o "$W/$1.exe" --os windows >"$W/$1.build" 2>&1
    fi
    code=$?
    if [ "$code" != 0 ]; then
        if [ "$5" = 1 ]; then printf '%s \n' "$code" >> "$W/$1.build"; fi
        if { [ "${6:-0}" = 1 ] || [ "$5" = 1 ]; } && cmp -s "$W/$1.build" "$4"; then
            compile_only=$((compile_only+1))
            return 0
        fi
        echo "ОШИБКА СБОРКИ: $1"
        cat "$W/$1.build"
        return 1
    fi
    cp "$3" "$W/$1.in"; cp "$4" "$W/$1.exp"; echo "$5" > "$W/$1.mode"
    extra=""
    [ "$1" != fix_workenv ] || extra=" bit_env_child.exe"
    printf '%s.exe%s < %s.in > %s.got 2>&1\r\necho %%ERRORLEVEL%% > %s.code\r\n' "$1" "$extra" "$1" "$1" "$1" >> "$bat"
}
./bitc build tests/windows/proc_target.bit -o "$W/bit_proc_target.exe" --os windows >/dev/null || exit 1
./bitc build tests/helpers/workenv_child.bit -o "$W/bit_env_child.exe" --os windows >/dev/null || exit 1
printf '9\nabc\n2\n' > "$W/ex.in"; : > "$W/null.in"
for f in hello demo ext chains; do add "ex_$f" "examples/$f.bit" "$W/ex.in" "tests/expected/$f.txt" 0 || exit 1; done
for f in examples/errors/*.bit; do n=$(basename "$f" .bit); add "err_$n" "$f" "$W/null.in" "tests/expected/err_$n.txt" 0 1 || exit 1; done
for f in tests/fixes/*.bit; do
    n="${f%.bit}"; inp="$W/null.in"; [ -f "$n.in" ] && inp="$n.in"
    expected="$n.out"
    variant="tests/windows/$(basename "$f")"
    if [ -f "$variant" ]; then
        f="$variant"
    fi
    [ ! -f "${variant%.bit}.out" ] || expected="${variant%.bit}.out"
    add "fix_$(basename "$n")" "$f" "$inp" "$expected" 1 || exit 1
done
if [ "$build_only" = 1 ]; then
    set -- "$W"/*.exp
    echo "Windows: собрано $# запусков; ошибки сборки проверены: $compile_only; на Windows не запускалось"
    exit 0
fi
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
echo "Windows: прошло $ok, упало $bad; ошибки сборки проверены: $compile_only (вывод в $W/got)"
[ "$bad" = 0 ]
