import 'dart:math' as math;

import '../model/chord_library.dart';
import '../model/fraction.dart';
import '../model/score.dart';
import '../render/display.dart';
import '../render/glyphs.dart';
import 'shapes.dart';

/// Seitengrösse und Ränder in Linienabständen. Grundwerte: A4 hoch mit einem
/// Linienabstand von 1,75 mm (7 mm hohes Notensystem).
class LayoutOptions {
  const LayoutOptions({
    this.pageWidth = 120,
    this.pageHeight = 169.7,
    this.marginLeft = 8.5,
    this.marginRight = 8.5,
    this.marginTop = 8,
    this.marginBottom = 9,
    this.showTab = true,
    this.showNotation = true,
    this.tabLineSpacing = 1.5,
    this.systemGap = 3.0,
    this.useLayoutHint = true,
    this.showChordDiagrams = true,
    this.germanNoteNames = false,
  });

  final double pageWidth;
  final double pageHeight;
  final double marginLeft;
  final double marginRight;
  final double marginTop;
  final double marginBottom;

  /// Tabulatur unter den Noten zeigen (nur bei Saiteninstrumenten).
  final bool showTab;

  /// Notenzeile zeigen. Ohne sie (bei Saiteninstrumenten) steht der Rhythmus
  /// als Hälse und Balken unter der Tabulatur.
  final bool showNotation;
  final double tabLineSpacing;

  /// Mindestabstand zwischen zwei Zeilen.
  final double systemGap;

  /// Takte pro Zeile aus der Datei übernehmen, wo sie passen.
  final bool useLayoutHint;

  /// Griffbilder der verwendeten Akkorde oben auf der ersten Seite.
  final bool showChordDiagrams;

  /// Deutsche Notennamen für Saiten (H statt B, B statt B♭).
  final bool germanNoteNames;

  double get contentWidth => pageWidth - marginLeft - marginRight;
}

/// Ergebnis des Notensatzes: die Seiten.
class ScoreLayout {
  ScoreLayout(this.pages);
  final List<PageDisplay> pages;
}

// Linienstärken aus der Schrift (Linienabstände).
final double _staffLineT = Glyphs.engraving('staffLineThickness', 0.13);
// Hälse etwas kräftiger als der Grundwert: am Bildschirm besser lesbar.
final double _stemT = Glyphs.engraving('stemThickness', 0.12) + 0.02;
final double _beamT = Glyphs.engraving('beamThickness', 0.5);
final double _beamGap = Glyphs.engraving('beamSpacing', 0.25);
final double _ledgerT = Glyphs.engraving('legerLineThickness', 0.16);
final double _ledgerExt = Glyphs.engraving('legerLineExtension', 0.4);
final double _thinT = Glyphs.engraving('thinBarlineThickness', 0.16);
final double _thickT = Glyphs.engraving('thickBarlineThickness', 0.5);
final double _barSep = Glyphs.engraving('barlineSeparation', 0.4);

// Schriftgrössen (Linienabstände)
const _chordSize = 1.6;
const _tabSize = 1.25;
const _sectionSize = 1.45;
const _textSize = 1.35;
const _lyricsSize = 1.4;
const _smallSize = 1.0;
const _techniqueSize = 1.1;

// Vorschlagsnoten: Grösse und Abstand
const _graceScale = 0.65;
const _graceStep = 1.4;

class _Head {
  _Head(this.note, this.y, this.glyph);
  final Note? note;
  final double y;
  final String glyph;
  double dx = 0;
  String? accidental;
  double accX = 0;

  double get width => Glyphs.get(glyph).right;
}

class _Tie {
  _Tie(this.from, this.fromHead, this.to, this.toHead);
  final _Ev from;
  final _Head fromHead;
  final _Ev to;
  final _Head toHead;
}

class _Ev {
  _Ev(this.beat, this.voice, this.bar, this.onset, this.voiceCount);
  final Beat beat;
  final int voice;
  final int bar;
  final Fraction onset;
  final int voiceCount;
  late _Col col;
  final heads = <_Head>[];
  bool stemUp = true;
  bool hasStem = false;
  _BeamGroup? beam;
  double stemBase = 0;
  double stemTip = 0;
  bool fullBarRest = false;
  bool showDynamic = false;
  final tiesOut = <_Tie>[];
  final tiesIn = <_Tie>[];
  _Ev? nextInVoice;

  /// Vorschlagsnoten vor diesem Schlag.
  final graces = <Beat>[];

  double get x => col.x;
  bool get isRest => beat.isRest;
  NoteValue get value => beat.duration.value;
  double get headW => heads.isEmpty ? 1.18 : heads.map((h) => h.width).reduce(math.max);
  double get top => heads.map((h) => h.y).reduce(math.min);
  double get bottom => heads.map((h) => h.y).reduce(math.max);

  /// x-Mitte des Hals (relativ zur Spalte).
  double get stemDx {
    if (heads.isEmpty) return 0;
    final w = heads.first.width;
    final slashUp = beat.slashed ? Glyphs.get(heads.first.glyph).anchors['stemUpSE']?.x ?? w : w;
    return stemUp ? slashUp - _stemT / 2 : _stemT / 2;
  }

  double get stemX => x + stemDx;
}

class _Col {
  _Col(this.onset);
  final Fraction onset;
  final evs = <_Ev>[];
  double accW = 0;

  /// Platz für Vorschlagsnoten ganz links in der Spalte (Teil von [accW]).
  double graceW = 0;
  double minW = 1.6;
  double spring = 0;
  double x = 0;

  double get natural => accW + math.max(spring, minW);
}

class _BeamGroup {
  _BeamGroup(this.evs, this.up);
  final List<_Ev> evs;
  final bool up;
}

class _Meas {
  _Meas(this.index, this.mb, this.bar);
  final int index;
  final MasterBar mb;
  final Bar bar;
  final cols = <_Col>[];
  final voices = <List<_Ev>>[];
  final beams = <_BeamGroup>[];
  bool keyChange = false;
  bool timeChange = false;
  double padL = 1.1;
  double padR = 0.5;
  double x = 0;
  double w = 0;

  /// Breite für Tonart-/Taktartwechsel mitten in der Zeile.
  double changeW = 0;

  double get colSum => cols.fold(0.0, (s, c) => s + c.natural);
  bool get empty => cols.isEmpty;
}

class _System {
  _System(this.measures);
  final List<_Meas> measures;
  double header = 0;
  bool first = false;
  double x0 = 0;
  double x1 = 0;
}

/// Setzt eine Spur eines Stücks als Noten mit Tabulatur auf Seiten.
class Engraver {
  Engraver(
    this.score, {
    this.trackIndex = 0,
    this.options = const LayoutOptions(),
    this.measurer = const ApproxTextMeasurer(),
  });

  final Score score;
  final int trackIndex;
  final LayoutOptions options;
  final TextMeasurer measurer;

  late final Track _track = score.tracks[trackIndex];
  late final bool _tab = (options.showTab || !options.showNotation) && _track.staff.isStringed;

  /// Nur Tabulatur, mit Rhythmus darunter.
  late final bool _tabOnly = _tab && !options.showNotation;
  final _measures = <_Meas>[];

  ScoreLayout layout() {
    if (score.tracks.isEmpty) return ScoreLayout([PageDisplay(options.pageWidth, options.pageHeight)]);
    _build();
    final systems = _breakSystems();
    return _paginate(systems);
  }

  // ───────────────────────── Vorbereitung ─────────────────────────

  void _build() {
    KeySignature? prevKey;
    TimeSignature? prevTime;
    final seqs = <int, List<_Ev>>{};
    for (var i = 0; i < score.masterBars.length; i++) {
      final mb = score.masterBars[i];
      final bar = i < _track.bars.length ? _track.bars[i] : Bar(clef: Clef.treble, voices: []);
      final m = _Meas(i, mb, bar);
      // Ohne Notenzeile gibt es keine Tonart.
      m.keyChange = !_tabOnly && prevKey != null && prevKey != mb.key;
      m.timeChange = prevTime != null && prevTime != mb.time;
      prevKey = mb.key;
      prevTime = mb.time;
      final cols = <Fraction, _Col>{};
      for (var v = 0; v < bar.voices.length; v++) {
        var onset = Fraction.zero;
        final list = <_Ev>[];
        final pendingGraces = <Beat>[];
        for (final b in bar.voices[v].beats) {
          // Vorschlagsnoten nehmen keine Zeit: sie hängen am nächsten Schlag.
          if (b.grace != GraceType.none) {
            if (b.notes.isNotEmpty) pendingGraces.add(b);
            continue;
          }
          final e = _Ev(b, v, i, onset, bar.voices.length);
          e.graces.addAll(pendingGraces);
          pendingGraces.clear();
          final col = cols.putIfAbsent(onset, () => _Col(onset));
          col.evs.add(e);
          e.col = col;
          list.add(e);
          (seqs[v] ??= []).add(e);
          onset = onset + b.duration.length;
        }
        if (list.length == 1 &&
            list.first.isRest &&
            (list.first.beat.duration.length >= mb.time.length || list.first.value == NoteValue.whole)) {
          list.first.fullBarRest = true;
        }
        m.voices.add(list);
      }
      m.cols.addAll(cols.values.toList()..sort((a, b) => a.onset.compareTo(b.onset)));
      _prepareNotation(m);
      _measures.add(m);
    }
    // Reihenfolge pro Stimme über alle Takte: für Haltebögen, Legato, Slides.
    for (final seq in seqs.values) {
      for (var k = 0; k + 1 < seq.length; k++) {
        seq[k].nextInVoice = seq[k + 1];
      }
      _linkTies(seq);
    }
    _markDynamics(seqs[0] ?? const []);
    for (final m in _measures) {
      _spaceMeasure(m);
    }
  }

  int _topDiatonic(Clef c) => switch (c) {
    Clef.bass => 26,
    Clef.alto => 32,
    Clef.tenor => 30,
    _ => 38,
  };

  String _headGlyph(Beat b, Note? n) {
    final v = b.duration.value;
    if (b.slashed) {
      return switch (v) {
        NoteValue.whole || NoteValue.doubleWhole => 'noteheadSlashWhiteWhole',
        NoteValue.half => 'noteheadSlashWhiteHalf',
        _ => 'noteheadSlashHorizontalEnds',
      };
    }
    final dead = n?.dead ?? false;
    final harm = n?.harmonic ?? false;
    return switch (v) {
      NoteValue.doubleWhole => dead ? 'noteheadXWhole' : 'noteheadDoubleWhole',
      NoteValue.whole => dead ? 'noteheadXWhole' : (harm ? 'noteheadDiamondWhole' : 'noteheadWhole'),
      NoteValue.half => dead ? 'noteheadXHalf' : (harm ? 'noteheadDiamondHalf' : 'noteheadHalf'),
      _ => dead ? 'noteheadXBlack' : (harm ? 'noteheadDiamondBlack' : 'noteheadBlack'),
    };
  }

