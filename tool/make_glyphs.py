"""Erzeugt packages/scrivi_core/lib/src/render/glyphs.g.dart aus der Schrift Bravura (SMuFL).

Für jedes benötigte Notenzeichen werden die Umrisse (als Pfad), die Ausdehnung und die
Ansatzpunkte (z. B. wo der Hals an den Notenkopf kommt) abgelegt. So zeichnen Bildschirm
und PDF dieselben Formen, ohne die Schrift selbst zu brauchen.

Masseinheit: Linienabstände (staff spaces). Bravura hat 1000 Einheiten pro Geviert,
ein Linienabstand sind 250 Einheiten. y zeigt nach oben (wie in der Schrift).

Aufruf:
  python3 tool/make_glyphs.py <glyphnames.json> <Bravura.json>
glyphnames.json: aus der SMuFL-Beschreibung, Bravura.json: Metadaten aus dem Bravura-Paket.
"""
import json
import os
import sys

from fontTools.pens.recordingPen import RecordingPen
from fontTools.ttLib import TTFont

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(BASE, 'assets/fonts/Bravura.otf')
OUT = os.path.join(BASE, 'packages/scrivi_core/lib/src/render/glyphs.g.dart')

GLYPHS = [
    # Notenköpfe
    'noteheadBlack', 'noteheadHalf', 'noteheadWhole', 'noteheadDoubleWhole',
    'noteheadXBlack', 'noteheadXHalf', 'noteheadXWhole',
    'noteheadSlashVerticalEnds', 'noteheadSlashWhiteHalf', 'noteheadSlashWhiteWhole',
    'noteheadSlashHorizontalEnds',
    'noteheadDiamondBlack', 'noteheadDiamondHalf', 'noteheadDiamondWhole',
    # Schlüssel
    'gClef', 'gClef8vb', 'fClef', 'cClef', 'unpitchedPercussionClef1', '6stringTabClef', '4stringTabClef',
    # Vorzeichen
    'accidentalSharp', 'accidentalFlat', 'accidentalNatural', 'accidentalDoubleSharp', 'accidentalDoubleFlat',
    'accidentalParensLeft', 'accidentalParensRight',
    # Taktangaben
    'timeSig0', 'timeSig1', 'timeSig2', 'timeSig3', 'timeSig4', 'timeSig5', 'timeSig6', 'timeSig7',
    'timeSig8', 'timeSig9', 'timeSigCommon', 'timeSigCutCommon',
    # Pausen
    'restDoubleWhole', 'restWhole', 'restHalf', 'restQuarter', 'rest8th', 'rest16th', 'rest32nd', 'rest64th',
    'rest128th', 'restWholeLegerLine', 'restHalfLegerLine',
    # Fähnchen
    'flag8thUp', 'flag8thDown', 'flag16thUp', 'flag16thDown', 'flag32ndUp', 'flag32ndDown',
    'flag64thUp', 'flag64thDown', 'flag128thUp', 'flag128thDown',
    # Punkte, Wiederholungen, Form
    'augmentationDot', 'repeatDot', 'segno', 'coda', 'repeat1Bar', 'repeat2Bars',
    # Oktavierung
    'ottavaAlta', 'ottavaBassaVb', 'quindicesimaAlta', 'quindicesimaBassaMb',
    # Dynamik
    'dynamicPiano', 'dynamicMezzo', 'dynamicForte', 'dynamicPPPP', 'dynamicPPP', 'dynamicPP', 'dynamicMP',
    'dynamicMF', 'dynamicFF', 'dynamicFFF', 'dynamicFFFF', 'dynamicSforzando1', 'dynamicFortePiano',
    # Artikulation
    'articAccentAbove', 'articAccentBelow', 'articStaccatoAbove', 'articStaccatoBelow',
    'articTenutoAbove', 'articTenutoBelow', 'articMarcatoAbove', 'articMarcatoBelow',
    'articStaccatissimoAbove', 'articStaccatissimoBelow', 'fermataAbove', 'fermataBelow',
    # Tempoangabe
    'metNoteWhole', 'metNoteHalfUp', 'metNoteQuarterUp', 'metNote8thUp', 'metNote16thUp', 'metAugmentationDot',
    # n-tolen
    'tuplet0', 'tuplet1', 'tuplet2', 'tuplet3', 'tuplet4', 'tuplet5', 'tuplet6', 'tuplet7', 'tuplet8', 'tuplet9',
    'tupletColon',
    # Verzierungen und Gitarre
    'ornamentTrill', 'wiggleTrill', 'wiggleVibrato', 'guitarVibratoStroke', 'stringsHarmonic',
    'arrowheadBlackUp', 'arrowheadBlackDown', 'stringsDownBow', 'stringsUpBow',
    'graceNoteSlashStemUp', 'graceNoteAcciaccaturaStemUp',
    # Fingersätze und Pedal
    'fingering0', 'fingering1', 'fingering2', 'fingering3', 'fingering4', 'fingering5', 'fingering6',
    'fingeringTUpper', 'fingeringPLower', 'fingeringILower', 'fingeringMLower', 'fingeringALower',
    'fingeringCLower', 'keyboardPedalPed', 'keyboardPedalUp',
    # Akkordsymbole
    'csymAccidentalFlat', 'csymAccidentalSharp', 'csymAccidentalNatural', 'csymAccidentalDoubleFlat',
    'csymAccidentalDoubleSharp', 'csymMajorSeventh', 'csymMinor', 'csymDiminished', 'csymHalfDiminished',
    'csymAugmented', 'csymParensLeftTall', 'csymParensRightTall', 'csymParensLeftVeryTall',
    'csymParensRightVeryTall',
]


