# Changelog

## Unreleased

### Added

- Gutter markers on the lines a diagram links to, showing the test results
  behind each link, with a hover that explains them.
- Flip Between Code and Diagram (`⌥⌘U` / `Ctrl+Alt+U`), which offers to create
  an empty diagram for a file that has none.
- A status bar item that summarizes the diagram's links, or says why the file
  could not be inspected.
- A drawing editor for `.excalidraw` and `.excalidraw.md` files, built on
  Excalidraw, that outlines linked shapes by test status and opens the code
  behind a clicked link. Flipping from code opens it.
- Saving, reverting and backups of unsaved drawings, through `omoteura save`,
  which keeps an Obsidian note intact and refuses to overwrite a change made
  elsewhere.
- Omoteura: Draft Diagram, which drafts the open file's diagram or adds
  what it lacks, with the `omoteura.draftFormat` setting.
- Omoteura: Link Shape to Code, which links the selected shape to a place
  picked from the attached code.
- The Omoteura Coverage panel, listing which declarations and public methods
  of the open file its specs cover.
- A one-time notice with the fix when omoteura cannot run: Ruby too old (as
  when VS Code finds the system Ruby), omoteura missing from the Gemfile, gems
  not installed, no Gemfile, or a program not on PATH.