  /// Köpfe, Vorzeichen, Halsrichtung und Balkengruppen eines Takts.
  void _prepareNotation(_Meas m) {
    final top = _topDiatonic(m.bar.clef);
    for (final voice in m.voices) {
      for (final e in voice) {
        if (e.isRest) continue;
        if (e.beat.slashed) {
          e.heads.add(_Head(null, 2, _headGlyph(e.beat, null)));
        } else {
          for (final n in e.beat.notes) {
            e.heads.add(_Head(n, (top - n.shown.diatonic) / 2, _headGlyph(e.beat, n)));
          }
          e.heads.sort((a, b) => a.y.compareTo(b.y));
        }
        final v = e.value;
        e.hasStem = e.beat.slashed ? v.hasFlag : v.log2 >= 1;
      }
    }
    // Vorzeichen: Stand pro Stammton und Oktave, ausgehend von der Tonart.
    final state = <int, int>{};
    for (final c in m.cols) {
      for (final e in c.evs) {
        for (final h in e.heads) {
          final n = h.note;
          if (n == null) continue;
          final p = n.shown;
          final current = state[p.diatonic] ?? m.mb.key.alterFor(p.step);
          if (n.tieDestination) {
            state[p.diatonic] = p.alter;
            continue;
          }
          if (p.alter != current) {
            h.accidental = switch (p.alter) {
              -2 => 'accidentalDoubleFlat',
              -1 => 'accidentalFlat',
              1 => 'accidentalSharp',
              2 => 'accidentalDoubleSharp',
              _ => 'accidentalNatural',
            };
            state[p.diatonic] = p.alter;
          }
        }
      }
    }
    // Balkengruppen und Halsrichtung
    for (final voice in m.voices) {
      final groups = _beamGroups(voice, m.mb.time);
      for (final g in groups) {
        final up = _stemDirection(g, voice.first.voiceCount);
        for (final e in g) {
          e.stemUp = up;
        }
        if (g.length > 1) {
          final bg = _BeamGroup(g, up);
          m.beams.add(bg);
          for (final e in g) {
            e.beam = bg;
          }
        }
      }
    }
    // Sekunden im Akkord: abwechselnd auf die andere Seite des Halses.
    for (final voice in m.voices) {
      for (final e in voice) {
        if (e.heads.length < 2) continue;
        final w = e.heads.first.width - _stemT;
        if (e.stemUp) {
          // von unten nach oben: bei Sekunde rechts daneben
          var prevDisplaced = false;
          for (var k = e.heads.length - 2; k >= 0; k--) {
            final h = e.heads[k], below = e.heads[k + 1];
            if ((below.y - h.y) < 0.75 && !prevDisplaced) {
              h.dx = w;
              prevDisplaced = true;
            } else {
              prevDisplaced = false;
            }
          }
        } else {
          var prevDisplaced = false;
          for (var k = 1; k < e.heads.length; k++) {
            final h = e.heads[k], above = e.heads[k - 1];
            if ((h.y - above.y) < 0.75 && !prevDisplaced) {
              h.dx = -w;
              prevDisplaced = true;
            } else {
              prevDisplaced = false;
            }
          }
        }
      }
    }
    // Stellung der Vorzeichen (von oben nach unten, versetzt bei Platzmangel)
    for (final c in m.cols) {
      var maxW = 0.0;
      for (final e in c.evs) {
        final withAcc = e.heads.where((h) => h.accidental != null).toList();
        final minDx = e.heads.isEmpty ? 0.0 : e.heads.map((h) => h.dx).reduce(math.min);
        final columns = <List<_Head>>[];
        for (final h in withAcc) {
          var placed = false;
          for (var k = 0; k < columns.length && !placed; k++) {
            if (columns[k].every((o) => (o.y - h.y).abs() >= 3)) {
              columns[k].add(h);
              placed = true;
              _setAccX(h, minDx, k);
            }
          }
          if (!placed) {
            columns.add([h]);
            _setAccX(h, minDx, columns.length - 1);
          }
          maxW = math.max(maxW, -h.accX);
        }
      }
      final graces = c.evs.fold(0, (m, e) => e.graces.length > m ? e.graces.length : m);
      c.graceW = graces == 0 ? 0 : graces * _graceStep + 0.5;
      c.accW = maxW + c.graceW;
    }
  }

  void _setAccX(_Head h, double minDx, int column) {
    final w = Glyphs.get(h.accidental!).right;
    h.accX = minDx - 0.22 - w - column * 1.05;
  }

  /// Balkengruppen: zusammen, was in denselben Schlag (bzw. dieselbe Takthälfte) fällt.
  List<List<_Ev>> _beamGroups(List<_Ev> voice, TimeSignature time) {
    final groups = <List<_Ev>>[];
    Fraction span(Fraction onset) {
      if (time.compound) return Fraction(3, 8);
      final beat = Fraction(1, time.beatType);
      if (time.beats == 4 && time.beatType == 4) {
        // Achtel in Takthälften, sobald Sechzehntel darin sind pro Schlag.
        final half = onset < Fraction(1, 2) ? 0 : 1;
        final hasShort = voice.any((e) => !e.isRest && e.value.log2 >= 4 && (e.onset < Fraction(1, 2) ? 0 : 1) == half);
        return hasShort ? beat : Fraction(1, 2);
      }
      return beat;
    }

    List<_Ev>? current;
    int? currentSlot;
    for (final e in voice) {
      final beamable = !e.isRest && e.value.hasFlag;
      if (!beamable) {
        current = null;
        if (!e.isRest) groups.add([e]);
        continue;
      }
      final s = span(e.onset);
      final slot = (e.onset / s).toDouble().floor();
      if (current != null && slot == currentSlot && e.beat.slashed == current.first.beat.slashed) {
        current.add(e);
      } else {
        current = [e];
        currentSlot = slot;
        groups.add(current);
      }
    }
    return groups;
  }

  bool _stemDirection(List<_Ev> g, int voiceCount) {
    final voice = g.first.voice;
    if (voiceCount > 1) return voice.isEven;
    var minY = double.infinity, maxY = -double.infinity;
    for (final e in g) {
      for (final h in e.heads) {
        minY = math.min(minY, h.y);
        maxY = math.max(maxY, h.y);
      }
    }
    if (minY == double.infinity) return true;
    // Weiter unten als oben von der Mittellinie → Hals nach oben.
    return (maxY - 2) > (2 - minY);
  }

  void _linkTies(List<_Ev> seq) {
    for (var k = 0; k < seq.length; k++) {
      final e = seq[k];
      for (final h in e.heads) {
        final n = h.note;
        if (n == null || !n.tieOrigin) continue;
        final next = e.nextInVoice;
        if (next == null) continue;
        for (final h2 in next.heads) {
          final n2 = h2.note;
          if (n2 != null && n2.tieDestination && n2.pitch.midi == n.pitch.midi) {
            final t = _Tie(e, h, next, h2);
            e.tiesOut.add(t);
            next.tiesIn.add(t);
            break;
          }
        }
      }
    }
  }

  void _markDynamics(List<_Ev> seq) {
    var prev = Dynamic.mf;
    for (final e in seq) {
      final d = e.beat.dynamic;
      if (d == null || e.isRest) continue;
      if (d != prev) e.showDynamic = true;
      prev = d;
    }
  }

  double _springFor(Fraction d) {
    final q = d.toDouble() * 4;
    if (q <= 0) return 1.6;
    return math.max(1.6, 3.0 * math.pow(q, 0.6).toDouble());
  }

  void _spaceMeasure(_Meas m) {
    final end = m.mb.time.length;
    for (var k = 0; k < m.cols.length; k++) {
      final c = m.cols[k];
      final next = k + 1 < m.cols.length ? m.cols[k + 1].onset : end;
      var delta = next - c.onset;
      if (delta <= Fraction.zero) delta = Fraction(1, 16);
      c.spring = _springFor(delta);
      var minW = 1.6;
      for (final e in c.evs) {
        var w = e.headW + 0.5;
        if (e.heads.any((h) => h.dx > 0)) w += e.heads.first.width;
        w += e.beat.duration.dots * 0.55;
        if (!e.isRest && e.hasStem && e.beam == null && e.value.hasFlag && e.stemUp) w += 0.9;
        if (_tab && !e.beat.slashed) {
          for (final n in e.beat.notes) {
            if (n.fret == null) continue;
            final tw = measurer.width(_fretText(n, false), TextRole.tab, _tabSize) + 0.7;
            w = math.max(w, tw);
          }
        }
        if (e.beat.chordId != null) {
          final name = _chordName(e.beat.chordId!);
          // Akkordnamen dürfen etwas überstehen, aber nicht zu viel.
          w = math.max(w, measurer.width(name, TextRole.chord, _chordSize, bold: true) * 0.85);
        }
        if (e.beat.lyrics.isNotEmpty) {
          w = math.max(w, measurer.width(e.beat.lyrics.first, TextRole.lyrics, _lyricsSize) + 0.6);
        }
        minW = math.max(minW, w);
      }
      c.minW = minW;
    }
    m.padL = 1.1 + (m.mb.repeatStart ? 1.5 : 0);
    m.padR = 0.5 + (m.mb.hasRepeatEnd ? 1.5 : 0);
    if (m.empty) m.padL += 0;
  }

  // ───────────────────────── Zeilen ─────────────────────────

  double _keyWidth(KeySignature k) => k.fifths.abs() * 1.0 + (k.fifths == 0 ? 0 : 0.6);
  double _timeWidth(TimeSignature t) => math.max(t.beats.toString().length, t.beatType.toString().length) * 1.8 + 1.0;

  double _headerWidth(_Meas m, bool firstSystem) {
    var w = 0.8 + 2.7 + 0.9;
    if (_tabOnly) w += math.max(0.0, _tabClefWidth - 2.7);
    if (!_tabOnly) w += _keyWidth(m.mb.key);
    if (firstSystem || m.timeChange) w += _timeWidth(m.mb.time);
    return w;
  }

  double _measureNatural(_Meas m, bool atStart) {
    var w = m.padL + m.padR + m.colSum;
    if (m.empty) w += 6;
    if (!atStart) {
      if (m.keyChange) w += _keyWidth(m.mb.key) + 0.4;
      if (m.timeChange) w += _timeWidth(m.mb.time);
    }
    return w;
  }

  List<_System> _breakSystems() {
    final avail = options.contentWidth;
    final systems = <_System>[];
    final hint = options.useLayoutHint ? _track.layoutHint : null;
    var i = 0;
    var hintIndex = 0;
    while (i < _measures.length) {
      final first = systems.isEmpty;
      var header = _headerWidth(_measures[i], first);
      int count;
      if (hint != null && hint.isNotEmpty) {
        final want = hint.length == 1 ? hint.first : (hintIndex < hint.length ? hint[hintIndex] : 0);
        count = want > 0 ? want : 0;
        hintIndex++;
      } else {
        count = 0;
      }
      if (count > 0) {
        count = math.min(count, _measures.length - i);
        // Passt die Vorgabe nicht, weniger Takte nehmen.
        while (count > 1) {
          var w = header;
          for (var k = 0; k < count; k++) {
            w += _measureNatural(_measures[i + k], k == 0);
          }
          if (w <= avail * 1.02) break;
          count--;
        }
      } else {
        var w = header;
        count = 0;
        while (i + count < _measures.length) {
          final add = _measureNatural(_measures[i + count], count == 0);
          if (count > 0 && w + add > avail) break;
          w += add;
          count++;
        }
      }
      final s = _System(_measures.sublist(i, i + count))
        ..header = header
        ..first = first;
      systems.add(s);
      i += count;
    }
    // Breiten verteilen (Blocksatz)
    for (var k = 0; k < systems.length; k++) {
      final s = systems[k];
      s.x0 = options.marginLeft;
      s.x1 = options.marginLeft + avail;
      var fixed = s.header;
      var springs = 0.0;
      for (var j = 0; j < s.measures.length; j++) {
        final m = s.measures[j];
        final nat = _measureNatural(m, j == 0);
        final cs = m.colSum + (m.empty ? 6 : 0);
        fixed += nat - cs;
        springs += cs;
      }
      var factor = springs > 0 ? (avail - fixed) / springs : 1.0;
      final last = k == systems.length - 1;
      if (last && factor > 1.6 && (hint == null)) {
        factor = 1.3;
        // Letzte Zeile nicht über die ganze Breite ziehen.
      }
      if (factor < 0.5) factor = 0.5;
      var x = s.x0 + s.header;
      for (var j = 0; j < s.measures.length; j++) {
        final m = s.measures[j];
        m.x = j == 0 ? s.x0 : x;
        var cx = x + m.padL;
        if (j > 0) {
          if (m.keyChange) cx += _keyWidth(m.mb.key) + 0.4;
          if (m.timeChange) cx += _timeWidth(m.mb.time);
        }
        m.changeW = j > 0
            ? (m.keyChange ? _keyWidth(m.mb.key) + 0.4 : 0) + (m.timeChange ? _timeWidth(m.mb.time) : 0)
            : 0;
        for (final c in m.cols) {
          c.x = cx + c.accW;
          cx += c.natural * factor;
        }
        if (m.empty) cx += 6 * factor;
        cx += m.padR;
        m.w = cx - m.x;
        x = cx;
      }
      if (last && factor != (springs > 0 ? (avail - fixed) / springs : 1.0)) s.x1 = x;
      // Rundungsfehler: letzte Taktlinie genau ans Zeilenende.
      final lastM = s.measures.last;
      lastM.w = s.x1 - lastM.x;
    }
    return systems;
  }

