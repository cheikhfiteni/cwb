# Contributing

## Testing

Run the `cwb` test suite from the repo root:

```bash
bash scripts/test_cwb.sh
```

The suite creates temporary git repos/remotes, stubs the CLI binaries (`claude`/`codex`), and verifies worktree/branch resolution behavior end-to-end.

## CI automation

- PRs targeting `main` run `.github/workflows/test-cwb.yml`, which executes `bash scripts/test_cwb.sh`.
- Pushes to `main` run `.github/workflows/release-cwb.yml`, which reruns the same tests and then executes `bash scripts/release_on_main.sh`.

## Release automation

cwb uses [Semantic Versioning](https://semver.org). The version lives in `cwb` at `CWB_VERSION="x.y.z"`. The Homebrew formula lives in the separate [`cheikhfiteni/homebrew-tap`](https://github.com/cheikhfiteni/homebrew-tap) repo.

The release script is idempotent:

- If `HEAD` is already tagged and released, it no-ops.
- If `CWB_VERSION` is new, it releases that version.
- If the current version was already released on an older commit, it bumps the patch version, commits `release: vx.y.z`, pushes that commit to `main`, then tags and releases it.

### Required release secret

`main` is protected, so the release workflow must authenticate as a release actor that can bypass the `main` branch ruleset.

1. Create or choose a dedicated release actor, such as a bot user token or GitHub App token, with `contents: write` access to `cheikhfiteni/cwb`.
2. Add that actor to the `main` ruleset bypass list with `Always allow` bypass mode.
3. Store the token as the repo secret `CWB_RELEASE_BYPASS_TOKEN`.

The workflow uses `CWB_RELEASE_BYPASS_TOKEN` for `actions/checkout`, so the script's `git push origin HEAD:main` and tag pushes authenticate as the bypass actor. The same token is passed to the GitHub CLI as `GH_TOKEN` for GitHub Release creation.

To auto-update the Homebrew tap as part of the release, set the repo secret `HOMEBREW_TAP_PUSH_TOKEN` with push access to `cheikhfiteni/homebrew-tap`. Without it, GitHub Releases still publish normally and tap sync is skipped.

## Manual release fallback

Use this only if the automated release workflow is disabled or needs to be repaired.

1. Update `CWB_VERSION` in `cwb` on a PR branch:

   ```bash
   # edit cwb: CWB_VERSION="x.y.z"
   git add cwb
   git commit -m "release: vx.y.z"
   ```

2. Merge the PR after `test-cwb` passes.

3. From updated `main`, tag and push the release:

   ```bash
   git checkout main
   git pull --ff-only origin main
   git tag vx.y.z
   git push origin vx.y.z
   ```

   GitHub automatically creates a source tarball at:
   `https://github.com/cheikhfiteni/cwb/archive/refs/tags/vx.y.z.tar.gz`

4. Create a GitHub Release from the tag:

   ```bash
   gh release create vx.y.z --title "vx.y.z" --generate-notes
   ```

5. Compute the SHA256 of the tarball:

   ```bash
   curl -sL https://github.com/cheikhfiteni/cwb/archive/refs/tags/vx.y.z.tar.gz | shasum -a 256
   ```

6. Update `Formula/cwb.rb` in the [`cheikhfiteni/homebrew-tap`](https://github.com/cheikhfiteni/homebrew-tap) repo:

   ```ruby
   url "https://github.com/cheikhfiteni/cwb/archive/refs/tags/vx.y.z.tar.gz"
   sha256 "<output from step 5>"
   ```

   A reference copy is kept at `Formula/cwb.rb` in this repo for convenience.

7. Commit and push the tap:

   ```bash
   git add Formula/cwb.rb
   git commit -m "cwb: vx.y.z"
   git push origin main
   ```

Users get the update on the next `brew upgrade cheikhfiteni/tap/cwb`.
