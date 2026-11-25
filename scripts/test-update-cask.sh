#!/bin/sh
# Exercises scripts/update-cask.sh through its command line against a throwaway tap directory.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAILURES=0

fail() {
    echo "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

echo "solvr asset" >"$WORK/Solvr-0.1.0.zip"
SHA=$(shasum -a 256 "$WORK/Solvr-0.1.0.zip" | cut -d ' ' -f 1)
TAP="$WORK/tap"
mkdir -p "$TAP"
CASK="$TAP/Casks/solvr.rb"

update() {
    sh "$ROOT/scripts/update-cask.sh" "$TAP" "$@" >"$WORK/out.log" 2>&1
}

# A verified asset writes the version and the checksum into the cask.
update 0.1.0 "$SHA" "$WORK/Solvr-0.1.0.zip" || { fail "update: expected exit 0"; cat "$WORK/out.log"; }
grep -q "version \"0.1.0\"" "$CASK" || fail "update: expected version 0.1.0 in the cask"
grep -q "sha256 \"$SHA\"" "$CASK" || fail "update: expected the sha256 in the cask"
grep -q 'cask "solvr"' "$CASK" || fail "update: expected the cask name solvr"
if grep -q '@[A-Z_]*@' "$CASK"; then fail "update: placeholder left in the cask"; fi

# Running again with the same version and checksum leaves the cask unchanged.
cp "$CASK" "$WORK/before.rb"
update 0.1.0 "$SHA" "$WORK/Solvr-0.1.0.zip" || fail "repeat: expected exit 0"
cmp -s "$CASK" "$WORK/before.rb" || fail "repeat: expected the cask unchanged"

# A different checksum at tap time fails and leaves the tap untouched.
rm -rf "$TAP/Casks"
OTHER=$(printf 'other' | shasum -a 256 | cut -d ' ' -f 1)
update 0.1.0 "$OTHER" "$WORK/Solvr-0.1.0.zip" && fail "mismatch: expected a nonzero exit"
[ -e "$CASK" ] && fail "mismatch: expected no cask written"
grep -qi "sha256" "$WORK/out.log" || fail "mismatch: expected an error naming the checksum"

if [ "$FAILURES" -ne 0 ]; then
    echo "$FAILURES failure(s)"
    exit 1
fi
echo "update cask tests passed"
