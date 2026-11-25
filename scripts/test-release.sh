#!/bin/sh
# Exercises scripts/release.sh through its command line, in throwaway copies of the repository.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAILURES=0

fail() {
    echo "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

# Copies the working tree into a fresh git repository with one commit.
new_repo() {
    dir="$WORK/$1"
    mkdir -p "$dir"
    (cd "$ROOT" && tar --exclude=.git --exclude=dist --exclude='*.xcodeproj' --exclude=.build --exclude=DerivedData --exclude=.artifacts -cf - .) | (cd "$dir" && tar -xf -)
    (cd "$dir" && git init -q && git add -A && git -c user.name=test -c user.email=test@example.com commit -q -m init)
    echo "$dir"
}

run_release() {
    dir=$1
    shift
    (cd "$dir" && env -u DEVELOPER_ID_IDENTITY -u NOTARY_KEYCHAIN_PROFILE "$@" sh scripts/release.sh $RELEASE_ARGS >"$WORK/out.log" 2>&1)
}

expect_error_before_build() {
    name=$1
    dir=$2
    pattern=$3
    if [ -n "${4:-}" ]; then
        run_release "$dir" "$4"
    else
        run_release "$dir"
    fi
    status=$?
    if [ "$status" -eq 0 ]; then
        fail "$name: expected a nonzero exit"
    fi
    if ! grep -qi "$pattern" "$WORK/out.log"; then
        fail "$name: expected an error matching '$pattern'"
        cat "$WORK/out.log"
    fi
    if [ -e "$dir/dist" ] || [ -e "$dir/Solvr.xcodeproj" ]; then
        fail "$name: the build started before the guard"
    fi
}

RELEASE_ARGS=""

# Uncommitted changes without the skip-checks flag.
repo=$(new_repo dirty)
(cd "$repo" && git tag v0.1.0 && echo change >>README.md)
expect_error_before_build "dirty tree" "$repo" "uncommitted"

# Clean tree without a tag for the current version on HEAD.
repo=$(new_repo untagged)
(cd "$repo" && git tag v9.9.9)
expect_error_before_build "missing tag" "$repo" "v0.1.0"

# Only one of the two signing variables.
repo=$(new_repo half-identity)
RELEASE_ARGS="--skip-checks"
expect_error_before_build "identity only" "$repo" "NOTARY_KEYCHAIN_PROFILE" "DEVELOPER_ID_IDENTITY=none"
repo=$(new_repo half-profile)
expect_error_before_build "profile only" "$repo" "DEVELOPER_ID_IDENTITY" "NOTARY_KEYCHAIN_PROFILE=none"

# Ad-hoc build on a dirty, untagged tree with the skip-checks flag.
repo=$(new_repo adhoc)
echo change >>"$repo/README.md"
if ! run_release "$repo"; then
    fail "ad-hoc build: expected exit 0"
    cat "$repo/out.log"
fi
zip="$repo/dist/Solvr-0.1.0.zip"
if [ ! -f "$zip" ]; then
    fail "ad-hoc build: dist/Solvr-0.1.0.zip missing"
else
    unpacked="$WORK/unpacked"
    mkdir -p "$unpacked"
    ditto -x -k "$zip" "$unpacked"
    app="$unpacked/Solvr.app"
    if ! codesign --verify --strict "$app" 2>"$WORK/verify.log"; then
        fail "ad-hoc build: signature verification failed"
        cat "$WORK/verify.log"
    fi
    if ! codesign -dv "$app" 2>&1 | grep -q "Signature=adhoc"; then
        fail "ad-hoc build: signature is not ad-hoc"
    fi
    plist="$app/Contents/Info.plist"
    [ "$(defaults read "$plist" CFBundleShortVersionString)" = "0.1.0" ] || fail "ad-hoc build: version is not 0.1.0"
    [ "$(defaults read "$plist" CFBundleVersion)" = "1" ] || fail "ad-hoc build: build is not 1"
    [ "$(defaults read "$plist" CFBundleIdentifier)" = "dev.adeonir.labs.Solvr" ] || fail "ad-hoc build: bundle identifier is wrong"
fi

if [ "$FAILURES" -ne 0 ]; then
    echo "$FAILURES failure(s)"
    exit 1
fi
echo "release script tests passed"
