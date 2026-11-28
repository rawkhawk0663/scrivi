import 'chord_symbol.dart';
import 'fraction.dart';
import 'page_setup.dart';
import 'pitch.dart';

export 'chord_symbol.dart' show ChordStyle;
export 'page_setup.dart';

/// Von Hand verschoben (Layout): so weit gegenüber dem Platz, den der Notensatz wählt, in Linienabständen.
class Nudge {
  const Nudge(this.dx, this.dy);
  final double dx;
  final double dy;
  static const zero = Nudge(0, 0);
  bool get isZero => dx.abs() < 0.005 && dy.abs() < 0.005;
  Nudge operator +(Nudge o) => Nudge(dx + o.dx, dy + o.dy);
  @override
  bool operator ==(Object other) => other is Nudge && other.dx == dx && other.dy == dy;
  @override
  int get hashCode => Object.hash(dx, dy);
}

/// Ein ganzes Stück: Angaben, Taktfolge (für alle Instrumente gleich) und Spuren.
class Score {
  Score({
    required this.info,
    required this.masterBars,
    required this.tracks,
    List<TempoMark>? tempos,
    this.reverb = defaultReverb,
    this.masterVolume = 1,
    this.chordStyle = ChordStyle.standard,
    Map<String, Nudge>? nudges,
    this.pageSetup = PageSetup.standard,
  }) : tempos = tempos ?? [],
       nudges = nudges ?? {};

  /// Seite einrichten: Papier, Ränder, Notengrösse, Abstände.
  PageSetup pageSetup;

  /// Verschobene Angaben im Kopf und Fuss der Seite ('title', 'subtitle', 'artist', 'album', 'credits',
  /// 'tabber', 'instructions', 'copyright').
  final Map<String, Nudge> nudges;

  /// Wie die Akkordsymbole geschrieben werden.
  ChordStyle chordStyle;

  /// Gesamtlautstärke (Masterspur), 0..1.
  double masterVolume;

  /// Hall beim Abspielen, 0 (trocken) bis 1 (grosser Raum).
  double reverb;
  static const defaultReverb = 0.2;

  final ScoreInfo info;

  /// Taktart, Tonart, Wiederholungen, Formteile … pro Takt.
  final List<MasterBar> masterBars;

  final List<Track> tracks;

  /// Tempoangaben, nach Takt sortiert. Die erste gilt ab Anfang.
  final List<TempoMark> tempos;

  /// Tempo am Anfang (Viertel pro Minute), falls angegeben.
  TempoMark? get initialTempo => tempos.isEmpty ? null : tempos.first;

  Score copyWith({ScoreInfo? info}) => Score(
    info: info ?? this.info,
    masterBars: masterBars,
    tracks: tracks,
    tempos: tempos,
    reverb: reverb,
    masterVolume: masterVolume,
    chordStyle: chordStyle,
    nudges: nudges,
    pageSetup: pageSetup,
  );
}

class ScoreInfo {
  const ScoreInfo({
    this.title = '',
    this.subtitle = '',
    this.artist = '',
    this.album = '',
    this.words = '',
    this.music = '',
    this.copyright = '',
    this.tabber = '',
    this.instructions = '',
    this.notice = '',
  });

  final String title;
  final String subtitle;
  final String artist;
  final String album;
  final String words;
  final String music;
  final String copyright;

  /// Copyright, wie es auf dem Blatt steht: immer mit „©“ vorne (ausser es steht schon da).
  String get copyrightLine {
    final c = copyright.trim();
    if (c.isEmpty) return '';
    if (RegExp(r'^(©|\(c\)|copyright\b)', caseSensitive: false).hasMatch(c)) return c;
    return '© $c';
  }

  final String tabber;

  /// Anleitungen: stehen über der ersten Zeile (z. B. „Kapo 2, mit Plektrum“).
  final String instructions;

  /// Bemerkung: nur für sich selbst, erscheint nicht auf dem Blatt.
  final String notice;

