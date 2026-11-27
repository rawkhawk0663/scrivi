import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';

/// Dialoge für die Schnell-Eingaben: Akkordzeile, Begleitmuster, Liedtext
/// einfügen und Formteil wiederholen.

/// Ergebnis der Akkordzeile: Text und (bei Gitarren) ein Begleitmuster.
typedef ChordLineResult = ({String text, core.StrumPattern? pattern});

Future<ChordLineResult?> askChordLine(
  BuildContext context, {
  required int fromBar,
  required List<core.StrumPattern> patterns,
}) {
  final ctrl = TextEditingController();
  core.StrumPattern? pattern;
  return showDialog<ChordLineResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final c = context.scrivi;
        final bars = core.ScoreEditor.parseChordLine(ctrl.text);
        return AlertDialog(
          title: Text(tr('Akkordzeile ab Takt ${fromBar + 1}', 'Chord line from bar ${fromBar + 1}')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 6,
                    style: const TextStyle(fontSize: 18, fontFeatures: [FontFeature.tabularFigures()]),
                    decoration: InputDecoration(
                      hintText: 'G | Em | C D | Am7',
                      helperText: tr(
                        'Takte mit | trennen, mehrere Akkorde im Takt mit Leerzeichen. % wiederholt den Takt, - hält einen Schlag. Ohne | ist jeder Akkord ein Takt.',
                        'Separate bars with |, several chords in a bar with spaces. % repeats the bar, - holds a beat. Without |, each chord is one bar.',
                      ),
                      helperMaxLines: 3,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    bars.isEmpty
                        ? ''
                        : tr(
                            '${bars.length} Takte: ${fromBar + 1} bis ${fromBar + bars.length}',
                            '${bars.length} bars: ${fromBar + 1} to ${fromBar + bars.length}',
                          ),
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                  if (patterns.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      tr('Begleitung gleich dazuschreiben', 'Write the accompaniment too'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    PatternPicker(
                      patterns: patterns,
                      selected: pattern,
                      allowNone: true,
                      onChanged: (p) => setState(() => pattern = p),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: bars.isEmpty ? null : () => Navigator.pop(context, (text: ctrl.text, pattern: pattern)),
              child: Text(tr('Übernehmen', 'Apply')),
            ),
          ],
        );
      },
    ),
  ).whenComplete(ctrl.dispose);
}

/// Begleitmuster zur Auswahl: Name und Pfeile.
class PatternPicker extends StatelessWidget {
  const PatternPicker({
    super.key,
    required this.patterns,
    required this.selected,
    required this.onChanged,
    this.allowNone = false,
  });

  final List<core.StrumPattern> patterns;
  final core.StrumPattern? selected;
  final ValueChanged<core.StrumPattern?> onChanged;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = context.scrivi;
    Widget tile(core.StrumPattern? p) {
      final on = p == selected;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(p),
        child: Container(
          width: 162,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: on ? scheme.primaryContainer : c.cardHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? scheme.primary : c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p == null ? tr('Nur Akkorde', 'Chords only') : tr(p.de, p.en),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: on ? scheme.onPrimaryContainer : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                p == null ? '–' : (p.picked ? _pickedText(p) : p.arrows),
                style: TextStyle(
                  fontSize: 15,
                  letterSpacing: 1.5,
                  color: on ? scheme.onPrimaryContainer : c.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: [if (allowNone) tile(null), for (final p in patterns) tile(p)]);
  }

  /// Zupfmuster lesbar: B = Bass, A = Wechselbass, 1 = höchste Saite …
  static String _pickedText(core.StrumPattern p) => p.steps.replaceAll('-', '·');
}

/// Begleitmuster mit Bereich (von–bis Takt, 0-basiert).
Future<(core.StrumPattern, int, int)?> askPattern(
  BuildContext context, {
  required List<core.StrumPattern> patterns,
  required int from,
  required int to,
  required int bars,
}) {
  core.StrumPattern? pattern = patterns.isEmpty ? null : patterns.first;
  final fromCtrl = TextEditingController(text: '${from + 1}');
  final toCtrl = TextEditingController(text: '${to + 1}');
  return showDialog<(core.StrumPattern, int, int)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final c = context.scrivi;
        Widget field(TextEditingController ctrl, String label) => SizedBox(
          width: 110,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: label),
          ),
        );
        return AlertDialog(
          title: Text(tr('Begleitmuster', 'Strum pattern')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                      'Scrivi schreibt die Begleitung mit den Griffen der Akkorde, die über den Takten stehen. Was in diesen Takten steht, wird ersetzt.',
                      'Scrivi writes the accompaniment using the chords above the bars. What is in these bars is replaced.',
                    ),
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                  const SizedBox(height: 12),
                  PatternPicker(patterns: patterns, selected: pattern, onChanged: (p) => setState(() => pattern = p)),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      '↓ abwärts, ↑ aufwärts, · halten. Zupfmuster: B Bass, A Wechselbass, 1 höchste Saite, 2 zweithöchste …',
                      '↓ down, ↑ up, · hold. Picking: B bass, A alternating bass, 1 highest string, 2 second highest …',
                    ),
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      field(fromCtrl, tr('Von Takt', 'From bar')),
                      const SizedBox(width: 16),
                      field(toCtrl, tr('Bis Takt', 'To bar')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: pattern == null
                  ? null
                  : () {
                      final a = (int.tryParse(fromCtrl.text) ?? 1).clamp(1, bars) - 1;
                      final b = (int.tryParse(toCtrl.text) ?? a + 1).clamp(1, bars) - 1;
                      Navigator.pop(context, (pattern!, a <= b ? a : b, a <= b ? b : a));
                    },
              child: Text(tr('Schreiben', 'Write')),
            ),
          ],
        );
      },
    ),
  ).whenComplete(() {
    fromCtrl.dispose();
    toCtrl.dispose();
  });
}

