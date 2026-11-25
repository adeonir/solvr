# Releasing Solvr

This page is for the maintainer. You build the notarized zip and publish the release, and CI verifies it before updating the cask.

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
3. Run `sh scripts/release.sh` on the tagged commit. The script stops if the tree has uncommitted or untracked files. With both signing variables set, it signs with Developer ID, notarizes, staples, and writes `dist/Solvr-<version>.zip`.
4. Push `main` and the tag: `git push --atomic origin main v<version>`.
5. Publish the release with the zip and its sha256:

   ```sh
   gh release create v<version> dist/Solvr-<version>.zip --verify-tag --title v<version> --notes "sha256: \`$(shasum -a 256 dist/Solvr-<version>.zip | cut -d ' ' -f 1)\`"
   ```

   CI checks that the asset is a notarized build from the expected team, then updates the cask in the tap.

If the check fails, the tap stays unchanged. To publish a corrected zip:

1. Return the release to draft: `gh release edit v<version> --draft`.
2. Replace the asset: `gh release upload v<version> dist/Solvr-<version>.zip --clobber`.
3. Replace the sha256 in the release notes:

   ```sh
   gh release edit v<version> --notes "sha256: \`$(shasum -a 256 dist/Solvr-<version>.zip | cut -d ' ' -f 1)\`"
   ```

4. Publish the release again: `gh release edit v<version> --draft=false`.

## Publish a version with the script

Commit your changes, then run the script on `main`:

```sh
sh scripts/publish.sh <version>
```

The script sets `MARKETING_VERSION` in `project.yml`, commits the change, and creates the tag `v<version>`. It then builds the notarized zip, pushes `main` and the tag, and publishes the release with the zip and its sha256. CI checks the asset and updates the cask in the tap.

The script stops before it changes anything in these cases:

- The version does not have the form `1.2.3`.
- The current branch is not `main`, the tree has uncommitted or untracked files, or `main` is behind `origin/main`.
- The tag already exists.
- `gh` is not authenticated, or a signing variable is not set.

If the build or the notarization fails, nothing is pushed. Delete the local tag with `git tag -d v<version>`, fix the cause, and run the script again.

## Build a zip without notarizing

`scripts/release.sh --skip-checks` builds an ad-hoc signed zip from any tree, without the clean-tree and tag checks. Unset the two signing variables, or leave `.env.release` empty, to skip signing with Developer ID.
