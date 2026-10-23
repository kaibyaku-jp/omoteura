# Changelog

All notable changes to this project are documented in this file. The format
is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

## 0.1.1 - 2026-10-23

No changes to the gems. Released with the same version as the VS Code
extension, which leaves out excalidraw.com's settings it never used.

## 0.1.0 - 2026-10-23

The first release.

### Added

- Read Excalidraw (`.excalidraw`) and Obsidian Excalidraw (`.md`) drawings,
  including compressed drawing data.
- Attach a diagram to a code file by magic comment, `.omoteura.yml` or the
  `ura/` path convention.
- Resolve `omoteura:` links to specs, methods and statements.
- `omoteura check` to report broken links and unattached diagrams.
- `Omoteura::RSpec::Formatter` to record test results as JSON, and the lines
  of the project's code that ran when SimpleCov or another tool measures
  coverage.
- `omoteura inspect` and `omoteura diagram`, which give editors one file's or
  one diagram's data as JSON.
- `omoteura draft` to draft a diagram from code, with every box linked, as
  `.excalidraw` or, with `--format md`, as an Obsidian note; it never replaces
  an existing diagram; `--merge` adds only what the diagram has no shape for
  yet, beside what is drawn, and `--json` prints the results for editors.
- Write Obsidian Excalidraw notes as the plugin does, keeping what the user
  wrote above the drawing, and read links edited under its Element Links.
- `omoteura links`, which lists the places in a code file a shape can link
  to, each with a link that resolves to exactly that place.
- `omoteura coverage`, which lists a file's declarations and public methods
  and the examples that name them, for the editor's coverage panel;
  `coverage_panel: false` turns it off.
- `omoteura save` for editors to save a changed drawing in the file's own
  format, in one step and never over a change made elsewhere since.
- A clear message, instead of a crash, on Ruby older than 3.4.