  // ───────────────────────── Seiten ─────────────────────────

  ScoreLayout _paginate(List<_System> systems) {
    final pages = <PageDisplay>[];
    var page = PageDisplay(options.pageWidth, options.pageHeight);
    pages.add(page);
    var y = options.marginTop;
    y = _drawHeader(page, y);
    y = _drawSetup(page, y);
    y = _drawDiagrams(page, y);
    var prevKey = const KeySignature(0);
    var firstOnPage = true;
    for (var si = 0; si < systems.length; si++) {
      final s = systems[si];
      final out = _SystemBuilder(this, s, si, systems).build(prevKey);
      prevKey = s.measures.last.mb.key;
      final height = out.bottom - out.top;
      var top = firstOnPage ? y : y + options.systemGap;
      if (top + height > options.pageHeight - options.marginBottom && !firstOnPage) {
        page = PageDisplay(options.pageWidth, options.pageHeight);
        pages.add(page);
        top = options.marginTop;
      } else if (top + height > options.pageHeight - options.marginBottom && pages.length == 1 && si == 0) {
        // passt nicht einmal auf die erste Seite: trotzdem setzen
      }
      final dy = top - out.top;
      for (final it in out.items) {
        page.items.add(shift(it, 0, dy));
      }
      page.systems.add(
        SystemBox(top: top, bottom: top + height, firstBar: s.measures.first.index, lastBar: s.measures.last.index),
      );
      y = top + height;
      firstOnPage = false;
    }
    // Copyright unten auf der ersten Seite, Seitenzahlen
    final cr = score.info.copyright;
    if (cr.isNotEmpty) {
      pages.first.items.add(
        TextItem(
          cr,
          options.pageWidth / 2,
          options.pageHeight - options.marginBottom / 2,
          TextRole.small,
          _smallSize,
          align: TextAlign.center,
        ),
      );
    }
    if (pages.length > 1) {
      for (var p = 0; p < pages.length; p++) {
        pages[p].items.add(
          TextItem(
            '${p + 1} / ${pages.length}',
            options.pageWidth - options.marginRight,
            options.pageHeight - options.marginBottom / 2,
            TextRole.small,
            _smallSize,
            align: TextAlign.right,
          ),
        );
      }
    }
    return ScoreLayout(pages);
  }

  double _drawHeader(PageDisplay page, double y) {
    final info = score.info;
    final cx = options.pageWidth / 2;
    if (info.title.isNotEmpty) {
      y += 3.0;
      page.items.add(TextItem(info.title, cx, y, TextRole.title, 3.2, align: TextAlign.center, bold: true));
      y += 1.2;
    }
    if (info.subtitle.isNotEmpty) {
      y += 2.0;
      page.items.add(TextItem(info.subtitle, cx, y, TextRole.subtitle, 1.8, align: TextAlign.center));
      y += 0.6;
    }
    if (info.artist.isNotEmpty) {
      y += 1.8;
      page.items.add(TextItem(info.artist, cx, y, TextRole.credit, 1.5, align: TextAlign.center));
      y += 0.6;
    }
    return y + 2.5;
  }

  // ───────────────────────── Kapo, Stimmung, Griffbilder ─────────────────────────

  /// TAB-Zeichen: Name und Grösse (auf die Höhe der Tabulatur gestreckt).
  String get _tabClef => _track.staff.stringCount == 4 ? '4stringTabClef' : '6stringTabClef';
  double get _tabClefScale =>
      ((_track.staff.stringCount - 1) * options.tabLineSpacing * 0.82) / Glyphs.get(_tabClef).height;
  double get _tabClefWidth => Glyphs.get(_tabClef).right * _tabClefScale;

  /// Übliche Stimmungen (tiefste Saite zuerst): dafür braucht es keine Saitennamen.
  static const _standardTunings = [
    [40, 45, 50, 55, 59, 64], // Gitarre
    [35, 40, 45, 50, 55, 59, 64], // 7-saitig
    [30, 35, 40, 45, 50, 55, 59, 64], // 8-saitig
    [28, 33, 38, 43], // Bass
    [23, 28, 33, 38, 43], // 5-saitiger Bass
    [28, 33, 38, 43, 48], // 5-saitiger Bass mit hoher C-Saite
    [23, 28, 33, 38, 43, 48], // 6-saitiger Bass
    [67, 60, 64, 69], // Ukulele
  ];

  bool get _standardTuning {
    final t = _track.staff.tuning;
    return _standardTunings.any(
      (s) => s.length == t.length && List.generate(s.length, (i) => s[i] == t[i]).every((b) => b),
    );
  }

  /// Stimmung mit ♭ schreiben (z. B. E♭ A♭ D♭ G♭ B♭ E♭), sonst mit ♯.
  late final bool _flatTuning = _track.staff.tuning.any((m) => const {3, 8, 10}.contains(m % 12));

  /// Name einer Saite (Tonklasse ohne Oktave).
  String _noteName(int midi) {
    final pc = midi % 12;
    final names = _flatTuning
        ? ['C', 'D♭', 'D', 'E♭', 'E', 'F', 'G♭', 'G', 'A♭', 'A', 'B♭', 'B']
        : ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'];
    var n = names[pc];
    if (options.germanNoteNames) {
      if (n == 'B') n = 'H';
      if (n == 'B♭') n = 'B';
    }
    return n;
  }

  /// Kapo und (ohne Tabulatur) eine besondere Stimmung über der ersten Zeile.
  double _drawSetup(PageDisplay page, double y) {
    final staff = _track.staff;
    if (!staff.isStringed) return y;
    final parts = <String>[];
    if (staff.capo > 0) parts.add('Capo ${staff.capo}');
    if (!_tab && !_standardTuning) parts.add(staff.tuning.map(_noteName).join(' '));
    if (parts.isEmpty) return y;
    y += 1.4;
    page.items.add(TextItem(parts.join('   ·   '), options.marginLeft, y, TextRole.text, _textSize, bold: true));
    return y + 1.6;
  }

  /// Griffbild für einen Akkord: aus der Datei, sonst aus der eingebauten Sammlung.
  ChordDiagram? _diagramFor(ChordDef def) {
    final staff = _track.staff;
    final d = def.diagram;
    if (d != null && d.stringCount == staff.stringCount) {
      if (!d.visible) return null;
      if (d.played >= 3) return d;
    }
    // Die Sammlung gilt für Griffe ohne Kapo.
    if (staff.capo != 0) return null;
    return ChordLibrary.lookup(def.name, staff.tuning);
  }

  double _drawDiagrams(PageDisplay page, double y) {
    if (!options.showChordDiagrams || !_track.staff.isStringed || _track.chords.isEmpty) return y;
    // Akkorde in der Reihenfolge ihres ersten Auftretens
    final names = <String>{};
    final list = <(String, ChordDiagram)>[];
    for (final bar in _track.bars) {
      for (final v in bar.voices) {
        for (final b in v.beats) {
          final id = b.chordId;
          if (id == null) continue;
          final def = _track.chords[id];
          if (def == null || def.name.trim().isEmpty || names.contains(def.name)) continue;
          names.add(def.name);
          final d = _diagramFor(def);
          if (d != null) list.add((_chordName(id), d));
        }
      }
    }
    if (list.isEmpty) return y;
    const nameSize = 1.35;
    const fs = 1.0; // Bundabstand
    const gap = 1.6;
    final n = _track.staff.stringCount;
    final ss = n <= 6 ? 0.8 : 0.65; // Saitenabstand
    const frets = 5;
    final gridW = (n - 1) * ss;
    var cw = gridW + 2.6;
    for (final (name, _) in list) {
      cw = math.max(cw, measurer.width(name, TextRole.chord, nameSize, bold: true) + 0.6);
    }
    final perRow = math.max(1, ((options.contentWidth + gap) / (cw + gap)).floor());
    final rowH = 2.6 + frets * fs + 1.8;
    y += 0.8;
    for (var r = 0; r * perRow < list.length; r++) {
      final row = list.skip(r * perRow).take(perRow).toList();
      final total = row.length * cw + (row.length - 1) * gap;
      var x = options.marginLeft + (options.contentWidth - total) / 2;
      for (final (name, d) in row) {
        _diagram(page, name, d, x + (cw - gridW) / 2, y, nameSize, ss, fs, frets);
        x += cw + gap;
      }
      y += rowH;
    }
    return y + 0.4;
  }

  /// Ein Griffbild: Name, darunter leere (o) und nicht gespielte (×) Saiten, Gitter mit Punkten.
  void _diagram(
    PageDisplay page,
    String name,
    ChordDiagram d,
    double gx,
    double y,
    double nameSize,
    double ss,
    double fs,
    int frets,
  ) {
    final items = page.items;
    final n = d.stringCount;
    final gridW = (n - 1) * ss;
    items.add(TextItem(name, gx + gridW / 2, y + 1.1, TextRole.chord, nameSize, align: TextAlign.center, bold: true));
    final gy = y + 2.6;
    final pressed = d.frets.where((f) => f > 0);
    final maxF = pressed.isEmpty ? 0 : pressed.reduce(math.max);
    final minF = pressed.isEmpty ? 1 : pressed.reduce(math.min);
    final start = maxF <= frets ? 1 : minF;
    // Gitter
    for (var i = 0; i < n; i++) {
      items.add(LineItem(gx + i * ss, gy, gx + i * ss, gy + frets * fs, 0.09));
    }
    for (var k = 0; k <= frets; k++) {
      items.add(LineItem(gx - 0.045, gy + k * fs, gx + gridW + 0.045, gy + k * fs, 0.09));
    }
    if (start == 1) {
      items.add(LineItem(gx - 0.045, gy - 0.15, gx + gridW + 0.045, gy - 0.15, 0.3));
    } else {
      items.add(TextItem('${start}fr', gx + gridW + 0.4, gy + fs * 0.5 + 0.35, TextRole.small, 0.95));
    }
    // Barrés
    final barreAt = <int>{};
    for (final b in d.barres) {
      final row = b.fret - start;
      if (row < 0 || row >= frets) continue;
      final cy = gy + (row + 0.5) * fs;
      items.add(LineItem(gx + b.from * ss, cy, gx + b.to * ss, cy, 0.6, roundCap: true));
      for (var i = b.from; i <= b.to; i++) {
        if (d.frets[i] == b.fret) barreAt.add(i);
      }
    }
    // Punkte und Markierungen über dem Sattel
    for (var i = 0; i < n && i < d.frets.length; i++) {
      final f = d.frets[i];
      final cx = gx + i * ss;
      final my = gy - 0.75;
      if (f < 0) {
        const r = 0.22;
        items.add(LineItem(cx - r, my - r, cx + r, my + r, 0.1));
        items.add(LineItem(cx - r, my + r, cx + r, my - r, 0.1));
      } else if (f == 0) {
        items.add(PathItem(ring(cx, my, 0.24, 0.1)));
      } else if (!barreAt.contains(i)) {
        final row = f - start;
        if (row >= 0 && row < frets) items.add(PathItem(circle(cx, gy + (row + 0.5) * fs, 0.3)));
      }
    }
  }

