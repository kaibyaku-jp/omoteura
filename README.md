# Omoteura

> Status: pre-release. Not yet published to RubyGems.

Omoteura overlays hand-drawn Excalidraw diagrams on your Rails and RSpec code.
The code is the *ura* (back), the diagram is the *omote* (front), and you flip between them in the editor.

- Omoteura never generates diagrams on its own. Draw them in Obsidian (Excalidraw plugin) or excalidraw.com and drop the file in.
- Link a shape to a spec or method with an `omoteura:` link to jump to the code and see test results on the diagram.
- Your code is never rewritten. No diagram, no effect.

## Installation

```ruby
group :development, :test do
  gem "omoteura"
end
```

`omoteura` bundles the following gems. You can also pick only the ones you need.

| gem | contents |
| --- | --- |
| `omoteura-core` | Diagram file I/O, `omoteura:` link resolution, CLI |
| `omoteura-rails` | Analysis of models, controllers and services |
| `omoteura-rspec` | Spec analysis and a formatter that writes test results |

## Supported versions

- Ruby 3.4, 4.0
- Rails 7.1, 7.2, 8.0, 8.1
- RSpec 3.12+
- Excalidraw (`.excalidraw`) / Obsidian Excalidraw (`.excalidraw.md`)

## License

MIT. See [LICENSE](LICENSE).
