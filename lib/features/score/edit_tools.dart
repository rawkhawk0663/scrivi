import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';

// ───────────────────────── Dialoge ─────────────────────────

/// Eine Zeile Text abfragen. [suggestions]: Vorschläge zum Antippen.
/// [next]: zusätzlicher Knopf „Weiter“ (gibt den Text mit Weiter-Kennzeichen zurück).
Future<(String, bool)?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  List<String> suggestions = const [],
  bool next = false,
}) {
  final ctrl = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<(String, bool)>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(hintText: hint),
              onSubmitted: (v) => Navigator.pop(context, (v, next)),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in suggestions)
                    ActionChip(label: Text(s), onPressed: () => Navigator.pop(context, (s, false))),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
        if (next)
          TextButton(onPressed: () => Navigator.pop(context, (ctrl.text, false)), child: Text(tr('Fertig', 'Done'))),
        FilledButton(
          onPressed: () => Navigator.pop(context, (ctrl.text, next)),
          child: Text(next ? tr('Weiter', 'Next') : tr('Übernehmen', 'Apply')),
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}

/// Eine Zahl abfragen (mit Grenzen).
Future<int?> askNumber(
  BuildContext context, {
  required String title,
  required int initial,
  required int min,
  required int max,
  String unit = '',
}) async {
  final r = await askText(context, title: title, initial: '$initial', hint: unit);
  final v = int.tryParse(r?.$1.trim() ?? '');
  return v?.clamp(min, max);
}

/// Taktart abfragen.
Future<core.TimeSignature?> askTimeSignature(BuildContext context, core.TimeSignature current) {
  final beats = TextEditingController(text: '${current.beats}');
  var type = current.beatType;
  return showDialog<core.TimeSignature>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(tr('Taktart', 'Time signature')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (b, t) in const [(4, 4), (3, 4), (2, 4), (6, 8), (12, 8), (5, 4), (7, 8), (2, 2)])
                  ActionChip(label: Text('$b/$t'), onPressed: () => Navigator.pop(context, core.TimeSignature(b, t))),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: beats,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('/')),
                DropdownButton<int>(
                  value: type,
                  items: [
                    for (final t in const [2, 4, 8, 16]) DropdownMenuItem(value: t, child: Text('$t')),
                  ],
                  onChanged: (v) => setState(() => type = v ?? type),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(
            onPressed: () {
              final b = (int.tryParse(beats.text) ?? current.beats).clamp(1, 32);
              Navigator.pop(context, core.TimeSignature(b, type));
            },
            child: Text(tr('Übernehmen', 'Apply')),
          ),
        ],
      ),
    ),
  ).whenComplete(beats.dispose);
}

/// Tonart abfragen (Dur, nach Vorzeichen geordnet).
Future<core.KeySignature?> askKey(BuildContext context, core.KeySignature current) {
  final de = !L10n.isEnglish;
  String name(int f) {
    const majors = ['Ces', 'Ges', 'Des', 'As', 'Es', 'B', 'F', 'C', 'G', 'D', 'A', 'E', 'H', 'Fis', 'Cis'];
    const majorsEn = ['C♭', 'G♭', 'D♭', 'A♭', 'E♭', 'B♭', 'F', 'C', 'G', 'D', 'A', 'E', 'B', 'F♯', 'C♯'];
    final acc = f == 0 ? '' : (f > 0 ? '  ${'♯' * f}' : '  ${'♭' * -f}');
    return '${(de ? majors : majorsEn)[f + 7]}-${tr('Dur', 'major')}$acc';
  }

  return showDialog<core.KeySignature>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('Tonart', 'Key')),
      children: [
        SizedBox(
          height: 420,
          width: 320,
          child: ListView(
            children: [
              for (var f = -7; f <= 7; f++)
                ListTile(
                  dense: true,
                  selected: f == current.fifths,
                  title: Text(name(f)),
                  onTap: () => Navigator.pop(context, core.KeySignature(f)),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Vorschläge für Formteile.
List<String> sectionSuggestions() => L10n.isEnglish
    ? ['Intro', 'Verse', 'Pre-Chorus', 'Chorus', 'Bridge', 'Solo', 'Interlude', 'Outro']
    : ['Intro', 'Strophe', 'Pre-Chorus', 'Refrain', 'Bridge', 'Solo', 'Zwischenspiel', 'Schluss'];

/// Titel und Interpret abfragen.
Future<(String, String)?> askTitle(BuildContext context, String title, String artist) {
  final t = TextEditingController(text: title);
  final a = TextEditingController(text: artist);
  return showDialog<(String, String)>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Titel und Interpret', 'Title and artist')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: t,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('Titel', 'Title')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: a,
              decoration: InputDecoration(labelText: tr('Interpret', 'Artist')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, (t.text, a.text)), child: Text(tr('Übernehmen', 'Apply'))),
      ],
    ),
  ).whenComplete(() {
    t.dispose();
    a.dispose();
  });
}

/// Halbtöne zum Transponieren abfragen (−12 … +12).
Future<int?> askTranspose(BuildContext context) {
  var v = 0;
  return showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(tr('Ganzes Stück transponieren', 'Transpose the whole piece')),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                v == 0
                    ? tr('nicht verschoben', 'not moved')
                    : '${v > 0 ? '+' : ''}$v ${tr(v.abs() == 1 ? 'Halbton' : 'Halbtöne', v.abs() == 1 ? 'semitone' : 'semitones')}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Slider(
                value: v.toDouble(),
                min: -12,
                max: 12,
                divisions: 24,
                onChanged: (x) => setState(() => v = x.round()),
              ),
              Text(
                tr(
                  'Noten, Bünde, Tonart und Akkordsymbole werden mitverschoben.',
                  'Notes, frets, key and chord symbols move along.',
                ),
                style: TextStyle(color: context.scrivi.muted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, v), child: Text(tr('Transponieren', 'Transpose'))),
        ],
      ),
    ),
  );
}

