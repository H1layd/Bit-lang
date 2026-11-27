#!/bin/sh
# Проверка bit: примеры, ошибки и исправления на arm64 и x86_64, плюс самосборка.
cd "$(dirname "$0")"
ok=0; bad=0
pass() { ok=$((ok+1)); }
fail() { bad=$((bad+1)); echo "НЕ СОВПАЛО: $1"; }

ARCHES="arm64 x86_64"
[ "$(uname -s)" = Linux ] && ARCHES="x86_64"
mkdir -p build/test-helpers
for a in $ARCHES; do
    helper="build/test-helpers/workenv_child_$a"
    ./bitc build tests/helpers/workenv_child.bit --arch "$a" -o "$helper" >/dev/null || exit 1
    for f in hello demo ext chains; do
        out=$(printf '9\nabc\n2\n' | ./bitc run "examples/$f.bit" --arch "$a" 2>&1)
        if [ "$out" = "$(cat "tests/expected/$f.txt")" ]; then
            pass
        else
            fail "$f [$a]"
            printf 'Ожидалось:\n%s\nПолучено:\n%s\n' "$(cat "tests/expected/$f.txt")" "$out"
        fi
    done
    for f in examples/errors/*.bit; do
        n=$(basename "$f" .bit)
        out=$(./bitc run "$f" --arch "$a" </dev/null 2>&1)
        if [ "$out" = "$(cat "tests/expected/err_$n.txt")" ]; then
            pass
        else
            fail "$f [$a]"
            printf 'Ожидалось:\n%s\nПолучено:\n%s\n' "$(cat "tests/expected/err_$n.txt")" "$out"
        fi
    done
    for f in tests/fixes/*.bit; do
        n="${f%.bit}"; inp=/dev/null; [ -f "$n.in" ] && inp="$n.in"
        if [ "$(basename "$n")" = workenv ]; then
            out=$(./bitc run "$f" --arch "$a" -- "$helper" < "$inp" 2>&1; echo "$? ")
        else
            out=$(./bitc run "$f" --arch "$a" < "$inp" 2>&1; echo "$? ")
        fi
        if [ "$out" = "$(cat "$n.out")" ]; then
            pass
        else
            fail "$f [$a]"
            printf 'Ожидалось:\n%s\nПолучено:\n%s\n' "$(cat "$n.out")" "$out"
        fi
    done
done

T="${TMPDIR:-/tmp}"
./bitc asm bitc.bit --arch arm64 > "$T/bit_self.s"
./bitc build bitc.bit -o "$T/bit_self" >/dev/null && "$T/bit_self" asm bitc.bit --arch arm64 | cmp -s - "$T/bit_self.s" \
    && { pass; echo "самосборка: сошлась"; } || fail "самосборка"
# Низкоуровневая проверка реально освобождённых строк и очистки recover.
# Не делает Python зависимостью компилятора: при его отсутствии сообщает о пропуске.
if command -v python3 >/dev/null 2>&1; then
    if python3 tools/test_string_refs.py; then pass; else fail "подсчёт ссылок строк"; fi
    if python3 tools/test_thread_lifecycle.py; then pass; else fail "ожидание потоков"; fi
    if python3 tools/test_x86_stack_audit.py; then pass; else fail "выравнивание стека x86"; fi
    if python3 tools/test_posix_signals.py; then pass; else fail "сигналы POSIX"; fi
    if python3 tools/test_ping_native.py; then pass; else fail "ping без внешней программы"; fi
else
    echo "проверки ссылок, потоков, стека x86, сигналов и ping пропущены: нужен python3"
fi
echo "прошло: $ok, упало: $bad"
[ "$bad" = 0 ]
