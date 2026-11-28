import 'package:flutter/material.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';

/// Layout-Modus: Elemente ausserhalb der Notenlinien (Titel, Akkorde, Texte, Dynamik,
/// Formteile, Tempo …) antippen und ziehen. Jedes hängt an einem Anker; angezeigt wird der
/// Abstand dazu waagrecht und senkrecht.
class LayoutControl {
  LayoutControl({required this.selected, required this.onNudge});

  /// Gewähltes Element (null = keines).
  final ValueNotifier<core.LayoutRef?> selected;

  /// Verschiebung übernehmen (ein Schritt zum Rückgängigmachen).
  final void Function(core.LayoutRef ref, core.Nudge n) onNudge;

  /// Laufendes Ziehen: so weit (in sp) gegenüber dem Stand vor dem Ziehen.
  final drag = ValueNotifier<Offset>(Offset.zero);
}

/// Millimeter auf dem Papier (1 sp = 1,75 mm), mit Komma auf Deutsch.
String layoutMm(double sp) {
  final t = (sp.abs() * 1.75).toStringAsFixed(1);
  return '${L10n.isEnglish ? t : t.replaceAll('.', ',')} mm';
}

/// Anfasser auf einer Seite: alle Elemente fein umrandet, das gewählte mit Anker und Massen.
class LayoutPainter extends CustomPainter {
  LayoutPainter(this.page, this.control) : super(repaint: Listenable.merge([control.selected, control.drag]));
  final core.PageDisplay page;
  final LayoutControl control;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / page.width;
    const color = ScriviColors.selection;
    final faint = Paint()
      ..color = color.withAlpha(90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final sel = control.selected.value;
    for (final h in page.handles) {
      if (h.ref == sel) continue;
      canvas.drawRect(Rect.fromLTRB(h.left * k - 2, h.top * k - 2, h.right * k + 2, h.bottom * k + 2), faint);
    }
    if (sel == null) return;
    final d = control.drag.value;
    for (final h in page.handles.where((h) => h.ref == sel)) {
      final r = Rect.fromLTRB(
        (h.left + d.dx) * k - 2,
        (h.top + d.dy) * k - 2,
        (h.right + d.dx) * k + 2,
        (h.bottom + d.dy) * k + 2,
      );
      canvas.drawRect(r, Paint()..color = color.withAlpha(30));
      canvas.drawRect(
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      // Anfasser an den Ecken
      for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
        canvas.drawRect(Rect.fromCenter(center: c, width: 6, height: 6), Paint()..color = color);
      }
      final ax = h.anchorX * k, ay = h.anchorY * k;
      final rx = (h.refX + d.dx) * k, ry = (h.refY + d.dy) * k;
      final line = Paint()
        ..color = color
        ..strokeWidth = 1.2;
      // Anker: kleiner Kreis mit Kreuz
      canvas.drawCircle(Offset(ax, ay), 4, Paint()..color = color);
      canvas.drawCircle(
        Offset(ax, ay),
        7,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      // Masslinien: waagrecht auf Höhe des Ankers, senkrecht beim Element
      if ((rx - ax).abs() > 0.5) {
        canvas.drawLine(Offset(ax, ay), Offset(rx, ay), line);
        _tick(canvas, Offset(rx, ay), vertical: true, paint: line);
        _label(canvas, Offset((ax + rx) / 2, ay + 10), '↔ ${layoutMm((rx - ax) / k)}');
      }
      if ((ry - ay).abs() > 0.5) {
        canvas.drawLine(Offset(rx, ay), Offset(rx, ry), line);
        _tick(canvas, Offset(rx, ry), vertical: false, paint: line);
        _label(canvas, Offset(rx + 8, (ay + ry) / 2), '↕ ${layoutMm((ry - ay) / k)}', left: true);
      }
    }
  }

  void _tick(Canvas canvas, Offset p, {required bool vertical, required Paint paint}) {
    if (vertical) {
      canvas.drawLine(p.translate(0, -4), p.translate(0, 4), paint);
    } else {
      canvas.drawLine(p.translate(-4, 0), p.translate(4, 0), paint);
    }
  }

  void _label(Canvas canvas, Offset at, String text, {bool left = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 8, h = tp.height + 3;
    final x = left ? at.dx : at.dx - w / 2;
    final y = at.dy - h / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(4)),
      Paint()..color = ScriviColors.selection,
    );
    tp.paint(canvas, Offset(x + 4, y + 1.5));
  }

  @override
  bool shouldRepaint(LayoutPainter old) => old.page != page;
}

/// Leiste oben im Layout-Modus: was gewählt ist, Abstände, zurück an den Platz.
class LayoutBar extends StatelessWidget {
  const LayoutBar({
    super.key,
    required this.handle,
    required this.onReset,
    required this.onResetAll,
    required this.onDone,
    this.drag = Offset.zero,
  });
  final core.LayoutHandle? handle;

  /// Laufendes Ziehen (sp): die Abstände werden schon während des Ziehens angezeigt.
  final Offset drag;
  final VoidCallback onReset;
  final VoidCallback onResetAll;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final scheme = Theme.of(context).colorScheme;
    final h = handle;
    final style = TextStyle(fontSize: 13, color: c.muted);
    return Material(
      color: c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_with_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            if (h == null)
              Text(
                tr(
                  'Element antippen und ziehen · Pfeiltasten schieben fein',
                  'Tap an element and drag · arrow keys nudge',
                ),
                style: style,
              )
            else ...[
              Text(h.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 14),
              Text(
                '↔ ${layoutMm(h.refX + drag.dx - h.anchorX)}   ↕ ${layoutMm(h.refY + drag.dy - h.anchorY)}',
                style: style,
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: h.dx == 0 && h.dy == 0 ? null : onReset,
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: Text(tr('Zurück an den Platz', 'Back to its place')),
              ),
            ],
            if (h == null)
              TextButton(onPressed: onResetAll, child: Text(tr('Alles zurücksetzen …', 'Reset everything …'))),
            const SizedBox(width: 4),
            FilledButton(onPressed: onDone, child: Text(tr('Fertig', 'Done'))),
          ],
        ),
      ),
    );
  }
}