/// Einstellungen für ein neues Stück.
class NewPieceSettings {
  NewPieceSettings(this.title, this.artist, this.kind, this.time, this.key, this.tempo, this.bars);
  final String title;
  final String artist;
  final core.NewPieceKind kind;
  final core.TimeSignature time;
  final core.KeySignature key;
  final double tempo;
  final int bars;
}

Future<NewPieceSettings?> askNewPiece(BuildContext context) {
  final title = TextEditingController();
  final artist = TextEditingController();
  final tempo = TextEditingController(text: '100');
  final bars = TextEditingController(text: '16');
  var kind = core.NewPieceKind.guitarTab;
  var time = const core.TimeSignature(4, 4);
  var key = const core.KeySignature(0);
  return showDialog<NewPieceSettings>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        String kindName(core.NewPieceKind k) => switch (k) {
          core.NewPieceKind.guitarTab => tr('Gitarre: Noten und Tabulatur', 'Guitar: notation and tab'),
          core.NewPieceKind.guitarNotation => tr('Gitarre: nur Noten', 'Guitar: notation only'),
          core.NewPieceKind.bass => tr('Bass: Noten und Tabulatur', 'Bass: notation and tab'),
          core.NewPieceKind.leadSheet => tr('Leadsheet: Melodie mit Akkorden', 'Lead sheet: melody with chords'),
        };
        return AlertDialog(
          title: Text(tr('Neues Stück', 'New piece')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: title,
                    autofocus: true,
                    decoration: InputDecoration(labelText: tr('Titel', 'Title')),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: artist,
                    decoration: InputDecoration(labelText: tr('Interpret', 'Artist')),
                  ),
                  const SizedBox(height: 16),
                  RadioGroup<core.NewPieceKind>(
                    groupValue: kind,
                    onChanged: (v) => setState(() => kind = v ?? kind),
                    child: Column(
                      children: [
                        for (final k in core.NewPieceKind.values)
                          RadioListTile<core.NewPieceKind>(
                            value: k,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(kindName(k)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ActionChip(
                        label: Text('${tr('Taktart', 'Time')} ${time.beats}/${time.beatType}'),
                        onPressed: () async {
                          final t = await askTimeSignature(context, time);
                          if (t != null) setState(() => time = t);
                        },
                      ),
                      ActionChip(
                        label: Text(
                          '${tr('Tonart', 'Key')} ${key.fifths == 0 ? (L10n.isEnglish ? 'C' : 'C') : (key.fifths > 0 ? '${key.fifths}♯' : '${-key.fifths}♭')}',
                        ),
                        onPressed: () async {
                          final k = await askKey(context, key);
                          if (k != null) setState(() => key = k);
                        },
                      ),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: tempo,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(labelText: tr('Tempo', 'Tempo'), suffixText: '♩'),
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: bars,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(labelText: tr('Takte', 'Bars')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                NewPieceSettings(
                  title.text.trim(),
                  artist.text.trim(),
                  kind,
                  time,
                  key,
                  (double.tryParse(tempo.text) ?? 100).clamp(20, 400).toDouble(),
                  (int.tryParse(bars.text) ?? 16).clamp(1, 500),
                ),
              ),
              child: Text(tr('Anlegen', 'Create')),
            ),
          ],
        );
      },
    ),
  ).whenComplete(() {
    title.dispose();
    artist.dispose();
    tempo.dispose();
    bars.dispose();
  });
}
