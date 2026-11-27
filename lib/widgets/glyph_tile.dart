import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../app/theme.dart';
import '../features/score/score_painter.dart';

/// Quadratisches Feld mit Notenzeichen (aus Bravura) oder einem Symbol.
///
/// Die Notenzeichen werden nach ihrer tatsächlichen Tinte eingepasst und
/// mittig gezeichnet: So sind Violinschlüssel, Bassschlüssel und TAB gleich
/// gross, egal wie die Schrift sie auf die Grundlinie setzt.
class GlyphTile extends StatelessWidget {
  const GlyphTile({super.key, this.glyphs = const [], this.icon, this.label, this.eighthNote = false, this.size = 56});

  /// Eine Achtelnote, zusammengesetzt aus Kopf, Hals und Fähnchen (die fertigen
  /// Notenzeichen haben so dünne Hälse, dass sie klein gezeichnet verschwinden).
  final bool eighthNote;

  /// Notenzeichen nebeneinander (Namen wie in `Glyphs`).
  final List<String> glyphs;
  final IconData? icon;

  /// Kleiner Text oben links (z. B. ein Akkordsymbol).
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: icon != null
          ? Icon(icon, size: size * 0.5, color: color)
          : CustomPaint(painter: _GlyphPainter(glyphs, label, color, c.muted, eighthNote)),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyphs, this.label, this.color, this.labelColor, this.eighthNote);
  final bool eighthNote;
  final List<String> glyphs;
  final String? label;
  final Color color;
  final Color labelColor;

  /// Zeichen [name] mit Grundlinie bei ([x], [y]) im Fenster, [scale] Pixel pro Linienabstand.
  static void _glyph(Canvas canvas, String name, double x, double y, double scale, Paint paint) {
    canvas.save();
    canvas.translate(x, y);
    final s = scale / PagePictures.glyphUnit;
    canvas.scale(s, -s);
    canvas.drawPath(PagePictures.glyphPath(name), paint);
    canvas.restore();
  }

  void _paintLabel(Canvas canvas, Size size) {
    final l = label;
    if (l == null) return;
    final tp = TextPainter(
      text: TextSpan(
        text: l,
        style: TextStyle(color: color, fontSize: size.height * 0.2, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width * 0.14, size.height * 0.1));
  }

  /// Achtelnote: Kopf, Hals (3,5 Linienabstände) und Fähnchen, mittig.
  void _paintEighth(Canvas canvas, Size size) {
    final head = core.Glyphs.get('noteheadBlack');
    final flag = core.Glyphs.get('flag8thUp');
    const stemLen = 3.5, stemW = 0.16;
    final w = head.right + flag.right - stemW / 2, h = stemLen + 0.5;
    final pad = size.width * 0.16;
    final labelSpace = label == null ? 0.0 : size.height * 0.2;
    final box = Rect.fromLTRB(pad, pad + labelSpace, size.width - pad, size.height - pad);
    final scale = math.min(box.width / w, box.height / h);
    final x0 = box.center.dx - w * scale / 2;
    final base = box.center.dy + h * scale / 2 - 0.5 * scale; // Mitte des Kopfs
    final paint = Paint()..color = color;
    _glyph(canvas, 'noteheadBlack', x0, base, scale, paint);
    final sx = x0 + (head.right - stemW / 2) * scale;
    canvas.drawLine(
      Offset(sx, base - 0.15 * scale),
      Offset(sx, base - stemLen * scale),
      Paint()
        ..color = color
        ..strokeWidth = math.max(1.6, stemW * scale),
    );
    _glyph(canvas, 'flag8thUp', sx - stemW / 2 * scale, base - stemLen * scale, scale, paint);
    _paintLabel(canvas, size);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (eighthNote) {
      _paintEighth(canvas, size);
      return;
    }
    if (glyphs.isEmpty) return;
    const gap = 0.9; // Abstand zwischen den Zeichen (Linienabstände)
    // Tinte aller Zeichen: Breite nebeneinander, gemeinsame Höhe
    var width = 0.0, top = double.negativeInfinity, bottom = double.infinity;
    final data = [for (final g in glyphs) core.Glyphs.get(g)];
    for (final d in data) {
      width += d.right - d.left;
      top = math.max(top, d.top);
      bottom = math.min(bottom, d.bottom);
    }
    width += gap * (data.length - 1);
    final height = top - bottom;
    // Platz: oben etwas frei, wenn eine Beschriftung da ist
    final pad = size.width * 0.13;
    final labelSpace = label == null ? 0.0 : size.height * 0.22;
    final box = Rect.fromLTRB(pad, pad + labelSpace, size.width - pad, size.height - pad);
    // Gemeinsamer Massstab: das Feld fasst mindestens 5 Linienabstände in der Höhe,
    // damit ein Bassschlüssel nicht grösser wirkt als ein Violinschlüssel
    final scale = math.min(box.width / width, box.height / math.max(height, 5.0));
    final x0 = box.center.dx - width * scale / 2;
    final y0 = box.center.dy - height * scale / 2;
    final paint = Paint()..color = color;
    var x = x0;
    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      canvas.save();
      // Grundlinie so, dass die gemeinsame Oberkante bei y0 liegt (die Umrisse zeigen nach oben)
      canvas.translate(x - d.left * scale, y0 + top * scale);
      final s = scale / PagePictures.glyphUnit;
      canvas.scale(s, -s);
      canvas.drawPath(PagePictures.glyphPath(glyphs[i]), paint);
      canvas.restore();
      x += (d.right - d.left + gap) * scale;
    }
    _paintLabel(canvas, size);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.color != color || old.label != label || old.eighthNote != eighthNote || old.glyphs.join() != glyphs.join();
}
