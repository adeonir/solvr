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

1. Set `MARKETING_VERSION` in `project.yml`, commit it, and tag that commit `v<version>`.
2. Push the tag. CI builds the ad-hoc zip and opens a draft release with the zip and its sha256.
3. On the tagged commit, run `scripts/release.sh`. With both signing variables set, it signs with Developer ID, notarizes, staples, and writes `dist/Solvr-<version>.zip`.
4. Replace the draft asset: `gh release upload v<version> dist/Solvr-<version>.zip --clobber`.
5. Publish the release. CI checks that the asset is a notarized build from the expected team, then updates the cask in the tap.

If the check fails, the tap stays unchanged. Replace the asset with a notarized zip and publish again.

## Build a zip without notarizing

`scripts/release.sh --skip-checks` builds an ad-hoc signed zip from any tree, without the clean-tree and tag checks. Unset the two signing variables, or leave `.env.release` empty, to skip signing with Developer ID.
