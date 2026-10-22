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
bundle exec rake          # specs and lint (standard)
bundle exec rake package  # build the four gems into pkg/
```

CI runs the same commands on Ruby 3.4 and 4.0.

## Layout

| directory | gem |
| --- | --- |
| `omoteura-core/` | diagrams, links, attachments and the `omoteura` command |
| `omoteura-rails/` | Rails analysis |
| `omoteura-rspec/` | the RSpec formatter |
| `lib/` (root) | the `omoteura` meta gem |

## Pull requests

- Keep each commit to one change, with its specs in the same commit.
- Write commit messages that say what changed and why.
- Run `bundle exec rake` before pushing.
- Add an entry under `Unreleased` in `CHANGELOG.md` for user-facing changes.

Please report security issues privately as described in
[SECURITY.md](SECURITY.md), not in public issues.
