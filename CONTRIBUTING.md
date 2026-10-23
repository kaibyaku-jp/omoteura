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
