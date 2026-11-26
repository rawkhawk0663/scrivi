import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';

/// Was die Werkzeugleiste von der Notenansicht braucht.
abstract class EditHost {
  core.ScoreEditor get editor;

  /// Eine Änderung ausführen; danach wird neu gesetzt und gespeichert.
  void apply(void Function(core.ScoreEditor e) op);

  /// Stift setzt Noten im Notensystem (statt nur den Cursor zu bewegen).
  bool get penNotes;
  set penNotes(bool v);

  /// Gibt es eine Notenzeile in der Ansicht?
  bool get showsNotation;

  Future<void> editChord();
  Future<void> editText();
  Future<void> editLyrics();
  void showMoreMenu(Offset globalPosition);
}

/// Werkzeugleiste, die beim Cursor schwebt: Notenwerte, Pause, Bogen,
/// Vorzeichen, Techniken, Akkord, Text, Bundzahlen.
class EditPalette extends StatefulWidget {
  const EditPalette({super.key, required this.host});
  final EditHost host;

  @override
  State<EditPalette> createState() => _EditPaletteState();
}

class _EditPaletteState extends State<EditPalette> {
  bool _techniques = false;
  bool _frets = false;

  core.ScoreEditor get _e => widget.host.editor;

  void _do(void Function(core.ScoreEditor e) op) {
    widget.host.apply(op);
    setState(() {});
  }

