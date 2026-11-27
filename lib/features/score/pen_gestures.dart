import 'dart:math' as math;
import 'dart:ui';

/// Was ein Strich mit dem Stift bedeutet.
enum PenStroke {
  /// Antippen: Note setzen (bzw. Cursor in der Tabulatur).
  tap,

  /// Waagrechter Strich: Bereich auswählen.
  line,

  /// Durchkritzeln (hin und her): löschen.
  scribble,

  /// Kurzer Strich nach oben bzw. unten: einen Halbton höher bzw. tiefer.
  flickUp,
  flickDown,

  /// Nicht erkannt: nichts tun.
  none,
}

/// Erkennt einen Strich aus den Punkten (Bildschirm-Pixel, in der Reihenfolge
/// des Zeichnens).
PenStroke classifyStroke(List<Offset> pts) {
  if (pts.isEmpty) return PenStroke.none;
  var minX = pts.first.dx, maxX = minX, minY = pts.first.dy, maxY = minY;
  var length = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
    if (i > 0) length += (p - pts[i - 1]).distance;
  }
  final w = maxX - minX, h = maxY - minY;
  if (w < 10 && h < 10) return PenStroke.tap;
  // Richtungswechsel waagrecht zählen (mit etwas Spiel gegen Zittern)
  const slack = 6.0;
  var reversals = 0, dir = 0;
  var ext = pts.first.dx;
  for (final p in pts) {
    final x = p.dx;
    if (dir == 0) {
      if (x - ext > slack) {
        dir = 1;
        ext = x;
      } else if (ext - x > slack) {
        dir = -1;
        ext = x;
      }
    } else if (dir > 0) {
      if (x > ext) {
        ext = x;
      } else if (ext - x > slack) {
        dir = -1;
        ext = x;
        reversals++;
      }
    } else {
      if (x < ext) {
        ext = x;
      } else if (x - ext > slack) {
        dir = 1;
        ext = x;
        reversals++;
      }
    }
  }
  if (reversals >= 3 && length > 2.5 * w) return PenStroke.scribble;
  if (h >= 18 && w <= h * 0.6) {
    return pts.last.dy < pts.first.dy ? PenStroke.flickUp : PenStroke.flickDown;
  }
  if (w >= 16 && h <= w * 0.8) return PenStroke.line;
  return PenStroke.none;
}
