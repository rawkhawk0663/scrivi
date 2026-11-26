import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

/// Texte werden in grosser Schrift gesetzt und dann verkleinert gezeichnet:
/// Sehr kleine Schriftgrössen (1–3 Einheiten) werden sonst ungenau gemessen.
const double _textScale = 20;

/// Schrift und Schnitt pro Textrolle.
TextStyle _styleFor(core.TextRole role, double size, {bool bold = false, bool italic = false}) {
  final family = switch (role) {
    core.TextRole.title || core.TextRole.section || core.TextRole.chord => 'Sora',
    _ => 'Plex',
  };
  var weight = switch (role) {
    core.TextRole.title => FontWeight.w700,
    core.TextRole.chord || core.TextRole.section => FontWeight.w600,
    core.TextRole.tab => FontWeight.w500,
    _ => FontWeight.w400,
  };
  if (bold && weight.value < 600) weight = FontWeight.w600;
  return TextStyle(
    fontFamily: family,
    fontSize: size * _textScale,
    fontWeight: weight,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    color: const Color(0xFF000000),
    height: 1.0,
  );
}

/// Misst Texte mit den Schriften der App (für den Notensatz).
class FlutterTextMeasurer implements core.TextMeasurer {
  final _cache = <String, double>{};

  @override
  double width(String text, core.TextRole role, double size, {bool bold = false, bool italic = false}) {
    final key = '${role.index}|$size|$bold|$italic|$text';
    return _cache.putIfAbsent(key, () {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: _styleFor(role, size, bold: bold, italic: italic),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = tp.width / _textScale;
      tp.dispose();
      return w;
    });
  }
}

/// Wandelt die Zeichenliste einer Seite in ein Bild (Vektoren, in
/// Linienabständen). Notenzeichen werden als Umrisse gezeichnet.
class PagePictures {
  PagePictures._();

  static final _glyphPaths = <String, Path>{};

  /// Notenzeichen werden 64-fach vergrössert als Pfad abgelegt und beim Zeichnen
  /// wieder verkleinert: In den winzigen Einheiten (Linienabstände) liess die
  /// Grafik sonst sehr dünne Teile weg, z. B. den Hals der Tempo-Note.
  static const glyphUnit = 64.0;

  static Path glyphPath(String name) => _glyphPaths.putIfAbsent(
    name,
    () =>
        _toPath(core.Glyphs.get(name).path)
            .transform((Matrix4.identity()..scaleByDouble(glyphUnit, glyphUnit, 1, 1)).storage),
  );

  static Path _toPath(List<double> c) {
    final path = Path();
    var i = 0;
    while (i < c.length) {
      final op = c[i].toInt();
      switch (op) {
        case 0:
          path.moveTo(c[i + 1], c[i + 2]);
          i += 3;
        case 1:
          path.lineTo(c[i + 1], c[i + 2]);
          i += 3;
        case 3:
          path.cubicTo(c[i + 1], c[i + 2], c[i + 3], c[i + 4], c[i + 5], c[i + 6]);
          i += 7;
        default:
          path.close();
          i += 1;
      }
    }
    return path;
  }

  /// Zeichnet die Seite in Linienabständen (der Aufrufer skaliert).
  static ui.Picture record(core.PageDisplay page) {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Rect.fromLTWH(0, 0, page.width, page.height));
    paint(canvas, page);
    return rec.endRecording();
  }

  static void paint(Canvas canvas, core.PageDisplay page) {
    final ink = Paint()
      ..color = const Color(0xFF000000)
      ..isAntiAlias = true;
    final paper = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 0, page.width, page.height), paper);
    for (final it in page.items) {
      switch (it) {
        case core.GlyphItem g:
          canvas.save();
          canvas.translate(g.x, g.y);
          canvas.scale(g.scale / glyphUnit, -g.scale / glyphUnit);
          canvas.drawPath(glyphPath(g.name), ink);
          canvas.restore();
        case core.LineItem l:
          final p = Paint()
            ..color = const Color(0xFF000000)
            ..strokeWidth = l.thickness
            ..strokeCap = l.roundCap ? StrokeCap.round : StrokeCap.butt;
          final dash = l.dash;
          if (dash == null) {
            canvas.drawLine(Offset(l.x1, l.y1), Offset(l.x2, l.y2), p);
          } else {
            final total = (Offset(l.x2, l.y2) - Offset(l.x1, l.y1)).distance;
            if (total <= 0) continue;
            final dir = (Offset(l.x2, l.y2) - Offset(l.x1, l.y1)) / total;
            var d = 0.0;
            while (d < total) {
              final e = (d + dash.$1).clamp(0.0, total);
              canvas.drawLine(Offset(l.x1, l.y1) + dir * d, Offset(l.x1, l.y1) + dir * e, p);
              d += dash.$1 + dash.$2;
            }
          }
        case core.RectItem r:
          final rect = Rect.fromLTWH(r.x, r.y, r.width, r.height);
          if (r.background) {
            canvas.drawRect(rect, paper);
          } else if (r.fill) {
            canvas.drawRect(rect, ink);
          } else {
            canvas.drawRect(
              rect,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = r.thickness
                ..color = const Color(0xFF000000),
            );
          }
        case core.PathItem pi:
          final path = _toPath(pi.commands);
          if (pi.fill) {
            canvas.drawPath(path, ink);
          } else {
            canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = pi.thickness
                ..color = const Color(0xFF000000),
            );
          }
        case core.TextItem t:
          final tp = TextPainter(
            text: TextSpan(
              text: t.text,
              style: _styleFor(t.role, t.size, bold: t.bold, italic: t.italic),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final w = tp.width / _textScale;
          final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic) / _textScale;
          final dx = switch (t.align) {
            core.TextAlign.left => 0.0,
            core.TextAlign.center => -w / 2,
            core.TextAlign.right => -w,
          };
          canvas.save();
          canvas.translate(t.x + dx, t.y - baseline);
          canvas.scale(1 / _textScale);
          tp.paint(canvas, Offset.zero);
          canvas.restore();
          tp.dispose();
      }
    }
  }
}

/// Zeigt eine Seite (als fertiges Bild, in Linienabständen aufgenommen).
class ScorePageView extends StatelessWidget {
  const ScorePageView({super.key, required this.picture, required this.page});
  final ui.Picture picture;
  final core.PageDisplay page;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: page.width / page.height,
      child: RepaintBoundary(child: CustomPaint(painter: _PicturePainter(picture, page.width))),
    );
  }
}

class _PicturePainter extends CustomPainter {
  _PicturePainter(this.picture, this.pageWidth);
  final ui.Picture picture;
  final double pageWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / pageWidth;
    canvas.save();
    canvas.scale(s);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PicturePainter old) => old.picture != picture;
}
