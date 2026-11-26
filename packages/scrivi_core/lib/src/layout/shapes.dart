import '../render/display.dart';

/// Bogen (Haltebogen oder Legatobogen) als gefüllte Form: aussen und innen eine
/// Kurve, in der Mitte [thickness] dick, an den Enden spitz.
/// [up]: nach oben gewölbt.
PathItem arc(double x1, double y1, double x2, double y2, {required bool up, double? height, double thickness = 0.22}) {
  final len = (x2 - x1).abs();
  final h = height ?? (len * 0.12).clamp(0.45, 1.6);
  final s = up ? -1.0 : 1.0;
  final c1x = x1 + (x2 - x1) * 0.25, c2x = x1 + (x2 - x1) * 0.75;
  // Kontrollpunkte einer Bézierkurve liegen höher als die Kurve selbst (4/3).
  final ho = h * 4 / 3, hi = (h - thickness) * 4 / 3;
  return PathItem([
    0, x1, y1,
    3, c1x, y1 + s * ho, c2x, y2 + s * ho, x2, y2,
    3, c2x, y2 + s * hi, c1x, y1 + s * hi, x1, y1,
    4,
  ]);
}

/// Balken als Parallelogramm von (x1, y1) nach (x2, y2), [thickness] dick,
/// [down]: die Dicke wächst nach unten.
PathItem beam(double x1, double y1, double x2, double y2, double thickness, {required bool down}) {
  final t = down ? thickness : -thickness;
  return PathItem([0, x1, y1, 1, x2, y2, 1, x2, y2 + t, 1, x1, y1 + t, 4]);
}

/// Gabel (crescendo/decrescendo) als zwei Linien.
List<LineItem> hairpin(double x1, double x2, double y, {required bool crescendo, double opening = 1.0, double thickness = 0.16, bool openStart = false, bool openEnd = false}) {
  final h = opening / 2;
  // Bei einer Fortsetzung über die Zeile bleibt die Gabel an der Kante etwas offen.
  final a = crescendo ? (openStart ? h * 0.5 : 0.0) : h;
  final b = crescendo ? h : (openEnd ? h * 0.5 : 0.0);
  return [
    LineItem(x1, y - a, x2, y - b, thickness),
    LineItem(x1, y + a, x2, y + b, thickness),
  ];
}

/// Pfeil von (x1, y1) gebogen nach oben zu (x2, y2), mit Spitze.
List<DisplayItem> bendArrow(double x1, double y1, double x2, double y2, {double thickness = 0.13}) {
  // Richtung: −1 nach oben, +1 nach unten
  final dir = y2 < y1 ? -1.0 : 1.0;
  final items = <DisplayItem>[
    PathItem([0, x1, y1, 3, x1 + (x2 - x1) * 0.8, y1, x2, y1 + (y2 - y1) * 0.4, x2, y2 - dir * 0.5], fill: false, thickness: thickness),
  ];
  // Spitze
  items.add(PathItem([0, x2, y2, 1, x2 - 0.3, y2 - dir * 0.6, 1, x2 + 0.3, y2 - dir * 0.6, 4]));
  return items;
}

/// Eine Zeichenliste um (dx, dy) verschieben.
DisplayItem shift(DisplayItem it, double dx, double dy) {
  switch (it) {
    case GlyphItem g:
      return GlyphItem(g.name, g.x + dx, g.y + dy, scale: g.scale);
    case LineItem l:
      return LineItem(l.x1 + dx, l.y1 + dy, l.x2 + dx, l.y2 + dy, l.thickness, dash: l.dash, roundCap: l.roundCap);
    case RectItem r:
      return RectItem(r.x + dx, r.y + dy, r.width, r.height, fill: r.fill, thickness: r.thickness, background: r.background);
    case TextItem t:
      return TextItem(t.text, t.x + dx, t.y + dy, t.role, t.size, align: t.align, bold: t.bold, italic: t.italic);
    case PathItem p:
      final c = p.commands;
      final out = <double>[];
      var i = 0;
      while (i < c.length) {
        final op = c[i].toInt();
        out.add(c[i]);
        final n = switch (op) {
          0 || 1 => 1,
          3 => 3,
          _ => 0,
        };
        for (var k = 0; k < n; k++) {
          out
            ..add(c[i + 1 + k * 2] + dx)
            ..add(c[i + 2 + k * 2] + dy);
        }
        i += 1 + n * 2;
      }
      return PathItem(out, fill: p.fill, thickness: p.thickness);
  }
}
