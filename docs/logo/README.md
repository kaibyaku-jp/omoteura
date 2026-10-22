# Omoteura logo

The mark is a red card of code in front of a hand-drawn card, with arrows
between the two: the code is the *omote* (front), the diagram and notes are
the *ura* (back). The wordmark and tagline are set in Kalam and outlined, so
the SVGs need no fonts.

| file | use |
| --- | --- |
| `omoteura-logo-vertical.svg` | Mark, wordmark and tagline stacked; README header |
| `omoteura-logo.svg` | Mark and wordmark side by side |
| `omoteura-mark.svg` | The mark alone |
| `omoteura-icon.svg` | A simpler mark for 16 to 48 px: favicons, extension icons |

Each file has a `-dark` variant for dark backgrounds.

## Colors

| role | light | dark |
| --- | --- | --- |
| Front card | `#C8352B` | `#C8352B` |
| Code lines | `#FBFAF6`, `#F7C873`, `#FFC9B8` | same |
| Hatched fill | `#2A9D8F` | `#2A9D8F` |
| Lines and wordmark | `#1E1E1E` | `#F2F0EA` |
| Back card | `#FFFFFF` | `#0D1117` |
| Tagline | `#5F6368` | `#A9AFB8` |

## Rebuilding

`build.py` draws the mark and outlines the text with fontTools. Download
Kalam from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/kalam)
and run:

```sh
nix shell --impure --expr 'let pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem}; in pkgs.python3.withPackages (ps: [ ps.fonttools ])' \
  -c python3 -I docs/logo/build.py path/to/kalam docs/logo
```

## License

The logo is part of this repository and released under its MIT license.
Kalam is by the Indian Type Foundry under the SIL Open Font License 1.1; the
wordmark uses outlines of its glyphs.