  // ───────────────────────── Hilfen ─────────────────────────

  String _chordName(int id) {
    final name = _track.chords[id]?.name ?? '';
    return name.replaceAll('#', '♯').replaceAllMapped(RegExp(r'([A-G])b'), (m) => '${m[1]}♭');
  }

  String _fretText(Note n, bool parens) {
    var t = n.dead ? 'x' : '${n.fret}';
    // Flageolett: Bund in spitzen Klammern
    if (n.harmonic && !n.dead) t = '<$t>';
    return (parens || n.ghost) ? '($t)' : t;
  }
}

/// Baut eine Zeile (System) in eigenen Koordinaten: oberste Notenlinie bei y = 0.
class _SystemBuilder {
  _SystemBuilder(this.e, this.s, this.index, this.all);
  final Engraver e;
  final _System s;
  final int index;
  final List<_System> all;

  final items = <DisplayItem>[];
  double top = 0;
  double bottom = 4;

  Track get track => e._track;
  int get firstBar => s.measures.first.index;
  int get lastBar => s.measures.last.index;
  bool inSystem(_Ev ev) => ev.bar >= firstBar && ev.bar <= lastBar;

  void add(DisplayItem it) {
    items.add(it);
    final (t, b) = _bounds(it);
    top = math.min(top, t);
    bottom = math.max(bottom, b);
  }

  (double, double) _bounds(DisplayItem it) {
    switch (it) {
      case GlyphItem g:
        final d = Glyphs.get(g.name);
        return (g.y - d.top * g.scale, g.y - d.bottom * g.scale);
      case LineItem l:
        return (math.min(l.y1, l.y2) - l.thickness / 2, math.max(l.y1, l.y2) + l.thickness / 2);
      case RectItem r:
        return (r.y, r.y + r.height);
      case TextItem t:
        return (t.y - t.size * 0.8, t.y + t.size * 0.25);
      case PathItem p:
        var mn = double.infinity, mx = -double.infinity;
        final c = p.commands;
        var i = 0;
        while (i < c.length) {
          final op = c[i].toInt();
          final n = (op == 0 || op == 1) ? 1 : (op == 3 ? 3 : 0);
          for (var k = 0; k < n; k++) {
            final y = c[i + 2 + k * 2];
            mn = math.min(mn, y);
            mx = math.max(mx, y);
          }
          i += 1 + n * 2;
        }
        return (mn.isFinite ? mn : 0, mx.isFinite ? mx : 0);
    }
  }

  void glyph(String name, double x, double y, {double scale = 1}) => add(GlyphItem(name, x, y, scale: scale));
  void line(double x1, double y1, double x2, double y2, double t, {(double, double)? dash}) =>
      add(LineItem(x1, y1, x2, y2, t, dash: dash));
  void text(
    String t,
    double x,
    double y,
    TextRole role,
    double size, {
    TextAlign align = TextAlign.left,
    bool bold = false,
    bool italic = false,
  }) => add(TextItem(t, x, y, role, size, align: align, bold: bold, italic: italic));
  double tw(String t, TextRole role, double size, {bool bold = false, bool italic = false}) =>
      e.measurer.width(t, role, size, bold: bold, italic: italic);

  Iterable<_Ev> get events sync* {
    for (final m in s.measures) {
      for (final c in m.cols) {
        yield* c.evs;
      }
    }
  }

  ({List<DisplayItem> items, double top, double bottom}) build(KeySignature prevKey) {
    if (e._tabOnly) return _buildTabOnly();
    _staff();
    _header();
    for (var j = 0; j < s.measures.length; j++) {
      _measure(s.measures[j], j);
    }
    _stemsAndBeams();
    for (final ev in events) {
      _notes(ev);
    }
    _ties();
    _legatoAndSlides();
    _tuplets();
    final notesTop = top;
    final notesBottom = bottom;
    _above(notesTop);
    _below(notesBottom);
    if (e._tab) _tabStaff();
    // Linie links über alle Notensysteme der Zeile
    if (e._tab) line(s.x0, 0 - _staffLineT / 2, s.x0, _tabBottom + _staffLineT / 2, _thinT);
    return (items: items, top: top, bottom: bottom);
  }

  /// Zeile nur mit Tabulatur: Rhythmus darunter, Akkorde und Formteile darüber.
  ({List<DisplayItem> items, double top, double bottom}) _buildTabOnly() {
    _tabStaff();
    final m0 = s.measures.first;
    final x = s.x0 + 0.8 + math.max(2.7, e._tabClefWidth) + 0.9;
    final mid = (_tabTop + _tabBottom) / 2;
    if (s.first || m0.timeChange) _timeSig(m0.mb.time, x, center: mid);
    for (var j = 1; j < s.measures.length; j++) {
      final m = s.measures[j];
      if (m.timeChange) _timeSig(m.mb.time, m.x + 0.3, center: mid);
    }
    if (m0.index > 0) text('${m0.index + 1}', s.x0, _tabTop - 1.0, TextRole.barNumber, _smallSize);
    final rhythmBottom = _tabRhythm();
    // Anschlag und Fermate über der Tabulatur
    final aboveY = top - 0.6;
    for (final ev in events) {
      if (ev.voice != 0) continue;
      var y = aboveY;
      final cx = ev.x + ev.headW / 2;
      if (ev.beat.pickStroke != 0) {
        final name = ev.beat.pickStroke > 0 ? 'stringsDownBow' : 'stringsUpBow';
        final g = Glyphs.get(name);
        glyph(name, cx - g.right / 2, y);
        y -= g.height + 0.4;
      }
      if (ev.beat.fermata) {
        final g = Glyphs.get('fermataAbove');
        glyph('fermataAbove', cx - g.right / 2, y);
      }
    }
    _above(top);
    _below(rhythmBottom);
    return (items: items, top: top, bottom: bottom);
  }

  /// Rhythmus unter der Tabulatur (Hauptstimme): Hälse nach unten, waagrechte Balken.
  /// Gibt die Unterkante zurück.
  double _tabRhythm() {
    final y0 = _tabBottom + 1.0;
    final yEnd = _tabBottom + 3.6;
    final restY = (y0 + yEnd) / 2;
    double stemX(_Ev ev) => ev.x + ev.headW / 2;
    for (final ev in events) {
      if (ev.voice != 0) continue;
      final v = ev.value;
      if (ev.isRest) {
        if (ev.fullBarRest) {
          final m = s.measures.firstWhere((m) => m.index == ev.bar);
          final start = m == s.measures.first ? _contentStart : m.x;
          final mid = (start + m.x + m.w) / 2;
          glyph('restWhole', mid - Glyphs.get('restWhole').right * 0.8 / 2, restY - 0.5, scale: 0.8);
          continue;
        }
        final name = switch (v) {
          NoteValue.doubleWhole => 'restDoubleWhole',
          NoteValue.whole => 'restWhole',
          NoteValue.half => 'restHalf',
          NoteValue.quarter => 'restQuarter',
          NoteValue.eighth => 'rest8th',
          NoteValue.sixteenth => 'rest16th',
          NoteValue.thirtySecond => 'rest32nd',
          NoteValue.sixtyFourth => 'rest64th',
          NoteValue.hundredTwentyEighth => 'rest128th',
        };
        final g = Glyphs.get(name);
        final y = v == NoteValue.whole || v == NoteValue.doubleWhole ? restY - 0.5 : restY;
        glyph(name, ev.x + ev.headW / 2 - g.right * 0.8 / 2, y, scale: 0.8);
        for (var d = 0; d < ev.beat.duration.dots; d++) {
          glyph('augmentationDot', ev.x + ev.headW / 2 + g.right * 0.4 + 0.3 + d * 0.5, restY - 0.5);
        }
        continue;
      }
      if (v.log2 < 1) {
        // Ganze: nur Punkte, kein Hals
        ev.stemTip = y0;
        continue;
      }
      final x = stemX(ev);
      // Halbe: kurzer Hals
      final from = v == NoteValue.half ? restY : y0;
      line(x, from, x, yEnd, _stemT);
      ev.stemBase = from;
      ev.stemTip = yEnd;
      if (ev.beam == null && v.hasFlag) {
        final name = switch (v.flagCount) {
          1 => 'flag8thDown',
          2 => 'flag16thDown',
          3 => 'flag32ndDown',
          4 => 'flag64thDown',
          _ => 'flag128thDown',
        };
        final a = Glyphs.get(name).anchors['stemDownSW'] ?? const Pt(0, 0);
        glyph(name, x - _stemT / 2 - a.x, yEnd + a.y);
      }
      for (var d = 0; d < ev.beat.duration.dots; d++) {
        glyph('augmentationDot', x + 0.45 + d * 0.5, (from + yEnd) / 2 - 0.2);
      }
      // Tremolo-Picking: Striche am Hals
      final n = ev.beat.tremolo;
      for (var k = 0; k < n; k++) {
        final yy = (from + yEnd) / 2 + (k - (n - 1) / 2) * 0.7;
        add(PathItem([0, x - 0.5, yy + 0.2, 1, x + 0.5, yy - 0.15, 1, x + 0.5, yy - 0.4, 1, x - 0.5, yy - 0.05, 4]));
      }
    }
    // Balken, waagrecht am Halsende
    for (final m in s.measures) {
      for (final g in m.beams) {
        final evs = g.evs.where((ev) => ev.voice == 0 && !ev.isRest).toList();
        if (evs.length < 2) continue;
        final maxFlags = evs.map((ev) => ev.value.flagCount).reduce(math.max);
        add(beam(stemX(evs.first) - _stemT / 2, yEnd, stemX(evs.last) + _stemT / 2, yEnd, _beamT, down: false));
        for (var level = 2; level <= maxFlags; level++) {
          final y = yEnd - (level - 1) * (_beamT + _beamGap);
          var k = 0;
          while (k < evs.length) {
            if (evs[k].value.flagCount < level) {
              k++;
              continue;
            }
            var j = k;
            while (j + 1 < evs.length && evs[j + 1].value.flagCount >= level) {
              j++;
            }
            double xa, xb;
            if (j > k) {
              xa = stemX(evs[k]) - _stemT / 2;
              xb = stemX(evs[j]) + _stemT / 2;
            } else {
              final ev = evs[k];
              final toLeft =
                  k == evs.length - 1 || (k > 0 && ev.beat.duration.dots == 0 && evs[k - 1].beat.duration.dots > 0);
              xa = toLeft ? stemX(ev) + _stemT / 2 - 1.1 : stemX(ev) - _stemT / 2;
              xb = xa + 1.1;
            }
            add(beam(xa, y, xb, y, _beamT, down: false));
            k = j + 1;
          }
        }
      }
    }
    _tuplets(belowY: yEnd + 0.2);
    return yEnd + 0.5;
  }

