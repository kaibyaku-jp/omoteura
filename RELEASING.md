# Releasing

The three gems (`omoteura-core`, `omoteura-rspec` and the `omoteura` meta
gem) share one version and are always released together by
`.github/workflows/release.yml` when a `v*` tag is pushed.

## One-time setup

1. On RubyGems.org, add a trusted publisher for each of the three gems.
   Before the first release, use **pending trusted publishers** under your
   account settings, since the gems do not exist yet.
   - Repository owner: `kaibyaku-jp`
   - Repository name: `omoteura`
   - Workflow filename: `release.yml`
   - Environment: `release`
2. In the GitHub repository settings, create the `release` environment and
   limit it to `v*` tags. Add required reviewers once the repository is public.
3. After the first release, add a second owner to every gem and make sure MFA
   is required for all owners.

## Each release

1. Update `Omoteura::VERSION` in `omoteura-core/lib/omoteura/core/version.rb`
   and run `bundle install` so `Gemfile.lock` follows.
2. Move the `Unreleased` entries in `CHANGELOG.md` under the new version and
   date.
3. Open a pull request with those changes and merge it once CI passes.
4. Tag the merge commit on `main` and push the tag:

   ```sh
   git switch main && git pull
   git tag v0.1.0
   git push origin v0.1.0
   ```

The workflow checks that the tag matches `Omoteura::VERSION`, runs the specs
and lint, builds the gems, pushes them dependencies first and creates the
GitHub release with the built gems attached.
