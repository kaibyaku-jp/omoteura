# Omoteura

> Status: pre-release. Not yet published to RubyGems. The VS Code extension
> that shows diagrams next to your code is still being built; the gems below
> already check links and record test results.

Omoteura puts a hand-drawn diagram behind each file of your Rails and RSpec
code. The code is the *omote* (front) and the diagram is the *ura* (back), and
shapes in the diagram link to the specs and methods they describe.

- Omoteura never draws diagrams for you. Draw them in Obsidian's Excalidraw
  plugin or on excalidraw.com and drop the file in.
- Your code is never rewritten, and nothing runs inside your application.
  Without a diagram, nothing happens.

## Installation

```ruby
group :development, :test do
  gem "omoteura"
end
```

`omoteura` installs the following gems. You can also pick only the ones you need.

| gem | contents |
| --- | --- |
| `omoteura-core` | Diagram files, `omoteura:` links and the `omoteura` command |
| `omoteura-rails` | Analysis of Rails models, controllers and services (planned) |
| `omoteura-rspec` | A formatter that records test results for diagrams |

## Attaching a diagram to code

Put the diagram under `ura/` at the same path as the code. Both Obsidian's
`.excalidraw.md` and excalidraw.com's `.excalidraw` work.

| code | diagram |
| --- | --- |
| `app/models/user.rb` | `ura/app/models/user.excalidraw.md` |
| `spec/models/user_spec.rb` | `ura/spec/models/user_spec.excalidraw` |

To share one diagram between files or give it any name, write a magic comment
on its own line at the top or the bottom of the file:

```ruby
class User < ApplicationRecord
end

# omoteura: ura/shared/user-validations.excalidraw.md
```

Or map files in `.omoteura.yml` without touching the code:

```yaml
diagrams_dir: ura # where diagrams live, "ura" by default
attach:
  app/models/user.rb: ura/shared/user-validations.excalidraw.md
```

A magic comment wins over `.omoteura.yml`, which wins over the path
convention. `.omoteura.local.yml` overrides individual entries for your own
machine; keep it out of version control.

## Linking shapes to code

Set a shape's link to text starting with `omoteura:`. Excalidraw and Obsidian
both let you edit links.

| link | points to |
| --- | --- |
| `omoteura:#email is unique` | the spec whose description ends with "email is unique", in the attached file |
| `omoteura:spec/models/user_spec.rb#validations email is unique` | the same, in another file |
| `omoteura:app/models/user.rb#display_name` | a method |
| `omoteura:app/models/user.rb#validates :email` | the statement that starts with that text |
| `omoteura:app/models/user.rb` | the whole file |

Links use names, not line numbers, so they survive edits around them.

## Checking links

```sh
bundle exec omoteura check
```

It reports broken links, missing or unreadable diagrams and diagrams that no
code file is attached to, and exits with status 1 if there are any. Add
`--format github` in GitHub Actions to get the problems as annotations.

## Recording test results

Add the formatter to `.rspec`:

```text
--format progress
--format Omoteura::RSpec::Formatter --out tmp/omoteura/results.json
```

Each example's status and failure message are written to
`tmp/omoteura/results.json`, which should not be committed.

## Supported versions

- Ruby 3.4, 4.0
- Rails 7.1, 7.2, 8.0, 8.1
- RSpec 3.12+
- Excalidraw (`.excalidraw`) / Obsidian Excalidraw (`.excalidraw.md`)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues as described in
[SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).