  ScoreInfo copyWith({
    String? title,
    String? subtitle,
    String? artist,
    String? album,
    String? words,
    String? music,
    String? copyright,
    String? tabber,
    String? instructions,
    String? notice,
  }) => ScoreInfo(
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    words: words ?? this.words,
    music: music ?? this.music,
    copyright: copyright ?? this.copyright,
    tabber: tabber ?? this.tabber,
    instructions: instructions ?? this.instructions,
    notice: notice ?? this.notice,
  );
}

/// Tempo: [bpm] Schläge pro Minute, ein Schlag ist [unit] lang (punktiert bei [dotted]).
class TempoMark {
  const TempoMark({
    required this.bar,
    this.position = 0,
    required this.bpm,
    this.unit = NoteValue.quarter,
    this.dotted = false,
    this.visible = true,
  });

  final int bar;

  /// Stelle im Takt (0 = Anfang).
  final double position;
  final double bpm;
  final NoteValue unit;
  final bool dotted;
  final bool visible;
}

class TimeSignature {
  const TimeSignature(this.beats, this.beatType, {this.common = false});
  final int beats;
  final int beatType;

  /// Als C bzw. ¢ geschrieben.
  final bool common;

  Fraction get length => Fraction(beats, beatType);

  /// Zusammengesetzte Taktart (6/8, 9/8, 12/8 …): Schläge sind punktierte Viertel.
  bool get compound => beatType >= 8 && beats % 3 == 0 && beats > 3;

  @override
  bool operator ==(Object other) =>
      other is TimeSignature && other.beats == beats && other.beatType == beatType && other.common == common;

  @override
  int get hashCode => Object.hash(beats, beatType, common);

  @override
  String toString() => '$beats/$beatType';
}

/// Tonart als Anzahl Vorzeichen: + Kreuze, − b.
class KeySignature {
  const KeySignature(this.fifths, {this.minor = false});
  final int fifths;
  final bool minor;

  /// Tonart um [semitones] Halbtöne verschoben (Vorzeichen zwischen −6 und +5).
  KeySignature transposed(int semitones) {
    if (semitones % 12 == 0) return this;
    final f = ((fifths + 7 * semitones + 6) % 12 + 12) % 12 - 6;
    return KeySignature(f, minor: minor);
  }

  /// Vorzeichen, das die Tonart einem Stammton gibt (0 = keins).
  int alterFor(int step) {
    // Reihenfolge der Kreuze: F C G D A E B, der b: B E A D G C F
    const sharpOrder = [3, 0, 4, 1, 5, 2, 6];
    const flatOrder = [6, 2, 5, 1, 4, 0, 3];
    if (fifths > 0) return sharpOrder.take(fifths).contains(step) ? 1 : 0;
    if (fifths < 0) return flatOrder.take(-fifths).contains(step) ? -1 : 0;
    return 0;
  }

  @override
  bool operator ==(Object other) => other is KeySignature && other.fifths == fifths && other.minor == minor;

  @override
  int get hashCode => Object.hash(fifths, minor);
}

/// Formteil wie „Intro“ oder „Refrain“, mit optionalem Buchstaben.
class Section {
  const Section({this.letter = '', this.text = ''});
  final String letter;
  final String text;

  String get label => [letter, text].where((s) => s.isNotEmpty).join(' ');
}

/// Sprungzeichen und Ziele (Segno, Coda, D.C. …).
enum Direction {
  segno,
  segnoSegno,
  coda,
  doubleCoda,
  fine,
  daCapo,
  daCapoAlFine,
  daCapoAlCoda,
  dalSegno,
  dalSegnoAlFine,
  dalSegnoAlCoda,
  toCoda,
}

/// Angaben, die für einen Takt in allen Instrumenten gelten.
class MasterBar {
  MasterBar({
    required this.time,
    required this.key,
    this.repeatStart = false,
    this.repeatEnd = 0,
    Set<int>? endings,
    this.section,
    this.doubleBar = false,
    this.freeTime = false,
    Set<Direction>? directions,
    this.swing = false,
    this.nudges = const {},
    this.breakAfter = 0,
  }) : endings = endings ?? {},
       directions = directions ?? {};