  // ── Notensystem ──

  void _staff() {
    for (var k = 0; k < 5; k++) {
      line(s.x0, k.toDouble(), s.x1, k.toDouble(), _staffLineT);
    }
  }

  double _keyYOffset(Clef c) => switch (c) {
    Clef.bass => 1.0,
    Clef.alto => 0.5,
    Clef.tenor => -0.5,
    _ => 0.0,
  };

  /// Tonart zeichnen ab x; gibt die Breite zurück.
  double _keySig(KeySignature k, double x, Clef clef) {
    const sharpY = [0.0, 1.5, -0.5, 1.0, 2.5, 0.5, 2.0];
    const flatY = [2.0, 0.5, 2.5, 1.0, 3.5, 1.5, 4.0];
    final off = _keyYOffset(clef);
    final n = k.fifths.abs().clamp(0, 7);
    for (var i = 0; i < n; i++) {
      if (k.fifths > 0) {
        glyph('accidentalSharp', x + i * 1.0, sharpY[i] + off);
      } else {
        glyph('accidentalFlat', x + i * 1.0, flatY[i] + off);
      }
    }
    return n * 1.0;
  }

  void _timeSig(TimeSignature t, double x, {double center = 2}) {
    void number(String digits, double y) {
      final w = digits.length * 1.8;
      var cx = x + (math.max(t.beats.toString().length, t.beatType.toString().length) * 1.8 - w) / 2;
      for (final ch in digits.split('')) {
        glyph('timeSig$ch', cx, y);
        cx += 1.8;
      }
    }

    number('${t.beats}', center - 1);
    number('${t.beatType}', center + 1);
  }

  String _clefGlyph(Clef c) => switch (c) {
    Clef.treble8vb => 'gClef8vb',
    Clef.bass => 'fClef',
    Clef.alto || Clef.tenor => 'cClef',
    Clef.neutral => 'unpitchedPercussionClef1',
    _ => 'gClef',
  };

  double _clefY(Clef c) => switch (c) {
    Clef.bass => 1,
    Clef.alto => 2,
    Clef.tenor => 1,
    Clef.neutral => 2,
    _ => 3,
  };

  void _header() {
    final m = s.measures.first;
    final clef = m.bar.clef;
    var x = s.x0 + 0.8;
    glyph(_clefGlyph(clef), x, _clefY(clef));
    x += 2.7 + 0.9;
    final kw = _keySig(m.mb.key, x, clef);
    x += kw + (kw > 0 ? 0.6 : 0);
    if (s.first || m.timeChange) _timeSig(m.mb.time, x);
    // Taktnummer über dem Schlüssel (ausser beim ersten Takt)
    if (m.index > 0) text('${m.index + 1}', s.x0, -2.2, TextRole.barNumber, _smallSize);
  }

  // ── Takt: Taktlinien, Wiederholungen, Wechsel ──

  double get _contentStart => s.x0 + s.header;

  void _measure(_Meas m, int j) {
    final startX = j == 0 ? _contentStart : m.x;
    var x = startX;
    if (j > 0) {
      if (m.keyChange) {
        x += 0.4;
        x += _keySig(m.mb.key, x, m.bar.clef) + 0.4;
      }
      if (m.timeChange) {
        _timeSig(m.mb.time, x + 0.3);
      }
    }
    if (m.mb.repeatStart) {
      final rx = j == 0 ? _contentStart - 0.2 : m.x;
      _repeatStart(rx, 0, 4);
    }
    // Taktlinie am Ende
    final end = m.x + m.w;
    final isLast = m.index == e.score.masterBars.length - 1;
    _barline(end, 0, 4, m, isLast);
    if (m.empty || (m.voices.isNotEmpty && m.voices.every((v) => v.isEmpty))) {
      final mid = ((j == 0 ? _contentStart : m.x) + end) / 2;
      glyph('restWhole', mid - Glyphs.get('restWhole').right / 2, 1);
    }
  }

  void _repeatStart(double x, double y0, double y1) {
    line(x + _thickT / 2, y0, x + _thickT / 2, y1, _thickT);
    final tx = x + _thickT + _barSep + _thinT / 2;
    line(tx, y0, tx, y1, _thinT);
    final mid = (y0 + y1) / 2;
    final d = (y1 - y0) <= 4.01 ? 0.5 : 0.75;
    glyph('repeatDot', tx + 0.3, mid - d);
    glyph('repeatDot', tx + 0.3, mid + d);
  }

  void _barline(double x, double y0, double y1, _Meas m, bool isLast) {
    final mid = (y0 + y1) / 2;
    final d = (y1 - y0) <= 4.01 ? 0.5 : 0.75;
    if (m.mb.hasRepeatEnd) {
      line(x - _thickT / 2, y0, x - _thickT / 2, y1, _thickT);
      final tx = x - _thickT - _barSep - _thinT / 2;
      line(tx, y0, tx, y1, _thinT);
      glyph('repeatDot', tx - 0.3 - 0.4, mid - d);
      glyph('repeatDot', tx - 0.3 - 0.4, mid + d);
      if (m.mb.repeatEnd > 2 && y0 == 0) {
        text('×${m.mb.repeatEnd}', x, y0 - 0.7, TextRole.small, _smallSize, align: TextAlign.right);
      }
    } else if (isLast) {
      line(x - _thickT / 2, y0, x - _thickT / 2, y1, _thickT);
      line(x - _thickT - _barSep - _thinT / 2, y0, x - _thickT - _barSep - _thinT / 2, y1, _thinT);
    } else if (m.mb.doubleBar) {
      line(x - _thinT / 2, y0, x - _thinT / 2, y1, _thinT);
      line(x - _thinT * 1.5 - _barSep, y0, x - _thinT * 1.5 - _barSep, y1, _thinT);
    } else {
      line(x - _thinT / 2, y0, x - _thinT / 2, y1, _thinT);
    }
  }

  // ── Hälse und Balken ──

  void _stemsAndBeams() {
    // Hälse ohne Balken
    for (final ev in events) {
      if (ev.isRest || ev.heads.isEmpty) continue;
      final up = ev.stemUp;
      final anchor = up
          ? (Glyphs.get(ev.heads.first.glyph).anchors['stemUpSE']?.y ?? 0.168)
          : (Glyphs.get(ev.heads.first.glyph).anchors['stemDownNW']?.y ?? -0.168);
      if (up) {
        ev.stemBase = ev.bottom - anchor;
        var tip = ev.top - 3.5 - math.max(0, ev.value.flagCount - 1) * 0.6;
        if (ev.beat.slashed) tip = ev.top - anchor - 3.0;
        ev.stemTip = math.min(tip, 2.0);
      } else {
        ev.stemBase = ev.top - anchor;
        var tip = ev.bottom + 3.5 + math.max(0, ev.value.flagCount - 1) * 0.6;
        if (ev.beat.slashed) tip = ev.bottom - anchor + 3.0;
        ev.stemTip = math.max(tip, 2.0);
      }
    }
    // Balken
    for (final m in s.measures) {
      for (final g in m.beams) {
        _beamGroup(g);
      }
    }
    // Zeichnen
    for (final ev in events) {
      if (ev.isRest || ev.heads.isEmpty || !ev.hasStem) continue;
      final x = ev.stemX;
      line(x, ev.stemBase, x, ev.stemTip, _stemT);
      if (ev.beam == null && ev.value.hasFlag) {
        final n = ev.value.flagCount;
        final name = switch (n) {
          1 => 'flag8th',
          2 => 'flag16th',
          3 => 'flag32nd',
          4 => 'flag64th',
          _ => 'flag128th',
        };
        if (ev.stemUp) {
          final g = Glyphs.get('${name}Up');
          final a = g.anchors['stemUpNW'] ?? const Pt(0, 0);
          glyph('${name}Up', x - _stemT / 2 - a.x, ev.stemTip + a.y);
        } else {
          final g = Glyphs.get('${name}Down');
          final a = g.anchors['stemDownSW'] ?? const Pt(0, 0);
          glyph('${name}Down', x - _stemT / 2 - a.x, ev.stemTip + a.y);
        }
      }
    }
  }

  void _beamGroup(_BeamGroup g) {
    final evs = g.evs;
    final up = g.up;
    final first = evs.first, last = evs.last;
    final x1 = first.stemX, x2 = last.stemX;
    final dxTotal = (x2 - x1).abs() < 0.01 ? 1.0 : x2 - x1;
    // Neigung aus den äusseren Köpfen, gedämpft und begrenzt
    final yFirst = up ? first.top : first.bottom;
    final yLast = up ? last.top : last.bottom;
    var slopeDy = ((yLast - yFirst) * 0.5).clamp(-1.0, 1.0);
    if (evs.length > 2) {
      // Innere Noten weiter aussen als die Enden: waagrecht
      final inner = evs.sublist(1, evs.length - 1);
      final extreme = up ? inner.map((e) => e.top).reduce(math.min) : inner.map((e) => e.bottom).reduce(math.max);
      if (up ? extreme < math.min(yFirst, yLast) : extreme > math.max(yFirst, yLast)) slopeDy = 0;
    }
    final maxFlags = evs.map((e) => e.value.flagCount).reduce(math.max);
    final minLen = 3.25 + math.max(0, maxFlags - 2) * (_beamT + _beamGap);
    // Startwert so wählen, dass jeder Hals mindestens minLen lang ist
    double beamAt(double start, double x) => start + slopeDy * (x - x1) / dxTotal;
    double start;
    if (up) {
      start = double.infinity;
      for (final ev in evs) {
        final need = ev.top - minLen - slopeDy * (ev.stemX - x1) / dxTotal;
        start = math.min(start, need);
      }
      // Hälse reichen mindestens bis zur Mittellinie
      start = math.min(start, 2.0 - math.max(0, slopeDy));
    } else {
      start = -double.infinity;
      for (final ev in evs) {
        final need = ev.bottom + minLen - slopeDy * (ev.stemX - x1) / dxTotal;
        start = math.max(start, need);
      }
      start = math.max(start, 2.0 - math.min(0, slopeDy));
    }
    for (final ev in evs) {
      ev.stemTip = beamAt(start, ev.stemX);
    }
    // Hauptbalken
    final bx1 = x1 - _stemT / 2, bx2 = x2 + _stemT / 2;
    add(beam(bx1, beamAt(start, bx1), bx2, beamAt(start, bx2), _beamT, down: up));
    // Weitere Balken (Sechzehntel usw.)
    for (var level = 2; level <= maxFlags; level++) {
      final off = (level - 1) * (_beamT + _beamGap) * (up ? 1 : -1);
      var k = 0;
      while (k < evs.length) {
        if (evs[k].value.flagCount < level) {
          k++;
          continue;
        }
        var j = k;
        while (j + 1 < evs.length && evs[j + 1].value.flagCount >= level) {
          j++;
        }
        double xa, xb;
        if (j > k) {
          xa = evs[k].stemX - _stemT / 2;
          xb = evs[j].stemX + _stemT / 2;
        } else {
          // Einzelne kurze Note: Stummel zum Nachbarn hin
          final ev = evs[k];
          final toLeft =
              k == evs.length - 1 || (k > 0 && ev.beat.duration.dots == 0 && evs[k - 1].beat.duration.dots > 0);
          if (toLeft) {
            xb = ev.stemX + _stemT / 2;
            xa = xb - 1.1;
          } else {
            xa = ev.stemX - _stemT / 2;
            xb = xa + 1.1;
          }
        }
        add(beam(xa, beamAt(start, xa) + off, xb, beamAt(start, xb) + off, _beamT, down: up));
        k = j + 1;
      }
    }
  }

