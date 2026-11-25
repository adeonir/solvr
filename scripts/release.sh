#!/bin/sh
# Builds dist/Solvr-<version>.zip, ad-hoc signed; with DEVELOPER_ID_IDENTITY and NOTARY_KEYCHAIN_PROFILE it signs with Developer ID, notarizes, and staples. Pass --skip-checks to skip the clean-tree and version-tag guards.
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

# Read the two signing variables from an optional gitignored file; a variable already set in the environment is kept.
if [ -f .env.release ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            DEVELOPER_ID_IDENTITY | NOTARY_KEYCHAIN_PROFILE)
                eval "current=\${$key:-}"
                [ -n "$current" ] || export "$key=$value"
                ;;
        esac
    done <.env.release
fi

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

if [ -n "${DEVELOPER_ID_IDENTITY:-}" ]; then
    # Nested code first, then the app; --deep is deprecated for signing.
    for framework in "$app"/Contents/Frameworks/*.framework; do
        codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$framework"
    done
    # The app and the framework share the Team ID, so library validation passes without the ad-hoc entitlement; --force drops it.
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$app"
fi
codesign --verify --strict --verbose=2 "$app"

if [ -n "${DEVELOPER_ID_IDENTITY:-}" ]; then
    submission_zip=".build/release/Solvr-notarize.zip"
    rm -f "$submission_zip"
    ditto -c -k --keepParent "$app" "$submission_zip"
    result=$(xcrun notarytool submit "$submission_zip" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait --output-format json) ||
        fail "notarization submission failed"
    submission_id=$(echo "$result" | plutil -extract id raw -o - - 2>/dev/null || echo unknown)
    status=$(echo "$result" | plutil -extract status raw -o - - 2>/dev/null || echo unknown)
    [ "$status" = "Accepted" ] || fail "notarization was not accepted (status: $status, submission id: $submission_id)"
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
fi

mkdir -p dist
zip="dist/Solvr-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
echo "built $zip"
