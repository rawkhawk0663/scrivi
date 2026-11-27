import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

/// Schreibt gesetzte Seiten als PDF: Notenzeichen als Umrisse (scharf in jeder
/// Grösse), Texte mit den Schriften der App (eingebettet). Die Seiten sind A4
/// (die Endlos-Zeile so breit wie nötig).
class PdfExport {
  PdfExport._();

  /// Punkte (1/72 Zoll) pro Linienabstand: A4 ist 120 Linienabstände breit.
  static final double _k = PdfPageFormat.a4.width / 120;

  static final Map<String, ByteData> _fontData = {};

  static Future<ByteData> _font(String asset) async =>
      _fontData[asset] ??= await rootBundle.load('assets/fonts/$asset');

  /// PDF aus den Seiten [pages] (mehrere Spuren: einfach hintereinander).
  static Future<Uint8List> build(List<core.PageDisplay> pages, {String title = ''}) async {
    final doc = PdfDocument();
    PdfInfo(doc, title: title, creator: 'Scrivi', producer: 'Scrivi');
    final fonts = <String, PdfTtfFont>{};
    Future<PdfTtfFont> font(String asset) async => fonts[asset] ??= PdfTtfFont(doc, await _font(asset));
    for (final page in pages) {
      final fmt = PdfPageFormat(page.width * _k, page.height * _k);
      final p = PdfPage(doc, pageFormat: fmt);
      final g = p.getGraphics();
      final h = fmt.height;
      double X(double x) => x * _k;
      double Y(double y) => h - y * _k;
      g.setFillColor(PdfColors.black);
      g.setStrokeColor(PdfColors.black);
      for (final it in page.items) {
        switch (it) {
          case core.GlyphItem gl:
            _path(g, core.Glyphs.get(gl.name).path, (px, py) => (X(gl.x + px * gl.scale), Y(gl.y - py * gl.scale)));
            g.fillPath();
          case core.LineItem l:
            g.setLineWidth(l.thickness * _k);
            g.setLineCap(l.roundCap ? PdfLineCap.round : PdfLineCap.butt);
            final dash = l.dash;
            if (dash != null) g.setLineDashPattern([dash.$1 * _k, dash.$2 * _k]);
            g.moveTo(X(l.x1), Y(l.y1));
            g.lineTo(X(l.x2), Y(l.y2));
            g.strokePath();
            if (dash != null) g.setLineDashPattern();
          case core.RectItem r:
            g.drawRect(X(r.x), Y(r.y + r.height), r.width * _k, r.height * _k);
            if (r.background) {
              g.setFillColor(PdfColors.white);
              g.fillPath();
              g.setFillColor(PdfColors.black);
            } else if (r.fill) {
              g.fillPath();
            } else {
              g.setLineWidth(r.thickness * _k);
              g.strokePath();
            }
          case core.PathItem pi:
            _path(g, pi.commands, (px, py) => (X(px), Y(py)));
            if (pi.fill) {
              g.fillPath();
            } else {
              g.setLineWidth(pi.thickness * _k);
              g.strokePath();
            }
          case core.TextItem t:
            final f = await font(_fontFor(t.role, t.bold));
            final text = _printable(t.text, f);
            if (text.isEmpty) continue;
            final size = t.size * _k;
            final w = f.stringMetrics(text).advanceWidth * size;
            final dx = switch (t.align) {
              core.TextAlign.left => 0.0,
              core.TextAlign.center => -w / 2,
              core.TextAlign.right => -w,
            };
            g.drawString(f, size, text, X(t.x) + dx, Y(t.y));
        }
      }
    }
    return Uint8List.fromList(await doc.save());
  }

  /// Umriss aus Befehlen (0 moveTo, 1 lineTo, 3 cubicTo, 4 close); [map] rechnet in PDF-Punkte um.
  static void _path(PdfGraphics g, List<double> c, (double, double) Function(double, double) map) {
    var i = 0;
    while (i < c.length) {
      switch (c[i].toInt()) {
        case 0:
          final (x, y) = map(c[i + 1], c[i + 2]);
          g.moveTo(x, y);
          i += 3;
        case 1:
          final (x, y) = map(c[i + 1], c[i + 2]);
          g.lineTo(x, y);
          i += 3;
        case 3:
          final (x1, y1) = map(c[i + 1], c[i + 2]);
          final (x2, y2) = map(c[i + 3], c[i + 4]);
          final (x3, y3) = map(c[i + 5], c[i + 6]);
          g.curveTo(x1, y1, x2, y2, x3, y3);
          i += 7;
        default:
          g.closePath();
          i += 1;
      }
    }
  }

  /// Schrift wie in der App (siehe score_painter): Sora für Titel, Formteile und Akkorde, sonst Plex.
  static String _fontFor(core.TextRole role, bool bold) => switch (role) {
    core.TextRole.title => 'Sora-Bold.ttf',
    core.TextRole.section || core.TextRole.chord => 'Sora-SemiBold.ttf',
    core.TextRole.tab => bold ? 'IBMPlexSans-SemiBold.ttf' : 'IBMPlexSans-Medium.ttf',
    _ => bold ? 'IBMPlexSans-SemiBold.ttf' : 'IBMPlexSans-Regular.ttf',
  };

  /// Zeichen, die die Schrift nicht hat, durch lesbare ersetzen (♯ → #, ♭ → b).
  static String _printable(String s, PdfTtfFont f) {
    final map = f.font.charToGlyphIndexMap;
    final out = StringBuffer();
    for (final r in s.runes) {
      if (map.containsKey(r) || r == 0x20) {
        out.writeCharCode(r);
      } else {
        out.write(switch (r) {
          0x266F => '#',
          0x266D => 'b',
          0x266E => '',
          0x2013 || 0x2014 => '-',
          _ => '?',
        });
      }
    }
    return out.toString();
  }
}