  // ── Noten und Pausen ──

  void _notes(_Ev ev) {
    final x = ev.x;
    if (ev.isRest) {
      if (ev.fullBarRest) {
        final m = s.measures.firstWhere((m) => m.index == ev.bar);
        final start = m == s.measures.first ? _contentStart : m.x;
        final mid = (start + m.x + m.w) / 2;
        var y = 1.0;
        if (ev.voiceCount > 1) y += ev.voice.isEven ? -2 : 2;
        glyph('restWhole', mid - Glyphs.get('restWhole').right / 2, y);
        return;
      }
      final v = ev.value;
      final name = switch (v) {
        NoteValue.doubleWhole => 'restDoubleWhole',
        NoteValue.whole => 'restWhole',
        NoteValue.half => 'restHalf',
        NoteValue.quarter => 'restQuarter',
        NoteValue.eighth => 'rest8th',
        NoteValue.sixteenth => 'rest16th',
        NoteValue.thirtySecond => 'rest32nd',
        NoteValue.sixtyFourth => 'rest64th',
        NoteValue.hundredTwentyEighth => 'rest128th',
      };
      var y = v == NoteValue.whole || v == NoteValue.doubleWhole ? 1.0 : 2.0;
      if (ev.voiceCount > 1) y += ev.voice.isEven ? -2 : 2;
      glyph(name, x, y);
      for (var d = 0; d < ev.beat.duration.dots; d++) {
        glyph('augmentationDot', x + Glyphs.get(name).right + 0.3 + d * 0.5, 1.5);
      }
      return;
    }
    _graceNotes(ev);
    // Hilfslinien
    final hw = ev.headW;
    var minX = x + ev.heads.map((h) => h.dx).reduce(math.min);
    var maxX = x + hw + ev.heads.map((h) => h.dx).reduce(math.max);
    for (final h in ev.heads) {
      if (h.y <= -1) {
        for (var ly = -1.0; ly >= h.y - 0.01; ly -= 1) {
          line(minX - _ledgerExt, ly, maxX + _ledgerExt, ly, _ledgerT);
        }
      }
      if (h.y >= 5) {
        for (var ly = 5.0; ly <= h.y + 0.01; ly += 1) {
          line(minX - _ledgerExt, ly, maxX + _ledgerExt, ly, _ledgerT);
        }
      }
    }
    for (final h in ev.heads) {
      glyph(h.glyph, x + h.dx, h.y);
      if (h.accidental != null) glyph(h.accidental!, x + h.accX, h.y);
      if (h.note?.ghost ?? false) {
        glyph('accidentalParensLeft', x + h.dx - 0.55, h.y);
        glyph('accidentalParensRight', x + h.dx + h.width + 0.1, h.y);
      }
    }
    // Punkte
    final dots = ev.beat.duration.dots;
    if (dots > 0) {
      var dx = x + ev.heads.map((h) => h.dx + h.width).reduce(math.max) + 0.35;
      if (ev.stemUp && ev.hasStem && ev.beam == null && ev.value.hasFlag) dx += 0.8;
      final ys = <double>{};
      for (final h in ev.heads) {
        var y = h.y;
        if ((y - y.roundToDouble()).abs() < 0.01) y -= 0.5;
        ys.add(y);
      }
      for (final y in ys) {
        for (var d = 0; d < dots; d++) {
          glyph('augmentationDot', dx + d * 0.5, y);
        }
      }
    }
    // Artikulation (gegenüber dem Hals)
    final acc = ev.beat.notes.fold(0, (a, n) => a | n.accent);
    if (acc != 0) {
      final cx = x + hw / 2;
      final below = ev.stemUp;
      var y = below ? math.max(ev.bottom + 1.0, 4.6) : math.min(ev.top - 1.0, -0.6);
      void art(String base) {
        final name = '$base${below ? 'Below' : 'Above'}';
        final g = Glyphs.get(name);
        glyph(name, cx - g.right / 2, below ? y + g.top : y + g.bottom);
        y += below ? g.height + 0.3 : -(g.height + 0.3);
      }

      if (acc & 1 != 0) art('articStaccato');
      if (acc & 16 != 0) art('articTenuto');
      if (acc & 8 != 0) art('articAccent');
      if (acc & 4 != 0) art('articMarcato');
    }
    _aboveNote(ev);
    _tremolo(ev);
  }

  /// Anschlag (auf/ab), Fermate und – ohne Tabulatur – Vibrato über der Note.
  void _aboveNote(_Ev ev) {
    var y = math.min(ev.top - 1.0, -0.6);
    if (ev.stemUp && ev.hasStem) y = math.min(y, ev.stemTip - 0.6);
    final cx = ev.x + ev.headW / 2;
    if (ev.beat.pickStroke != 0) {
      final name = ev.beat.pickStroke > 0 ? 'stringsDownBow' : 'stringsUpBow';
      final g = Glyphs.get(name);
      glyph(name, cx - g.right / 2, y);
      y -= g.height + 0.4;
    }
    if (ev.beat.fermata) {
      final g = Glyphs.get('fermataAbove');
      glyph('fermataAbove', cx - g.right / 2, y);
      y -= g.height + 0.3;
    }
    if (!e._tab && ev.beat.notes.any((n) => n.vibrato)) {
      final end = ev.nextInVoice != null && inSystem(ev.nextInVoice!) ? ev.nextInVoice!.x - 0.4 : ev.x + 3.0;
      add(_wavy(ev.x, end, y - 0.3));
    }
  }

  /// Wellenlinie (Vibrato) von x1 bis x2.
  PathItem _wavy(double x1, double x2, double y) {
    final c = <double>[0, x1, y];
    var x = x1;
    var up = true;
    while (x + 0.35 <= x2) {
      x += 0.35;
      c.addAll([1, x, y + (up ? -0.28 : 0.28)]);
      up = !up;
    }
    return PathItem(c, fill: false, thickness: 0.16);
  }

  /// Tremolo-Picking: schräge Striche am Hals (bei Ganzen über dem Kopf).
  void _tremolo(_Ev ev) {
    final n = ev.beat.tremolo;
    if (n <= 0 || ev.heads.isEmpty) return;
    final cx = ev.hasStem ? ev.stemX : ev.x + ev.headW / 2;
    final up = ev.stemUp;
    // Mitte zwischen Kopf und Halsende (bzw. über dem Kopf ohne Hals)
    final yMid = ev.hasStem ? (ev.stemBase + ev.stemTip) / 2 : ev.top - 1.6;
    for (var k = 0; k < n; k++) {
      final yy = yMid + (k - (n - 1) / 2) * 0.75 * (up ? 1 : -1);
      add(
        PathItem([0, cx - 0.6, yy + 0.25, 1, cx + 0.6, yy - 0.15, 1, cx + 0.6, yy - 0.45, 1, cx - 0.6, yy - 0.05, 4]),
      );
    }
  }

  /// Kleine Noten mit Querstrich vor dem Schlag, mit Bogen zur Hauptnote.
  void _graceNotes(_Ev ev) {
    if (ev.graces.isEmpty) return;
    final top = e._topDiatonic(track.bars[ev.bar].clef);
    final start = ev.col.x - ev.col.accW + 0.25;
    final head = Glyphs.get('noteheadBlack');
    final hw = head.right * _graceScale;
    for (var k = 0; k < ev.graces.length; k++) {
      final g = ev.graces[k];
      final x = start + k * _graceStep;
      final ys = [for (final n in g.notes) (top - n.shown.diatonic) / 2]..sort();
      if (ys.isEmpty) continue;
      // Hilfslinien
      for (final y in ys) {
        for (var ly = -1.0; ly >= y - 0.01; ly -= 1) {
          line(x - 0.25, ly, x + hw + 0.25, ly, _ledgerT * 0.8);
        }
        for (var ly = 5.0; ly <= y + 0.01; ly += 1) {
          line(x - 0.25, ly, x + hw + 0.25, ly, _ledgerT * 0.8);
        }
      }
      for (var i = 0; i < g.notes.length; i++) {
        final n = g.notes[i];
        final y = (top - n.shown.diatonic) / 2;
        glyph(n.dead ? 'noteheadXBlack' : 'noteheadBlack', x, y, scale: _graceScale);
      }
      // Hals nach oben mit Fähnchen und Querstrich
      final sx = x + hw - _stemT * 0.4;
      final tip = ys.first - 2.6;
      line(sx, ys.last - 0.12, sx, tip, _stemT * 0.8);
      final flag = Glyphs.get('flag8thUp');
      final a = flag.anchors['stemUpNW'] ?? const Pt(0, 0);
      glyph('flag8thUp', sx - _stemT * 0.4 - a.x * _graceScale, tip + a.y * _graceScale, scale: _graceScale);
      if (g.grace == GraceType.beforeBeat) line(sx - 0.55, tip + 1.7, sx + 0.8, tip + 0.6, 0.12);
      // Bogen zur Hauptnote
      if (k == ev.graces.length - 1 && ev.heads.isNotEmpty) {
        final yb = math.max(ys.last, ev.bottom) + 0.7;
        final x2 = ev.x + ev.heads.map((h) => h.dx).reduce(math.min) + 0.4;
        if (x2 > x + 0.6) add(arc(x + hw / 2, ys.last + 0.6, x2, yb, up: false, height: 0.5, thickness: 0.18));
      }
    }
  }

  // ── Haltebögen ──

  void _ties() {
    for (final ev in events) {
      for (final t in ev.tiesOut) {
        final up = _tieUp(ev, t.fromHead);
        final y = t.fromHead.y + (up ? -0.6 : 0.6);
        final x1 = ev.x + t.fromHead.dx + t.fromHead.width + 0.12;
        if (inSystem(t.to)) {
          final x2 = t.to.x + t.toHead.dx - 0.12;
          if (x2 > x1) add(arc(x1, y, x2, y, up: up));
        } else {
          add(arc(x1, y, s.x1 - 0.3, y, up: up));
        }
      }
      for (final t in ev.tiesIn) {
        if (inSystem(t.from)) continue;
        final up = _tieUp(t.from, t.fromHead);
        final y = t.toHead.y + (up ? -0.6 : 0.6);
        final x2 = ev.x + t.toHead.dx - 0.12;
        final x1 = math.max(_contentStart - 1.0, x2 - 3.0);
        if (x2 > x1) add(arc(x1, y, x2, y, up: up));
      }
    }
  }

  bool _tieUp(_Ev ev, _Head h) {
    if (ev.heads.length > 1) {
      final idx = ev.heads.indexOf(h);
      return idx < ev.heads.length / 2;
    }
    return !ev.stemUp || !ev.hasStem && h.y < 2;
  }

  // ── Legato (Hammer-on/Pull-off) und Slides in den Noten ──

  void _legatoAndSlides() {
    for (final ev in events) {
      final next = ev.nextInVoice;
      for (final h in ev.heads) {
        final n = h.note;
        if (n == null) continue;
        _Head? target;
        if (next != null && (n.hammerOrigin || n.slide & 3 != 0)) {
          for (final h2 in next.heads) {
            if (h2.note?.string == n.string) target = h2;
          }
        }
        if (n.hammerOrigin) {
          final up = !ev.stemUp;
          final y = h.y + (up ? -0.9 : 0.9);
          final x1 = ev.x + h.dx + h.width / 2;
          if (next != null && target != null && inSystem(next)) {
            final x2 = next.x + target.dx + target.width / 2;
            if (x2 > x1) add(arc(x1, y, x2, target.y + (up ? -0.9 : 0.9), up: up));
          } else {
            add(arc(x1, y, s.x1 - 0.3, y, up: up));
          }
        }
        if (n.slide & 3 != 0) {
          final x1 = ev.x + h.dx + h.width + 0.25;
          if (next != null && target != null && inSystem(next)) {
            final x2 = next.x + target.dx - 0.25 - (target.accidental != null ? -target.accX : 0);
            if (x2 > x1) line(x1, h.y, x2, target.y, 0.14);
          }
        }
      }
    }
  }

