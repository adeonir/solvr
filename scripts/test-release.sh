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
    (cd "$ROOT" && tar --exclude=.git --exclude=dist --exclude='*.xcodeproj' --exclude=.build --exclude=DerivedData --exclude=.artifacts --exclude=.env.release -cf - .) | (cd "$dir" && tar -xf -)
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
    cat "$WORK/out.log"
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

# Developer ID mode, with codesign, xcrun, and spctl replaced by stubs that log their calls.
make_stubs() {
    stubs="$WORK/stubs"
    mkdir -p "$stubs"
    cat >"$stubs/codesign" <<'STUB'
#!/bin/sh
case " $* " in
    *" --sign "*)
        case " $* " in *" --sign - "*) ;; *) echo "codesign $*" >>"$STUB_LOG"; exit 0 ;; esac
        ;;
esac
exec /usr/bin/codesign "$@"
STUB
    cat >"$stubs/xcrun" <<'STUB'
#!/bin/sh
case "$1 $2" in
    "notarytool submit")
        echo "xcrun $*" >>"$STUB_LOG"
        echo "{\"id\":\"1234-abcd\",\"status\":\"$STUB_NOTARY_STATUS\",\"message\":\"stub\"}"
        ;;
    "stapler staple" | "stapler validate")
        echo "xcrun $*" >>"$STUB_LOG"
        ;;
    *) exec /usr/bin/xcrun "$@" ;;
esac
STUB
    cat >"$stubs/spctl" <<'STUB'
#!/bin/sh
echo "spctl $*" >>"$STUB_LOG"
STUB
    chmod +x "$stubs/codesign" "$stubs/xcrun" "$stubs/spctl"
}

make_stubs
SIGN_ENV="DEVELOPER_ID_IDENTITY=Stub-Identity NOTARY_KEYCHAIN_PROFILE=stub-profile PATH=$WORK/stubs:$PATH STUB_LOG=$WORK/stub.log"

# Accepted notarization.
repo=$(new_repo notarized)
: >"$WORK/stub.log"
# shellcheck disable=SC2086
if ! run_release "$repo" $SIGN_ENV STUB_NOTARY_STATUS=Accepted; then
    fail "notarized build: expected exit 0"
    cat "$WORK/out.log"
fi
log=$(cat "$WORK/stub.log")
core_line=$(echo "$log" | grep -n "codesign.*Core.framework" | head -1 | cut -d: -f1)
app_line=$(echo "$log" | grep -n "codesign.*Solvr.app$" | head -1 | cut -d: -f1)
[ -n "$core_line" ] && [ -n "$app_line" ] && [ "$core_line" -lt "$app_line" ] || fail "notarized build: nested code is not signed before the app"
echo "$log" | grep "^codesign" | grep -q -- "--options runtime" || fail "notarized build: hardened runtime missing"
[ "$(echo "$log" | grep '^codesign' | grep -c -- '--timestamp')" -eq 2 ] || fail "notarized build: secure timestamp missing"
echo "$log" | grep "^codesign" | grep -q -- "Stub-Identity" || fail "notarized build: Developer ID identity unused"
echo "$log" | grep "^codesign" | grep -q -- "--deep" && fail "notarized build: --deep used"
echo "$log" | grep -q "notarytool submit.*--keychain-profile stub-profile" || fail "notarized build: submission missing"
echo "$log" | grep -q "stapler staple.*Solvr.app" || fail "notarized build: ticket not stapled"
echo "$log" | grep -q "spctl .*--assess.*Solvr.app" || fail "notarized build: Gatekeeper assessment missing"
[ -f "$repo/dist/Solvr-0.1.0.zip" ] || fail "notarized build: zip missing"

# Notarization that is not Accepted.
repo=$(new_repo rejected)
: >"$WORK/stub.log"
# shellcheck disable=SC2086
if run_release "$repo" $SIGN_ENV STUB_NOTARY_STATUS=Invalid; then
    fail "rejected notarization: expected a nonzero exit"
fi
grep -q "1234-abcd" "$WORK/out.log" || fail "rejected notarization: submission id not reported"
grep -q "stapler staple" "$WORK/stub.log" && fail "rejected notarization: stapled anyway"
[ -f "$repo/dist/Solvr-0.1.0.zip" ] && fail "rejected notarization: zip produced"

# The optional environment file supplies the signing variables, and the real environment wins over it.
repo=$(new_repo envfile-half)
echo "DEVELOPER_ID_IDENTITY=Stub-Identity" >"$repo/.env.release"
RELEASE_ARGS="--skip-checks"
expect_error_before_build "environment file, identity only" "$repo" "NOTARY_KEYCHAIN_PROFILE"

repo=$(new_repo envfile-loses)
printf 'DEVELOPER_ID_IDENTITY=File-Identity\nNOTARY_KEYCHAIN_PROFILE=file-profile\n' >"$repo/.env.release"
: >"$WORK/stub.log"
# shellcheck disable=SC2086
if ! run_release "$repo" $SIGN_ENV STUB_NOTARY_STATUS=Accepted; then
    fail "environment file: expected exit 0"
    cat "$WORK/out.log"
fi
grep -q "keychain-profile stub-profile" "$WORK/stub.log" || fail "environment file: the real environment did not win"
grep -q "file-profile" "$WORK/stub.log" && fail "environment file: the file overrode the real environment"

grep -qx ".env.release" "$ROOT/.gitignore" || fail "the environment file is not gitignored"

if [ "$FAILURES" -ne 0 ]; then
    echo "$FAILURES failure(s)"
    exit 1
fi
echo "release script tests passed"
