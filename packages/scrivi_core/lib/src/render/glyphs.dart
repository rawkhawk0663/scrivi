/// Notenzeichen aus Bravura: Umrisse, Ausdehnung und Ansatzpunkte, in
/// Linienabständen, y nach oben (wie in der Schrift).
library;

part 'glyphs.g.dart';

class Pt {
  const Pt(this.x, this.y);
  final double x;
  final double y;

  @override
  String toString() => 'Pt($x, $y)';
}

class GlyphData {
  const GlyphData(this.codepoint, this.left, this.bottom, this.right, this.top, this.advance, this.anchors, this.path);

  final int codepoint;

  /// Ausdehnung (Tinte) um den Ursprung.
  final double left;
  final double bottom;
  final double right;
  final double top;
  final double advance;
  final Map<String, Pt> anchors;

  /// Umriss: 0 moveTo(x,y), 1 lineTo(x,y), 3 cubicTo(x1,y1,x2,y2,x,y), 4 close.
  final List<double> path;

  double get width => right - left;
  double get height => top - bottom;
}

class Glyphs {
  Glyphs._();

  static String get fontVersion => _fontVersion;

  static GlyphData get(String name) {
    final g = _glyphData[name];
    if (g == null) throw ArgumentError('Unbekanntes Notenzeichen: $name');
    return g;
  }

  static bool has(String name) => _glyphData.containsKey(name);

  static Iterable<String> get names => _glyphData.keys;

  /// Grundwert aus der Schrift, z. B. `stemThickness`.
  static double engraving(String key, [double fallback = 0.13]) => _engravingDefaults[key] ?? fallback;
}
