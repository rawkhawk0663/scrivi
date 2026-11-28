import 'package:flutter/material.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';

/// Seite einrichten: rechts am Rand, jede Änderung erscheint sofort auf dem Blatt
/// ([onChanged]; alle Änderungen zusammen sind ein Schritt zum Rückgängigmachen).
Future<void> showPageSetup(
  BuildContext context,
  core.PageSetup start,
  void Function(core.PageSetup setup, bool first) onChanged,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Schliessen', 'Close'),
    barrierColor: Colors.transparent,
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 64, 12, 12),
        child: _PageSetupPanel(start: start, onChanged: onChanged),
      ),
    ),
  );
}

class _PageSetupPanel extends StatefulWidget {
  const _PageSetupPanel({required this.start, required this.onChanged});
  final core.PageSetup start;
  final void Function(core.PageSetup setup, bool first) onChanged;

  @override
  State<_PageSetupPanel> createState() => _PageSetupPanelState();
}

class _PageSetupPanelState extends State<_PageSetupPanel> {
  late core.PageSetup s = widget.start;
  bool _changed = false;

  void _set(core.PageSetup v) {
    setState(() => s = v);
    widget.onChanged(v, !_changed);
    _changed = true;
  }

  String _mm(double v) {
    final t = v.toStringAsFixed(1);
    return '${L10n.isEnglish ? t : t.replaceAll('.', ',')} mm';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final scheme = Theme.of(context).colorScheme;
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        t.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: c.muted),
      ),
    );
    Widget segments<T>(List<(T, String)> options, T value, ValueChanged<T> onSelected) => SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 12.5),
          padding: const EdgeInsets.symmetric(horizontal: 6),
        ),
        segments: [for (final (v, l) in options) ButtonSegment(value: v, label: Text(l))],
        selected: {value},
        onSelectionChanged: (v) => onSelected(v.first),
      ),
    );
    Widget row(String name, Widget child) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(name, style: TextStyle(fontSize: 13, color: c.muted)),
          ),
          Expanded(child: child),
        ],
      ),
    );
    Widget stepper(double value, ValueChanged<double> onChanged, {double step = 1, double min = 0, double max = 60}) =>
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: value - step >= min - 0.001 ? () => onChanged((value - step).clamp(min, max)) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 64,
              child: Text(_mm(value), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: value + step <= max + 0.001 ? () => onChanged((value + step).clamp(min, max)) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        );
    Widget slider(double value, double min, double max, String text, ValueChanged<double> onChanged) => Row(
      children: [
        Expanded(
          child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ),
        SizedBox(
          width: 64,
          child: Text(text, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5)),
        ),
      ],
    );
    String percent(double f) => (f - 1).abs() < 0.02 ? tr('normal', 'normal') : '${(f * 100).round()} %';

    return Material(
      color: c.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.line),
      ),
      child: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('Seite einrichten', 'Page setup'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Schliessen', 'Close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    label(tr('Papier', 'Paper')),
                    segments(
                      [('a4', 'A4'), ('letter', 'Letter'), ('a3', 'A3')],
                      s.paper,
                      (v) => _set(s.copyWith(paper: v)),
                    ),
                    const SizedBox(height: 8),
                    segments(
                      [(false, tr('Hoch', 'Portrait')), (true, tr('Quer', 'Landscape'))],
                      s.landscape,
                      (v) => _set(s.copyWith(landscape: v)),
                    ),
                    label(tr('Ränder', 'Margins')),
                    row(tr('Oben', 'Top'), stepper(s.marginTop, (v) => _set(s.copyWith(marginTop: v)))),
                    row(tr('Unten', 'Bottom'), stepper(s.marginBottom, (v) => _set(s.copyWith(marginBottom: v)))),
                    row(tr('Links', 'Left'), stepper(s.marginLeft, (v) => _set(s.copyWith(marginLeft: v)))),
                    row(tr('Rechts', 'Right'), stepper(s.marginRight, (v) => _set(s.copyWith(marginRight: v)))),
                    label(tr('Grösse und Abstände', 'Size and spacing')),
                    row(
                      tr('Notengrösse', 'Staff size'),
                      slider(
                        s.spaceMm * 4,
                        4.8,
                        10,
                        _mm(s.spaceMm * 4),
                        (v) => _set(s.copyWith(spaceMm: (v / 4 * 20).round() / 20)),
                      ),
                    ),
                    row(
                      tr('Zeilenabstand', 'Line spacing'),
                      slider(
                        s.lineGap,
                        0.4,
                        2.5,
                        percent(s.lineGap),
                        (v) => _set(s.copyWith(lineGap: (v * 20).round() / 20)),
                      ),
                    ),
                    row(
                      tr('Noten-Dichte', 'Note spacing'),
                      slider(
                        s.spacing,
                        0.6,
                        1.6,
                        percent(s.spacing),
                        (v) => _set(s.copyWith(spacing: (v * 20).round() / 20)),
                      ),
                    ),
                    label(tr('Takte pro Zeile', 'Bars per line')),
                    segments(
                      [
                        (0, tr('Auto', 'Auto')),
                        for (final n in [2, 3, 4, 5, 6]) (n, '$n'),
                      ],
                      s.barsPerLine,
                      (v) => _set(s.copyWith(barsPerLine: v)),
                    ),
                    label(tr('Taktnummern', 'Bar numbers')),
                    segments(
                      [
                        (0, tr('Zeilenanfang', 'Line start')),
                        (1, tr('Alle 5', 'Every 5')),
                        (2, tr('Jeder', 'Every')),
                        (3, tr('Keine', 'None')),
                      ],
                      s.barNumbers,
                      (v) => _set(s.copyWith(barNumbers: v)),
                    ),
                    label(tr('Seitenzahlen', 'Page numbers')),
                    segments(
                      [
                        (0, tr('Rechts', 'Right')),
                        (1, tr('Mitte', 'Centre')),
                        (2, tr('Aussen', 'Outside')),
                        (3, tr('Keine', 'None')),
                      ],
                      s.pageNumbers,
                      (v) => _set(s.copyWith(pageNumbers: v)),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: s.isStandard ? null : () => _set(core.PageSetup.standard),
                    child: Text(tr('Grundeinstellung', 'Defaults')),
                  ),
                  const Spacer(),
                  FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Fertig', 'Done'))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