  /// Von Hand verschoben: 'section' (Formteil), 'tempo', 'system' (die Zeile, die mit diesem Takt beginnt).
  final Map<String, Nudge> nudges;

  /// Umbruch nach diesem Takt: 0 automatisch, 1 neue Zeile, 2 neue Seite, −1 nie (mit dem nächsten zusammen).
  final int breakAfter;

  final TimeSignature time;
  final KeySignature key;
  final bool repeatStart;

  /// Wiederholungsende: wie oft insgesamt gespielt wird (0 = kein Ende).
  final int repeatEnd;

  /// Häuser (1., 2. …), zu denen dieser Takt gehört.
  final Set<int> endings;
  final Section? section;
  final bool doubleBar;
  final bool freeTime;
  final Set<Direction> directions;

  /// Achtel werden geswingt gespielt (lang–kurz, wie Triolen-Viertel und -Achtel).
  final bool swing;

  bool get hasRepeatEnd => repeatEnd > 0;

  MasterBar copyWith({
    TimeSignature? time,
    KeySignature? key,
    bool? repeatStart,
    int? repeatEnd,
    Set<int>? endings,
    Section? section,
    bool clearSection = false,
    bool? doubleBar,
    Set<Direction>? directions,
    bool? swing,
    Map<String, Nudge>? nudges,
    int? breakAfter,
  }) => MasterBar(
    time: time ?? this.time,
    key: key ?? this.key,
    repeatStart: repeatStart ?? this.repeatStart,
    repeatEnd: repeatEnd ?? this.repeatEnd,
    endings: endings ?? {...this.endings},
    section: clearSection ? null : (section ?? this.section),
    doubleBar: doubleBar ?? this.doubleBar,
    freeTime: freeTime,
    directions: directions ?? {...this.directions},
    swing: swing ?? this.swing,
    nudges: nudges ?? this.nudges,
    breakAfter: breakAfter ?? this.breakAfter,
  );
}

/// Ein Instrument (eine Spur) mit seinen Takten.
class Track {
  Track({
    required this.name,
    this.shortName = '',
    required this.staff,
    required this.bars,
    Map<int, ChordDef>? chords,
    this.layoutHint,
    this.transposeSemitones = 0,
    this.program = -1,
    this.instrumentKey = 0,
    this.mix = const TrackMix(),
  }) : chords = chords ?? {};

  /// Mischpult: Lautstärke, links/rechts, stumm, solo (mit dem Stück gespeichert).
  final TrackMix mix;

  final String name;
  final String shortName;
  final StaffDef staff;
  final List<Bar> bars;

  /// Akkorde, auf die Schläge verweisen (Nummer → Akkord).
  final Map<int, ChordDef> chords;

  /// Takte pro Zeile, wie sie in der Datei festgelegt sind (null = frei).
  final List<int>? layoutHint;

  /// Geschrieben = klingend + so viele Halbtöne (Gitarre: +12).
  final int transposeSemitones;

  /// Klangfarbe als General-MIDI-Nummer (0..127), −1 = unbekannt.
  final int program;

  /// Transponierendes Instrument: so viele Halbtöne wird es in der Ansicht
  /// „transponiert“ höher geschrieben als es klingt, zusätzlich zu
  /// [transposeSemitones] (Trompete und Klarinette in B: 2, Altsaxofon in Es: 9,
  /// Horn in F: 7). 0 = in C.
  final int instrumentKey;

  /// Schlagzeug (neutraler Schlüssel).
  bool get percussion => bars.isNotEmpty && bars.first.clef == Clef.neutral;
}

/// Einstellungen einer Spur im Mischpult.
class TrackMix {
  const TrackMix({this.volume = 1, this.pan = 0, this.muted = false, this.solo = false});

  /// Lautstärke 0..1.
  final double volume;

