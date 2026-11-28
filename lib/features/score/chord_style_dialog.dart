import 'package:flutter/material.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';
import 'score_painter.dart';

/// Beispielakkorde für die Vorschau.
const _examples = [
  'C',
  'Am',
  'Am7',
  'Cmaj7',
  'Cmaj9',
  'CmMaj7',
  'G7(b9)',
  'G7(b9,#11)',
  'C7#5',
  'Bdim7',
  'F#m7b5',
  'D7sus4',
  'Cadd9',
  'Cm7add11',
  'C6/9',
  'Bb13',
  'G/B',
];

/// Schreibweise der Akkordsymbole für das Stück wählen, mit Vorschau (so, wie der Notensatz sie zeichnet).
Future<core.ChordStyle?> askChordStyle(
  BuildContext context,
  core.ChordStyle start, {
  bool germanNames = false,
  Map<String, String> fonts = const {},
}) {
  return showDialog<core.ChordStyle>(
    context: context,
    builder: (context) => _ChordStyleDialog(start: start, germanNames: germanNames, fonts: fonts),
  );
}

class _ChordStyleDialog extends StatefulWidget {
  const _ChordStyleDialog({required this.start, required this.germanNames, required this.fonts});
  final core.ChordStyle start;
  final bool germanNames;

  /// Gewählte Schriften des Stücks (die Vorschau zeigt die Akkorde in ihrer Schrift).
  final Map<String, String> fonts;

  @override
  State<_ChordStyleDialog> createState() => _ChordStyleDialogState();
}

class _ChordStyleDialogState extends State<_ChordStyleDialog> {
  late core.ChordStyle s = widget.start;
  late final core.TextMeasurer _measurer = core.FontMeasurer.of(FlutterTextMeasurer(), widget.fonts);

