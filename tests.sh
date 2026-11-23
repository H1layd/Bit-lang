#!/bin/sh
# Проверка bit: примеры, ошибки и исправления на arm64 и x86_64, плюс самосборка.
cd "$(dirname "$0")"
ok=0; bad=0
pass() { ok=$((ok+1)); }
fail() { bad=$((bad+1)); echo "НЕ СОВПАЛО: $1"; }

ARCHES="arm64 x86_64"
[ "$(uname -s)" = Linux ] && ARCHES="x86_64"
for a in $ARCHES; do
    for f in hello demo ext chains; do
        out=$(printf '9\nabc\n2\n' | ./bitc run "examples/$f.bit" --arch "$a" 2>&1)
        [ "$out" = "$(cat "tests/expected/$f.txt")" ] && pass || fail "$f [$a]"
    done
    for f in examples/errors/*.bit; do
        n=$(basename "$f" .bit)
        out=$(./bitc run "$f" --arch "$a" </dev/null 2>&1)
        [ "$out" = "$(cat "tests/expected/err_$n.txt")" ] && pass || fail "$f [$a]"
    done
    for f in tests/fixes/*.bit; do
        n="${f%.bit}"; inp=/dev/null; [ -f "$n.in" ] && inp="$n.in"
        out=$(./bitc run "$f" --arch "$a" < "$inp" 2>&1; echo "$? ")
        [ "$out" = "$(cat "$n.out")" ] && pass || fail "$f [$a]"
    done
done

T="${TMPDIR:-/tmp}"
./bitc asm bitc.bit --arch arm64 > "$T/bit_self.s"
./bitc build bitc.bit -o "$T/bit_self" >/dev/null && "$T/bit_self" asm bitc.bit --arch arm64 | cmp -s - "$T/bit_self.s" \
    && { pass; echo "самосборка: сошлась"; } || fail "самосборка"
echo "прошло: $ok, упало: $bad"
[ "$bad" = 0 ]