def main():
    names = json.load(open(sys.argv[1]))
    meta = json.load(open(sys.argv[2]))
    font = TTFont(FONT)
    gs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = 1 / 250.0

    def f(v):
        s = f'{v:.4f}'.rstrip('0').rstrip('.')
        return '0' if s in ('-0', '') else s

    lines = [
        '// ERZEUGT von tool/make_glyphs.py – nicht von Hand ändern.',
        '// Umrisse und Masse aus der Schrift Bravura (SIL Open Font License).',
        '// ignore_for_file: constant_identifier_names',
        '',
        "part of 'glyphs.dart';",
        '',
        f"const _fontVersion = '{meta.get('fontVersion')}';",
        '',
        '/// Grundwerte für Linienstärken usw. in Linienabständen.',
        'const _engravingDefaults = <String, double>{',
    ]
    for k, v in sorted(meta['engravingDefaults'].items()):
        if isinstance(v, (int, float)):
            lines.append(f"  '{k}': {f(float(v))},")
    lines.append('};')
    lines.append('')
    lines.append('const _glyphData = <String, GlyphData>{')
    for name in GLYPHS:
        if name not in names:
            raise SystemExit(f'Unbekanntes Zeichen: {name}')
        cp = int(names[name]['codepoint'][2:], 16)
        gname = cmap.get(cp)
        if gname is None:
            raise SystemExit(f'Nicht in der Schrift: {name}')
        pen = RecordingPen()
        gs[gname].draw(pen)
        path = []
        for op, pts in pen.value:
            if op == 'moveTo':
                path += [0, *pts[0]]
            elif op == 'lineTo':
                path += [1, *pts[0]]
            elif op == 'curveTo':
                # Mehrere Kontrollpunkte: in kubische Stücke zerlegen (CFF hat immer genau 3).
                if len(pts) != 3:
                    raise SystemExit(f'Unerwartete Kurve in {name}')
                path += [3, *pts[0], *pts[1], *pts[2]]
            elif op == 'qCurveTo':
                raise SystemExit(f'Quadratische Kurve in {name}')
            elif op in ('closePath', 'endPath'):
                path += [4]
        # Masse in Linienabstände umrechnen (Opcodes bleiben ganzzahlig)
        out = []
        i = 0
        while i < len(path):
            opc = path[i]
            n = {0: 2, 1: 2, 3: 6, 4: 0}[opc]
            out.append(str(opc))
            for v in path[i + 1:i + 1 + n]:
                out.append(f(v * scale))
            i += 1 + n
        bb = meta['glyphBBoxes'].get(name, {})
        sw = bb.get('bBoxSW', [0, 0])
        ne = bb.get('bBoxNE', [0, 0])
        adv = meta.get('glyphAdvanceWidths', {}).get(name, ne[0])
        anchors = meta['glyphsWithAnchors'].get(name, {})
        a = ', '.join(f"'{k}': Pt({f(v[0])}, {f(v[1])})" for k, v in sorted(anchors.items()))
        lines.append(f"  '{name}': GlyphData(0x{cp:X}, {f(sw[0])}, {f(sw[1])}, {f(ne[0])}, {f(ne[1])}, {f(adv)},")
        lines.append(f'      {{{a}}},')
        lines.append(f"      [{', '.join(out)}]),")
    lines.append('};')
    lines.append('')
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w') as fh:
        fh.write('\n'.join(lines))
    print(f'{len(GLYPHS)} Zeichen geschrieben: {OUT}')


main()
