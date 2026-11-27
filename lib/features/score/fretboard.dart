import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';

/// Griffbrett zum Antippen: Saite und Bund ergeben einen Ton am Cursor.
///
/// Die Töne des Schlags unter dem Cursor leuchten kräftig, die übrigen Töne
/// des Takts blass (so sieht man die Lage). Saiten von oben nach unten wie
/// beim Blick auf die Gitarre: oben die höchste.
class Fretboard extends StatelessWidget {
  const Fretboard({super.key, required this.editor, required this.onTap, this.germanNames = true});
  final core.ScoreEditor editor;
  final void Function(int string, int fret) onTap;
  final bool germanNames;

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final staff = editor.score.tracks[editor.track].staff;
    final n = staff.stringCount;
    if (n == 0) return const SizedBox.shrink();
    final frets = math.min(staff.fretCount, 24);
    final current = <(int, int)>{};
    final bar = <(int, int)>{};
    final beat = editor.currentBeat;
    for (final note in beat?.notes ?? const <core.Note>[]) {
      if (note.string != null && note.fret != null) current.add((note.string!, note.fret!));
    }
    for (final b in editor.beatsOf(editor.cursor.bar)) {
      for (final note in b.notes) {
        if (note.string != null && note.fret != null) bar.add((note.string!, note.fret!));
      }
    }
    return Container(
      color: c.card,
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
      height: 26.0 + n * 17,
      child: Row(
        children: [
          // Saitennamen (oben die höchste)
          SizedBox(
            width: 22,
            child: Column(
              children: [
                const SizedBox(height: 16),
                for (var s = n - 1; s >= 0; s--)
                  SizedBox(
                    height: 17,
                    child: Center(
                      child: Text(
                        _name(staff.tuning[s]),
                        style: TextStyle(
                          fontSize: 11,
                          color: s == editor.cursor.string ? Theme.of(context).colorScheme.primary : c.muted,
                          fontWeight: s == editor.cursor.string ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final geo = _Geometry(box.maxWidth, frets, n);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final hit = geo.hit(d.localPosition);
                    if (hit != null) onTap(hit.$1, hit.$2);
                  },
                  child: CustomPaint(
                    size: Size(box.maxWidth, box.maxHeight),
                    painter: _FretboardPainter(
                      geo,
                      current: current,
                      bar: bar,
                      cursorString: editor.cursor.string,
                      accent: Theme.of(context).colorScheme.primary,
                      onAccent: Theme.of(context).colorScheme.onPrimary,
                      muted: c.muted,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _name(int midi) {
    final names = germanNames && !L10n.isEnglish
        ? const ['C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B', 'H']
        : const ['C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B♭', 'B'];
    return names[midi % 12];
  }
}

/// Lage der Bünde: wie auf einer echten Gitarre zum Korpus hin enger.
class _Geometry {
  _Geometry(this.width, this.frets, this.strings) {
    // Bund 0 (leere Saite) bekommt ein eigenes Feld links
    const open = 34.0;
    final rest = width - open;
    var total = 0.0;
    final w = <double>[];
    for (var f = 1; f <= frets; f++) {
      final x = math.pow(2, -(f - 1) / 12).toDouble();
      w.add(x);
      total += x;
    }
    xs = [0, open];
    var x = open;
    for (final v in w) {
      x += v / total * rest;
      xs.add(x);
    }
  }
  final double width;
  final int frets;
  final int strings;
  static const top = 16.0;
  static const rowH = 17.0;

  /// Grenzen der Bund-Felder: Feld f reicht von xs[f] bis xs[f+1].
  late final List<double> xs;

  double stringY(int s) => top + (strings - 1 - s) * rowH + rowH / 2;
  double fretCenter(int f) => (xs[f] + xs[f + 1]) / 2;

  (int, int)? hit(Offset p) {
    final row = ((p.dy - top) / rowH).floor();
    if (row < 0 || row >= strings) return null;
    for (var f = 0; f <= frets; f++) {
      if (p.dx >= xs[f] && p.dx < xs[f + 1]) return (strings - 1 - row, f);
    }
    return null;
  }
}

class _FretboardPainter extends CustomPainter {
  _FretboardPainter(
    this.g, {
    required this.current,
    required this.bar,
    required this.cursorString,
    required this.accent,
    required this.onAccent,
    required this.muted,
  });
  final _Geometry g;
  final Set<(int, int)> current;
  final Set<(int, int)> bar;
  final int cursorString;
  final Color accent;
  final Color onAccent;
  final Color muted;

  static const wood = Color(0xFF3A2A20);
  static const fretColor = Color(0xFFB9A98F);
  static const stringColor = Color(0xFFE8E1D3);
  static const inlay = Color(0xFF6B5A47);

  @override
  void paint(Canvas canvas, Size size) {
    final top = _Geometry.top;
    final bottom = top + g.strings * _Geometry.rowH;
    // Bundnummern
    for (final f in const [3, 5, 7, 9, 12, 15, 17, 19, 21, 24]) {
      if (f > g.frets) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: '$f',
          style: TextStyle(fontSize: 10, color: muted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(g.fretCenter(f) - tp.width / 2, 1));
    }
    // Holz ab Bund 1, Sattel
    canvas.drawRRect(RRect.fromLTRBR(g.xs[1], top, g.xs.last, bottom, const Radius.circular(4)), Paint()..color = wood);
    canvas.drawRect(Rect.fromLTRB(g.xs[1] - 3, top, g.xs[1] + 2, bottom), Paint()..color = stringColor);
    // Bünde
    final fp = Paint()
      ..color = fretColor
      ..strokeWidth = 2;
    for (var f = 2; f < g.xs.length; f++) {
      canvas.drawLine(Offset(g.xs[f], top), Offset(g.xs[f], bottom), fp..strokeWidth = f == 13 ? 3.5 : 2);
    }
    // Einlagen
    final ip = Paint()..color = inlay;
    final mid = (top + bottom) / 2;
    for (final f in const [3, 5, 7, 9, 15, 17, 19, 21]) {
      if (f <= g.frets) canvas.drawCircle(Offset(g.fretCenter(f), mid), 4, ip);
    }
    if (g.frets >= 12) {
      canvas.drawCircle(Offset(g.fretCenter(12), mid - _Geometry.rowH), 4, ip);
      canvas.drawCircle(Offset(g.fretCenter(12), mid + _Geometry.rowH), 4, ip);
    }
    // Saiten (tiefe dicker), Saite des Cursors hervorgehoben
    for (var s = 0; s < g.strings; s++) {
      final y = g.stringY(s);
      final thick = 1.0 + (g.strings - 1 - s) * 0.35;
      canvas.drawLine(
        Offset(4, y),
        Offset(g.xs.last, y),
        Paint()
          ..color = s == cursorString ? accent.withAlpha(200) : stringColor
          ..strokeWidth = thick,
      );
    }
    // Töne des Takts (blass) und des Schlags (kräftig)
    for (final (s, f) in bar) {
      if (current.contains((s, f)) || f > g.frets) continue;
      canvas.drawCircle(Offset(g.fretCenter(f), g.stringY(s)), 7, Paint()..color = accent.withAlpha(90));
    }
    for (final (s, f) in current) {
      if (f > g.frets) continue;
      final c = Offset(g.fretCenter(f), g.stringY(s));
      canvas.drawCircle(c, 8, Paint()..color = accent);
      final tp = TextPainter(
        text: TextSpan(
          text: '$f',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: onAccent),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_FretboardPainter old) =>
      old.current != current || old.bar != bar || old.cursorString != cursorString || old.g.width != g.width;
}
