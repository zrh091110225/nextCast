#!/usr/bin/env python3
"""Generate a compact BMFont atlas from the text currently displayed in Views.mc."""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
FONT_SIZE = 16
LINE_HEIGHT = 21
ATLAS_WIDTH = 256


def displayed_characters() -> list[str]:
    source = (ROOT / "source" / "Views.mc").read_text(encoding="utf-8")
    literals = re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', source)
    # Keep a minimal Latin set for dynamic durations and the English app title.
    characters = set("0123456789: /-?CastTimer")
    characters.update("".join(literals))
    return sorted(characters, key=ord)


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate_cjk_font.py /path/to/NotoSansCJKsc-Regular.otf")

    font_path = Path(sys.argv[1])
    font = ImageFont.truetype(font_path, FONT_SIZE)
    glyphs = []
    for char in displayed_characters():
        left, top, right, bottom = font.getbbox(char)
        width = max(1, right - left)
        height = max(1, bottom - top)
        advance = max(1, math.ceil(font.getlength(char)))
        glyphs.append((char, left, top, width, height, advance))

    rows = []
    row = []
    row_width = 0
    row_height = 0
    for glyph in glyphs:
        glyph_width = glyph[3] + 2
        if row and row_width + glyph_width > ATLAS_WIDTH:
            rows.append((row, row_height))
            row, row_width, row_height = [], 0, 0
        row.append(glyph)
        row_width += glyph_width
        row_height = max(row_height, glyph[4] + 2)
    if row:
        rows.append((row, row_height))

    atlas_height = sum(height for _, height in rows)
    atlas = Image.new("L", (ATLAS_WIDTH, atlas_height), 0)
    draw = ImageDraw.Draw(atlas)
    chars = []
    y = 0
    for row, row_height in rows:
        x = 0
        for char, left, top, width, height, advance in row:
            draw.text((x - left, y - top), char, font=font, fill=255)
            chars.append((ord(char), x, y, width, height, left, top, advance))
            x += width + 2
        y += row_height

    output_dir = ROOT / "resources" / "fonts"
    output_dir.mkdir(parents=True, exist_ok=True)
    atlas.save(output_dir / "cjk-ui.png")

    lines = [
        'info face="STHeiti Medium UI subset" size=-16 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1 outline=0',
        f"common lineHeight={LINE_HEIGHT} base={FONT_SIZE} scaleW={ATLAS_WIDTH} scaleH={atlas_height} pages=1 packed=0 alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0",
        'page id=0 file="cjk-ui.png"',
        f"chars count={len(chars)}",
    ]
    for codepoint, x, y, width, height, left, top, advance in chars:
        lines.append(
            f"char id={codepoint} x={x} y={y} width={width} height={height} "
            f"xoffset={left} yoffset={top} xadvance={advance} page=0 chnl=15"
        )
    lines.append("kernings count=0")
    (output_dir / "cjk-ui.fnt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Generated {len(chars)} glyphs at {ATLAS_WIDTH}x{atlas_height}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
