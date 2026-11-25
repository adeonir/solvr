# Releasing Solvr

This page is for the maintainer. CI builds an ad-hoc signed zip, and you replace it with a notarized zip before the release goes public.

## Before the first release

- Install the Developer ID Application certificate in your keychain.
- Store the notarization credentials once with `xcrun notarytool store-credentials <profile-name>`.
- Put both values in `.env.release` at the repository root, which git ignores:

  ```text
  DEVELOPER_ID_IDENTITY=Developer ID Application: Your Name (TEAMID)
  NOTARY_KEYCHAIN_PROFILE=<profile-name>
  ```

  A variable set in your shell wins over the file. Set both variables or neither.
- Add the repository secret `HOMEBREW_TAP_TOKEN`, a token with write access to `adeonir/homebrew-tap`.

## Publish a version

1. Set `MARKETING_VERSION` in `project.yml` and commit the change.
2. Create the matching version tag on that commit: `git tag v<version>`.
3. Push the tag: `git push origin v<version>`. This starts CI, which builds the ad-hoc zip and creates a draft release with the zip and its sha256.
4. After CI creates the draft, run `sh scripts/release.sh` on the tagged commit. The script stops if the tree has uncommitted or untracked files. With both signing variables set, it signs with Developer ID, notarizes, staples, and writes `dist/Solvr-<version>.zip`.
5. Replace the draft asset: `gh release upload v<version> dist/Solvr-<version>.zip --clobber`.
6. Replace the sha256 in the release notes, which still belongs to the ad-hoc zip:

   ```sh
   gh release edit v<version> --notes "sha256: \`$(shasum -a 256 dist/Solvr-<version>.zip | cut -d ' ' -f 1)\`"
   ```

7. Publish the release: `gh release edit v<version> --draft=false`. CI checks that the asset is a notarized build from the expected team, then updates the cask in the tap.

If the check fails, the tap stays unchanged. Return the release to draft with `gh release edit v<version> --draft`, then repeat steps 4 to 7.

## Build a zip without notarizing

`scripts/release.sh --skip-checks` builds an ad-hoc signed zip from any tree, without the clean-tree and tag checks. Unset the two signing variables, or leave `.env.release` empty, to skip signing with Developer ID.
