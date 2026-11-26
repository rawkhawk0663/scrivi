/// Zeichenliste: Was auf einer Seite zu zeichnen ist, unabhängig davon, ob
/// es auf den Bildschirm oder in ein PDF geht.
///
/// Masseinheit: Linienabstände (sp). Ursprung oben links, y zeigt nach unten.
library;

/// Rolle eines Textes: Die App wählt dazu Schrift, Schnitt und Farbe.
enum TextRole { title, subtitle, credit, chord, section, tab, text, lyrics, barNumber, tempo, technique, volta, small }

enum TextAlign { left, center, right }

sealed class DisplayItem {
  const DisplayItem();
}

/// Notenzeichen aus Bravura, Ursprung auf (x, y), Grösse [scale] (1 = normal).
class GlyphItem extends DisplayItem {
  const GlyphItem(this.name, this.x, this.y, {this.scale = 1});
  final String name;
  final double x;
  final double y;
  final double scale;
}

class LineItem extends DisplayItem {
  const LineItem(this.x1, this.y1, this.x2, this.y2, this.thickness, {this.dash, this.roundCap = false});
  final double x1, y1, x2, y2;
  final double thickness;

  /// Gestrichelt: Länge von Strich und Lücke.
  final (double, double)? dash;
  final bool roundCap;
}

class RectItem extends DisplayItem {
  const RectItem(
    this.x,
    this.y,
    this.width,
    this.height, {
    this.fill = true,
    this.thickness = 0.13,
    this.background = false,
  });
  final double x, y, width, height;
  final bool fill;
  final double thickness;

  /// In Papierfarbe (zum Freistellen, z. B. hinter Tab-Zahlen).
  final bool background;
}

/// Gefüllte Fläche (Balken, Bögen, Gabeln): 0 moveTo, 1 lineTo, 3 cubicTo, 4 close.
class PathItem extends DisplayItem {
  const PathItem(this.commands, {this.fill = true, this.thickness = 0.13});
  final List<double> commands;
  final bool fill;
  final double thickness;
}

/// Text mit Grundlinie auf y.
class TextItem extends DisplayItem {
  const TextItem(
    this.text,
    this.x,
    this.y,
    this.role,
    this.size, {
    this.align = TextAlign.left,
    this.bold = false,
    this.italic = false,
  });
  final String text;
  final double x;
  final double y;
  final TextRole role;

  /// Schriftgrösse in Linienabständen.
  final double size;
  final TextAlign align;
  final bool bold;
  final bool italic;
}

/// Eine Seite: Grösse und Inhalt.
class PageDisplay {
  PageDisplay(this.width, this.height);
  final double width;
  final double height;
  final List<DisplayItem> items = [];
  final List<SystemBox> systems = [];
}

/// Wo eine Zeile (System) auf der Seite liegt und welche Takte sie zeigt.
class SystemBox {
  const SystemBox({
    required this.top,
    required this.bottom,
    required this.firstBar,
    required this.lastBar,
    this.bars = const [],
  });
  final double top;
  final double bottom;
  final int firstBar;
  final int lastBar;

  /// Lage der Takte und ihrer Schläge (für die mitlaufende Markierung).
  final List<BarSpan> bars;

  /// x-Stelle zu Takt [bar] und Stelle [position] (ganze Noten), null = nicht in dieser Zeile.
  double? xAt(int bar, double position) {
    for (final b in bars) {
      if (b.bar == bar) return b.xAt(position);
    }
    return null;
  }
}

/// Ein Takt in einer Zeile: von [x0] bis [x1], Schläge an [beats] (Stelle in ganzen Noten, x).
class BarSpan {
  const BarSpan(this.bar, this.x0, this.x1, this.length, this.beats);
  final int bar;
  final double x0;
  final double x1;
  final double length;
  final List<(double, double)> beats;

  /// x-Stelle zur Stelle [position]: zwischen den Schlägen gleichmässig verteilt.
  double xAt(double position) {
    final pts = [(0.0, beats.isEmpty ? x0 : beats.first.$2), ...beats, (length, x1)];
    for (var i = 0; i + 1 < pts.length; i++) {
      final (p0, a) = pts[i];
      final (p1, b) = pts[i + 1];
      if (position <= p1 || i + 2 == pts.length) {
        if (p1 <= p0) return b;
        return a + (b - a) * ((position - p0) / (p1 - p0)).clamp(0.0, 1.0);
      }
    }
    return x0;
  }
}

/// Misst Texte, damit der Notensatz Platz lassen kann. Die App misst genau,
/// Tests und Werkzeuge schätzen.
abstract class TextMeasurer {
  double width(String text, TextRole role, double size, {bool bold = false, bool italic = false});
}

class ApproxTextMeasurer implements TextMeasurer {
  const ApproxTextMeasurer();
  @override
  double width(String text, TextRole role, double size, {bool bold = false, bool italic = false}) =>
      text.length * size * (bold ? 0.62 : 0.56);
}
