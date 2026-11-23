#!/bin/sh
# Build the optimizing variant from the same frontend and runtime as bitc.
set -eu
cd "$(dirname "$0")/.."

if [ ! -x ./bitc ]; then
    echo "Сначала собери ./bitc через ./bootstrap.sh" >&2
    exit 1
fi

mkdir -p build
tmp=$(mktemp -d build/bitc-opt.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM

awk '
    /^bool OPTIMIZE = false;$/ { sub(/false/, "true"); enabled++ }
    { print }
    END { if (enabled != 1) exit 1 }
' bitc.bit > "$tmp/bitc.bit"

./bitc build "$tmp/bitc.bit" -o "$tmp/bitc-opt" >/dev/null
mv -f "$tmp/bitc-opt" build/bitc-opt
echo "готово: build/bitc-opt"
