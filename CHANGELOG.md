# Changelog

All notable changes to this project are documented in this file. The format
is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- Read Excalidraw (`.excalidraw`) and Obsidian Excalidraw (`.md`) drawings,
  including compressed drawing data.
- Attach a diagram to a code file by magic comment, `.omoteura.yml` or the
  `ura/` path convention.
- Resolve `omoteura:` links to specs, methods and statements.
- `omoteura check` to report broken links and unattached diagrams.
- `Omoteura::RSpec::Formatter` to record test results as JSON.
- `omoteura inspect` and `omoteura diagram`, which give editors one file's or
  one diagram's data as JSON.
- `omoteura draft` to draft a diagram from code, with every box linked; it
  never replaces an existing diagram.
- A clear message, instead of a crash, on Ruby older than 3.4.
