# Omoteura for VS Code

Code in front, context behind.

[Omoteura](https://github.com/kaibyaku-jp/omoteura) puts a hand-drawn
Excalidraw drawing behind each Ruby file: diagrams, notes and the reasons
behind the code, with shapes that link to the specs and methods they describe.
This extension shows those links where you write code.

> **Status:** pre-release. Drawings open read-only for now; edit them in
> Obsidian or on excalidraw.com, and VS Code shows the changes as you save.

## Features

- **Markers next to linked lines.** A line that a shape links to gets a marker
  with the result of the tests behind it: passing, failing, pending or no
  result yet. Each status has its own shape as well as its own color.
- **Hover for details.** Hovering a marked line shows the shapes linked to it,
  their links and the failure messages of failing examples.
- **Flip between code and diagram** with `⌥⌘U` (`Ctrl+Alt+U` on Windows and
  Linux) or the status bar item. In a file without a diagram, it offers to
  create an empty one where Omoteura looks for it.
- **See the drawing in VS Code.** `.excalidraw` and Obsidian `.excalidraw.md`
  files open in a viewer built on Excalidraw. Linked shapes are outlined in the
  color of their test status, broken links dashed, without changing the file.
  Clicking a shape's link opens the code it points to.
- **Stays up to date** when you save, when RSpec writes new results or when a
  diagram changes.

## Requirements

The `omoteura` gem in your project's Gemfile, with the formatter in `.rspec` to
see test results:

```ruby
group :development, :test do
  gem "omoteura", require: false
end
```

```text
--format progress
--format Omoteura::RSpec::Formatter --out tmp/omoteura/results.json
```

The extension runs `bundle exec omoteura` from the workspace folder. It needs
a trusted workspace, since Bundler loads the project's Gemfile.

## Privacy

The drawing view loads nothing from the network: Excalidraw and its fonts ship
inside the extension, and the view's content security policy allows only the
extension's own files.

## Settings

| setting | default | meaning |
| --- | --- | --- |
| `omoteura.command` | `["bundle", "exec", "omoteura"]` | How to run omoteura, as a program and its arguments, without a shell |

VS Code started from the Dock or Start menu may not see the Ruby that your
version manager selects. If the status bar shows a warning about the Ruby
version, start VS Code from a terminal in the project, or name the version
manager in the command:

```json
{
  "omoteura.command": ["mise", "exec", "--", "bundle", "exec", "omoteura"]
}
```

## License

MIT. See [LICENSE](LICENSE).
