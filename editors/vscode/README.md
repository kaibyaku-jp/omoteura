# Omoteura for VS Code

Code in front, context behind.

[Omoteura](https://github.com/kaibyaku-jp/omoteura) puts a hand-drawn
Excalidraw drawing behind each Ruby file: diagrams, notes and the reasons
behind the code, with shapes that link to the tests and methods they describe.
This extension shows those links where you write code.

> **Status:** pre-release.

## Features

- **Markers next to linked lines.** A line that a shape links to gets a marker
  with the result of the tests behind it: passing, failing, pending or no
  result yet. Each status has its own shape as well as its own color.
- **Hover for details.** Hovering a marked line shows the shapes linked to it,
  their links and the failure messages of failing examples.
- **Flip between code and diagram** with `⌥⌘U` (`Ctrl+Alt+U` on Windows and
  Linux) or the status bar item. In a file without a diagram, it offers to
  create an empty one where Omoteura looks for it.
- **Link shapes to code by picking.** Select a shape and run **Omoteura:
  Link Shape to Code**, or press the link button in the editor's title bar,
  and choose from the examples, declarations and methods of the code the
  diagram is attached to.
- **Draw in VS Code.** `.excalidraw` and Obsidian `.excalidraw.md` files open
  in Excalidraw. Linked shapes are outlined in the color of their test status,
  broken links dashed; the outlines are never saved. Clicking a shape's link
  opens the code it points to.
- **Save in the file's own format.** An Obsidian note keeps your notes around
  the drawing and stays compressed if it was. If the file changed elsewhere
  since it opened, say in Obsidian, saving stops instead of overwriting it.
- **Draft a diagram to draw on.** **Omoteura: Draft Diagram** drafts the
  open file's diagram, with every box linked to its code, and opens it. When
  the file already has one, it adds only what the diagram has no shape for
  yet, beside what is drawn, or drafts a separate file to copy from.
- **See what the tests cover.** The Omoteura Coverage panel in the Explorer
  lists the open file's validations, associations, callbacks, scopes, enums
  and public methods, each marked by whether an example names it, failing if
  one of those failed, or whether its body ran in the last test run when
  SimpleCov measures coverage. Click an entry to go to it, or to an example.
  `coverage_panel: false` in `.omoteura.yml` turns it off.
- **Stays up to date** when you save, when your tests write new results or when a
  diagram changes.

## Requirements

The `omoteura` gem in your project's Gemfile:

```ruby
group :development, :test do
  gem "omoteura", require: false
end
```

To see test results, record them from your test framework. With RSpec, in
`.rspec`:

```text
--format progress
--format Omoteura::RSpec::Formatter --out tmp/omoteura/results.json
```

With Minitest, in `test/test_helper.rb`:

```ruby
require "omoteura/minitest"
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
| `omoteura.draftFormat` | `"excalidraw"` | The format of a drafted diagram: `"excalidraw"`, or `"obsidian"` for a `.excalidraw.md` note |

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
