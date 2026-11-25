#!/bin/sh
# Writes the Homebrew cask into a tap checkout. Usage: update-cask.sh <tap-dir> <version> <verified-sha256> <zip>.
# Fails before writing when the zip's sha256 differs from the verified one. Rewriting an identical cask changes nothing.
set -eu

[ $# -eq 4 ] || { echo "usage: update-cask.sh <tap-dir> <version> <verified-sha256> <zip>" >&2; exit 2; }
tap=$1
version=$2
verified=$3
zip=$4

actual=$(shasum -a 256 "$zip" | cut -d ' ' -f 1)
if [ "$actual" != "$verified" ]; then
    echo "error: the asset sha256 $actual differs from the verified sha256 $verified; the tap is not updated" >&2
    exit 1
fi

template="$(cd "$(dirname "$0")/.." && pwd)/packaging/homebrew/solvr.rb"
mkdir -p "$tap/Casks"
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$verified/" "$template" >"$tap/Casks/solvr.rb"