  /// Links (−1) bis rechts (1).
  final double pan;
  final bool muted;
  final bool solo;

  bool get isDefault => volume == 1 && pan == 0 && !muted && !solo;

  TrackMix copyWith({double? volume, double? pan, bool? muted, bool? solo}) => TrackMix(
    volume: volume ?? this.volume,
    pan: pan ?? this.pan,
    muted: muted ?? this.muted,
    solo: solo ?? this.solo,
  );

  @override
  bool operator ==(Object other) =>
      other is TrackMix && other.volume == volume && other.pan == pan && other.muted == muted && other.solo == solo;

  @override
  int get hashCode => Object.hash(volume, pan, muted, solo);
}

/// Angaben zum Notensystem eines Instruments.
class StaffDef {
  const StaffDef({
    this.tuning = const [],
    this.capo = 0,
    this.fretCount = 24,
    this.showNotation = true,
    this.showTab = true,
    this.tuningName = '',
  });

  /// Stimmung, tiefste Saite zuerst (MIDI). Leer = kein Saiteninstrument.
  final List<int> tuning;
  final int capo;
  final int fretCount;
  final bool showNotation;
  final bool showTab;
  final String tuningName;

  bool get isStringed => tuning.isNotEmpty;
  int get stringCount => tuning.length;
}

/// Akkordsymbol mit optionalem Griffbild.
class ChordDef {
  const ChordDef({required this.name, this.diagram});
  final String name;
  final ChordDiagram? diagram;
}

class ChordDiagram {
  const ChordDiagram({
    required this.stringCount,
    required this.baseFret,
    required this.frets,
    this.fretCount = 5,
    this.barres = const [],
    this.visible = true,
  });
  final int stringCount;

  /// Erster gezeigter Bund (0 = Sattel). Die Bünde in [frets] sind immer absolut.
  final int baseFret;

  /// Bund pro Saite (tiefste zuerst), −1 = nicht gespielt, 0 = leer.
  final List<int> frets;
  final int fretCount;

  /// Barrés (ein Finger über mehrere Saiten).
  final List<ChordBarre> barres;

  /// In der Datei als sichtbar markiert.
  final bool visible;

  /// Anzahl gespielter Saiten.
  int get played => frets.where((f) => f >= 0).length;
}

/// Ein Finger über mehrere Saiten auf demselben Bund (Saiten wie im Modell: 0 = tiefste).
class ChordBarre {
  const ChordBarre({required this.fret, required this.from, required this.to});
  final int fret;
  final int from;
  final int to;
}

enum Clef { treble, treble8vb, bass, alto, tenor, neutral }

class Bar {
  Bar({required this.clef, required this.voices, this.simile = 0});
  final Clef clef;

  /// Wiederholungszeichen statt der Noten: 0 keines, 1 „wie der Takt davor“,
  /// 2 „wie die zwei Takte davor“ (erster der beiden), 3 zweiter Takt davon.
  /// Die Noten stehen trotzdem im Takt (zum Abspielen), gezeigt wird das Zeichen.
  final int simile;

  /// Stimmen (meist nur eine). Leere Stimmen fehlen.
  final List<Voice> voices;
}

class Voice {
  Voice(this.beats);
  final List<Beat> beats;
}

enum NoteValue {
  doubleWhole(-1),
  whole(0),
  half(1),
  quarter(2),
  eighth(3),
  sixteenth(4),
  thirtySecond(5),
  sixtyFourth(6),
  hundredTwentyEighth(7);

  const NoteValue(this.log2);

  /// 0 = Ganze, 1 = Halbe, 2 = Viertel …
  final int log2;

  Fraction get length => log2 < 0 ? Fraction(2) : Fraction(1, 1 << log2);

  /// Bekommt Fähnchen oder Balken (Achtel und kürzer).
  bool get hasFlag => log2 >= 3;
  int get flagCount => log2 >= 3 ? log2 - 2 : 0;
}

class Tuplet {
  const Tuplet(this.actual, this.normal);