  // ── n-tolen ──

  void _tuplets({double? belowY}) {
    for (final m in s.measures) {
      for (final voice in belowY == null ? m.voices : m.voices.take(1)) {
        var k = 0;
        while (k < voice.length) {
          final t = voice[k].beat.duration.tuplet;
          if (t == null) {
            k++;
            continue;
          }
          // Gruppe: so viele Schläge, bis die n-tole voll ist
          var total = Fraction.zero;
          final full = voice[k].beat.duration.value.length.scale(t.normal);
          var j = k;
          while (j < voice.length && voice[j].beat.duration.tuplet?.actual == t.actual) {
            total = total + voice[j].beat.duration.length;
            j++;
            if (total >= full) break;
          }
          final group = voice.sublist(k, j);
          final notes = group.where((ev) => !ev.isRest && ev.heads.isNotEmpty).toList();
          final up = notes.isEmpty ? true : notes.first.stemUp;
          final xa = group.first.x, xb = group.last.x + group.last.headW;
          double y;
          if (belowY != null) {
            y = belowY;
          } else if (notes.isEmpty) {
            y = up ? -1.0 : 5.5;
          } else if (up) {
            y = notes.map((ev) => math.min(ev.stemTip, ev.top)).reduce(math.min) - 1.6;
          } else {
            y = notes.map((ev) => math.max(ev.stemTip, ev.bottom)).reduce(math.max) + 0.4;
          }
          final digits = '${t.actual}'.split('');
          var w = 0.0;
          for (final d in digits) {
            w += Glyphs.get('tuplet$d').right;
          }
          var x = (xa + xb) / 2 - w / 2;
          for (final d in digits) {
            glyph('tuplet$d', x, y + 1.2);
            x += Glyphs.get('tuplet$d').right;
          }
          k = j;
        }
      }
    }
  }

  // ── Über dem System: Häuser, Akkorde, Text, Formteile, Tempo ──

  void _above(double notesTop) {
    var rowTop = math.min(notesTop, -1.0);
    // Häuser
    final hasVolta = s.measures.any((m) => m.mb.endings.isNotEmpty);
    if (hasVolta) {
      final vy = math.min(rowTop - 1.0, -2.2);
      _voltas(vy);
      rowTop = math.min(top, vy - 1.0);
    }
    // Akkordsymbole
    final chordEvs = events.where((ev) => ev.voice == 0 && ev.beat.chordId != null).toList();
    if (chordEvs.isNotEmpty) {
      final y = rowTop - 0.9;
      var lastEnd = -double.infinity;
      for (final ev in chordEvs) {
        final name = e._chordName(ev.beat.chordId!);
        if (name.isEmpty) continue;
        var x = ev.x;
        if (x < lastEnd + 0.6) x = lastEnd + 0.6;
        text(name, x, y, TextRole.chord, _chordSize, bold: true);
        lastEnd = x + tw(name, TextRole.chord, _chordSize, bold: true);
      }
      rowTop = y - _chordSize * 0.8;
    }
    // Freier Text, Sprungzeichen
    final textEvs = events.where((ev) => ev.voice == 0 && ev.beat.text != null).toList();
    final jumps = s.measures.where((m) => m.mb.directions.isNotEmpty).toList();
    if (textEvs.isNotEmpty || jumps.isNotEmpty) {
      final y = rowTop - 0.6;
      for (final ev in textEvs) {
        text(ev.beat.text!, ev.x, y, TextRole.text, _textSize, italic: true);
      }
      for (final m in jumps) {
        _directions(m, y);
      }
      rowTop = math.min(top, y - _textSize * 0.8);
    }
    // Formteile und Tempo
    final sections = s.measures.where((m) => m.mb.section != null && m.mb.section!.label.isNotEmpty).toList();
    final tempos = e.score.tempos.where((t) => t.visible && t.bar >= firstBar && t.bar <= lastBar).toList();
    if (sections.isNotEmpty || tempos.isNotEmpty) {
      final y = rowTop - 0.9;
      final tempoX = <int, double>{};
      for (final m in sections) {
        final label = m.mb.section!.label;
        final x = (m == s.measures.first ? s.x0 : m.x) + 0.2;
        final w = tw(label, TextRole.section, _sectionSize, bold: true);
        add(RectItem(x - 0.4, y - _sectionSize * 0.95, w + 0.8, _sectionSize * 1.35, fill: false, thickness: 0.14));
        text(label, x, y, TextRole.section, _sectionSize, bold: true);
        tempoX[m.index] = x + w + 1.6;
      }
      for (final t in tempos) {
        final m = s.measures.firstWhere((m) => m.index == t.bar);
        var x = tempoX[t.bar] ?? ((m == s.measures.first ? _contentStart : m.x) + 0.5);
        if (t.bar == firstBar && !tempoX.containsKey(t.bar)) x = _contentStart;
        final name = switch (t.unit) {
          NoteValue.half => 'metNoteHalfUp',
          NoteValue.eighth => 'metNote8thUp',
          _ => 'metNoteQuarterUp',
        };
        glyph(name, x, y, scale: 0.8);
        var tx = x + Glyphs.get(name).right * 0.8 + 0.15;
        if (t.dotted) {
          glyph('metAugmentationDot', tx, y, scale: 0.8);
          tx += 0.5;
        }
        final bpm = t.bpm == t.bpm.roundToDouble() ? t.bpm.round().toString() : t.bpm.toStringAsFixed(1);
        text(' = $bpm', tx, y, TextRole.tempo, 1.3);
      }
    }
  }

  void _voltas(double y) {
    final ms = s.measures;
    var k = 0;
    while (k < ms.length) {
      final set = ms[k].mb.endings;
      if (set.isEmpty) {
        k++;
        continue;
      }
      var j = k;
      while (j + 1 < ms.length &&
          _sameSet(ms[j + 1].mb.endings, set) &&
          !ms[j].mb.hasRepeatEnd &&
          !ms[j + 1].mb.repeatStart) {
        j++;
      }
      final startM = ms[k], endM = ms[j];
      final contFromPrev =
          k == 0 &&
          startM.index > 0 &&
          _sameSet(e.score.masterBars[startM.index - 1].endings, set) &&
          !e.score.masterBars[startM.index - 1].hasRepeatEnd;
      final contToNext =
          j == ms.length - 1 &&
          endM.index + 1 < e.score.masterBars.length &&
          _sameSet(e.score.masterBars[endM.index + 1].endings, set) &&
          !endM.mb.hasRepeatEnd;
      final x1 = (k == 0 ? _contentStart - 0.5 : startM.x) + 0.3;
      final x2 = endM.x + endM.w - 0.4;
      line(x1, y, x2, y, 0.16);
      if (!contFromPrev) {
        line(x1, y, x1, y + 1.8, 0.16);
        final sorted = set.toList()..sort();
        text(sorted.map((n) => '$n.').join(' '), x1 + 0.4, y + 1.4, TextRole.volta, 1.2);
      }
      if (endM.mb.hasRepeatEnd && !contToNext) line(x2, y, x2, y + 1.8, 0.16);
      k = j + 1;
    }
  }

  bool _sameSet(Set<int> a, Set<int> b) => a.length == b.length && a.containsAll(b);

  void _directions(_Meas m, double y) {
    final start = (m == s.measures.first ? _contentStart : m.x) + 0.3;
    final end = m.x + m.w - 0.3;
    for (final d in m.mb.directions) {
      switch (d) {
        case Direction.segno || Direction.segnoSegno:
          glyph('segno', start, y + 0.2, scale: 0.7);
        case Direction.coda || Direction.doubleCoda:
          glyph('coda', start, y + 0.2, scale: 0.6);
        case Direction.fine:
          text('Fine', end, y, TextRole.text, _textSize, align: TextAlign.right, italic: true, bold: true);
        case Direction.daCapo:
          text('D.C.', end, y, TextRole.text, _textSize, align: TextAlign.right, italic: true);
        case Direction.daCapoAlFine:
          text('D.C. al Fine', end, y, TextRole.text, _textSize, align: TextAlign.right, italic: true);
        case Direction.daCapoAlCoda:
          text('D.C. al Coda', end, y, TextRole.text, _textSize, align: TextAlign.right, italic: true);
        case Direction.dalSegno:
          text('D.S.', end, y, TextRole.text, _textSize, align: TextAlign.right, italic: true);
        case Direction.dalSegnoAlFine:
          text('D.S. al Fine', end, y, TextRole.text, _textSize, align: TextAlign.right, italic: true);
        case Direction.dalSegnoAlCoda:
          text('D.S. al Coda', end, y, TextRole.text, _textSize, align: TextAlign.right, italic: true);
        case Direction.toCoda:
          text('To Coda', end - 2.6, y, TextRole.text, _textSize, align: TextAlign.right, italic: true);
          glyph('coda', end - 2.3, y + 0.2, scale: 0.6);
      }
    }
  }

  // ── Unter dem System: Dynamik, Gabeln, Liedtext ──

  void _below(double notesBottom) {
    final voice0 = events.where((ev) => ev.voice == 0).toList();
    final hasDyn = voice0.any((ev) => ev.showDynamic) || voice0.any((ev) => ev.beat.hairpin != Hairpin.none);
    var rowBottom = math.max(notesBottom, 4.0);
    if (hasDyn) {
      final y = rowBottom + 2.0;
      for (final ev in voice0.where((ev) => ev.showDynamic)) {
        final name = switch (ev.beat.dynamic!) {
          Dynamic.pppp => 'dynamicPPPP',
          Dynamic.ppp => 'dynamicPPP',
          Dynamic.pp => 'dynamicPP',
          Dynamic.p => 'dynamicPiano',
          Dynamic.mp => 'dynamicMP',
          Dynamic.mf => 'dynamicMF',
          Dynamic.f => 'dynamicForte',
          Dynamic.ff => 'dynamicFF',
          Dynamic.fff => 'dynamicFFF',
          Dynamic.ffff => 'dynamicFFFF',
        };
        glyph(name, ev.x, y + 0.4);
      }
      // Gabeln: zusammenhängende Schläge mit derselben Gabel
      var k = 0;
      while (k < voice0.length) {
        final hp = voice0[k].beat.hairpin;
        if (hp == Hairpin.none) {
          k++;
          continue;
        }
        var j = k;
        while (j + 1 < voice0.length && voice0[j + 1].beat.hairpin == hp) {
          j++;
        }
        final startEv = voice0[k], endEv = voice0[j];
        var x1 = startEv.x;
        if (startEv.showDynamic) x1 += 3.6;
        final after = j + 1 < voice0.length ? voice0[j + 1].x - 0.6 : s.x1 - 0.6;
        final x2 = math.max(after, endEv.x + 1.5);
        final openStart = startEv.nextInVoice != null && k == 0 && _prevHairpin(startEv) == hp;
        final openEnd = j == voice0.length - 1 && endEv.nextInVoice?.beat.hairpin == hp;
        for (final l in hairpin(
          x1,
          x2,
          y,
          crescendo: hp == Hairpin.crescendo,
          openStart: openStart,
          openEnd: openEnd,
        )) {
          add(l);
        }
        k = j + 1;
      }
      rowBottom = y + 1.0;
    }
    // Liedtext
    final lyricEvs = voice0.where((ev) => ev.beat.lyrics.isNotEmpty).toList();
    if (lyricEvs.isNotEmpty) {
      final lines = lyricEvs.map((ev) => ev.beat.lyrics.length).reduce(math.max);
      for (var l = 0; l < lines; l++) {
        final y = rowBottom + 2.0 + l * 1.8;
        for (final ev in lyricEvs) {
          if (l >= ev.beat.lyrics.length || ev.beat.lyrics[l].isEmpty) continue;
          text(ev.beat.lyrics[l], ev.x + ev.headW / 2, y, TextRole.lyrics, _lyricsSize, align: TextAlign.center);
        }
      }
    }
  }

