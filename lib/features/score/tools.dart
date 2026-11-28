import 'package:flutter/material.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';
import 'tool_glyphs.g.dart';

/// Was die Werkzeuge von der Notenansicht brauchen.
abstract class ToolHost {
  core.ScoreEditor get editor;

  /// Eine Änderung ausführen; danach wird neu gesetzt, gespeichert und der Ton gespielt.
  void apply(void Function(core.ScoreEditor e) op, {bool sound = false});

  /// Maus und Finger schreiben wie der Stift (Noten setzen, Gesten); sonst nur der Stift.
  bool get penNotes;
  set penNotes(bool v);

  /// Mikrofon: vorgespielte Töne werden an den Cursor geschrieben.
  bool get micOn;
  Future<void> toggleMic();

  Future<void> editChord();
  Future<void> editText();
  Future<void> editLyrics();
  Future<void> editTimeSignature();
  Future<void> editKey();
  Future<void> editTempo();
  Future<void> editSection();
  Future<void> editRepeatEnd();

  /// Häuser (1., 2. …) und Sprungzeichen (D.C., D.S., Fine …) wählen.
  Future<void> editEndings();
  Future<void> editJumps();
  Future<void> editTitle();
  Future<void> editChordStyle();
  Future<void> editPageSetup();
  Future<void> editTranspose();

  /// Spur: Name, Klang, Stimmung/Kapo (Spur am Cursor), neue Spur.
  Future<void> editTrackName(int track);
  Future<void> editTrackSound(int track);
  Future<void> editTuning();
  Future<void> editInstrumentKey(int track);
  Future<void> addTrack();

  /// Schnell-Eingaben: Akkordzeile, Begleitmuster, Liedtext einfügen, Formteil wiederholen.
  Future<void> quickChords();
  Future<void> quickPattern();
  Future<void> quickLyrics();
  Future<void> quickSection();
  Future<void> save();
  Future<void> saveAs();

  /// Weiteres Stück in einem neuen Reiter öffnen.
  Future<void> openPiece();

  /// Ausgeben als PDF, MusicXML oder MIDI; Drucken.
  Future<void> exportPiece();
  Future<void> printPiece();
  void copy();
  void cut();
  void paste();
  bool get canPaste;
}

/// Gruppen der Werkzeugspalte (Reihenfolge = Anzeige).
enum ToolGroup {
  notes('Noten', 'Notes'),
  guitar('Gitarre', 'Guitar'),
  drums('Schlagzeug', 'Drums'),
  finger('Fingersatz', 'Fingering'),
  quick('Schnell', 'Quick'),
  expression('Ausdruck', 'Expression'),
  bar('Takt', 'Bar'),
  text('Text', 'Text'),
  piece('Stück', 'Piece');

  const ToolGroup(this.de, this.en);
  final String de;
  final String en;
  String get label => tr(de, en);
}

/// Wie ein Werkzeug aussieht: Notenzeichen (Bravura), kurzer Text oder Symbol.
sealed class ToolLook {
  const ToolLook();
}

class GlyphLook extends ToolLook {
  const GlyphLook(this.char, {this.size = 22, this.dy = 0});
  final String char;
  final double size;
  final double dy;
}

class TextLook extends ToolLook {
  const TextLook(this.text, {this.italic = false});
  final String text;
  final bool italic;
}

class IconLook extends ToolLook {
  const IconLook(this.icon);
  final IconData icon;
}

/// Ein Werkzeug: Aussehen, Name, Kürzel, wann es aktiv bzw. möglich ist, was es tut.
class ToolDef {
  const ToolDef({
    required this.id,
    required this.group,
    required this.look,
    required this.de,
    required this.en,
    required this.run,
    this.shortcut,
    this.keywords = const [],
    this.active,
    this.enabled,
    this.stringedOnly = false,
    this.drumsOnly = false,
  });
  final String id;
  final ToolGroup group;
  final ToolLook look;
  final String de;
  final String en;
  final String? shortcut;

  /// Weitere Suchwörter (beide Sprachen).
  final List<String> keywords;
  final bool Function(core.ScoreEditor e)? active;
  final bool Function(core.ScoreEditor e)? enabled;
  final void Function(ToolHost host) run;

  /// Nur bei Saiteninstrumenten.
  final bool stringedOnly;

  /// Nur bei Schlagzeug-Spuren.
  final bool drumsOnly;

  /// Passt das Werkzeug zur Spur am Cursor?
  bool fits(core.ScoreEditor e) => (!stringedOnly || e.stringed) && (!drumsOnly || e.percussion);

  String get name => tr(de, en);
  String get tooltip => shortcut == null ? name : '$name   $shortcut';

  bool matches(String q) {
    final s = q.toLowerCase().trim();
    if (s.isEmpty) return true;
    return [de, en, group.de, group.en, ...keywords].any((w) => w.toLowerCase().contains(s));
  }
}

bool _hasNotes(core.ScoreEditor e) => !(e.currentBeat?.isRest ?? true);

/// Steht am Cursor eine Note mit diesem Vorzeichen (geschrieben)?
bool _accidentalIs(core.ScoreEditor e, int alter) {
  final b = e.currentBeat;
  if (b == null || b.isRest) return false;
  final t = e.score.tracks[e.track];
  return b.notes.every((n) => n.shownFor(t.transposeSemitones).alter == alter) && alter != 0;
}

bool _hasBeat(core.ScoreEditor e) => e.currentBeat != null;

core.NoteValue _value(core.ScoreEditor e) => e.currentBeat?.duration.value ?? e.duration.value;

ToolDef _duration(core.NoteValue v, String glyph, String de, String en, String key) => ToolDef(
  id: 'd-${v.name}',
  group: ToolGroup.notes,
  look: GlyphLook(glyph, size: 24, dy: 4),
  de: de,
  en: en,
  shortcut: key,
  active: (e) => _value(e) == v,
  run: (h) => h.apply((e) => e.setDuration(v)),
);

ToolDef _tech(
  core.Technique t,
  ToolLook look,
  String de,
  String en, {
  List<String> keywords = const [],
  bool guitar = true,
}) => ToolDef(
  id: 't-${t.name}',
  group: guitar ? ToolGroup.guitar : ToolGroup.expression,
  look: look,
  de: de,
  en: en,
  keywords: keywords,
  stringedOnly: guitar,
  active: (e) => e.hasTechnique(t),
  enabled: _hasNotes,
  run: (h) => h.apply((e) => e.toggleTechnique(t), sound: true),
);

/// Fingersatz der Greifhand (1–4, 5 = Daumen) bzw. der Anschlagshand (1 p … 5 c).
ToolDef _finger(int f, String glyph, String de, String en, {required bool left, List<String> keywords = const []}) =>
    ToolDef(
      id: left ? 'lf-$f' : 'rf-$f',
      group: ToolGroup.finger,
      look: GlyphLook(glyph, size: 30, dy: left ? 6 : 3),
      de: de,
      en: en,
      keywords: [
        'fingersatz',
        'fingering',
        if (left) ...['greifhand', 'linke hand', 'left hand'] else ...['anschlag', 'rechte hand', 'right hand'],
        ...keywords,
      ],
      stringedOnly: !left,
      active: (e) => e.fingerAtCursor(left: left) == f,
      enabled: _hasNotes,
      run: (h) => h.apply((e) => left ? e.setFinger(left: f) : e.setFinger(right: f)),
    );