  void _set(core.ChordStyle v) => setState(() => s = v);

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final size = MediaQuery.sizeOf(context);
    Widget heading(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        t,
        style: TextStyle(fontWeight: FontWeight.w600, color: c.muted, fontSize: 12.5),
      ),
    );
    Widget radio(String label, bool on, VoidCallback onTap, {bool enabled = true, double indent = 0}) => InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent, 3, 6, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: !enabled ? c.line : (on ? Theme.of(context).colorScheme.primary : c.muted),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label, style: TextStyle(fontSize: 13, color: enabled ? null : c.muted)),
            ),
          ],
        ),
      ),
    );
    Widget check(String label, bool on, ValueChanged<bool> onChanged, {bool enabled = true, double indent = 0}) =>
        InkWell(
          onTap: enabled ? () => onChanged(!on) : null,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: EdgeInsets.fromLTRB(indent, 3, 6, 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  on ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  size: 18,
                  color: !enabled ? c.line : (on ? Theme.of(context).colorScheme.primary : c.muted),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label, style: TextStyle(fontSize: 13, color: enabled ? null : c.muted)),
                ),
              ],
            ),
          ),
        );
    Widget grid(List<Widget> children, {int columns = 2}) => Wrap(
      runSpacing: 0,
      children: [for (final w in children) SizedBox(width: 400 / columns - 4, child: w)],
    );
    Widget box(String title, List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          ...children,
        ],
      ),
    );

    const triadLabels = [
      'C / Cm',
      'Cma / Cmi',
      'CMA / CMI',
      'Cmaj / Cmin',
      'CM / Cm',
      'CM / Cm ↑',
      'CΔ / C−',
      'CΔ / C− ↑',
    ];
    const major7Labels = ['Cma7', 'CMA7', 'Cmaj7', 'CM7', 'CM7 ↑', 'CΔ', 'CΔ ↑', 'CΔ7', 'CΔ7 ↑'];

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        box(tr('Darstellung', 'Appearance'), [
          heading(tr('Über den Noten', 'Above the notes')),
          radio(tr('Nur Akkordname', 'Chord name only'), s.show == 0, () => _set(s.copyWith(show: 0))),
          radio(tr('Nur Griffbild', 'Chord diagram only'), s.show == 1, () => _set(s.copyWith(show: 1))),
          radio(tr('Name und Griffbild', 'Name and diagram'), s.show == 2, () => _set(s.copyWith(show: 2))),
          check(
            tr('Griffbilder nur bei Saiteninstrumenten', 'Diagrams only on string instruments'),
            s.diagramsStringedOnly,
            (v) => _set(s.copyWith(diagramsStringedOnly: v)),
            enabled: s.show != 0,
          ),
          check(
            tr('Übersicht der Griffbilder oben auf Seite 1', 'Overview of diagrams at the top of page 1'),
            s.diagrams,
            (v) => _set(s.copyWith(diagrams: v)),
          ),
        ]),
        box(tr('Dur- und Moll-Dreiklänge', 'Major / minor triads'), [
          grid([
            for (var i = 0; i < triadLabels.length; i++)
              radio(triadLabels[i], s.triads == i, () => _set(s.copyWith(triads: i))),
          ]),
        ]),
        box(tr('Grosse Septime', 'Major seventh chords'), [
          grid([
            for (var i = 0; i < major7Labels.length; i++)
              radio(major7Labels[i], s.major7 == i, () => _set(s.copyWith(major7: i))),
          ], columns: 3),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr('↑ = hochgestellt (klein)', '↑ = superscript (small)'),
              style: TextStyle(fontSize: 11.5, color: c.muted),
            ),
          ),
        ]),
        box(tr('Veränderte Töne und Zusätze', 'Alterations and extensions'), [
          radio(tr('Mit ♯ und ♭', 'Use ♯ / ♭'), !s.plusMinus, () => _set(s.copyWith(plusMinus: false))),
          check(
            tr('♯ und ♭ hinter der Zahl (9♭)', '♯ / ♭ after numbers (9♭)'),
            s.accAfter,
            (v) => _set(s.copyWith(accAfter: v)),
            enabled: !s.plusMinus,
            indent: 26,
          ),
          radio(tr('Mit + und −', 'Use + / −'), s.plusMinus, () => _set(s.copyWith(plusMinus: true))),
          const SizedBox(height: 6),
          check(
            tr('Veränderte Töne ans Ende des Akkords', 'Move alterations to end of chord'),
            s.moveAlts,
            (v) => _set(s.copyWith(moveAlts: v)),
          ),
          radio(
            tr('wenn sie gleich nach dem Grundton kämen', 'if they occur directly after the root'),
            !s.moveAlways,
            () => _set(s.copyWith(moveAlways: false)),
            enabled: s.moveAlts,
            indent: 26,
          ),
          radio(
            tr('immer', 'always'),
            s.moveAlways,
            () => _set(s.copyWith(moveAlways: true)),
            enabled: s.moveAlts,
            indent: 26,
          ),
          const SizedBox(height: 6),
          radio(
            tr('Übereinander (gestapelt)', 'Stacked arrangement'),
            s.stacked,
            () => _set(s.copyWith(stacked: true)),
          ),
          check(
            tr('Reihenfolge umkehren (tiefste oben)', 'Invert numerical order (lowest on top)'),
            s.invertOrder,
            (v) => _set(s.copyWith(invertOrder: v)),
            enabled: s.stacked,
            indent: 26,
          ),
          radio(tr('Nebeneinander', 'Linear arrangement'), !s.stacked, () => _set(s.copyWith(stacked: false))),
          const SizedBox(height: 6),
          check(
            tr('Zahlen und Zusätze hochgestellt (klein)', 'Numbers and extensions as superscript (small)'),
            s.raised,
            (v) => _set(s.copyWith(raised: v)),
          ),
        ]),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        box(tr('Wörter', 'Word modifiers'), [
          radio('sus, add, omit', !s.upperWords, () => _set(s.copyWith(upperWords: false))),
          radio('SUS, ADD, OMIT', s.upperWords, () => _set(s.copyWith(upperWords: true))),
          check(
            tr('„no“ statt „omit“', 'Use “no” instead of “omit”'),
            s.noInsteadOfOmit,
            (v) => _set(s.copyWith(noInsteadOfOmit: v)),
          ),
          check(
            tr('„4“ bei sus4 zeigen', 'Show “4” in suspended fourth chords'),
            s.showSus4,
            (v) => _set(s.copyWith(showSus4: v)),
          ),
        ]),
        box(tr('Übermässig, vermindert, halbvermindert', 'Augmented, diminished and half-diminished'), [
          radio('+  °  ø', s.symbols, () => _set(s.copyWith(symbols: true))),
          radio('aug  dim  m7♭5', !s.symbols, () => _set(s.copyWith(symbols: false))),
          heading(tr('Zeichen', 'Symbols')),
          radio(
            tr('Auf der Grundlinie (gross)', 'Baseline symbols (large)'),
            !s.symbolsRaised,
            () => _set(s.copyWith(symbolsRaised: false)),
            enabled: s.symbols,
          ),
          radio(
            tr('Hochgestellt (klein)', 'Superscript (small)'),
            s.symbolsRaised,
            () => _set(s.copyWith(symbolsRaised: true)),
            enabled: s.symbols,
          ),
          check(
            tr('Die „7“ bei ° und ø zeigen', 'Show “7” in dim7 and half-dim chords'),
            s.dimSeven,
            (v) => _set(s.copyWith(dimSeven: v)),
            enabled: s.symbols,
          ),
          heading(tr('Übermässig mit Septime', 'Augmented with seventh')),
          radio('Caug7 / C+7', s.augBefore, () => _set(s.copyWith(augBefore: true))),
          radio('C7aug / C7+', !s.augBefore, () => _set(s.copyWith(augBefore: false))),
        ]),
        box(tr('Grundton', 'Root notes'), [
          radio(
            tr('Vorzeichen auf der Grundlinie (B♭)', 'Baseline root accidentals (B♭)'),
            !s.rootAccRaised,
            () => _set(s.copyWith(rootAccRaised: false)),
          ),
          radio(
            tr('Vorzeichen hochgestellt', 'Superscript root accidentals'),
            s.rootAccRaised,
            () => _set(s.copyWith(rootAccRaised: true)),
          ),
        ]),
        box(tr('Klammern', 'Parentheses'), [
          Row(
            children: [
              Flexible(
                child: check(
                  tr('Um veränderte Töne, ab', 'Around alterations, from'),
                  s.parenAlts,
                  (v) => _set(s.copyWith(parenAlts: v)),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: s.parenAlts && s.parenMin > 1 ? () => _set(s.copyWith(parenMin: s.parenMin - 1)) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Text('${s.parenMin}', style: const TextStyle(fontWeight: FontWeight.w600)),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: s.parenAlts && s.parenMin < 5 ? () => _set(s.copyWith(parenMin: s.parenMin + 1)) : null,
                icon: const Icon(Icons.add_rounded),
              ),
              Text(tr('Stück', 'or more'), style: const TextStyle(fontSize: 13)),
            ],
          ),
          check(
            tr('Um Wörter (sus, add, omit)', 'Around word modifiers (sus, add, omit)'),
            s.parenWords,
            (v) => _set(s.copyWith(parenWords: v)),
          ),
          check(
            tr('Um grosse Septime bei Moll: Cm(maj7)', 'Around major 7ths on minor chords: Cm(maj7)'),
            s.parenMinMaj7,
            (v) => _set(s.copyWith(parenMinMaj7: v)),
          ),
        ]),
        box(tr('Sprache der Grundtöne', 'Language of root names'), [
          radio(tr('Wie die App', 'As the app'), s.rootNames == 0, () => _set(s.copyWith(rootNames: 0))),
          radio(tr('International (B, B♭)', 'English (B, B♭)'), s.rootNames == 1, () => _set(s.copyWith(rootNames: 1))),
          radio(tr('Deutsch (H, B)', 'German (H, B)'), s.rootNames == 2, () => _set(s.copyWith(rootNames: 2))),
        ]),
      ],
    );

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
      contentPadding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
      title: Text(tr('Akkordsymbole', 'Chord symbols')),
      content: SizedBox(
        width: 860,
        height: size.height * 0.72,
        child: Column(
          children: [
            // Vorschau: genau so, wie der Notensatz zeichnet
            Container(
              width: double.infinity,
              height: 150,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CustomPaint(painter: _PreviewPainter(s, widget.germanNames, _measurer, widget.fonts)),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: left),
                    const SizedBox(width: 14),
                    Expanded(child: right),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => _set(core.ChordStyle.standard), child: Text(tr('Grundeinstellung', 'Defaults'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, s), child: Text(tr('Übernehmen', 'Apply'))),
      ],
    );
  }
}

