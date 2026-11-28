import 'package:flutter/material.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';
import 'score_painter.dart';

/// Seite einrichten: rechts am Rand, jede Änderung erscheint sofort auf dem Blatt
/// ([onChanged]; alle Änderungen zusammen sind ein Schritt zum Rückgängigmachen).
Future<void> showPageSetup(
  BuildContext context,
  core.PageSetup start,
  void Function(core.PageSetup setup, bool first) onChanged, {
  core.PageSetup? template,
  Future<void> Function(core.PageSetup setup)? onSaveTemplate,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Schliessen', 'Close'),
    barrierColor: Colors.transparent,
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 64, 12, 12),
        child: _PageSetupPanel(start: start, onChanged: onChanged, template: template, onSaveTemplate: onSaveTemplate),
      ),
    ),
  );
}

class _PageSetupPanel extends StatefulWidget {
  const _PageSetupPanel({required this.start, required this.onChanged, this.template, this.onSaveTemplate});
  final core.PageSetup start;
  final void Function(core.PageSetup setup, bool first) onChanged;

  /// Gespeicherte Vorlage für neue Stücke (null = keine).
  final core.PageSetup? template;
  final Future<void> Function(core.PageSetup setup)? onSaveTemplate;

  @override
  State<_PageSetupPanel> createState() => _PageSetupPanelState();
}

class _PageSetupPanelState extends State<_PageSetupPanel> {
  late core.PageSetup s = widget.start;
  bool _changed = false;
  late core.PageSetup? _template = widget.template;

  static String _fontName(String f) => switch (f) {
    'sora' => tr('Modern', 'Modern'),
    'garamond' => tr('Klassisch', 'Classic'),
    'kalam' => tr('Handschrift', 'Handwritten'),
    _ => tr('Schlicht', 'Plain'),
  };

  static String _groupName(String g) => switch (g) {
    'title' => tr('Titel', 'Title'),
    'chord' => tr('Akkorde', 'Chords'),
    'lyrics' => tr('Liedtext', 'Lyrics'),
    _ => tr('Übrige Texte', 'Other text'),
  };

  void _set(core.PageSetup v) {
    setState(() => s = v);
    widget.onChanged(v, !_changed);
    _changed = true;
  }

  /// Schrift und Grösse einer Gruppe (Titel, Akkorde, Liedtext, übrige Texte).
  Widget _fontRow(String g, ScriviColors c) {
    final font = s.fontOf(g);
    final scale = s.scaleOf(g);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(_groupName(g), style: TextStyle(fontSize: 13, color: c.muted)),
          ),
          Expanded(
            child: DropdownButton<String>(
              value: font,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: [
                for (final f in core.PageSetup.fontKeys)
                  DropdownMenuItem(
                    value: f,
                    child: Text(
                      _fontName(f),
                      style: TextStyle(
                        fontFamily: fontFamilyOf(f),
                        fontSize: f == 'garamond' ? 15.5 : 14,
                        fontWeight: f == 'sora' ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) _set(s.withFont(g, v));
              },
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            tooltip: tr('Kleiner', 'Smaller'),
            onPressed: scale > 0.61 ? () => _set(s.withScale(g, ((scale - 0.1) * 10).round() / 10)) : null,
            icon: const Icon(Icons.text_decrease_rounded),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${(scale * 100).round()} %',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            tooltip: tr('Grösser', 'Larger'),
            onPressed: scale < 1.79 ? () => _set(s.withScale(g, ((scale + 0.1) * 10).round() / 10)) : null,
            icon: const Icon(Icons.text_increase_rounded),
          ),
        ],
      ),
    );
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(tr('Seiten füllen', 'Fill pages'), style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        tr(
                          'Zeilen gleichmässig verteilen, bis jede volle Seite unten reicht.',
                          'Spread the lines evenly until each full page reaches the bottom.',
                        ),
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                      value: s.fillPages,
                      onChanged: (v) => _set(s.copyWith(fillPages: v)),
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
                    label(tr('Partitur', 'Full score')),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        tr('Leere Spuren ausblenden', 'Hide empty tracks'),
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        tr(
                          'Spuren, die in einer Zeile nichts spielen, fallen weg (nicht in der ersten Zeile).',
                          'Tracks with nothing to play in a line are left out (not in the first line).',
                        ),
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                      value: s.hideEmpty,
                      onChanged: (v) => _set(s.copyWith(hideEmpty: v)),
                    ),
                    label(tr('Schriften', 'Fonts')),
                    for (final g in core.PageSetup.fontGroups) _fontRow(g, c),
                    label(tr('Vorlage für neue Stücke', 'Template for new pieces')),
                    Text(
                      tr(
                        'Diese Seite, die Schriften und die Akkordsymbole gelten dann für jedes neue Stück.',
                        'This page, the fonts and the chord symbols are then used for every new piece.',
                      ),
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          onPressed: widget.onSaveTemplate == null
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.maybeOf(context);
                                  await widget.onSaveTemplate!(s);
                                  if (!mounted) return;
                                  setState(() => _template = s);
                                  messenger?.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        tr(
                                          'Als Vorlage für neue Stücke gespeichert.',
                                          'Saved as template for new pieces.',
                                        ),
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                          label: Text(tr('Als Vorlage speichern', 'Save as template')),
                        ),
                        if (_template != null)
                          TextButton(
                            onPressed: () => _set(_template!),
                            child: Text(tr('Vorlage übernehmen', 'Use template')),
                          ),
                      ],
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
