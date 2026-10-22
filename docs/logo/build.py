"""Builds the Omoteura logo SVGs with the wordmark outlined from Kalam.

Usage: python -I build.py <fonts dir> <output dir>

The fonts dir must hold Kalam-Bold.ttf and Kalam-Regular.ttf; see README.md.
"""

import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

FONTS = Path(sys.argv[1])
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)

RED = "#C8352B"
YELLOW = "#F7C873"
PINK = "#FFC9B8"
CODE_WHITE = "#FBFAF6"
TEAL = "#2A9D8F"

THEMES = {
    "light": {"ink": "#1E1E1E", "paper": "#FFFFFF", "muted": "#5F6368"},
    "dark": {"ink": "#F2F0EA", "paper": "#0D1117", "muted": "#A9AFB8"},
}


def text_path(font_file, text, size, x, baseline):
    """Returns (svg path data, advance width) for text set at size."""
    font = TTFont(FONTS / font_file)
    glyph_set = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    pen = SVGPathPen(glyph_set)
    cursor = 0.0
    for char in text:
        name = cmap[ord(char)]
        # Font units are y-up; SVG is y-down.
        transform = (scale, 0, 0, -scale, x + cursor * scale, baseline)
        glyph_set[name].draw(TransformPen(pen, transform))
        cursor += font["hmtx"][name][0]
    return pen.getCommands(), cursor * scale


def mark(theme, simple=False):
    """The mark in a 200x200 box: the red code card in front, the drawn card behind."""
    ink, paper = theme["ink"], theme["paper"]
    if simple:
        # For 16 and 32 px: thicker lines, one hatched circle, no arrows.
        back = f"""
    <g transform="rotate(12 130 92)">
      <path d="M78 30 L178 26 L182 150 L82 154 Z" fill="{paper}" stroke="{ink}" stroke-width="9" stroke-linejoin="round"/>
      <g clip-path="url(#hatch)" stroke="{TEAL}" stroke-width="6" stroke-linecap="round">
        <path d="M118 104 L158 64 M130 104 L170 64 M142 104 L182 64 M106 104 L146 64 M154 104 L194 64"/>
      </g>
      <circle cx="146" cy="84" r="22" fill="none" stroke="{ink}" stroke-width="8"/>
    </g>"""
        clip = '<clipPath id="hatch"><circle cx="146" cy="84" r="22"/></clipPath>'
        front = f"""
    <rect x="16" y="56" width="120" height="132" rx="18" fill="{RED}"/>
    <rect x="36" y="92" width="56" height="16" rx="8" fill="{CODE_WHITE}"/>
    <rect x="50" y="126" width="66" height="16" rx="8" fill="{YELLOW}"/>"""
        return clip, back + front

    back = f"""
    <g transform="rotate(12 130 92)">
      <path d="M82 34 L176 30 L180 148 L86 152 Z" fill="{paper}" stroke="{ink}" stroke-width="5" stroke-linejoin="round"/>
      <path d="M141 43 L162 42 L163 63 L142 64 Z" fill="none" stroke="{ink}" stroke-width="4" stroke-linejoin="round"/>
      <g clip-path="url(#hatch)" stroke="{TEAL}" stroke-width="3.5" stroke-linecap="round">
        <path d="M128 108 L156 80 M135 108 L163 80 M142 108 L170 80 M149 108 L177 80 M156 108 L184 80 M163 108 L191 80"/>
      </g>
      <circle cx="157" cy="94" r="13" fill="none" stroke="{ink}" stroke-width="4"/>
      <path d="M146 138 L160 114 L174 138 Z" fill="none" stroke="{ink}" stroke-width="4" stroke-linejoin="round"/>
    </g>"""
    clip = '<clipPath id="hatch"><circle cx="157" cy="94" r="13"/></clipPath>'
    front = f"""
    <rect x="22" y="60" width="112" height="124" rx="14" fill="{RED}"/>
    <rect x="40" y="84" width="40" height="9" rx="4.5" fill="{CODE_WHITE}"/>
    <rect x="52" y="102" width="62" height="9" rx="4.5" fill="{YELLOW}"/>
    <rect x="52" y="120" width="44" height="9" rx="4.5" fill="{PINK}"/>
    <rect x="40" y="138" width="28" height="9" rx="4.5" fill="{CODE_WHITE}"/>
    <g fill="none" stroke="{ink}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">
      <path d="M38 46 C 42 30, 54 21, 70 20"/>
      <path d="M62 13 L72 20 L62 28"/>
      <path d="M170 170 C 170 183, 162 190, 150 190"/>
      <path d="M158 183 L148 190 L158 197"/>
    </g>"""
    return clip, back + front


def svg(width, height, title, defs, body):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:.0f} {height:.0f}" width="{width:.0f}" height="{height:.0f}" role="img" aria-labelledby="title">
  <title id="title">{title}</title>
  <defs>{defs}</defs>{body}
</svg>
"""


def write(name, content):
    (OUT / name).write_text(content)
    print(name)


TITLE = "omoteura — code in front, context behind."

for theme_name, theme in THEMES.items():
    suffix = "" if theme_name == "light" else "-dark"
    clip, body = mark(theme)
    write(f"omoteura-mark{suffix}.svg", svg(200, 200, "omoteura", clip, body))

    simple_clip, simple_body = mark(theme, simple=True)
    write(f"omoteura-icon{suffix}.svg", svg(200, 200, "omoteura", simple_clip, simple_body))

    # Horizontal: mark, then the wordmark centred on the mark's height.
    word, word_width = text_path("Kalam-Bold.ttf", "omoteura", 120, 0, 0)
    width = 200 + 32 + word_width + 8
    body_h = f"{body}\n  <g transform=\"translate(232 132)\"><path d=\"{word}\" fill=\"{theme['ink']}\"/></g>"
    write(f"omoteura-logo{suffix}.svg", svg(width, 200, TITLE, clip, body_h))

    # Vertical: mark, wordmark and tagline, centred.
    word, word_width = text_path("Kalam-Bold.ttf", "omoteura", 112, 0, 0)
    tag, tag_width = text_path("Kalam-Regular.ttf", "code in front, context behind.", 34, 0, 0)
    width = max(word_width, tag_width) + 40
    mark_x = (width - 200) / 2
    body_v = (
        f"\n  <g transform=\"translate({mark_x:.1f} 0)\">{body}\n  </g>"
        f"\n  <g transform=\"translate({(width - word_width) / 2:.1f} 300)\"><path d=\"{word}\" fill=\"{theme['ink']}\"/></g>"
        f"\n  <g transform=\"translate({(width - tag_width) / 2:.1f} 358)\"><path d=\"{tag}\" fill=\"{theme['muted']}\"/></g>"
    )
    write(f"omoteura-logo-vertical{suffix}.svg", svg(width, 380, TITLE, clip, body_v))
