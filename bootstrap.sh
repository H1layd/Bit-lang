#!/bin/sh
# Собирает компилятор bit с нуля — без Python и без C.
#   1. системные as/ld собирают bitc0 из готового ассемблера (bootstrap/)
#   2. bitc0 собирает bitc из исходника bitc.bit
#   3. bitc собирает себя ещё раз и проверяет, что код не изменился
set -e
cd "$(dirname "$0")"
ARCH=$(uname -m)
OS=$(uname -s)
TMP="${TMPDIR:-/tmp}/bit_bootstrap"
mkdir -p "$TMP"

if [ "$OS" = Linux ]; then
    SEED="bootstrap/bitc_x86_64-linux.s"
    L=$(for d in /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu; do [ -f "$d/crt1.o" ] && echo "$d" && break; done)
    echo "1/3 as + ld: $SEED -> bitc0"
    as --64 -o "$TMP/bitc0.o" "$SEED"
    ld -o "$TMP/bitc0" -dynamic-linker /lib64/ld-linux-x86-64.so.2 "$L/crt1.o" "$L/crti.o" "$TMP/bitc0.o" -ldl -lpthread -lc "$L/crtn.o"
    OSFLAG="--os linux"
else
    SEED="bootstrap/bitc_$ARCH.s"
    SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
    echo "1/3 as + ld: $SEED -> bitc0"
    as -arch "$ARCH" -mmacosx-version-min=13.0 -o "$TMP/bitc0.o" "$SEED"
    ld -arch "$ARCH" -platform_version macos 13.0 13.0 -syslibroot "$SDK" -lSystem -e _main -o "$TMP/bitc0" "$TMP/bitc0.o"
    OSFLAG=""
fi

echo "2/3 bitc0: bitc.bit -> bitc"
"$TMP/bitc0" build bitc.bit -o bitc >/dev/null
echo "3/3 bitc собирает сам себя"
./bitc asm bitc.bit $OSFLAG > "$TMP/a.s"
"$TMP/bitc0" asm bitc.bit $OSFLAG > "$TMP/b.s"
cmp -s "$TMP/a.s" "$TMP/b.s" && echo "готово: ./bitc (самосборка сошлась)"
