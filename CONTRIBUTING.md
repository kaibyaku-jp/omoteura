# Contributing

Thank you for helping with Omoteura. Bug reports, ideas and pull requests are
all welcome.

## Setting up

The repository has a Nix flake with the Ruby and Bundler used in development:

```sh
nix develop   # or `direnv allow` if you use direnv
bundle install
```

Without Nix, use Ruby 3.4 or later.

## Running the checks

```sh
bundle exec rake          # all specs and lint (standard)
bundle exec rake package  # build the three gems into pkg/
bundle exec rspec omoteura-core/spec/omoteura/cli_spec.rb  # one spec file
```

CI runs the same commands on Ruby 3.4 and 4.0. To run the specs against the
oldest rspec-core that omoteura-rspec supports, point Bundler at its Gemfile:

```sh
BUNDLE_GEMFILE=gemfiles/rspec_3_12.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rspec_3_12.gemfile bundle exec rake spec
```

## The VS Code extension

The extension lives in `editors/vscode` and uses Node 24 from the same Nix
shell:

```sh
cd editors/vscode
npm ci
npm run lint && npm run typecheck && npm test
npm run test:integration   # downloads VS Code and runs it on the sample project
```

Set `VSCODE_VERSION=1.95.0` to run the integration tests on the oldest
supported VS Code, as CI does.

## Performance

Omoteura runs over every Ruby file in a project, so keep an eye on
allocations as well as time. `bundle exec rake bench` reports both for
the main code paths on large generated inputs; include its before and
after numbers in pull requests that touch those paths.

## Layout

| directory | gem |
| --- | --- |
| `omoteura-core/` | diagrams, links, attachments and the `omoteura` command |
| `omoteura-rspec/` | the RSpec formatter |
| `lib/` (root) | the `omoteura` meta gem |
| `editors/vscode/` | the VS Code extension |

## Pull requests

- Keep each commit to one change, with its specs in the same commit.
- Write commit messages that say what changed and why.
- Run `bundle exec rake` before pushing.
- Add an entry under `Unreleased` in `CHANGELOG.md` for user-facing changes.

Please report security issues privately as described in
[SECURITY.md](SECURITY.md), not in public issues.

## Branches and releases

Omoteura works on one branch, `main`, as RuboCop, kaminari and Tapioca do.

- Every change is a short-lived branch merged into `main` through a pull
  request. There is no `develop` branch, and no long-lived feature branch:
  a large feature lands as a series of small pull requests, tracked by a
  milestone and a parent issue.
- `main` can be released at any time. Parts of a feature that is not done
  yet may be merged when nothing reaches them yet or they are off unless
  turned on, and they are not described in the README or CHANGELOG until
  they work.
- A release is a `v*` tag on `main` (see RELEASING.md). Versions follow
  Semantic Versioning: new features raise the minor version, fixes alone the
  patch version. While the version is 0.x, a change that breaks
  compatibility also raises the minor version and is called out in the
  CHANGELOG.
- A maintenance branch such as `0-1-stable` is made only when a fix has to
  reach an older version while `main` holds unreleased work. It starts from
  that version's tag, takes the fix by cherry-pick, and is released by
  tagging it like `main`.
