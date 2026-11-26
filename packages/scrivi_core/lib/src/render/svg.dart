import 'display.dart';
import 'glyphs.dart';

/// Schreibt eine Seite als SVG (Vektorgrafik). Masse in Linienabständen,
/// [unit] Pixel pro Linienabstand.
String pageToSvg(PageDisplay page, {double unit = 10, Map<TextRole, String>? fonts}) {
  final b = StringBuffer();
  final w = page.width * unit, h = page.height * unit;
  String n(double v) => (v * unit).toStringAsFixed(2);
  b.writeln('<svg xmlns="http://www.w3.org/2000/svg" width="${w.toStringAsFixed(0)}" height="${h.toStringAsFixed(0)}" viewBox="0 0 ${w.toStringAsFixed(0)} ${h.toStringAsFixed(0)}">');
  b.writeln('<rect width="100%" height="100%" fill="#fff"/>');
  final defs = <String>{};
  for (final it in page.items) {
    if (it is GlyphItem) defs.add(it.name);
  }
  b.writeln('<defs>');
  for (final name in defs) {
    b.writeln('<path id="g_$name" d="${_glyphPath(Glyphs.get(name).path)}"/>');
  }
  b.writeln('</defs>');
  for (final it in page.items) {
    switch (it) {
      case GlyphItem g:
        final s = unit * g.scale;
        b.writeln('<use href="#g_${g.name}" transform="translate(${n(g.x)} ${n(g.y)}) scale(${s.toStringAsFixed(3)} ${(-s).toStringAsFixed(3)})"/>');
      case LineItem l:
        final dash = l.dash == null ? '' : ' stroke-dasharray="${n(l.dash!.$1)} ${n(l.dash!.$2)}"';
        b.writeln('<line x1="${n(l.x1)}" y1="${n(l.y1)}" x2="${n(l.x2)}" y2="${n(l.y2)}" stroke="#000" stroke-width="${n(l.thickness)}"$dash/>');
      case RectItem r:
        if (r.background) {
          b.writeln('<rect x="${n(r.x)}" y="${n(r.y)}" width="${n(r.width)}" height="${n(r.height)}" fill="#fff"/>');
        } else if (r.fill) {
          b.writeln('<rect x="${n(r.x)}" y="${n(r.y)}" width="${n(r.width)}" height="${n(r.height)}" fill="#000"/>');
        } else {
          b.writeln('<rect x="${n(r.x)}" y="${n(r.y)}" width="${n(r.width)}" height="${n(r.height)}" fill="none" stroke="#000" stroke-width="${n(r.thickness)}"/>');
        }
      case PathItem p:
        final d = _pathData(p.commands, (v) => n(v));
        b.writeln(p.fill ? '<path d="$d" fill="#000"/>' : '<path d="$d" fill="none" stroke="#000" stroke-width="${n(p.thickness)}"/>');
      case TextItem t:
        final anchor = switch (t.align) {
          TextAlign.left => 'start',
          TextAlign.center => 'middle',
          TextAlign.right => 'end',
        };
        final family = fonts?[t.role] ?? 'sans-serif';
        final weight = t.bold ? ' font-weight="bold"' : '';
        final style = t.italic ? ' font-style="italic"' : '';
        b.writeln('<text x="${n(t.x)}" y="${n(t.y)}" font-family="$family" font-size="${n(t.size)}" text-anchor="$anchor"$weight$style>${_esc(t.text)}</text>');
    }
  }
  b.writeln('</svg>');
  return b.toString();
}

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _glyphPath(List<double> c) => _pathData(c, (v) => v.toStringAsFixed(3));

String _pathData(List<double> c, String Function(double) f) {
  final b = StringBuffer();
  var i = 0;
  while (i < c.length) {
    final op = c[i].toInt();
    switch (op) {
      case 0:
        b.write('M${f(c[i + 1])} ${f(c[i + 2])}');
        i += 3;
      case 1:
        b.write('L${f(c[i + 1])} ${f(c[i + 2])}');
        i += 3;
      case 3:
        b.write('C${f(c[i + 1])} ${f(c[i + 2])} ${f(c[i + 3])} ${f(c[i + 4])} ${f(c[i + 5])} ${f(c[i + 6])}');
        i += 7;
      default:
        b.write('Z');
        i += 1;
    }
  }
  return b.toString();
}
