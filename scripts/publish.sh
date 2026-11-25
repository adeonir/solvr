#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

fail() {
    echo "error: $1" >&2
    exit 1
}

[ $# -eq 1 ] || fail "usage: sh scripts/publish.sh <version>"
version=$1
echo "$version" | grep -Eqx '[0-9]+\.[0-9]+\.[0-9]+' || fail "the version must look like 1.2.3, got $version"
tag="v$version"
zip="dist/Solvr-$version.zip"

[ "$(git branch --show-current)" = main ] || fail "the current branch is not main"
[ -z "$(git status --porcelain)" ] || fail "the tree has uncommitted changes"
git fetch -q origin main
git merge-base --is-ancestor origin/main HEAD || fail "main is behind origin/main"
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || fail "tag $tag already exists locally"
remote_tag=$(git ls-remote --tags origin "refs/tags/$tag")
[ -z "$remote_tag" ] || fail "tag $tag already exists on origin"
gh auth status >/dev/null || fail "gh is not authenticated"

for key in DEVELOPER_ID_IDENTITY NOTARY_KEYCHAIN_PROFILE; do
    eval "value=\${$key:-}"
    [ -n "$value" ] || grep -q "^$key=." .env.release 2>/dev/null || fail "$key is not set in the shell or in .env.release"
done

sed -i '' "s/^\( *MARKETING_VERSION: *\)\".*\"/\1\"$version\"/" project.yml
grep -q "^ *MARKETING_VERSION: *\"$version\"" project.yml || fail "MARKETING_VERSION was not updated in project.yml"
git diff --quiet || git commit -qm "chore: bump version to $version" project.yml
git tag "$tag"

sh scripts/release.sh
xcrun stapler validate .build/release/Build/Products/Release/Solvr.app

git push --atomic origin main "$tag"
sha=$(shasum -a 256 "$zip" | cut -d ' ' -f 1)
gh release create "$tag" "$zip" --verify-tag --title "$tag" --notes "sha256: \`$sha\`"