ToolDef _pedal(int p, String de, String en) => ToolDef(
  id: 'pedal-$p',
  group: ToolGroup.expression,
  look: p == 2 ? const GlyphLook('\uE655', size: 26, dy: 4) : const GlyphLook('\uE650', size: 24, dy: 4),
  de: de,
  en: en,
  keywords: const ['pedal', 'klavier', 'piano', 'halten', 'sustain', 'ped'],
  active: (e) => e.currentBeat?.pedal == p,
  enabled: _hasBeat,
  run: (h) => h.apply((e) => e.setPedal(p)),
);

ToolDef _dynamic(core.Dynamic d, String glyph) => ToolDef(
  id: 'dyn-${d.name}',
  group: ToolGroup.expression,
  look: GlyphLook(glyph, size: 24, dy: 2),
  de: 'Dynamik ${d.name}',
  en: 'Dynamic ${d.name}',
  keywords: const ['laut', 'leise', 'loud', 'soft', 'dynamik'],
  active: (e) => e.currentBeat?.dynamic == d,
  enabled: _hasBeat,
  run: (h) => h.apply((e) => e.setDynamic(e.currentBeat?.dynamic == d ? null : d)),
);

/// Alle Werkzeuge, nach Gruppen geordnet.
final List<ToolDef> allTools = [
  // ── Notenwert ──
  _duration(core.NoteValue.whole, '\uECA2', 'Ganze', 'Whole note', '−'),
  _duration(core.NoteValue.half, '\uECA3', 'Halbe', 'Half note', '−'),
  _duration(core.NoteValue.quarter, '\uECA5', 'Viertel', 'Quarter note', '+ / −'),
  _duration(core.NoteValue.eighth, '\uECA7', 'Achtel', 'Eighth note', '+'),
  _duration(core.NoteValue.sixteenth, '\uECA9', 'Sechzehntel', 'Sixteenth note', '+'),
  _duration(core.NoteValue.thirtySecond, '\uECAB', 'Zweiunddreissigstel', 'Thirty-second note', '+'),
  ToolDef(
    id: 'dot',
    group: ToolGroup.notes,
    look: const GlyphLook('\uECB7', size: 34, dy: 4),
    de: 'Punkt (punktiert)',
    en: 'Dot (dotted)',
    shortcut: '.',
    active: (e) => (e.currentBeat?.duration.dots ?? e.duration.dots) > 0,
    run: (h) => h.apply((e) => e.toggleDot()),
  ),
  ToolDef(
    id: 'double-dot',
    group: ToolGroup.notes,
    look: const GlyphLook('\uECB7\uE1E7', size: 34, dy: 4),
    de: 'Doppelpunkt',
    en: 'Double dot',
    keywords: const ['punktiert', 'dotted'],
    active: (e) => (e.currentBeat?.duration.dots ?? e.duration.dots) == 2,
    run: (h) => h.apply((e) => e.toggleDoubleDot()),
  ),
  ToolDef(
    id: 'triplet',
    group: ToolGroup.notes,
    look: const GlyphLook('\uE883', size: 20),
    de: 'Triole',
    en: 'Triplet',
    shortcut: 'T',
    keywords: const ['tuplet', 'n-tole'],
    active: (e) => e.currentBeat?.duration.tuplet?.actual == 3,
    enabled: _hasBeat,
    run: (h) => h.apply((e) => e.toggleTriplet()),
  ),
  ToolDef(
    id: 'tuplet-5',
    group: ToolGroup.notes,
    look: const GlyphLook('\uE885', size: 20),
    de: 'Quintole',
    en: 'Quintuplet',
    keywords: const ['tuplet', 'n-tole', 'tole'],
    active: (e) => e.currentBeat?.duration.tuplet?.actual == 5,
    enabled: _hasBeat,
    run: (h) => h.apply((e) => e.toggleTuplet(5)),
  ),
  ToolDef(
    id: 'tuplet-6',
    group: ToolGroup.notes,
    look: const GlyphLook('\uE886', size: 20),
    de: 'Sextole',
    en: 'Sextuplet',
    keywords: const ['tuplet', 'n-tole', 'tole'],
    active: (e) => e.currentBeat?.duration.tuplet?.actual == 6,
    enabled: _hasBeat,
    run: (h) => h.apply((e) => e.toggleTuplet(6)),
  ),
  ToolDef(
    id: 'tuplet-7',
    group: ToolGroup.notes,
    look: const GlyphLook('\uE887', size: 20),
    de: 'Septole',
    en: 'Septuplet',
    keywords: const ['tuplet', 'n-tole', 'tole'],
    active: (e) => e.currentBeat?.duration.tuplet?.actual == 7,
    enabled: _hasBeat,
    run: (h) => h.apply((e) => e.toggleTuplet(7)),
  ),
  ToolDef(
    id: 'grace',
    group: ToolGroup.notes,
    look: const GlyphLook('\uE560', size: 24, dy: 2),
    de: 'Vorschlagsnote (die nächste Note) / entfernen',
    en: 'Grace note (the next note) / remove',
    keywords: const ['vorschlag', 'grace', 'acciaccatura', 'appoggiatura'],
    active: (e) => e.graceNext || e.hasGraceBefore,
    run: (h) => h.apply((e) => e.toggleGrace()),
  ),
  ToolDef(
    id: 'rest',
    group: ToolGroup.notes,
    look: const GlyphLook('\uE4E5', size: 24, dy: 4),
    de: 'Pause',
    en: 'Rest',
    shortcut: 'Entf',
    keywords: const ['löschen', 'delete'],
    active: (e) => e.currentBeat?.isRest ?? false,
    run: (h) => h.apply((e) => e.toRest()),
  ),
  ToolDef(
    id: 'tie',
    group: ToolGroup.notes,
    look: const TextLook('‿'),
    de: 'Haltebogen zum vorigen Ton',
    en: 'Tie to the previous note',
    shortcut: 'L',
    keywords: const ['bindebogen', 'tie'],
    active: (e) => (e.currentBeat?.notes.isNotEmpty ?? false) && e.currentBeat!.notes.every((n) => n.tieDestination),
    enabled: _hasBeat,
    run: (h) => h.apply((e) => e.toggleTie(), sound: true),
  ),
  ToolDef(
    id: 'up',
    group: ToolGroup.notes,
    look: const IconLook(Icons.north_rounded),
    de: 'Halbton höher',
    en: 'Semitone up',
    shortcut: 'Umschalt+↑',
    keywords: const ['kreuz', 'sharp', 'transponieren'],
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.transposeSelection(1), sound: true),
  ),
  ToolDef(
    id: 'down',
    group: ToolGroup.notes,
    look: const IconLook(Icons.south_rounded),
    de: 'Halbton tiefer',
    en: 'Semitone down',
    shortcut: 'Umschalt+↓',
    keywords: const ['b', 'flat', 'transponieren'],
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.transposeSelection(-1), sound: true),
  ),
  ToolDef(
    id: 'acc-sharp',
    group: ToolGroup.notes,
    look: const GlyphLook('\uE262', size: 22, dy: 2),
    de: 'Kreuz ♯',
    en: 'Sharp ♯',
    keywords: const ['vorzeichen', 'accidental', 'erhöhen'],
    active: (e) => _accidentalIs(e, 1),
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.setAccidental(1), sound: true),
  ),
  ToolDef(
    id: 'acc-flat',
    group: ToolGroup.notes,
    look: const GlyphLook('\uE260', size: 22, dy: 2),
    de: 'Be ♭',
    en: 'Flat ♭',
    keywords: const ['vorzeichen', 'accidental', 'erniedrigen'],
    active: (e) => _accidentalIs(e, -1),
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.setAccidental(-1), sound: true),
  ),
  ToolDef(
    id: 'acc-natural',
    group: ToolGroup.notes,
    look: const GlyphLook('\uE261', size: 22, dy: 2),
    de: 'Auflösungszeichen ♮',
    en: 'Natural ♮',
    keywords: const ['vorzeichen', 'accidental', 'auflösen'],
    active: (e) => _accidentalIs(e, 0),
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.setAccidental(0), sound: true),
  ),
  ToolDef(
    id: 'acc-dsharp',
    group: ToolGroup.notes,
    look: const GlyphLook('\uE263', size: 22, dy: 2),
    de: 'Doppelkreuz 𝄪',
    en: 'Double sharp 𝄪',
    keywords: const ['vorzeichen', 'accidental'],
    active: (e) => _accidentalIs(e, 2),
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.setAccidental(2), sound: true),
  ),
  ToolDef(
    id: 'acc-dflat',
    group: ToolGroup.notes,
    look: const GlyphLook('\uE264', size: 22, dy: 2),
    de: 'Doppel-Be 𝄫',
    en: 'Double flat 𝄫',
    keywords: const ['vorzeichen', 'accidental'],
    active: (e) => _accidentalIs(e, -2),
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.setAccidental(-2), sound: true),
  ),
  ToolDef(
    id: 'acc-courtesy',
    group: ToolGroup.notes,
    look: const GlyphLook('\uE26A\uE261\uE26B', size: 20, dy: 2),
    de: 'Vorzeichen zur Erinnerung (in Klammern)',
    en: 'Courtesy accidental (in brackets)',
    keywords: const ['vorzeichen', 'klammer', 'warnung', 'courtesy', 'cautionary'],
    active: (e) => e.currentBeat?.notes.any((n) => n.courtesy) ?? false,
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.toggleCourtesy()),
  ),
  ToolDef(
    id: 'next',
    group: ToolGroup.notes,
    look: const IconLook(Icons.arrow_forward_rounded),
    de: 'Weiter zum nächsten Schlag',
    en: 'Next beat',
    shortcut: '→',
    run: (h) => h.apply((e) => e.moveBeat(1)),
  ),
  ToolDef(
    id: 'pen',
    group: ToolGroup.notes,
    look: const IconLook(Icons.edit_outlined),
    de: 'Maus und Finger schreiben wie der Stift',
    en: 'Mouse and finger write like the pen',
    keywords: const ['stift', 'pen', 'zeichnen', 'maus', 'finger', 'gesten', 'gestures'],
    active: (e) => false,
    run: (h) => h.penNotes = !h.penNotes,
  ),
  ToolDef(
    id: 'mic',
    group: ToolGroup.notes,
    look: const IconLook(Icons.mic_none_rounded),
    de: 'Vorspielen: Töne über das Mikrofon schreiben',
    en: 'Play in: write notes through the microphone',
    shortcut: 'M',
    keywords: const ['mikrofon', 'microphone', 'vorspielen', 'spielen', 'hören', 'tonerkennung', 'listen'],
    run: (h) => h.toggleMic(),
  ),

  for (var v = 0; v < 4; v++)
    ToolDef(
      id: 'voice-${v + 1}',
      group: ToolGroup.notes,
      look: TextLook('${v + 1}'),
      de: 'Stimme ${v + 1}${v == 1 ? ' (z. B. Bass mit Hälsen nach unten)' : ''}',
      en: 'Voice ${v + 1}${v == 1 ? ' (e.g. bass with stems down)' : ''}',
      shortcut: 'Alt+${v + 1}',
      keywords: const ['stimme', 'voice', 'zweistimmig', 'mehrstimmig', 'bass', 'polyphon'],
      active: (e) => e.voice == v,
      run: (h) => h.apply((e) => e.setVoice(v)),
    ),
  // ── Schlagzeug ──
  for (final (key, look, de, en) in const [
    (36, 'BD', 'Bassdrum', 'Bass drum'),
    (38, 'SD', 'Snare', 'Snare'),
    (37, 'Rim', 'Rimshot (Sidestick)', 'Side stick'),
    (39, 'Clap', 'Klatschen', 'Hand clap'),
    (42, 'HH', 'Hi-Hat geschlossen', 'Hi-hat closed'),
    (46, 'HH○', 'Hi-Hat offen', 'Hi-hat open'),
    (44, 'HH↓', 'Hi-Hat mit dem Fuss', 'Hi-hat pedal'),
    (51, 'Ride', 'Ride', 'Ride'),
    (49, 'Crash', 'Crash', 'Crash'),
    (50, 'T1', 'Tom hoch', 'High tom'),
    (47, 'T2', 'Tom mittel', 'Mid tom'),
    (43, 'T3', 'Standtom', 'Floor tom'),
  ])
    ToolDef(
      id: 'drum-$key',
      group: ToolGroup.drums,
      look: TextLook(look),
      de: de,
      en: en,
      keywords: const ['schlagzeug', 'drums', 'drum', 'perkussion', 'percussion'],
      drumsOnly: true,
      active: (e) => e.hasDrum(key),
      enabled: (e) => e.currentBeat != null,
      run: (h) => h.apply((e) => e.inputDrum(key), sound: true),
    ),
  // ── Gitarre ──
  _tech(
    core.Technique.hammer,
    const TextLook('H/P'),
    'Hammer-on / Pull-off',
    'Hammer-on / pull-off',
    keywords: const ['legato', 'bogen'],
  ),
  _tech(
    core.Technique.slide,
    const TextLook('⟋'),
    'Slide zur nächsten Note',
    'Slide to the next note',
    keywords: const ['gleiten', 'rutschen'],
  ),
  _tech(
    core.Technique.shiftSlide,
    const TextLook('S⟋'),
    'Slide zur nächsten Note (neu angeschlagen)',
    'Shift slide (picked again)',
    keywords: const ['gleiten', 'rutschen', 'shift'],
  ),
  _tech(
    core.Technique.slideInBelow,
    const TextLook('⟋•'),
    'Hineingleiten von unten',
    'Slide in from below',
    keywords: const ['gleiten', 'slide in'],
  ),
  _tech(
    core.Technique.slideInAbove,
    const TextLook('⟍•'),
    'Hineingleiten von oben',
    'Slide in from above',
    keywords: const ['gleiten', 'slide in'],
  ),
  _tech(
    core.Technique.slideOutDown,
    const TextLook('•⟍'),
    'Hinausgleiten nach unten',
    'Slide out downwards',
    keywords: const ['gleiten', 'slide out'],
  ),
  _tech(
    core.Technique.slideOutUp,
    const TextLook('•⟋'),
    'Hinausgleiten nach oben',
    'Slide out upwards',
    keywords: const ['gleiten', 'slide out'],
  ),
  _tech(
    core.Technique.bendHalf,
    const TextLook('½↑'),
    'Bending um einen Halbton',
    'Bend a semitone',
    keywords: const ['ziehen', 'bend'],
  ),
  _tech(
    core.Technique.bend,
    const TextLook('1↑'),
    'Bending um einen Ganzton',
    'Bend a whole tone',
    keywords: const ['ziehen', 'bend', 'full'],
  ),
  _tech(core.Technique.vibrato, const GlyphLook('\uEAB0', size: 34, dy: 9), 'Vibrato', 'Vibrato'),
  _tech(
    core.Technique.wideVibrato,
    const GlyphLook('\uEAB3\uEAB3', size: 26, dy: 4),
    'Weites Vibrato',
    'Wide vibrato',
    keywords: const ['vibrato', 'wide'],
  ),
  _tech(
    core.Technique.palmMute,
    const TextLook('P.M.', italic: true),
    'Palm Mute (abgedämpft)',
    'Palm mute',
    keywords: const ['dämpfen', 'pm'],
  ),
  _tech(core.Technique.letRing, const TextLook('L.R.', italic: true), 'Let ring (klingen lassen)', 'Let ring'),
  _tech(
    core.Technique.dead,
    const GlyphLook('\uE0A9', size: 32, dy: 6),
    'Gedämpfte Note (x)',
    'Dead note (x)',
    keywords: const ['x', 'tot', 'muted'],
  ),
  _tech(
    core.Technique.harmonic,
    const GlyphLook('\uE0DD', size: 32, dy: 6),
    'Flageolett',
    'Harmonic',
    keywords: const ['harmonic', 'oberton'],
  ),
  _tech(
    core.Technique.artificialHarmonic,
    const TextLook('A.H.'),
    'Künstliches Flageolett',
    'Artificial harmonic',
    keywords: const ['harmonic', 'oberton', 'flageolett', 'ah'],
  ),
  _tech(
    core.Technique.pinchHarmonic,
    const TextLook('P.H.'),
    'Pinch Harmonic (gezupftes Flageolett)',
    'Pinch harmonic',
    keywords: const ['harmonic', 'oberton', 'flageolett', 'pinch', 'ph'],
  ),
  _tech(core.Technique.tapping, const TextLook('T'), 'Tapping', 'Tapping'),
  _tech(core.Technique.slap, const TextLook('S'), 'Slap (geschlagen)', 'Slap', keywords: const ['bass', 'daumen']),
  _tech(core.Technique.pop, const TextLook('P'), 'Pop (gezupft und schnalzen)', 'Pop', keywords: const ['bass']),
  ToolDef(
    id: 'tremolo-picking',
    group: ToolGroup.guitar,
    look: const GlyphLook('\uE222', size: 26, dy: 4),
    de: 'Tremolo-Picking (schnell wiederholt)',
    en: 'Tremolo picking',
    keywords: const ['tremolo', 'wiederholen', 'schnell'],
    stringedOnly: true,
    active: (e) => (e.currentBeat?.tremolo ?? 0) > 0,
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.toggleTremolo()),
  ),
  ToolDef(
    id: 'whammy',
    group: ToolGroup.guitar,
    look: const TextLook('w/b', italic: true),
    de: 'Tremolo-Hebel: kurz einen Halbton hinunter',
    en: 'Whammy bar: dip a semitone',
    keywords: const ['whammy', 'hebel', 'dip', 'vibratohebel'],
    stringedOnly: true,
    active: (e) => (e.currentBeat?.whammy ?? 0) != 0,
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.setWhammy(-1), sound: true),
  ),
  ToolDef(
    id: 'arpeggio-up',
    group: ToolGroup.guitar,
    look: const GlyphLook('\uE634', size: 24, dy: 4),
    de: 'Akkord gebrochen, aufwärts',
    en: 'Arpeggio up',
    keywords: const ['arpeggio', 'brechen', 'brush', 'gebrochen'],
    active: (e) => e.currentBeat?.arpeggio == 1,
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.setArpeggio(1), sound: true),
  ),
  ToolDef(
    id: 'arpeggio-down',
    group: ToolGroup.guitar,
    look: const GlyphLook('\uE635', size: 24, dy: 4),
    de: 'Akkord gebrochen, abwärts',
    en: 'Arpeggio down',
    keywords: const ['arpeggio', 'brechen', 'brush', 'gebrochen'],
    active: (e) => e.currentBeat?.arpeggio == -1,
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.setArpeggio(-1), sound: true),
  ),
  _finger(1, '\uED11', 'Finger 1 (Zeigefinger)', 'Finger 1 (index)', left: true),
  _finger(2, '\uED12', 'Finger 2 (Mittelfinger)', 'Finger 2 (middle)', left: true),
  _finger(3, '\uED13', 'Finger 3 (Ringfinger)', 'Finger 3 (ring)', left: true),
  _finger(4, '\uED14', 'Finger 4 (kleiner Finger)', 'Finger 4 (little)', left: true),
  _finger(5, '\uED16', 'Daumen (T)', 'Thumb (T)', left: true),
  _finger(1, '\uED17', 'p – Daumen (Anschlag)', 'p – thumb (picking)', left: false),
  _finger(2, '\uED19', 'i – Zeigefinger (Anschlag)', 'i – index (picking)', left: false),
  _finger(3, '\uED1A', 'm – Mittelfinger (Anschlag)', 'm – middle (picking)', left: false),
  _finger(4, '\uED1B', 'a – Ringfinger (Anschlag)', 'a – ring (picking)', left: false),
  _finger(5, '\uED1C', 'c – kleiner Finger (Anschlag)', 'c – little finger (picking)', left: false),
  ToolDef(
    id: 't-stringNumber',
    group: ToolGroup.finger,
    look: const TextLook('③'),
    de: 'Saitennummer im Kreis',
    en: 'String number in a circle',
    keywords: const ['saite', 'string', 'kreis', 'circle', 'nummer'],
    stringedOnly: true,
    active: (e) => e.hasTechnique(core.Technique.stringNumber),
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.toggleTechnique(core.Technique.stringNumber)),
  ),
  _pedal(1, 'Pedal treten (Ped.)', 'Pedal down (Ped.)'),
  _pedal(2, 'Pedal loslassen (*)', 'Pedal up (*)'),
  _pedal(3, 'Pedal wechseln (* Ped.)', 'Change pedal (* Ped.)'),
  ToolDef(
    id: 'rasgueado',
    group: ToolGroup.guitar,
    look: const TextLook('rasg.', italic: true),
    de: 'Rasgueado',
    en: 'Rasgueado',
    keywords: const ['flamenco', 'fächer', 'strum'],
    stringedOnly: true,
    active: (e) => e.currentBeat?.rasgueado ?? false,
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.toggleRasgueado(), sound: true),
  ),
  ToolDef(
    id: 'stroke-down',
    group: ToolGroup.guitar,
    look: const GlyphLook('\uE610', size: 30, dy: 7),
    de: 'Anschlag abwärts',
    en: 'Downstroke',
    keywords: const ['pick', 'plektrum', 'strum'],
    stringedOnly: true,
    active: (e) => e.currentBeat?.pickStroke == 1,
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.togglePickStroke(1)),
  ),
  ToolDef(
    id: 'stroke-up',
    group: ToolGroup.guitar,
    look: const GlyphLook('\uE612', size: 30, dy: 6),
    de: 'Anschlag aufwärts',
    en: 'Upstroke',
    keywords: const ['pick', 'plektrum', 'strum'],
    stringedOnly: true,
    active: (e) => e.currentBeat?.pickStroke == -1,
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.togglePickStroke(-1)),
  ),

  // ── Ausdruck ──
  _dynamic(core.Dynamic.ppp, '\uE52A'),
  _dynamic(core.Dynamic.pp, '\uE52B'),
  _dynamic(core.Dynamic.p, '\uE520'),
  _dynamic(core.Dynamic.mp, '\uE52C'),
  _dynamic(core.Dynamic.mf, '\uE52D'),
  _dynamic(core.Dynamic.f, '\uE522'),
  _dynamic(core.Dynamic.ff, '\uE52F'),
  _dynamic(core.Dynamic.fff, '\uE530'),
  ToolDef(
    id: 'cresc',
    group: ToolGroup.expression,
    look: const GlyphLook('\uE53E', size: 22, dy: 2),
    de: 'Crescendo (lauter werden)',
    en: 'Crescendo',
    keywords: const ['gabel', 'hairpin'],
    active: (e) => e.currentBeat?.hairpin == core.Hairpin.crescendo,
    enabled: _hasBeat,
    run: (h) => h.apply((e) => e.toggleHairpin(core.Hairpin.crescendo)),
  ),
  ToolDef(
    id: 'decresc',
    group: ToolGroup.expression,
    look: const GlyphLook('\uE53F', size: 22, dy: 2),
    de: 'Decrescendo (leiser werden)',
    en: 'Decrescendo',
    keywords: const ['gabel', 'hairpin', 'diminuendo'],
    active: (e) => e.currentBeat?.hairpin == core.Hairpin.decrescendo,
    enabled: _hasBeat,
    run: (h) => h.apply((e) => e.toggleHairpin(core.Hairpin.decrescendo)),
  ),
  _tech(core.Technique.accent, const GlyphLook('\uE4A0', size: 32, dy: 9), 'Akzent', 'Accent', guitar: false),
  _tech(core.Technique.staccato, const GlyphLook('\uE4A2', size: 44, dy: 13), 'Staccato', 'Staccato', guitar: false),
  _tech(core.Technique.tenuto, const GlyphLook('\uE4A4', size: 36, dy: 12), 'Tenuto', 'Tenuto', guitar: false),
  _tech(core.Technique.marcato, const GlyphLook('\uE4AC', size: 30, dy: 9), 'Marcato', 'Marcato', guitar: false),
  _tech(core.Technique.ghost, const TextLook('( )'), 'Geisternote', 'Ghost note', guitar: false),
  _tech(core.Technique.trill, const GlyphLook('\uE566', size: 26, dy: 4), 'Triller', 'Trill', guitar: false),
  for (final (f, glyph, de, en) in [
    (1, '\uE843', 'Einblenden (Fade-in)', 'Fade in'),
    (2, '\uE844', 'Ausblenden (Fade-out)', 'Fade out'),
    (3, '\uE845', 'Anschwellen (Volume Swell)', 'Volume swell'),
  ])
    ToolDef(
      id: 'fade-$f',
      group: ToolGroup.expression,
      look: GlyphLook(glyph, size: 22, dy: 2),
      de: de,
      en: en,
      keywords: const ['lautstärke', 'volume', 'fade', 'swell', 'einblenden', 'ausblenden'],
      active: (e) => e.currentBeat?.fade == f,
      enabled: _hasNotes,
      run: (h) => h.apply((e) => e.setFade(f)),
    ),
  ToolDef(
    id: 'fermata',
    group: ToolGroup.expression,
    look: const GlyphLook('\uE4C0', size: 28, dy: 8),
    de: 'Fermate',
    en: 'Fermata',
    active: (e) => e.currentBeat?.fermata ?? false,
    enabled: _hasBeat,
    run: (h) => h.apply((e) => e.toggleFermata()),
  ),
  ToolDef(
    id: 'ottava-8va',
    group: ToolGroup.expression,
    look: const GlyphLook('\uE511', size: 18, dy: 2),
    de: '8va (eine Oktave höher spielen)',
    en: '8va (play an octave higher)',
    keywords: const ['oktave', 'octave', 'ottava', '8va', '8vb', '15ma', '15mb'],
    active: (e) => e.currentBeat?.ottava == 1,
    enabled: _hasBeat,
    run: (h) => h.apply((e) => e.setOttava(1)),
  ),
  ToolDef(
    id: 'ottava-8vb',
    group: ToolGroup.expression,
    look: const GlyphLook('\uE51C', size: 18, dy: 2),
    de: '8vb (eine Oktave tiefer spielen)',
    en: '8vb (play an octave lower)',
    keywords: const ['oktave', 'octave', 'ottava', '8va', '8vb', '15ma', '15mb'],
    active: (e) => e.currentBeat?.ottava == -1,
    enabled: _hasBeat,
    run: (h) => h.apply((e) => e.setOttava(-1)),
  ),
  ToolDef(
    id: 'ottava-15ma',
    group: ToolGroup.expression,
    look: const GlyphLook('\uE515', size: 18, dy: 2),
    de: '15ma (zwei Oktaven höher)',
    en: '15ma (two octaves higher)',
    keywords: const ['oktave', 'octave', 'ottava', '8va', '8vb', '15ma', '15mb'],
    active: (e) => e.currentBeat?.ottava == 2,
    enabled: _hasBeat,
    run: (h) => h.apply((e) => e.setOttava(2)),
  ),
  ToolDef(
    id: 'ottava-15mb',
    group: ToolGroup.expression,
    look: const GlyphLook('\uE51D', size: 18, dy: 2),
    de: '15mb (zwei Oktaven tiefer)',
    en: '15mb (two octaves lower)',
    keywords: const ['oktave', 'octave', 'ottava', '8va', '8vb', '15ma', '15mb'],
    active: (e) => e.currentBeat?.ottava == -2,
    enabled: _hasBeat,
    run: (h) => h.apply((e) => e.setOttava(-2)),
  ),

  // ── Takt ──
  ToolDef(
    id: 'bar-before',
    group: ToolGroup.bar,
    look: const IconLook(Icons.first_page_rounded),
    de: 'Takt davor einfügen',
    en: 'Insert bar before',
    keywords: const ['neu', 'new'],
    run: (h) => h.apply((e) => e.insertBars(after: false)),
  ),
  ToolDef(
    id: 'bar-after',
    group: ToolGroup.bar,
    look: const IconLook(Icons.last_page_rounded),
    de: 'Takt danach einfügen',
    en: 'Insert bar after',
    keywords: const ['neu', 'new'],
    run: (h) => h.apply((e) => e.insertBars()),
  ),
  ToolDef(
    id: 'bar-delete',
    group: ToolGroup.bar,
    look: const IconLook(Icons.delete_outline),
    de: 'Takt löschen (bzw. ausgewählte Takte)',
    en: 'Delete bar (or selected bars)',
    keywords: const ['entfernen', 'remove'],
    run: (h) => h.apply((e) => e.deleteBars()),
  ),
  ToolDef(
    id: 'time',
    group: ToolGroup.bar,
    look: const GlyphLook('\uE084\n\uE084', size: 15, dy: 0),
    de: 'Taktart …',
    en: 'Time signature …',
    keywords: const ['4/4', '3/4', '6/8', 'takt'],
    run: (h) => h.editTimeSignature(),
  ),
  ToolDef(
    id: 'key',
    group: ToolGroup.bar,
    look: const GlyphLook('\uE262\uE260', size: 18, dy: 2),
    de: 'Tonart …',
    en: 'Key …',
    keywords: const ['dur', 'moll', 'major', 'minor', 'vorzeichen'],
    run: (h) => h.editKey(),
  ),
  ToolDef(
    id: 'tempo',
    group: ToolGroup.bar,
    look: const GlyphLook('\uECA5', size: 22, dy: 4),
    de: 'Tempo …',
    en: 'Tempo …',
    keywords: const ['bpm', 'schnell', 'langsam'],
    run: (h) => h.editTempo(),
  ),
  ToolDef(
    id: 'repeat-start',
    group: ToolGroup.bar,
    look: const GlyphLook('\uE040', size: 24, dy: 4),
    de: 'Wiederholung: Anfang',
    en: 'Repeat: start',
    keywords: const ['wiederholen', 'repeat'],
    active: (e) => e.score.masterBars[e.cursor.bar].repeatStart,
    run: (h) => h.apply((e) => e.toggleRepeatStart()),
  ),
  ToolDef(
    id: 'repeat-end',
    group: ToolGroup.bar,
    look: const GlyphLook('\uE041', size: 24, dy: 4),
    de: 'Wiederholung: Ende …',
    en: 'Repeat: end …',
    keywords: const ['wiederholen', 'repeat'],
    active: (e) => e.score.masterBars[e.cursor.bar].hasRepeatEnd,
    run: (h) => h.editRepeatEnd(),
  ),
  ToolDef(
    id: 'endings',
    group: ToolGroup.bar,
    look: const TextLook('1.'),
    de: 'Häuser (1., 2. …) …',
    en: 'Endings (1st, 2nd …) …',
    keywords: const ['haus', 'volta', 'klammer', 'ending', 'ausgang'],
    active: (e) => e.score.masterBars[e.cursor.bar].endings.isNotEmpty,
    run: (h) => h.editEndings(),
  ),
  ToolDef(
    id: 'segno',
    group: ToolGroup.bar,
    look: const GlyphLook('\uE047', size: 22, dy: 2),
    de: 'Segno',
    en: 'Segno',
    keywords: const ['dal segno', 'zeichen', 'sprung'],
    active: (e) => e.score.masterBars[e.cursor.bar].directions.contains(core.Direction.segno),
    run: (h) => h.apply((e) => e.toggleDirection(core.Direction.segno)),
  ),
  ToolDef(
    id: 'coda',
    group: ToolGroup.bar,
    look: const GlyphLook('\uE048', size: 22, dy: 2),
    de: 'Coda',
    en: 'Coda',
    keywords: const ['schluss', 'sprung'],
    active: (e) => e.score.masterBars[e.cursor.bar].directions.contains(core.Direction.coda),
    run: (h) => h.apply((e) => e.toggleDirection(core.Direction.coda)),
  ),
  ToolDef(
    id: 'jumps',
    group: ToolGroup.bar,
    look: const TextLook('D.C.', italic: true),
    de: 'D.C., D.S., Fine, To Coda …',
    en: 'D.C., D.S., Fine, To Coda …',
    keywords: const ['da capo', 'dal segno', 'fine', 'sprung', 'jump', 'al coda'],
    active: (e) =>
        e.score.masterBars[e.cursor.bar].directions.any((d) => d != core.Direction.segno && d != core.Direction.coda),
    run: (h) => h.editJumps(),
  ),
  ToolDef(
    id: 'simile-1',
    group: ToolGroup.bar,
    look: const GlyphLook('\uE500', size: 22, dy: 2),
    de: 'Wie der Takt davor (%)',
    en: 'Same as the bar before (%)',
    keywords: const ['wiederholen', 'prozent', 'simile', 'repeat bar'],
    active: (e) => e.score.tracks[e.track].bars[e.cursor.bar].simile == 1,
    run: (h) => h.apply((e) => e.setSimile(e.score.tracks[e.track].bars[e.cursor.bar].simile == 1 ? 0 : 1)),
  ),
  ToolDef(
    id: 'simile-2',
    group: ToolGroup.bar,
    look: const GlyphLook('\uE501', size: 22, dy: 2),
    de: 'Wie die zwei Takte davor',
    en: 'Same as the two bars before',
    keywords: const ['wiederholen', 'prozent', 'simile', 'repeat bars'],
    active: (e) => e.score.tracks[e.track].bars[e.cursor.bar].simile >= 2,
    run: (h) => h.apply((e) => e.setSimile(e.score.tracks[e.track].bars[e.cursor.bar].simile >= 2 ? 0 : 2)),
  ),
  ToolDef(
    id: 'double-bar',
    group: ToolGroup.bar,
    look: const GlyphLook('\uE031', size: 24, dy: 4),
    de: 'Doppelstrich',
    en: 'Double bar line',
    active: (e) => e.score.masterBars[e.cursor.bar].doubleBar,
    run: (h) => h.apply((e) => e.toggleDoubleBar()),
  ),
  ToolDef(
    id: 'swing',
    group: ToolGroup.bar,
    look: const TextLook('Swing'),
    de: 'Swing ein/aus (ab hier)',
    en: 'Swing on/off (from here)',
    keywords: const ['jazz', 'triolen', 'achtel', 'shuffle', 'gerade', 'straight'],
    active: (e) => e.score.masterBars[e.cursor.bar].swing,
    run: (h) => h.apply((e) => e.setSwing(!e.score.masterBars[e.cursor.bar].swing)),
  ),
  ToolDef(
    id: 'section',
    group: ToolGroup.bar,
    look: const TextLook('[A]'),
    de: 'Formteil … (Intro, Strophe, Refrain)',
    en: 'Section … (intro, verse, chorus)',
    keywords: const ['refrain', 'strophe', 'chorus', 'verse', 'teil'],
    active: (e) => e.score.masterBars[e.cursor.bar].section != null,
    run: (h) => h.editSection(),
  ),

  // ── Schnell-Eingaben ──
  ToolDef(
    id: 'quick-chords',
    group: ToolGroup.quick,
    look: const TextLook('G|C'),
    de: 'Akkordzeile tippen …',
    en: 'Type a chord line …',
    keywords: const ['akkorde', 'chords', 'begleitung', 'harmonie', 'tippen'],
    run: (h) => h.quickChords(),
  ),
  ToolDef(
    id: 'quick-pattern',
    group: ToolGroup.quick,
    look: const TextLook('↓↑'),
    de: 'Begleitmuster (Anschlag, Zupfen) …',
    en: 'Strum or picking pattern …',
    keywords: const ['schlagmuster', 'strum', 'rhythmus', 'zupfen', 'picking', 'begleitung'],
    stringedOnly: true,
    run: (h) => h.quickPattern(),
  ),
  ToolDef(
    id: 'quick-lyrics',
    group: ToolGroup.quick,
    look: const IconLook(Icons.subject_rounded),
    de: 'Liedtext einfügen …',
    en: 'Paste lyrics …',
    keywords: const ['text', 'lyrics', 'silben', 'gesang', 'einfügen'],
    run: (h) => h.quickLyrics(),
  ),
  ToolDef(
    id: 'quick-section',
    group: ToolGroup.quick,
    look: const TextLook('[A]+'),
    de: 'Formteil wiederholen …',
    en: 'Repeat a section …',
    keywords: const ['refrain', 'strophe', 'kopieren', 'copy', 'chorus', 'verse'],
    enabled: (e) => e.sections.isNotEmpty,
    run: (h) => h.quickSection(),
  ),

  // ── Text ──
  ToolDef(
    id: 'chord',
    group: ToolGroup.text,
    look: const TextLook('Am⁷'),
    de: 'Akkordsymbol …',
    en: 'Chord symbol …',
    shortcut: 'K',
    keywords: const ['akkord', 'chord', 'griff'],
    active: (e) => e.currentBeat?.chordId != null,
    enabled: _hasBeat,
    run: (h) => h.editChord(),
  ),
  ToolDef(
    id: 'lyrics',
    group: ToolGroup.text,
    look: const IconLook(Icons.lyrics_outlined),
    de: 'Liedtext …',
    en: 'Lyrics …',
    shortcut: 'Y',
    keywords: const ['text', 'silbe', 'gesang'],
    active: (e) => e.currentBeat?.lyrics.isNotEmpty ?? false,
    enabled: _hasBeat,
    run: (h) => h.editLyrics(),
  ),
  ToolDef(
    id: 'text',
    group: ToolGroup.text,
    look: const IconLook(Icons.text_fields_rounded),
    de: 'Text über der Note …',
    en: 'Text above the note …',
    keywords: const ['hinweis', 'anmerkung'],
    active: (e) => e.currentBeat?.text != null,
    enabled: _hasBeat,
    run: (h) => h.editText(),
  ),

  // ── Stück ──
  ToolDef(
    id: 'save',
    group: ToolGroup.piece,
    look: const IconLook(Icons.save_outlined),
    de: 'Speichern',
    en: 'Save',
    shortcut: 'Strg+S',
    keywords: const ['sichern', 'datei', 'file'],
    run: (h) => h.save(),
  ),
  ToolDef(
    id: 'save-as',
    group: ToolGroup.piece,
    look: const IconLook(Icons.save_as_outlined),
    de: 'Speichern unter …',
    en: 'Save as …',
    shortcut: 'Strg+Umschalt+S',
    keywords: const ['sichern', 'datei', 'file', 'kopie'],
    run: (h) => h.saveAs(),
  ),
  ToolDef(
    id: 'open-another',
    group: ToolGroup.piece,
    look: const IconLook(Icons.tab_outlined),
    de: 'Weiteres Stück öffnen (neuer Reiter) …',
    en: 'Open another piece (new tab) …',
    shortcut: 'Strg+N',
    keywords: const ['reiter', 'tab', 'öffnen', 'open', 'stück', 'datei', 'mehrere', 'neu', 'new'],
    run: (h) => h.openPiece(),
  ),
  ToolDef(
    id: 'export',
    group: ToolGroup.piece,
    look: const IconLook(Icons.ios_share_rounded),
    de: 'Exportieren (PDF, MusicXML, MIDI) …',
    en: 'Export (PDF, MusicXML, MIDI) …',
    shortcut: 'Strg+E',
    keywords: const ['pdf', 'musicxml', 'midi', 'xml', 'ausgeben', 'teilen', 'share', 'weitergeben'],
    run: (h) => h.exportPiece(),
  ),
  ToolDef(
    id: 'print',
    group: ToolGroup.piece,
    look: const IconLook(Icons.print_outlined),
    de: 'Drucken …',
    en: 'Print …',
    shortcut: 'Strg+P',
    keywords: const ['drucker', 'papier', 'pdf', 'printer'],
    run: (h) => h.printPiece(),
  ),
  ToolDef(
    id: 'title',
    group: ToolGroup.piece,
    look: const IconLook(Icons.info_outline_rounded),
    de: 'Angaben zum Stück …',
    en: 'Piece information …',
    keywords: const [
      'titel',
      'title',
      'name',
      'künstler',
      'interpret',
      'album',
      'copyright',
      'text',
      'musik',
      'untertitel',
      'transkription',
      'anleitung',
      'bemerkung',
      'eigenschaften',
      'info',
    ],
    run: (h) => h.editTitle(),
  ),
  ToolDef(
    id: 'break-line',
    group: ToolGroup.bar,
    look: const IconLook(Icons.keyboard_return_rounded),
    de: 'Neue Zeile nach diesem Takt',
    en: 'New line after this bar',
    keywords: const ['umbruch', 'zeilenumbruch', 'break', 'line break', 'zeile', 'layout'],
    active: (e) => e.score.masterBars[e.cursor.bar].breakAfter == 1,
    run: (h) => h.apply((e) => e.setBreak(e.cursor.bar, e.score.masterBars[e.cursor.bar].breakAfter == 1 ? 0 : 1)),
  ),
  ToolDef(
    id: 'break-page',
    group: ToolGroup.bar,
    look: const IconLook(Icons.vertical_align_bottom_rounded),
    de: 'Neue Seite nach diesem Takt',
    en: 'New page after this bar',
    keywords: const ['umbruch', 'seitenumbruch', 'page break', 'seite', 'layout'],
    active: (e) => e.score.masterBars[e.cursor.bar].breakAfter == 2,
    run: (h) => h.apply((e) => e.setBreak(e.cursor.bar, e.score.masterBars[e.cursor.bar].breakAfter == 2 ? 0 : 2)),
  ),
  ToolDef(
    id: 'page-setup',
    group: ToolGroup.piece,
    look: const IconLook(Icons.description_outlined),
    de: 'Seite einrichten …',
    en: 'Page setup …',
    keywords: const [
      'seite',
      'page',
      'papier',
      'paper',
      'rand',
      'margin',
      'notengrösse',
      'staff size',
      'quer',
      'landscape',
      'takte pro zeile',
      'taktnummer',
      'seitenzahl',
      'layout',
    ],
    run: (h) => h.editPageSetup(),
  ),
  ToolDef(
    id: 'chord-style',
    group: ToolGroup.piece,
    look: const TextLook('C⁷'),
    de: 'Akkordsymbole einstellen …',
    en: 'Chord symbol settings …',
    keywords: const ['akkord', 'chord', 'moll', 'minor', 'maj7', 'sus', 'griffbild', 'diagram', 'schreibweise'],
    run: (h) => h.editChordStyle(),
  ),
  ToolDef(
    id: 'transpose',
    group: ToolGroup.piece,
    look: const IconLook(Icons.swap_vert_rounded),
    de: 'Ganzes Stück transponieren …',
    en: 'Transpose the whole piece …',
    keywords: const ['tonart', 'höher', 'tiefer', 'key'],
    run: (h) => h.editTranspose(),
  ),
  ToolDef(
    id: 'tuning',
    group: ToolGroup.piece,
    look: const IconLook(Icons.tune_rounded),
    de: 'Stimmung und Kapo …',
    en: 'Tuning and capo …',
    keywords: const ['drop', 'capo', 'saiten', 'strings', 'open'],
    stringedOnly: true,
    run: (h) => h.editTuning(),
  ),
  ToolDef(
    id: 'track-sound',
    group: ToolGroup.piece,
    look: const IconLook(Icons.music_note_rounded),
    de: 'Klang der Spur …',
    en: 'Track sound …',
    keywords: const ['instrument', 'sound', 'midi', 'klangfarbe'],
    run: (h) => h.editTrackSound(h.editor.track),
  ),
  ToolDef(
    id: 'track-add',
    group: ToolGroup.piece,
    look: const IconLook(Icons.playlist_add_rounded),
    de: 'Spur hinzufügen …',
    en: 'Add track …',
    keywords: const ['instrument', 'bass', 'gitarre', 'melodie', 'track'],
    run: (h) => h.addTrack(),
  ),
  ToolDef(
    id: 'copy',
    group: ToolGroup.piece,
    look: const IconLook(Icons.content_copy_rounded),
    de: 'Kopieren',
    en: 'Copy',
    shortcut: 'Strg+C',
    run: (h) => h.copy(),
  ),
  ToolDef(
    id: 'cut',
    group: ToolGroup.piece,
    look: const IconLook(Icons.content_cut_rounded),
    de: 'Ausschneiden',
    en: 'Cut',
    shortcut: 'Strg+X',
    run: (h) => h.cut(),
  ),
  ToolDef(
    id: 'paste',
    group: ToolGroup.piece,
    look: const IconLook(Icons.content_paste_rounded),
    de: 'Einfügen',
    en: 'Paste',
    shortcut: 'Strg+V',
    run: (h) => h.paste(),
  ),
];

