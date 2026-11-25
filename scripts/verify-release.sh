#!/bin/sh
# Verifies that a release zip holds a notarized build from the expected team. Usage: verify-release.sh <zip>.
# Needs EXPECTED_TEAM_ID. The Gatekeeper assessment fails the check only when the runner has assessments enabled.
set -eu

fail() {
    echo "error: $1" >&2
    echo "Replace the release asset with a notarized zip: run scripts/release.sh with DEVELOPER_ID_IDENTITY and NOTARY_KEYCHAIN_PROFILE set, upload it with 'gh release upload <tag> dist/Solvr-<version>.zip --clobber', and publish the release again." >&2
    exit 1
}

[ $# -eq 1 ] || { echo "usage: verify-release.sh <zip>" >&2; exit 2; }
[ -n "${EXPECTED_TEAM_ID:-}" ] || { echo "error: EXPECTED_TEAM_ID is not set" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ditto -x -k "$1" "$work"
app="$work/Solvr.app"
[ -d "$app" ] || fail "the zip does not contain Solvr.app"

codesign --verify --strict --verbose=2 "$app" || fail "the app signature is not valid"

team=$(codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ "$team" = "$EXPECTED_TEAM_ID" ] || fail "the app is signed by team '${team:-none}', expected $EXPECTED_TEAM_ID"

xcrun stapler validate "$app" || fail "the app has no valid stapled notarization ticket"

if spctl --status 2>&1 | grep -q "assessments enabled"; then
    spctl --assess --type execute --verbose "$app" || fail "Gatekeeper rejects the app"
else
    spctl --assess --type execute --verbose "$app" || echo "warning: Gatekeeper rejects the app, but the runner has assessments disabled"
fi

echo "verified $1: team $team, stapled"
