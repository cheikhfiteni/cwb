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

### Release GitHub App setup

`main` is protected, so the release workflow authenticates as a GitHub App installation. The workflow mints a short-lived installation token for `cheikhfiteni/cwb` and `cheikhfiteni/homebrew-tap` at runtime.

1. Create a GitHub App under the `cheikhfiteni` account:
   - Go to GitHub `Settings -> Developer settings -> GitHub Apps -> New GitHub App`.
   - Use a clear name, such as `cwb-release`.
   - Use the account or repo URL as the homepage URL.
   - Disable webhooks; this app is only used for Actions authentication.
   - Repository permissions: `Contents` read/write.
   - Installation target: only the `cheikhfiteni` account.
2. After creating the app, generate a private key and copy the app's client ID.
3. Install the app on only these repositories:
   - `cheikhfiteni/cwb`
   - `cheikhfiteni/homebrew-tap`
4. In `cheikhfiteni/cwb`, add the Actions repository variable:
   - `CWB_RELEASE_APP_CLIENT_ID`: the app client ID.
5. In `cheikhfiteni/cwb`, add the Actions repository secret:
   - `CWB_RELEASE_APP_PRIVATE_KEY`: the full private key PEM generated for the app.
6. In the `cheikhfiteni/cwb` `main` ruleset, add the GitHub App to the bypass list with `Always allow` bypass mode.
7. In `cheikhfiteni/homebrew-tap`, leave `main` unprotected or add the same GitHub App to the tap's `main` ruleset/branch protection with direct-push access. The release script updates `Formula/cwb.rb` directly during release.

The workflow uses `actions/create-github-app-token` to mint an installation token with `contents: write` for both repos. That token is used for checkout, release commits, tag pushes, GitHub Release creation via `GH_TOKEN`, and the Homebrew tap clone/push via `CWB_RELEASE_APP_TOKEN`.

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
