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

/// Häuser wählen (1., 2. …); leer = keine.
Future<Set<int>?> askEndings(BuildContext context, Set<int> current) {
  final chosen = {...current};
  return showDialog<Set<int>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(tr('Häuser', 'Endings')),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'Bei welchem Durchgang wird dieser Takt gespielt? Mehrere Takte vorher auswählen, um das Haus über alle zu ziehen.',
                  'On which pass is this bar played? Select several bars first to span the ending over all of them.',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (var n = 1; n <= 6; n++)
                    FilterChip(
                      label: Text('$n.'),
                      selected: chosen.contains(n),
                      onSelected: (on) => setState(() => on ? chosen.add(n) : chosen.remove(n)),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, <int>{}), child: Text(tr('Keine', 'None'))),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, chosen), child: Text(tr('Übernehmen', 'Apply'))),
        ],
      ),
    ),
  );
}

/// Sprungzeichen am Takt wählen (D.C., D.S., Fine, To Coda …).
Future<Set<core.Direction>?> askJumps(BuildContext context, Set<core.Direction> current) {
  final chosen = {...current};
  String label(core.Direction d) => switch (d) {
    core.Direction.segno => 'Segno',
    core.Direction.segnoSegno => 'Segno Segno',
    core.Direction.coda => 'Coda',
    core.Direction.doubleCoda => 'Double Coda',
    core.Direction.fine => 'Fine',
    core.Direction.daCapo => tr('D.C. (Da Capo: von vorne)', 'D.C. (Da Capo: from the beginning)'),
    core.Direction.daCapoAlFine => tr('D.C. al Fine (von vorne bis Fine)', 'D.C. al Fine (from the beginning to Fine)'),
    core.Direction.daCapoAlCoda => tr(
      'D.C. al Coda (von vorne, dann zur Coda)',
      'D.C. al Coda (from the beginning, then to the coda)',
    ),
    core.Direction.dalSegno => tr('D.S. (Dal Segno: ab dem Segno)', 'D.S. (Dal Segno: from the sign)'),
    core.Direction.dalSegnoAlFine => tr('D.S. al Fine (ab dem Segno bis Fine)', 'D.S. al Fine (from the sign to Fine)'),
    core.Direction.dalSegnoAlCoda => tr(
      'D.S. al Coda (ab dem Segno, dann zur Coda)',
      'D.S. al Coda (from the sign, then to the coda)',
    ),
    core.Direction.toCoda => tr('To Coda (hier zur Coda springen)', 'To Coda (jump to the coda here)'),
  };
  return showDialog<Set<core.Direction>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(tr('Sprungzeichen', 'Jumps')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in core.Direction.values)
                  CheckboxListTile(
                    dense: true,
                    value: chosen.contains(d),
                    title: Text(label(d)),
                    onChanged: (on) => setState(() => on == true ? chosen.add(d) : chosen.remove(d)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, chosen), child: Text(tr('Übernehmen', 'Apply'))),
        ],
      ),
    ),
  );
}

/// Angaben zum Stück: alles, was oben auf dem Blatt steht, dazu eine private Bemerkung.
Future<core.ScoreInfo?> askScoreInfo(BuildContext context, core.ScoreInfo info) {
  final fields = <String, TextEditingController>{
    'title': TextEditingController(text: info.title),
    'subtitle': TextEditingController(text: info.subtitle),
    'artist': TextEditingController(text: info.artist),
    'album': TextEditingController(text: info.album),
    'words': TextEditingController(text: info.words),
    'music': TextEditingController(text: info.music),
    'copyright': TextEditingController(text: _withoutSign(info.copyright)),
    'tabber': TextEditingController(text: info.tabber),
    'instructions': TextEditingController(text: info.instructions),
    'notice': TextEditingController(text: info.notice),
  };
  Widget field(String key, String label, {String? hint, bool autofocus = false, int lines = 1, String? prefix}) =>
      TextField(
        controller: fields[key],
        autofocus: autofocus,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 6,
        keyboardType: lines == 1 ? TextInputType.text : TextInputType.multiline,
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          prefixText: prefix,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
  Widget pair(Widget a, Widget b) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: a),
      const SizedBox(width: 12),
      Expanded(child: b),
    ],
  );
  core.ScoreInfo result() => core.ScoreInfo(
    title: fields['title']!.text.trim(),
    subtitle: fields['subtitle']!.text.trim(),
    artist: fields['artist']!.text.trim(),
    album: fields['album']!.text.trim(),
    words: fields['words']!.text.trim(),
    music: fields['music']!.text.trim(),
    copyright: _withoutSign(fields['copyright']!.text),
    tabber: fields['tabber']!.text.trim(),
    instructions: fields['instructions']!.text.trim(),
    notice: fields['notice']!.text.trim(),
  );
  return showDialog<core.ScoreInfo>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Angaben zum Stück', 'Piece information')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              field('title', tr('Titel', 'Title'), autofocus: true),
              const SizedBox(height: 12),
              field('subtitle', tr('Untertitel', 'Subtitle')),
              const SizedBox(height: 12),
              pair(field('artist', tr('Interpret', 'Artist')), field('album', tr('Album', 'Album'))),
              const SizedBox(height: 12),
              pair(
                field('words', tr('Text', 'Words'), hint: tr('steht rechts oben', 'shown top right')),
                field(
                  'music',
                  tr('Musik', 'Music'),
                  hint: tr('gleich wie Text: „Text und Musik“', 'same as words: “Words and music”'),
                ),
              ),
              const SizedBox(height: 12),
              pair(
                field(
                  'copyright',
                  tr('Copyright', 'Copyright'),
                  hint: tr('steht unten auf Seite 1', 'shown at the bottom of page 1'),
                  prefix: '© ',
                ),
                field('tabber', tr('Transkription', 'Transcribed by'), hint: tr('steht links oben', 'shown top left')),
              ),
              const SizedBox(height: 12),
              field(
                'instructions',
                tr('Anleitungen', 'Instructions'),
                hint: tr(
                  'stehen über der ersten Zeile, z. B. „Kapo 2, mit Plektrum“',
                  'shown above the first line, e.g. “Capo 2, with a pick”',
                ),
                lines: 2,
              ),
              const SizedBox(height: 12),
              field(
                'notice',
                tr('Bemerkung', 'Notes'),
                hint: tr('nur für dich, erscheint nicht auf dem Blatt', 'just for you, not printed'),
                lines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, result()), child: Text(tr('Übernehmen', 'Apply'))),
      ],
    ),
  ).whenComplete(() {
    for (final c in fields.values) {
      c.dispose();
    }
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
          core.NewPieceKind.drums => tr('Schlagzeug', 'Drums'),
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

/// Copyright ohne „©“ vorne: das Zeichen setzt Scrivi selbst.
String _withoutSign(String text) => text.trim().replaceFirst(RegExp(r'^(©|\(c\))\s*', caseSensitive: false), '').trim();