  static const _durations = [
    (core.NoteValue.whole, '', 'Ganze', 'Whole'),
    (core.NoteValue.half, '', 'Halbe', 'Half'),
    (core.NoteValue.quarter, '', 'Viertel', 'Quarter'),
    (core.NoteValue.eighth, '', 'Achtel', 'Eighth'),
    (core.NoteValue.sixteenth, '', 'Sechzehntel', 'Sixteenth'),
    (core.NoteValue.thirtySecond, '', 'Zweiunddreissigstel', 'Thirty-second'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final e = _e;
    final beat = e.currentBeat;
    final value = beat?.duration.value ?? e.duration.value;
    final stringed = e.stringed;
    return Material(
      color: c.cardHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (final (v, glyph, de, en) in _durations)
                  _Tool(
                    glyph: glyph,
                    tooltip: '${tr(de, en)}  (+ / −)',
                    selected: v == value,
                    onTap: () => _do((e) => e.setDuration(v)),
                  ),
                _Tool(
                  glyph: '',
                  tooltip: tr('Punkt  (.)', 'Dot  (.)'),
                  selected: (beat?.duration.dots ?? e.duration.dots) > 0,
                  onTap: () => _do((e) => e.toggleDot()),
                ),
                _Tool(
                  label: '3',
                  tooltip: tr('Triole  (T)', 'Triplet  (T)'),
                  selected: beat?.duration.tuplet != null,
                  onTap: () => _do((e) => e.toggleTriplet()),
                ),
                _Tool(glyph: '', tooltip: tr('Pause  (Entf)', 'Rest  (Del)'), onTap: () => _do((e) => e.toRest())),
                _Tool(
                  label: '‿',
                  tooltip: tr('Haltebogen  (L)', 'Tie  (L)'),
                  selected: beat != null && beat.notes.isNotEmpty && beat.notes.every((n) => n.tieDestination),
                  onTap: () => _do((e) => e.toggleTie()),
                ),
                _Tool(
                  glyph: '',
                  tooltip: tr('Halbton höher  (Umschalt + ↑)', 'Semitone up  (Shift + ↑)'),
                  onTap: () => _do((e) => e.transposeSelection(1)),
                ),
                _Tool(
                  glyph: '',
                  tooltip: tr('Halbton tiefer  (Umschalt + ↓)', 'Semitone down  (Shift + ↓)'),
                  onTap: () => _do((e) => e.transposeSelection(-1)),
                ),
                if (widget.host.showsNotation)
                  _Tool(
                    icon: Icons.edit_outlined,
                    tooltip: tr('Stift setzt Noten ins Notensystem', 'Pen places notes on the staff'),
                    selected: widget.host.penNotes,
                    onTap: () => setState(() => widget.host.penNotes = !widget.host.penNotes),
                  ),
                if (stringed)
                  _Tool(
                    label: '0–24',
                    wide: true,
                    tooltip: tr('Bundzahlen', 'Fret numbers'),
                    selected: _frets,
                    onTap: () => setState(() => _frets = !_frets),
                  ),
                _Tool(
                  label: tr('Technik', 'Technique'),
                  wide: true,
                  tooltip: tr('Spieltechniken', 'Playing techniques'),
                  selected: _techniques,
                  onTap: () => setState(() => _techniques = !_techniques),
                ),
                _Tool(
                  label: tr('Akkord', 'Chord'),
                  wide: true,
                  tooltip: tr('Akkordsymbol  (K)', 'Chord symbol  (K)'),
                  onTap: widget.host.editChord,
                ),
                _Tool(
                  label: tr('Text', 'Text'),
                  wide: true,
                  tooltip: tr('Text über der Note', 'Text above the note'),
                  onTap: widget.host.editText,
                ),
                _Tool(
                  label: tr('Liedtext', 'Lyrics'),
                  wide: true,
                  tooltip: tr('Liedtext  (Y)', 'Lyrics  (Y)'),
                  onTap: widget.host.editLyrics,
                ),
                Builder(
                  builder: (context) => _Tool(
                    icon: Icons.more_horiz,
                    tooltip: tr('Takt und Stück', 'Bar and piece'),
                    onTap: () {
                      final box = context.findRenderObject() as RenderBox;
                      widget.host.showMoreMenu(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
                    },
                  ),
                ),
              ],
            ),
            if (_techniques) ...[const SizedBox(height: 4), _techniqueRow()],
            if (_frets && stringed) ...[const SizedBox(height: 4), _fretPad()],
          ],
        ),
      ),
    );
  }

  Widget _techniqueRow() {
    Widget t(core.Technique tech, String label, String de, String en) => _Tool(
      label: label,
      wide: label.length > 2,
      tooltip: tr(de, en),
      selected: _e.hasTechnique(tech),
      onTap: () => _do((e) => e.toggleTechnique(tech)),
    );
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        if (_e.stringed) ...[
          t(core.Technique.hammer, 'H/P', 'Hammer-on / Pull-off', 'Hammer-on / pull-off'),
          t(core.Technique.slide, '⟋', 'Slide zur nächsten Note', 'Slide to the next note'),
          t(core.Technique.bendHalf, '↑½', 'Bending um einen Halbton', 'Bend a semitone'),
          t(core.Technique.bend, '↑1', 'Bending um einen Ganzton', 'Bend a whole tone'),
          t(core.Technique.palmMute, 'P.M.', 'Palm Mute', 'Palm mute'),
          t(core.Technique.letRing, 'L.R.', 'Let ring (klingen lassen)', 'Let ring'),
          t(core.Technique.dead, '×', 'Gedämpfte Note', 'Dead note'),
          t(core.Technique.harmonic, '◇', 'Flageolett', 'Harmonic'),
          t(core.Technique.tapping, 'T', 'Tapping', 'Tapping'),
        ],
        t(core.Technique.vibrato, '∿', 'Vibrato', 'Vibrato'),
        t(core.Technique.ghost, '( )', 'Geisternote', 'Ghost note'),
        t(core.Technique.accent, '>', 'Akzent', 'Accent'),
        t(core.Technique.staccato, '·', 'Staccato', 'Staccato'),
        _Tool(
          glyph: '',
          tooltip: tr('Fermate', 'Fermata'),
          selected: _e.currentBeat?.fermata ?? false,
          onTap: () => _do((e) => e.toggleFermata()),
        ),
      ],
    );
  }

  Widget _fretPad() {
    final max = _e.score.tracks[_e.track].staff.fretCount.clamp(12, 24);
    return SizedBox(
      width: 13 * 37,
      child: Wrap(
        spacing: 3,
        runSpacing: 3,
        children: [
          for (var f = 0; f <= max; f++)
            _Tool(label: '$f', tooltip: tr('Bund $f', 'Fret $f'), onTap: () => _do((e) => e.inputFret(f))),
        ],
      ),
    );
  }
}

/// Ein Knopf der Werkzeugleiste (gross genug für Stift und Finger).
class _Tool extends StatelessWidget {
  const _Tool({
    this.label,
    this.glyph,
    this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
    this.wide = false,
  });
  final String? label;

  /// Zeichen aus der Notenschrift Bravura.
  final String? glyph;
  final IconData? icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = context.scrivi;
    final fg = selected ? scheme.onPrimary : null;
    Widget child;
    if (glyph != null) {
      child = Text(
        glyph!,
        style: TextStyle(fontFamily: 'Bravura', fontSize: 22, height: 1, color: fg ?? c.muted),
      );
    } else if (icon != null) {
      child = Icon(icon, size: 20, color: fg);
    } else {
      child = Text(
        label!,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
      );
    }
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minWidth: wide ? 52 : 34),
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: wide ? 8 : 0),
          decoration: BoxDecoration(color: selected ? scheme.primary : c.card, borderRadius: BorderRadius.circular(8)),
          // Nur so breit wie nötig (eine Ausrichtung würde die ganze Breite füllen)
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [child]),
        ),
      ),
    );
  }
}

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