  /// [actual] Noten in der Zeit von [normal] (Triole: 3 in 2).
  final int actual;
  final int normal;
}

class NoteDuration {
  const NoteDuration(this.value, {this.dots = 0, this.tuplet});
  final NoteValue value;
  final int dots;
  final Tuplet? tuplet;

  Fraction get length {
    var l = value.length;
    var add = value.length;
    for (var i = 0; i < dots; i++) {
      add = add.scale(1, 2);
      l = l + add;
    }
    final t = tuplet;
    if (t != null) l = l.scale(t.normal, t.actual);
    return l;
  }
}

enum Hairpin { none, crescendo, decrescendo }

enum Dynamic { pppp, ppp, pp, p, mp, mf, f, ff, fff, ffff }

enum GraceType { none, beforeBeat, onBeat }

/// Ein Schlag: eine Note, ein Akkord oder eine Pause, mit allem, was dazugehört.
class Beat {
  Beat({
    required this.duration,
    List<Note>? notes,
    this.slashed = false,
    this.chordId,
    this.text,
    this.dynamic,
    this.hairpin = Hairpin.none,
    List<String>? lyrics,
    this.grace = GraceType.none,
    this.fermata = false,
    this.pickStroke = 0,
    this.letRingText = false,
    this.tremolo = 0,
    this.ottava = 0,
    this.arpeggio = 0,
    this.rasgueado = false,
    this.fade = 0,
    this.whammy = 0,
    this.pedal = 0,
    this.nudges = const {},
  }) : notes = notes ?? [],
       lyrics = lyrics ?? [];

  final NoteDuration duration;
  final List<Note> notes;

  /// Als Rhythmus-Schrägstrich geschrieben (ohne Tonhöhe).
  final bool slashed;

  /// Verweis auf einen Akkord der Spur.
  final int? chordId;

  /// Freier Text über dem Notensystem.
  final String? text;
  final Dynamic? dynamic;
  final Hairpin hairpin;

  /// Liedtext, eine Zeile pro Strophe.
  final List<String> lyrics;
  final GraceType grace;
  final bool fermata;

  /// Anschlag: 0 keiner, 1 abwärts, −1 aufwärts.
  final int pickStroke;
  final bool letRingText;

  /// Tremolo-Picking: Anzahl Striche am Hals (1 = Achtel, 2 = Sechzehntel, 3 = Zweiunddreissigstel).
  final int tremolo;

  /// Oktavierung: 1 = 8va, 2 = 15ma (eine bzw. zwei Oktaven tiefer geschrieben),
  /// −1 = 8vb, −2 = 15mb. Die Töne bleiben klingend gespeichert.
  final int ottava;

  /// Akkord gebrochen: 1 = aufwärts (vom tiefsten Ton), −1 = abwärts.
  final int arpeggio;

  /// Rasgueado: schneller Fächerschlag mit den Fingern.
  final bool rasgueado;

  /// Lautstärke im Ton: 1 = einblenden, 2 = ausblenden, 3 = anschwellen und abschwellen.
  final int fade;

  /// Tremolo-Hebel: kurz so viele Halbtöne hinunter und zurück (negativ, 0 = keiner).
  final int whammy;

  /// Haltepedal: 1 = treten („Ped.“), 2 = loslassen („*“), 3 = wechseln (los und gleich wieder treten).
  final int pedal;

  /// Von Hand verschoben: 'chord', 'text', 'dynamic'.
  final Map<String, Nudge> nudges;

  bool get isRest => notes.isEmpty;