/// Werkzeugspalte links: Suchfeld, Gruppen (einklappbar), Werkzeuge als Zeichen
/// mit schnell erscheinendem Hinweis.
class ToolPanel extends StatefulWidget {
  const ToolPanel({super.key, required this.host, required this.open, required this.onToggleGroup});
  final ToolHost host;

  /// Offene Gruppen.
  final Set<ToolGroup> open;
  final ValueChanged<ToolGroup> onToggleGroup;

  @override
  State<ToolPanel> createState() => _ToolPanelState();
}

class _ToolPanelState extends State<ToolPanel> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final e = widget.host.editor;
    final q = _search.text;
    final tools = [
      for (final t in allTools)
        if (t.fits(e) && t.matches(q)) t,
    ];
    return Material(
      color: c.card,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
        children: [
          SizedBox(
            height: 36,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: tr('Werkzeug suchen …', 'Find a tool …'),
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(_search.clear)),
              ),
            ),
          ),
          for (final g in ToolGroup.values)
            if (tools.any((t) => t.group == g)) ..._group(context, g, tools.where((t) => t.group == g).toList(), q),
        ],
      ),
    );
  }

  List<Widget> _group(BuildContext context, ToolGroup g, List<ToolDef> tools, String q) {
    final c = context.scrivi;
    final open = q.isNotEmpty || widget.open.contains(g);
    return [
      const SizedBox(height: 10),
      InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: q.isEmpty ? () => widget.onToggleGroup(g) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            children: [
              Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 18, color: c.muted),
              const SizedBox(width: 4),
              Text(
                g.label.toUpperCase(),
                style: TextStyle(fontSize: 11, letterSpacing: 1.3, fontWeight: FontWeight.w600, color: c.muted),
              ),
            ],
          ),
        ),
      ),
      if (open) ...[
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [for (final t in tools) ToolButton(tool: t, host: widget.host)],
        ),
      ],
    ];
  }
}

