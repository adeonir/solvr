#!/bin/sh
# Builds dist/Solvr-<version>.zip, ad-hoc signed. Pass --skip-checks to skip the clean-tree and version-tag guards.
set -eu

cd "$(dirname "$0")/.."

fail() {
    echo "error: $1" >&2
    exit 1
}

skip_checks=false
for arg in "$@"; do
    case "$arg" in
        --skip-checks) skip_checks=true ;;
        *) fail "unknown argument: $arg" ;;
    esac
done

if [ -n "${DEVELOPER_ID_IDENTITY:-}" ] && [ -z "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
    fail "DEVELOPER_ID_IDENTITY is set but NOTARY_KEYCHAIN_PROFILE is not; set both or neither"
fi
if [ -z "${DEVELOPER_ID_IDENTITY:-}" ] && [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
    fail "NOTARY_KEYCHAIN_PROFILE is set but DEVELOPER_ID_IDENTITY is not; set both or neither"
fi

version=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
[ -n "$version" ] || fail "MARKETING_VERSION not found in project.yml"

if [ "$skip_checks" = false ]; then
    [ -z "$(git status --porcelain)" ] || fail "the tree has uncommitted changes; commit them or pass --skip-checks"
    git tag --points-at HEAD | grep -qx "v$version" || fail "HEAD has no tag v$version; tag it or pass --skip-checks"
fi

xcodegen generate
xcodebuild -project Solvr.xcodeproj -scheme Solvr -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath .build/release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build

app=.build/release/Build/Products/Release/Solvr.app
codesign --verify --strict --verbose=2 "$app"

mkdir -p dist
zip="dist/Solvr-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
echo "built $zip"