/// Zeichnet die Beispielakkorde mit dem Notensatz (Bravura-Zeichen, Stapel, hochgestellt).
class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.style, this.german, this.measurer, this.fonts);
  final core.ChordStyle style;
  final Map<String, String> fonts;
  final bool german;
  final core.TextMeasurer measurer;

  @override
  void paint(Canvas canvas, Size size) {
    const chordSize = 1.6, gap = 2.2, rowH = 4.4;
    // Zuerst in sp anordnen, dann auf die Breite einpassen
    const width = 68.0;
    final page = core.PageDisplay(width, rowH * 3);
    var x = 1.2, y = 3.4;
    for (final ex in _examples) {
      final parts = core.ChordSymbol.format(ex, style, germanNames: german);
      final w = core.drawChord(parts, 0, 0, chordSize, measurer).width;
      if (x + w > width - 1 && x > 1.2) {
        x = 1.2;
        y += rowH;
      }
      page.items.addAll(core.drawChord(parts, x, y, chordSize, measurer).items);
      x += w + gap;
    }
    final k = size.width / width;
    canvas.save();
    canvas.scale(k, k);
    PagePictures.paint(canvas, core.PageDisplay(width, size.height / k, fonts: fonts)..items.addAll(page.items));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.style != style || old.german != german || old.fonts != fonts;
}