/// Ein Werkzeug-Knopf: Zeichen, Hinweis nach kurzer Zeit, leuchtet wenn aktiv, blass wenn nicht möglich.
class ToolButton extends StatelessWidget {
  const ToolButton({super.key, required this.tool, required this.host});
  final ToolDef tool;
  final ToolHost host;

  static const size = 38.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = context.scrivi;
    final e = host.editor;
    final enabled = tool.enabled?.call(e) ?? true;
    final active = switch (tool.id) {
      'pen' => host.penNotes,
      'mic' => host.micOn,
      _ => tool.active?.call(e) ?? false,
    };
    final fg = active ? scheme.onPrimary : (enabled ? Theme.of(context).colorScheme.onSurface : c.muted.withAlpha(110));
    Widget child = switch (tool.look) {
      GlyphLook g => ToolGlyph(text: g.char, size: g.size, color: fg),
      TextLook t => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            t.text,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontStyle: t.italic ? FontStyle.italic : null,
              color: fg,
            ),
          ),
        ),
      ),
      IconLook i => Icon(i.icon, size: 20, color: fg),
    };
    return Tooltip(
      message: tool.tooltip,
      waitDuration: const Duration(milliseconds: 150),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: enabled ? () => tool.run(host) : null,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: active ? scheme.primary : c.cardHigh,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Suche über alle Werkzeuge (Strg+K): tippen, Enter führt das erste aus.
Future<void> showToolSearch(BuildContext context, ToolHost host) async {
  final ctrl = TextEditingController();
  final chosen = await showDialog<ToolDef>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final list = [
          for (final t in allTools)
            if (t.fits(host.editor) && t.matches(ctrl.text) && (t.enabled?.call(host.editor) ?? true)) t,
        ];
        return Dialog(
          alignment: const Alignment(0, -0.6),
          child: SizedBox(
            width: 480,
            height: 420,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: tr('Was möchtest du tun?', 'What would you like to do?'),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => Navigator.pop(context, list.isEmpty ? null : list.first),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final t in list)
                        ListTile(
                          dense: true,
                          leading: SizedBox(
                            width: ToolButton.size,
                            child: IgnorePointer(
                              child: ToolButton(tool: t, host: host),
                            ),
                          ),
                          title: Text(t.name),
                          subtitle: Text(t.group.label),
                          trailing: t.shortcut == null
                              ? null
                              : Text(t.shortcut!, style: TextStyle(color: context.scrivi.muted)),
                          onTap: () => Navigator.pop(context, t),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  ctrl.dispose();
  if (chosen != null) chosen.run(host);
}

/// Notenzeichen auf einem Knopf: genau in der Mitte und so klein, dass es nicht übersteht.
/// Die Ausdehnung der Tinte stammt aus [toolGlyphBoxes] (der Ursprung eines Notenzeichens liegt
/// auf der Notenlinie, nicht in seiner Mitte). Mehrere Zeilen (mit \n) stehen übereinander.
class ToolGlyph extends StatelessWidget {
  const ToolGlyph({super.key, required this.text, required this.size, required this.color});
  final String text;

  /// Gewünschte Schriftgrösse (Bildpunkte); kleiner, wenn das Zeichen sonst zu gross wäre.
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(ToolButton.size, ToolButton.size), painter: _GlyphPainter(text, size, color));
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.text, this.size, this.color);
  final String text;
  final double size;
  final Color color;

  /// Platz für die Tinte im Knopf (Bildpunkte) und kleinste Ausdehnung (damit ein Punkt sichtbar bleibt).
  static const _maxW = 30.0, _maxH = 28.0, _minInk = 5.5;

  @override
  void paint(Canvas canvas, Size box) {
    // Tinte jeder Zeile in Linienabständen (y nach oben), Zeichen nebeneinander nach ihrem Vorschub
    final lines = text.split('\n');
    final boxes = <(double, double, double, double)>[];
    for (final line in lines) {
      var x = 0.0, l = double.infinity, b = double.infinity, r = -double.infinity, t = -double.infinity;
      for (final rune in line.runes) {
        final g = toolGlyphBoxes[rune];
        if (g == null) continue;
        l = l < x + g.$1 ? l : x + g.$1;
        b = b < g.$2 ? b : g.$2;
        r = r > x + g.$3 ? r : x + g.$3;
        t = t > g.$4 ? t : g.$4;
        x += g.$5;
      }
      boxes.add(l.isFinite ? (l, b, r, t) : (0.0, 0.0, 1.0, 1.0));
    }
    // Zeilenabstand (Linienabstände) und Gesamtgrösse
    final lineH = boxes.map((e) => e.$4 - e.$2).reduce((a, c) => a > c ? a : c) + 0.25;
    final first = boxes.first, last = boxes.last;
    final w = boxes.map((e) => e.$3 - e.$1).reduce((a, c) => a > c ? a : c);
    final h = (lines.length - 1) * lineH + first.$4 - last.$2;
    // Schriftgrösse: ein Geviert = 4 Linienabstände
    var font = size;
    if (w * font / 4 > _maxW) font = _maxW * 4 / w;
    if (h * font / 4 > _maxH) font = _maxH * 4 / h;
    final ink = (w > h ? w : h) * font / 4;
    if (ink < _minInk) font *= _minInk / ink;
    final sp = font / 4;
    // Grundlinie der ersten Zeile so, dass die Tinte senkrecht in der Mitte steht
    final cy = box.height / 2, cx = box.width / 2;
    final base0 = cy + (first.$4 + last.$2 - (lines.length - 1) * lineH) * sp / 2;
    for (var i = 0; i < lines.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: lines[i],
          style: TextStyle(fontFamily: 'Bravura', fontSize: font, height: 1, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      final (l, _, r, _) = boxes[i];
      tp.paint(canvas, Offset(cx - (l + r) / 2 * sp, base0 + i * lineH * sp - baseline));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.text != text || old.size != size || old.color != color;
}
