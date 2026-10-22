# Changelog

## Unreleased

### Added

- Gutter markers on the lines a diagram links to, showing the test results
  behind each link, with a hover that explains them.
- Flip Between Code and Diagram (`⌥⌘U` / `Ctrl+Alt+U`), which offers to create
  an empty diagram for a file that has none.
- A status bar item that summarizes the diagram's links, or says why the file
  could not be inspected.
- A read-only drawing view for `.excalidraw` and `.excalidraw.md` files,
  built on Excalidraw, that outlines linked shapes by test status and opens
  the code behind a clicked link. Flipping from code opens it.
- A one-time notice with the fix when omoteura cannot run: Ruby too old (as
  when VS Code finds the system Ruby), omoteura missing from the Gemfile, gems
  not installed, no Gemfile, or a program not on PATH.
