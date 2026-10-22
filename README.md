# Omoteura [![CI](https://github.com/kaibyaku-jp/omoteura/actions/workflows/ci.yml/badge.svg)](https://github.com/kaibyaku-jp/omoteura/actions/workflows/ci.yml)

Hand-drawn diagrams on the back of your Rails and RSpec code.

The code is the *omote* (front). Behind it sits an Excalidraw diagram, the
*ura* (back), whose shapes link to the specs and methods they describe.

> **Status:** pre-release, not yet on RubyGems. The gems below already resolve
> links, check them in CI and record test results. The VS Code extension that
> flips between code and diagram is being built.


## Features

### Drawn by You

Omoteura never generates diagrams. Draw them in Obsidian's Excalidraw plugin
or on excalidraw.com, the way you would sketch on a whiteboard, and drop the
file next to your code.

### Linked by Name

A shape's link names a spec description, a method or the start of a statement,
not a line number, so links survive the edits around them.

### Checked in CI

`omoteura check` fails the build when a spec is renamed and a diagram still
points at the old name, or when a diagram is left behind by a moved file.

### Hands Off Your Code

Omoteura only reads files. It runs from the command line and next to RSpec,
never inside your application, never rewrites your code and does nothing at
all where there is no diagram.

### Light

Omoteura reads every Ruby file in a project, so it is measured for allocations
as well as time. Files without a magic comment are skipped without allocating.


## Supported Versions

* Ruby 3.4, 4.0

* Rails 7.1, 7.2, 8.0, 8.1

* RSpec 3.12+

* Excalidraw (`.excalidraw`) and Obsidian Excalidraw (`.excalidraw.md`)


## Installation

Put this in your Gemfile:

```ruby
group :development, :test do
  gem "omoteura", require: false
end
```

`require: false` keeps Rails from loading Omoteura into your application; the
`omoteura` command and RSpec load what they need. Then bundle:

```sh
% bundle
```

`omoteura` installs the following gems. You can also pick only the ones you need.

| gem | contents |
| --- | --- |
| `omoteura-core` | Diagram files, `omoteura:` links and the `omoteura` command |
| `omoteura-rails` | Analysis of Rails models, controllers and services (planned) |
| `omoteura-rspec` | A formatter that records test results for diagrams |


## Attaching Diagrams

### By Path

Put the diagram under `ura/` at the same path as the code. Nothing else is
needed.

| code | diagram |
| --- | --- |
| `app/models/user.rb` | `ura/app/models/user.excalidraw.md` |
| `spec/models/user_spec.rb` | `ura/spec/models/user_spec.excalidraw` |

When both `.excalidraw.md` and `.excalidraw` exist, `.excalidraw.md` is used.

### By Magic Comment

To share one diagram between files or give it any name, write a magic comment
on its own line at the top or the bottom of the file:

```ruby
class User < ApplicationRecord
end

# omoteura: ura/shared/user-validations.excalidraw.md
```

A path copied from Obsidian without its `.md` works too.

### By `.omoteura.yml`

To leave the code untouched, map files in `.omoteura.yml`:

```yaml
attach:
  app/models/user.rb: ura/shared/user-validations.excalidraw.md
```

A magic comment wins over `.omoteura.yml`, which wins over the path.


## Linking Shapes to Code

Set a shape's link to text starting with `omoteura:`. Both Excalidraw and
Obsidian let you edit a shape's link.

| link | points to |
| --- | --- |
| `omoteura:#email is unique` | the spec whose description ends with "email is unique", in the attached file |
| `omoteura:#display_name` | the `describe "#display_name"` group, or the method |
| `omoteura:spec/models/user_spec.rb#validations email is unique` | the same, in another file |
| `omoteura:app/models/user.rb#validates :email` | the statement that starts with that text |
| `omoteura:app/models/user.rb` | the whole file |

A fragment is tried as a spec description, then a method name, then the start
of a statement. A link that matches nothing, or more than one place, is broken.


## Checking Links

```sh
% bundle exec omoteura check
ura/app/models/user.excalidraw: omoteura:#full_name matches nothing in app/models/user.rb (shape "Display name")
Checked 12 diagrams and 48 links: 1 problem.
```

It reports broken links, missing or unreadable diagrams and diagrams no code
file is attached to, and exits with status 1 when there are any. In GitHub
Actions, add `--format github` to see the problems as annotations.


## Recording Test Results

Add the formatter to `.rspec`, next to your usual one:

```text
--format progress
--format Omoteura::RSpec::Formatter --out tmp/omoteura/results.json
```

Each example's status and failure message go to `tmp/omoteura/results.json`.
Keep `tmp/omoteura/` out of version control.


## Commands

| command | does |
| --- | --- |
| `omoteura check` | Report broken links and diagrams not attached to code |
| `omoteura inspect FILE` | Print one file's diagram, links and test results as JSON, for editors |
| `omoteura version` | Print the version |

Run `omoteura <command> --help` for options.


## Configuring Omoteura

`.omoteura.yml` at the project root is optional:

| key | default | meaning |
| --- | --- | --- |
| `diagrams_dir` | `ura` | Where diagrams live, relative to the root |
| `attach` | none | Code paths mapped to diagram paths |

`.omoteura.local.yml` is read on top of it, entry by entry, for settings of
your own. Keep it out of version control.


## Questions, Feedback

Open an issue on GitHub. Report security problems privately as described in
[SECURITY.md](SECURITY.md).


## Contributing to Omoteura

Fork, fix, then send a pull request. [CONTRIBUTING.md](CONTRIBUTING.md) has the
details.

To run the specs and lint:

```sh
% nix develop          # or use Ruby 3.4+ without Nix
% bundle install
% bundle exec rake
```

To run the specs against the oldest supported rspec-core:

```sh
% BUNDLE_GEMFILE=gemfiles/rspec_3_12.gemfile bundle install
% BUNDLE_GEMFILE=gemfiles/rspec_3_12.gemfile bundle exec rake spec
```

To measure allocations and time of the main code paths:

```sh
% bundle exec rake bench
```


## Copyright

Copyright (c) 2026- KAIBYAKU K.K. See [LICENSE](LICENSE) for further details.