  Hairpin? _prevHairpin(_Ev ev) {
    // Letzter Schlag der Hauptstimme vor dieser Zeile
    _Ev? prev;
    for (final m in e._measures.where((m) => m.index < firstBar).toList().reversed) {
      if (m.voices.isNotEmpty && m.voices.first.isNotEmpty) {
        prev = m.voices.first.last;
        break;
      }
    }
    return prev?.beat.hairpin;
  }

  // ── Tabulatur ──

  double _tabTop = 0;
  double _tabBottom = 0;

  double _stringY(int string) {
    final n = track.staff.stringCount;
    return _tabTop + (n - 1 - string) * e.options.tabLineSpacing;
  }

  void _tabStaff() {
    final sp = e.options.tabLineSpacing;
    final n = track.staff.stringCount;
    final voice0 = events.toList();
    final hasPm = voice0.any((ev) => ev.beat.notes.any((x) => x.palmMuted || x.letRing));
    final hasBend = voice0.any((ev) => ev.beat.notes.any((x) => x.bend != null));
    var y = e._tabOnly ? 0.0 : math.max(bottom, 4.0) + 2.2;
    if (hasPm) y += 1.4;
    if (hasBend) y += 2.0;
    _tabTop = y;
    _tabBottom = y + (n - 1) * sp;
    for (var k = 0; k < n; k++) {
      line(s.x0, _tabTop + k * sp, s.x1, _tabTop + k * sp, _staffLineT);
    }
    // TAB-Schlüssel, auf die Höhe der Tabulatur gestreckt
    final clef = e._tabClef;
    final g = Glyphs.get(clef);
    final scale = e._tabClefScale;
    glyph(clef, s.x0 + 0.9, (_tabTop + _tabBottom) / 2 - (g.top + g.bottom) / 2 * scale, scale: scale);
    // Besondere Stimmung: Saitennamen vor der ersten Zeile
    if (s.first && !e._standardTuning) {
      for (var k = 0; k < n; k++) {
        final ly = _stringY(k);
        text(e._noteName(track.staff.tuning[k]), s.x0 - 0.5, ly + 0.36, TextRole.small, 1.0, align: TextAlign.right);
      }
    }
    // Taktlinien und Wiederholungen
    for (var j = 0; j < s.measures.length; j++) {
      final m = s.measures[j];
      if (m.mb.repeatStart) _repeatStart(j == 0 ? _contentStart - 0.2 : m.x, _tabTop, _tabBottom);
      _barline(m.x + m.w, _tabTop, _tabBottom, m, m.index == e.score.masterBars.length - 1);
    }
    // P.M. und let ring
    if (hasPm) _techniqueLines(_tabTop - (hasBend ? 3.2 : 1.2));
    // Vibrato: Wellenlinie über der Tabulatur
    for (final ev in events) {
      if (!ev.beat.notes.any((n) => n.vibrato)) continue;
      final next = ev.nextInVoice;
      final end = next != null && inSystem(next) ? next.x - 0.3 : math.min(ev.x + 3.0, s.x1 - 0.3);
      if (end > ev.x + 0.8) add(_wavy(ev.x, end, _tabTop - 0.6));
    }
    // Zahlen der Vorschlagsnoten (klein, mit Bogen zur Hauptnote)
    for (final ev in events) {
      if (ev.graces.isEmpty || ev.beat.slashed) continue;
      final start = ev.col.x - ev.col.accW + 0.25;
      for (var k = 0; k < ev.graces.length; k++) {
        final cx = start + k * _graceStep + 0.4;
        for (final nt in ev.graces[k].notes) {
          if (nt.string == null || nt.fret == null) continue;
          final ly = _stringY(nt.string!);
          final t = nt.dead ? 'x' : '${nt.fret}';
          final w = tw(t, TextRole.tab, _tabSize * 0.72);
          add(RectItem(cx - w / 2 - 0.1, ly - 0.45, w + 0.2, 0.9, background: true));
          text(t, cx, ly + _tabSize * 0.72 * 0.36, TextRole.tab, _tabSize * 0.72, align: TextAlign.center);
          if (k == ev.graces.length - 1 && ev.beat.notes.any((m) => m.string == nt.string)) {
            final x2 = ev.x + ev.headW / 2;
            if (x2 > cx + 0.8) add(arc(cx, ly - 0.65, x2, ly - 0.75, up: true, height: 0.45, thickness: 0.18));
          }
        }
      }
    }
    // Zahlen
    for (final ev in events) {
      if (ev.isRest || ev.beat.slashed) continue;
      final cx = ev.x + ev.headW / 2;
      for (final nt in ev.beat.notes) {
        if (nt.string == null || nt.fret == null) continue;
        final ly = _stringY(nt.string!);
        if (nt.tieDestination) {
          // Gehaltene Note: nur am Zeilenanfang in Klammern
          final firstInSystem = ev.tiesIn.any((t) => !inSystem(t.from));
          if (!firstInSystem) continue;
          _fret(e._fretText(nt, true), cx, ly);
          continue;
        }
        _fret(e._fretText(nt, false), cx, ly);
        // Tapping: T über der Zahl
        if (nt.tapped) text('T', cx, ly - 0.9, TextRole.technique, 0.95, align: TextAlign.center);
      }
    }
    _tabConnections();
  }

  void _fret(String t, double cx, double ly) {
    final w = tw(t, TextRole.tab, _tabSize);
    add(RectItem(cx - w / 2 - 0.15, ly - 0.55, w + 0.3, 1.1, background: true));
    text(t, cx, ly + _tabSize * 0.36, TextRole.tab, _tabSize, align: TextAlign.center);
  }

  void _techniqueLines(double y) {
    final evs = events.toList();
    void runs(bool Function(_Ev) test, String label) {
      var k = 0;
      while (k < evs.length) {
        if (!test(evs[k])) {
          k++;
          continue;
        }
        var j = k;
        while (j + 1 < evs.length && test(evs[j + 1])) {
          j++;
        }
        final x1 = evs[k].x;
        final endEv = evs[j];
        final next = endEv.nextInVoice;
        final x2 = (next != null && inSystem(next)) ? next.x - 0.5 : endEv.x + endEv.headW + 0.8;
        text(label, x1, y, TextRole.technique, _techniqueSize, italic: true);
        final lw = tw(label, TextRole.technique, _techniqueSize, italic: true);
        if (x2 > x1 + lw + 0.6) {
          line(x1 + lw + 0.3, y - 0.35, x2, y - 0.35, 0.12, dash: (0.4, 0.3));
          line(x2, y - 0.35, x2, y + 0.3, 0.12);
        }
        k = j + 1;
      }
    }

    runs((ev) => ev.beat.notes.any((n) => n.palmMuted), 'P.M.');
    runs((ev) => ev.beat.notes.any((n) => n.letRing), 'let ring');
  }

  void _tabConnections() {
    for (final ev in events) {
      if (ev.isRest || ev.beat.slashed) continue;
      final next = ev.nextInVoice;
      final cx = ev.x + ev.headW / 2;
      for (final n in ev.beat.notes) {
        if (n.string == null || n.fret == null) continue;
        final ly = _stringY(n.string!);
        final w = tw(e._fretText(n, false), TextRole.tab, _tabSize);
        Note? target;
        _Ev? targetEv;
        if (next != null && !next.beat.slashed) {
          for (final n2 in next.beat.notes) {
            if (n2.string == n.string) {
              target = n2;
              targetEv = next;
            }
          }
        }
        final sameSystem = targetEv != null && inSystem(targetEv);
        final cx2 = sameSystem ? targetEv.x + targetEv.headW / 2 : s.x1 + 1.0;
        final w2 = target == null ? 1.0 : tw(e._fretText(target, false), TextRole.tab, _tabSize);
        // Hammer-on / Pull-off: Bogen mit H oder P
        if (n.hammerOrigin) {
          final xa = cx, xb = sameSystem ? cx2 : s.x1 - 0.3;
          if (xb > xa + 0.5) {
            add(arc(xa, ly - 0.75, xb, ly - 0.75, up: true, height: 0.55));
            final label = (target != null && (target.fret ?? 0) < (n.fret ?? 0)) ? 'P' : 'H';
            text(label, (xa + xb) / 2, ly - 1.55, TextRole.technique, 0.95, align: TextAlign.center);
          }
        }
        // Slides
        if (n.slide & 3 != 0) {
          final upward = target != null ? (target.fret ?? 0) > (n.fret ?? 0) : true;
          final xa = cx + w / 2 + 0.2;
          final xb = sameSystem ? cx2 - w2 / 2 - 0.2 : s.x1 - 0.3;
          if (xb > xa) {
            line(xa, ly + (upward ? 0.35 : -0.35), xb, ly + (upward ? -0.35 : 0.35), 0.13);
          }
        }
        if (n.slide & 4 != 0) line(cx + w / 2 + 0.2, ly - 0.3, cx + w / 2 + 1.7, ly + 0.6, 0.13);
        if (n.slide & 8 != 0) line(cx + w / 2 + 0.2, ly + 0.3, cx + w / 2 + 1.7, ly - 0.6, 0.13);
        if (n.slide & 16 != 0) line(cx - w / 2 - 1.7, ly + 0.6, cx - w / 2 - 0.2, ly - 0.3, 0.13);
        if (n.slide & 32 != 0) line(cx - w / 2 - 1.7, ly - 0.6, cx - w / 2 - 0.2, ly + 0.3, 0.13);
        // Saitenziehen
        final b = n.bend;
        if (b != null && b.maxSemitones > 0) {
          final xa = cx + w / 2 + 0.1;
          final topY = _tabTop - 1.6;
          final xb = xa + 1.4;
          if (b.preBent) {
            line(cx, ly - 0.6, cx, topY + 0.5, 0.13);
            add(PathItem([0, cx, topY, 1, cx - 0.3, topY + 0.6, 1, cx + 0.3, topY + 0.6, 4]));
          } else {
            for (final it in bendArrow(xa, ly - 0.2, xb, topY)) {
              add(it);
            }
          }
          text(
            _bendLabel(b.maxSemitones),
            b.preBent ? cx : xb,
            topY - 0.4,
            TextRole.technique,
            1.0,
            align: TextAlign.center,
          );
          if (b.releases) {
            final xr = xb + 1.4;
            for (final it in bendArrow(xb + 0.1, topY + 0.2, xr, ly - 0.7)) {
              add(it);
            }
          }
        }
      }
    }
  }

  String _bendLabel(double semitones) {
    final tones = semitones / 2;
    if ((tones - 1).abs() < 0.01) return 'full';
    final whole = tones.floor();
    final rest = tones - whole;
    final frac = rest < 0.13
        ? ''
        : rest < 0.38
        ? '¼'
        : rest < 0.63
        ? '½'
        : '¾';
    if (whole == 0) return frac;
    return '$whole$frac';
  }
}
