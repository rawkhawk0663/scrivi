import 'package:flutter/material.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';

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
  Future<void> editTitle();
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
  duration('Notenwert', 'Note value'),
  guitar('Gitarre', 'Guitar'),
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

  String get name => tr(de, en);
  String get tooltip => shortcut == null ? name : '$name   $shortcut';

  bool matches(String q) {
    final s = q.toLowerCase().trim();
    if (s.isEmpty) return true;
    return [de, en, group.de, group.en, ...keywords].any((w) => w.toLowerCase().contains(s));
  }
}

bool _hasNotes(core.ScoreEditor e) => !(e.currentBeat?.isRest ?? true);
bool _hasBeat(core.ScoreEditor e) => e.currentBeat != null;

core.NoteValue _value(core.ScoreEditor e) => e.currentBeat?.duration.value ?? e.duration.value;

ToolDef _duration(core.NoteValue v, String glyph, String de, String en, String key) => ToolDef(
  id: 'd-${v.name}',
  group: ToolGroup.duration,
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
    group: ToolGroup.duration,
    look: const GlyphLook('\uECB7', size: 34, dy: 4),
    de: 'Punkt (punktiert)',
    en: 'Dot (dotted)',
    shortcut: '.',
    active: (e) => (e.currentBeat?.duration.dots ?? e.duration.dots) > 0,
    run: (h) => h.apply((e) => e.toggleDot()),
  ),
  ToolDef(
    id: 'triplet',
    group: ToolGroup.duration,
    look: const GlyphLook('\uE883', size: 20),
    de: 'Triole',
    en: 'Triplet',
    shortcut: 'T',
    keywords: const ['tuplet', 'n-tole'],
    active: (e) => e.currentBeat?.duration.tuplet != null,
    enabled: _hasBeat,
    run: (h) => h.apply((e) => e.toggleTriplet()),
  ),
  ToolDef(
    id: 'rest',
    group: ToolGroup.duration,
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
    group: ToolGroup.duration,
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
    group: ToolGroup.duration,
    look: const GlyphLook('\uE262', size: 22, dy: 2),
    de: 'Halbton höher',
    en: 'Semitone up',
    shortcut: 'Umschalt+↑',
    keywords: const ['kreuz', 'sharp', 'transponieren'],
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.transposeSelection(1), sound: true),
  ),
  ToolDef(
    id: 'down',
    group: ToolGroup.duration,
    look: const GlyphLook('\uE260', size: 22, dy: 2),
    de: 'Halbton tiefer',
    en: 'Semitone down',
    shortcut: 'Umschalt+↓',
    keywords: const ['b', 'flat', 'transponieren'],
    enabled: _hasNotes,
    run: (h) => h.apply((e) => e.transposeSelection(-1), sound: true),
  ),
  ToolDef(
    id: 'next',
    group: ToolGroup.duration,
    look: const IconLook(Icons.arrow_forward_rounded),
    de: 'Weiter zum nächsten Schlag',
    en: 'Next beat',
    shortcut: '→',
    run: (h) => h.apply((e) => e.moveBeat(1)),
  ),
  ToolDef(
    id: 'pen',
    group: ToolGroup.duration,
    look: const IconLook(Icons.edit_outlined),
    de: 'Maus und Finger schreiben wie der Stift',
    en: 'Mouse and finger write like the pen',
    keywords: const ['stift', 'pen', 'zeichnen', 'maus', 'finger', 'gesten', 'gestures'],
    active: (e) => false,
    run: (h) => h.penNotes = !h.penNotes,
  ),
  ToolDef(
    id: 'mic',
    group: ToolGroup.duration,
    look: const IconLook(Icons.mic_none_rounded),
    de: 'Vorspielen: Töne über das Mikrofon schreiben',
    en: 'Play in: write notes through the microphone',
    shortcut: 'M',
    keywords: const ['mikrofon', 'microphone', 'vorspielen', 'spielen', 'hören', 'tonerkennung', 'listen'],
    run: (h) => h.toggleMic(),
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
  _tech(core.Technique.tapping, const TextLook('T'), 'Tapping', 'Tapping'),
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
  _dynamic(core.Dynamic.pp, '\uE52B'),
  _dynamic(core.Dynamic.p, '\uE520'),
  _dynamic(core.Dynamic.mp, '\uE52C'),
  _dynamic(core.Dynamic.mf, '\uE52D'),
  _dynamic(core.Dynamic.f, '\uE522'),
  _dynamic(core.Dynamic.ff, '\uE52F'),
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
    look: const IconLook(Icons.title_rounded),
    de: 'Titel und Interpret …',
    en: 'Title and artist …',
    keywords: const ['name', 'künstler'],
    run: (h) => h.editTitle(),
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
    final stringed = e.stringed;
    final q = _search.text;
    final tools = [
      for (final t in allTools)
        if ((!t.stringedOnly || stringed) && t.matches(q)) t,
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
      GlyphLook g => Transform.translate(
        offset: Offset(0, g.dy),
        child: Text(
          g.char,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Bravura',
            fontSize: g.size,
            height: g.char.contains('\n') ? 0.62 : 1,
            color: fg,
          ),
        ),
      ),
      TextLook t => Text(
        t.text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontStyle: t.italic ? FontStyle.italic : null,
          color: fg,
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
  final stringed = host.editor.stringed;
  final chosen = await showDialog<ToolDef>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final list = [
          for (final t in allTools)
            if ((!t.stringedOnly || stringed) && t.matches(ctrl.text) && (t.enabled?.call(host.editor) ?? true)) t,
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