  /// Kopie mit Änderungen. Für null-fähige Felder: [clearChord], [clearText], [clearDynamic].
  Beat copyWith({
    NoteDuration? duration,
    List<Note>? notes,
    bool? slashed,
    int? chordId,
    bool clearChord = false,
    String? text,
    bool clearText = false,
    Dynamic? dynamic,
    bool clearDynamic = false,
    Hairpin? hairpin,
    List<String>? lyrics,
    GraceType? grace,
    bool? fermata,
    int? pickStroke,
    bool? letRingText,
    int? tremolo,
    int? ottava,
    int? arpeggio,
    bool? rasgueado,
    int? fade,
    int? whammy,
    int? pedal,
    Map<String, Nudge>? nudges,
  }) => Beat(
    duration: duration ?? this.duration,
    notes: notes ?? [...this.notes],
    slashed: slashed ?? this.slashed,
    chordId: clearChord ? null : (chordId ?? this.chordId),
    text: clearText ? null : (text ?? this.text),
    dynamic: clearDynamic ? null : (dynamic ?? this.dynamic),
    hairpin: hairpin ?? this.hairpin,
    lyrics: lyrics ?? [...this.lyrics],
    grace: grace ?? this.grace,
    fermata: fermata ?? this.fermata,
    pickStroke: pickStroke ?? this.pickStroke,
    letRingText: letRingText ?? this.letRingText,
    tremolo: tremolo ?? this.tremolo,
    ottava: ottava ?? this.ottava,
    arpeggio: arpeggio ?? this.arpeggio,
    rasgueado: rasgueado ?? this.rasgueado,
    fade: fade ?? this.fade,
    whammy: whammy ?? this.whammy,
    pedal: pedal ?? this.pedal,
    nudges: nudges ?? this.nudges,
  );
}

/// Ein Ton im Schlag, mit Saite und Bund und den Spieltechniken.
class Note {
  Note({
    required this.pitch,
    this.written,
    this.string,
    this.fret,
    this.tieOrigin = false,
    this.tieDestination = false,
    this.palmMuted = false,
    this.dead = false,
    this.ghost = false,
    this.letRing = false,
    this.slide = 0,
    this.hammerOrigin = false,
    this.hammerDestination = false,
    this.bend,
    this.accent = 0,
    this.vibrato = false,
    this.harmonic = false,
    this.tapped = false,
    this.courtesy = false,
    this.wideVibrato = false,
    this.harmonicType = 0,
    this.slap = false,
    this.pop = false,
    this.trill = 0,
    this.leftFinger = 0,
    this.rightFinger = 0,
    this.stringNumber = false,
  });

  /// Fingersatz der Greifhand: 0 keiner, 1–4 Finger, 5 Daumen (T).
  final int leftFinger;

  /// Fingersatz der Anschlagshand: 0 keiner, 1 p, 2 i, 3 m, 4 a, 5 c (kleiner Finger).
  final int rightFinger;

  /// Saitennummer im Kreis zeigen (1 = höchste Saite).
  final bool stringNumber;

  /// Weites Vibrato (grosse, langsame Welle).
  final bool wideVibrato;

  /// Art des Flageoletts, wenn [harmonic]: 0 natürlich, 1 künstlich (A.H.), 2 gezupft „Pinch“ (P.H.).
  final int harmonicType;

  /// Bass: geschlagen (S) bzw. gezupft-geschnalzt (P).
  final bool slap;
  final bool pop;

  /// Triller mit dem Ton so viele Halbtöne höher (0 = kein Triller).
  final int trill;

  /// Vorzeichen zur Erinnerung zeigen, in Klammern (auch wenn es nicht nötig wäre).
  final bool courtesy;

  /// Klingende Tonhöhe.
  final Pitch pitch;

  /// Geschriebene Tonhöhe (falls anders als klingend, z. B. Gitarre eine Oktave höher).
  final Pitch? written;

  /// Saite (0 = tiefste) und Bund, falls Saiteninstrument.
  final int? string;
  final int? fret;

  final bool tieOrigin;
  final bool tieDestination;
  final bool palmMuted;

  /// Gedämpfte Note (x).
  final bool dead;

  /// Geisternote (in Klammern).
  final bool ghost;
  final bool letRing;

  /// Slides als Bitmaske: 1 Shift, 2 Legato, 4 raus nach unten, 8 raus nach oben,
  /// 16 rein von unten, 32 rein von oben.
  final int slide;
  final bool hammerOrigin;
  final bool hammerDestination;
  final Bend? bend;

