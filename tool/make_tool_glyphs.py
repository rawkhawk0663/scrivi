"""Erzeugt lib/features/score/tool_glyphs.g.dart: Ausdehnung der Notenzeichen auf den Werkzeug-Knöpfen.

Die Knöpfe zeigen Zeichen aus der Schrift Bravura. Ihr Ursprung liegt auf der Notenlinie, nicht in
der Mitte; damit jedes Zeichen genau in der Mitte des Knopfs steht und nicht übersteht, braucht die
App die Ausdehnung der Tinte. Das Skript sucht alle Zeichen (\\uE000–\\uF8FF) in
lib/features/score/tools.dart und schreibt für jedes links, unten, rechts, oben und die Vorschubbreite.

Masseinheit: Linienabstände (ein Geviert = 4 Linienabstände), y nach oben (wie in der Schrift).

Aufruf:
  python3 tool/make_tool_glyphs.py
"""
import os
import re

from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(BASE, 'assets/fonts/Bravura.otf')
TOOLS = os.path.join(BASE, 'lib/features/score/tools.dart')
OUT = os.path.join(BASE, 'lib/features/score/tool_glyphs.g.dart')


def main():
    src = open(TOOLS, encoding='utf-8').read()
    codes = sorted({int(h, 16) for h in re.findall(r'\\u([0-9A-Fa-f]{4})', src) if 0xE000 <= int(h, 16) <= 0xF8FF})
    font = TTFont(FONT)
    cmap = font.getBestCmap()
    gs = font.getGlyphSet()
    upm = font['head'].unitsPerEm
    sp = upm / 4
    lines = []
    for c in codes:
        name = cmap.get(c)
        if name is None:
            raise SystemExit(f'Nicht in der Schrift: U+{c:04X}')
        pen = BoundsPen(gs)
        gs[name].draw(pen)
        l, b, r, t = pen.bounds or (0, 0, 0, 0)
        adv = font['hmtx'][name][0]
        vals = ', '.join(f'{v / sp:.3f}' for v in (l, b, r, t, adv))
        lines.append(f'  0x{c:04X}: ({vals}),')
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write('// Erzeugt mit tool/make_tool_glyphs.py – nicht von Hand ändern.\n\n')
        f.write('/// Ausdehnung der Zeichen auf den Werkzeug-Knöpfen in Linienabständen:\n')
        f.write('/// (links, unten, rechts, oben, Vorschub), y nach oben.\n')
        f.write('const toolGlyphBoxes = <int, (double, double, double, double, double)>{\n')
        f.write('\n'.join(lines))
        f.write('\n};\n')
    print(f'{len(codes)} Zeichen geschrieben: {OUT}')


if __name__ == '__main__':
    main()