/// Liedtext zum Einfügen: Text und Strophe (0 = erste).
Future<(String, int)?> askLyricsText(BuildContext context, {required int fromBar}) {
  final ctrl = TextEditingController();
  var verse = 0;
  return showDialog<(String, int)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final n = core.ScoreEditor.parseLyrics(ctrl.text).length;
        return AlertDialog(
          title: Text(tr('Liedtext einfügen ab Takt ${fromBar + 1}', 'Paste lyrics from bar ${fromBar + 1}')),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 10,
                  decoration: InputDecoration(
                    hintText: tr('Son-nen-schein am Mor-gen …', 'Sun-shine in the mor-ning …'),
                    helperText: tr(
                      'Eine Silbe pro Note. Silben mit - trennen, _ lässt eine Note aus (die Silbe wird gehalten). Pausen und übergebundene Noten werden übersprungen.',
                      'One syllable per note. Split syllables with -, _ skips a note (the syllable is held). Rests and tied notes are skipped.',
                    ),
                    helperMaxLines: 3,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(tr('Strophe', 'Verse')),
                    const SizedBox(width: 12),
                    for (var v = 0; v < 4; v++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('${v + 1}'),
                          selected: verse == v,
                          onSelected: (_) => setState(() => verse = v),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      n == 0 ? '' : tr('$n Silben', '$n syllables'),
                      style: TextStyle(fontSize: 12.5, color: context.scrivi.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: n == 0 ? null : () => Navigator.pop(context, (ctrl.text, verse)),
              child: Text(tr('Verteilen', 'Distribute')),
            ),
          ],
        );
      },
    ),
  ).whenComplete(ctrl.dispose);
}

/// Formteil wiederholen: welcher Teil und wohin. Gibt (von, bis, einfügen vor) zurück.
Future<(int, int, int)?> askSectionCopy(
  BuildContext context, {
  required List<(String, int, int)> sections,
  required int cursorBar,
  required int bars,
}) {
  var chosen = 0;
  var atEnd = false;
  return showDialog<(int, int, int)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final c = context.scrivi;
        return AlertDialog(
          title: Text(tr('Formteil wiederholen', 'Repeat section')),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    'Die Takte des Teils werden mit allen Spuren kopiert, samt Akkorden und Text.',
                    'The bars of the section are copied with all tracks, including chords and text.',
                  ),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                const SizedBox(height: 10),
                RadioGroup<int>(
                  groupValue: chosen,
                  onChanged: (v) => setState(() => chosen = v ?? 0),
                  child: Column(
                    children: [
                      for (var i = 0; i < sections.length; i++)
                        RadioListTile<int>(
                          value: i,
                          dense: true,
                          title: Text(sections[i].$1),
                          subtitle: Text(
                            tr(
                              'Takt ${sections[i].$2 + 1} bis ${sections[i].$3 + 1}',
                              'Bars ${sections[i].$2 + 1} to ${sections[i].$3 + 1}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                RadioGroup<bool>(
                  groupValue: atEnd,
                  onChanged: (v) => setState(() => atEnd = v ?? false),
                  child: Column(
                    children: [
                      RadioListTile<bool>(
                        value: false,
                        dense: true,
                        title: Text(
                          tr('Nach Takt ${cursorBar + 1} (beim Cursor)', 'After bar ${cursorBar + 1} (at the cursor)'),
                        ),
                      ),
                      RadioListTile<bool>(
                        value: true,
                        dense: true,
                        title: Text(tr('Am Ende des Stücks', 'At the end of the piece')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: () {
                final s = sections[chosen];
                Navigator.pop(context, (s.$2, s.$3, atEnd ? bars : cursorBar + 1));
              },
              child: Text(tr('Einfügen', 'Insert')),
            ),
          ],
        );
      },
    ),
  );
}
