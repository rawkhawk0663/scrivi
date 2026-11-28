import 'dart:math' as math;

import '../model/chord_symbol.dart';
import '../render/display.dart';
import '../render/glyphs.dart';

/// Zeichen der Akkordsymbole, die aus Bravura kommen (Rest: Schrift der Akkorde).
const _symbols = {
  '♯': 'csymAccidentalSharp',
  '♭': 'csymAccidentalFlat',
  '♮': 'csymAccidentalNatural',
  'Δ': 'csymMajorSeventh',
  '°': 'csymDiminished',
  'ø': 'csymHalfDiminished',
  '+': 'csymAugmented',
  '−': 'csymMinor',
};

/// Grösse der hochgestellten Teile und der Zeilen im Stapel (Teil der Grösse des Grundtons).
const chordRaisedScale = 0.7;
const _stackScale = 0.6;

/// Ein Akkordsymbol als Zeichen: ab [x], Grundlinie [y], Grösse [size] (sp).
/// Liefert die Zeichen, die Breite und die Oberkante.
({List<DisplayItem> items, double width, double top}) drawChord(
  List<ChordPart> parts,
  double x,
  double y,
  double size,
  TextMeasurer measurer,
) {
  final items = <DisplayItem>[];
  var top = y - size * 0.8;
  var cx = x;
  for (final p in parts) {
    if (p.stack != null) {
      final w = _stack(items, p, cx, y, size, measurer);
      top = math.min(top, y - size * 0.45 - p.stack!.length * size * _stackScale / 2 - size * 0.1);
      cx += w;
    } else if (p.raised) {
      final s = size * chordRaisedScale;
      cx += _run(items, p.text, cx, y - size * 0.42, s, measurer);
      top = math.min(top, y - size * 0.42 - s * 0.8);
    } else {
      cx += _run(items, p.text, cx, y, size, measurer);
    }
  }
  return (items: items, width: cx - x, top: top);
}

/// Text mit Bravura-Zeichen; gibt die Breite zurück.
double _run(List<DisplayItem> items, String text, double x, double y, double size, TextMeasurer measurer) {
  var cx = x;
  final buf = StringBuffer();
  void flush() {
    if (buf.isEmpty) return;
    final t = buf.toString();
    items.add(TextItem(t, cx, y, TextRole.chord, size, bold: true));
    cx += measurer.width(t, TextRole.chord, size, bold: true);
    buf.clear();
  }

  for (final ch in text.split('')) {
    final name = _symbols[ch];
    if (name == null) {
      buf.write(ch);
      continue;
    }
    flush();
    // Bravura: ein Geviert = 4 sp. Vorzeichen in Schriftgrösse, die übrigen Zeichen etwas grösser,
    // damit sie neben den fetten Buchstaben nicht verloren wirken.
    final accidental = name.startsWith('csymAccidental');
    final scale = size / 4 * (accidental ? 1.0 : 1.35);
    final g = Glyphs.get(name);
    items.add(GlyphItem(name, cx + size * 0.03, y, scale: scale));
    cx += g.right * scale + size * 0.06;
  }
  flush();
  return cx - x;
}

/// Mehrere veränderte Töne übereinander, auf Wunsch in hohen Klammern; gibt die Breite zurück.
double _stack(List<DisplayItem> items, ChordPart p, double x, double y, double size, TextMeasurer measurer) {
  final lines = p.stack!;
  final ls = size * _stackScale;
  final lh = ls * 1.02;
  final h = lines.length * lh;
  final mid = y - size * 0.45;
  final blockTop = mid - h / 2;
  var cx = x + size * 0.05;
  String? closing;
  double k = 0;
  if (p.parens) {
    final name = lines.length >= 3 ? 'csymParensLeftVeryTall' : 'csymParensLeftTall';
    closing = lines.length >= 3 ? 'csymParensRightVeryTall' : 'csymParensRightTall';
    final g = Glyphs.get(name);
    k = (h + size * 0.2) / (g.top - g.bottom);
    items.add(GlyphItem(name, cx, blockTop + h + size * 0.1 + g.bottom * k, scale: k));
    cx += g.right * k + size * 0.06;
  }
  var w = 0.0;
  final scratch = <DisplayItem>[];
  for (final l in lines) {
    w = math.max(w, _run(scratch, l, 0, 0, ls, measurer));
  }
  for (var i = 0; i < lines.length; i++) {
    final lw = _run(<DisplayItem>[], lines[i], 0, 0, ls, measurer);
    // Rechtsbündig, damit Zahlen untereinander stehen
    _run(items, lines[i], cx + w - lw, blockTop + (i + 1) * lh - lh * 0.18, ls, measurer);
  }
  cx += w;
  if (closing != null) {
    final g = Glyphs.get(closing);
    cx += size * 0.06;
    items.add(GlyphItem(closing, cx, blockTop + h + size * 0.1 + g.bottom * k, scale: k));
    cx += g.right * k;
  }
  return cx - x + size * 0.05;
}