  /// Akzente als Bitmaske: 1 Staccato, 4 Marcato, 8 Akzent, 16 Tenuto.
  final int accent;
  final bool vibrato;
  final bool harmonic;
  final bool tapped;

  Pitch get shown => written ?? pitch;

  /// Geschriebene Tonhöhe in einer Spur, die [transposeSemitones] höher
  /// geschrieben wird als sie klingt (Gitarre: 12). Fehlt die Schreibweise
  /// aus der Datei, wird die klingende Tonhöhe entsprechend verschoben.
  Pitch shownFor(int transposeSemitones) {
    final w = written;
    if (w != null || transposeSemitones == 0) return w ?? pitch;
    if (transposeSemitones % 12 == 0) return pitch.octaves(transposeSemitones ~/ 12);
    return Pitch.fromMidi(pitch.midi + transposeSemitones);
  }

  /// Kopie mit Änderungen. [clearBend] entfernt das Saitenziehen.
  Note copyWith({
    Pitch? pitch,
    Pitch? written,
    bool clearWritten = false,
    int? string,
    int? fret,
    bool? tieOrigin,
    bool? tieDestination,
    bool? palmMuted,
    bool? dead,
    bool? ghost,
    bool? letRing,
    int? slide,
    bool? hammerOrigin,
    bool? hammerDestination,
    Bend? bend,
    bool clearBend = false,
    int? accent,
    bool? vibrato,
    bool? harmonic,
    bool? tapped,
    bool? courtesy,
    bool? wideVibrato,
    int? harmonicType,
    bool? slap,
    bool? pop,
    int? trill,
    int? leftFinger,
    int? rightFinger,
    bool? stringNumber,
  }) => Note(
    pitch: pitch ?? this.pitch,
    written: clearWritten ? null : (written ?? this.written),
    string: string ?? this.string,
    fret: fret ?? this.fret,
    tieOrigin: tieOrigin ?? this.tieOrigin,
    tieDestination: tieDestination ?? this.tieDestination,
    palmMuted: palmMuted ?? this.palmMuted,
    dead: dead ?? this.dead,
    ghost: ghost ?? this.ghost,
    letRing: letRing ?? this.letRing,
    slide: slide ?? this.slide,
    hammerOrigin: hammerOrigin ?? this.hammerOrigin,
    hammerDestination: hammerDestination ?? this.hammerDestination,
    bend: clearBend ? null : (bend ?? this.bend),
    accent: accent ?? this.accent,
    vibrato: vibrato ?? this.vibrato,
    harmonic: harmonic ?? this.harmonic,
    tapped: tapped ?? this.tapped,
    courtesy: courtesy ?? this.courtesy,
    wideVibrato: wideVibrato ?? this.wideVibrato,
    harmonicType: harmonicType ?? this.harmonicType,
    slap: slap ?? this.slap,
    pop: pop ?? this.pop,
    trill: trill ?? this.trill,
    leftFinger: leftFinger ?? this.leftFinger,
    rightFinger: rightFinger ?? this.rightFinger,
    stringNumber: stringNumber ?? this.stringNumber,
  );
}

/// Saitenziehen: Punkte mit Stelle (0..1 der Notenlänge) und Höhe in Halbtönen.
class Bend {
  const Bend(this.points);
  final List<BendPoint> points;

  /// Höchster Wert in Halbtönen.
  double get maxSemitones => points.fold(0.0, (m, p) => p.semitones > m ? p.semitones : m);

  /// Endet tiefer als der Höchstwert (Ziehen und wieder loslassen).
  bool get releases => points.isNotEmpty && points.last.semitones < maxSemitones - 0.01;

  /// Beginnt schon gezogen (Pre-Bend).
  bool get preBent => points.isNotEmpty && points.first.semitones > 0.01;
}

class BendPoint {
  const BendPoint(this.position, this.semitones);
  final double position;
  final double semitones;
}
