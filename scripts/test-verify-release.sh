#!/bin/sh
# Exercises scripts/verify-release.sh through its command line. The real ad-hoc build checks the rejection path;
# stubs for codesign, xcrun, and spctl stand in for a notarized build, which needs a certificate.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAILURES=0

fail() {
    echo "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

# A signed copy of /usr/bin/true wrapped as Solvr.app, zipped.
mkdir -p "$WORK/real/Solvr.app/Contents/MacOS"
cp /usr/bin/true "$WORK/real/Solvr.app/Contents/MacOS/Solvr"
cat >"$WORK/real/Solvr.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Solvr</string>
<key>CFBundleIdentifier</key><string>dev.adeonir.labs.Solvr</string>
</dict></plist>
PLIST
codesign --force --sign - "$WORK/real/Solvr.app" 2>/dev/null
ditto -c -k --keepParent "$WORK/real/Solvr.app" "$WORK/adhoc.zip"

mkdir -p "$WORK/stub/Solvr.app"
echo x >"$WORK/stub/Solvr.app/file"
ditto -c -k --keepParent "$WORK/stub/Solvr.app" "$WORK/notarized.zip"

mkdir -p "$WORK/bin"
cat >"$WORK/bin/codesign" <<'STUB'
#!/bin/sh
case "$1" in
    -dv) echo "TeamIdentifier=$STUB_TEAM" >&2 ;;
esac
exit 0
STUB
cat >"$WORK/bin/xcrun" <<'STUB'
#!/bin/sh
exit "${STUB_STAPLE:-0}"
STUB
cat >"$WORK/bin/spctl" <<'STUB'
#!/bin/sh
case "$1" in
    --status) echo "assessments ${STUB_GATEKEEPER:-enabled}" ;;
    *) exit "${STUB_ASSESS:-0}" ;;
esac
STUB
chmod +x "$WORK/bin/"*

verify() {
    zip=$1
    shift
    env EXPECTED_TEAM_ID=TEAM123456 "$@" sh "$ROOT/scripts/verify-release.sh" "$zip" >"$WORK/out.log" 2>&1
}

stubbed() {
    zip=$1
    shift
    verify "$zip" PATH="$WORK/bin:$PATH" STUB_TEAM=TEAM123456 "$@"
}

# The ad-hoc CI build is rejected with instructions to replace the asset.
if verify "$WORK/adhoc.zip"; then
    fail "ad-hoc build: expected a nonzero exit"
fi
grep -qi "replace" "$WORK/out.log" || fail "ad-hoc build: expected instructions to replace the asset"

# Signed by the expected team with a stapled ticket.
stubbed "$WORK/notarized.zip" || { fail "notarized build: expected exit 0"; cat "$WORK/out.log"; }

# Signed by another team.
verify "$WORK/notarized.zip" PATH="$WORK/bin:$PATH" STUB_TEAM=OTHER00000 && fail "other team: expected a nonzero exit"
grep -qi "replace" "$WORK/out.log" || fail "other team: expected instructions to replace the asset"

# No stapled ticket.
stubbed "$WORK/notarized.zip" STUB_STAPLE=1 && fail "no ticket: expected a nonzero exit"

# Gatekeeper rejection: hard failure when assessments are enabled, a warning otherwise.
stubbed "$WORK/notarized.zip" STUB_ASSESS=3 && fail "gatekeeper enabled: expected a nonzero exit"
stubbed "$WORK/notarized.zip" STUB_ASSESS=3 STUB_GATEKEEPER=disabled || { fail "gatekeeper disabled: expected exit 0"; cat "$WORK/out.log"; }
grep -qi "warning" "$WORK/out.log" || fail "gatekeeper disabled: expected a warning"

if [ "$FAILURES" -ne 0 ]; then
    echo "$FAILURES failure(s)"
    exit 1
fi
echo "verify script tests passed"
