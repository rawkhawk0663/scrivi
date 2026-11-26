import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../model/fraction.dart';
import '../model/pitch.dart';
import '../model/score.dart';
import 'gp_reader.dart';

/// Liest MusicXML (`.musicxml`, `.xml`, gepackt `.mxl`), die übliche Form
/// „score-partwise“. Jede Notenzeile eines Instruments wird zu einer Spur;
/// eine Tabulatur zum selben Instrument liefert Saiten und Bünde dazu.
class MusicXmlReader {
  MusicXmlReader._();

  static bool looksLikeXml(String head) => head.contains('<score-partwise') || head.contains('<score-timewise');

  /// Gepacktes MusicXML (ZIP mit META-INF/container.xml).
  static Score readMxl(Archive zip) {
    String? path;
    final container = zip.findFile('META-INF/container.xml');
    if (container != null) {
      try {
        final doc = XmlDocument.parse(utf8.decode(container.content, allowMalformed: true));
        path = doc.findAllElements('rootfile').firstOrNull?.getAttribute('full-path');
      } catch (_) {}
    }
    ArchiveFile? entry = path == null ? null : zip.findFile(path);
    entry ??= zip.files
        .where(
          (f) =>
              f.isFile && !f.name.startsWith('META-INF') && (f.name.endsWith('.xml') || f.name.endsWith('.musicxml')),
        )
        .firstOrNull;
    if (entry == null) throw const ScoreFileException(ScoreFileProblem.unknownFormat, 'mxl ohne Noten');
    return readXml(_decode(entry.content));
  }

  static String _decode(Uint8List b) {
    // UTF-16 mit Kennung
    if (b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) {
      final le = b[0] == 0xFF;
      final units = <int>[];
      for (var i = 2; i + 1 < b.length; i += 2) {
        units.add(le ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    return utf8.decode(b, allowMalformed: true);
  }

  static Score readBytes(Uint8List b) => readXml(_decode(b));

  static Score readXml(String xml) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } catch (e) {
      throw ScoreFileException(ScoreFileProblem.damaged, 'XML: $e');
    }
    var root = doc.rootElement;
    if (root.name.local == 'score-timewise') root = _timewiseToPartwise(root);
    if (root.name.local != 'score-partwise') {
      throw const ScoreFileException(ScoreFileProblem.unknownFormat, 'kein MusicXML');
    }
    try {
      return _Parser(root).parse();
    } on ScoreFileException {
      rethrow;
    } catch (e) {
      throw ScoreFileException(ScoreFileProblem.damaged, '$e');
    }
  }
}

/// „timewise“ (Takte enthalten Stimmen) in „partwise“ (Stimmen enthalten Takte) umbauen.
XmlElement _timewiseToPartwise(XmlElement tw) {
  final out = XmlElement(XmlName('score-partwise'));
  final parts = <String, XmlElement>{};
  for (final c in tw.childElements) {
    if (c.name.local != 'measure') {
      out.children.add(c.copy());
      continue;
    }
    for (final p in c.childElements.where((e) => e.name.local == 'part')) {
      final id = p.getAttribute('id') ?? '';
      final part = parts.putIfAbsent(id, () {
        final e = XmlElement(XmlName('part'), [XmlAttribute(XmlName('id'), id)]);
        out.children.add(e);
        return e;
      });
      part.children.add(
        XmlElement(
          XmlName('measure'),
          [for (final a in c.attributes) a.copy()],
          [for (final n in p.children) n.copy()],
        ),
      );
    }
  }
  return out;
}

XmlElement? _child(XmlElement? e, String name) {
  if (e == null) return null;
  for (final c in e.childElements) {
    if (c.name.local == name) return c;
  }
  return null;
}

Iterable<XmlElement> _children(XmlElement? e, String name) =>
    e == null ? const [] : e.childElements.where((c) => c.name.local == name);

String _text(XmlElement? e, String name) => _child(e, name)?.innerText.trim() ?? '';

int? _int(XmlElement? e, String name) => int.tryParse(_text(e, name));

const _steps = {'C': 0, 'D': 1, 'E': 2, 'F': 3, 'G': 4, 'A': 5, 'B': 6};

/// Ein Ereignis (Note, Akkord oder Pause) einer Stimme, vor dem Umbau ins Modell.
class _Ev {
  _Ev(this.onset, this.duration, this.ticks);
  final Fraction onset;
  final NoteDuration duration;
  final int ticks;
  final notes = <_N>[];
  bool rest = false;
  bool fullBar = false;
  String? chord;
  String? text;
  Dynamic? dynamic;
  Hairpin hairpin = Hairpin.none;
  final lyrics = <int, String>{};
  bool fermata = false;
  GraceType grace = GraceType.none;
  int tremolo = 0;
}

class _N {
  _N(this.written);
  final Pitch written;
  int? string;
  int? fret;
  bool tieStart = false;
  bool tieStop = false;
  bool dead = false;
  bool ghost = false;
  bool hammer = false;
  int slide = 0;
  Bend? bend;
  int accent = 0;
  bool harmonic = false;
}

/// Angaben pro Notenzeile (Schlüssel, Stimmung …).
class _StaffInfo {
  Clef clef = Clef.treble;
  bool tab = false;
  int clefOctave = 0;
  List<int>? tuning;
  int capo = 0;
}

class _Parser {
  _Parser(this.root);
  final XmlElement root;

  final _tempos = <TempoMark>[];
  final _masters = <_Master>[];

  Score parse() {
    final names = <String, String>{};
    for (final sp in root.findAllElements('score-part')) {
      final id = sp.getAttribute('id') ?? '';
      names[id] = _text(sp, 'part-name');
    }
    final parts = _children(root, 'part').toList();
    if (parts.isEmpty) throw const ScoreFileException(ScoreFileProblem.unknownFormat, 'keine Stimmen');
    final tracks = <Track>[];
    for (var pi = 0; pi < parts.length; pi++) {
      final p = parts[pi];
      tracks.addAll(_part(p, names[p.getAttribute('id')] ?? '', pi == 0));
    }
    final masterBars = [
      for (final m in _masters)
        MasterBar(
          time: m.time,
          key: m.key,
          repeatStart: m.repeatStart,
          repeatEnd: m.repeatEnd,
          endings: m.endings,
          section: m.rehearsal == null ? null : Section(letter: m.rehearsal!),
          doubleBar: m.doubleBar,
          directions: m.directions,
        ),
    ];
    // Spuren auf dieselbe Taktzahl bringen
    for (final t in tracks) {
      while (t.bars.length < masterBars.length) {
        t.bars.add(Bar(clef: t.bars.isEmpty ? Clef.treble : t.bars.last.clef, voices: []));
      }
    }
    _tempos.sort((a, b) => a.bar.compareTo(b.bar));
    return Score(info: _info(), masterBars: masterBars, tracks: tracks, tempos: _tempos);
  }

  ScoreInfo _info() {
    var title = _text(_child(root, 'work'), 'work-title');
    final movement = _text(root, 'movement-title');
    var subtitle = '';
    if (title.isEmpty) {
      title = movement;
    } else if (movement.isNotEmpty && movement != title) {
      subtitle = movement;
    }
    final ident = _child(root, 'identification');
    String creator(String type) => _children(
      ident,
      'creator',
    ).where((c) => c.getAttribute('type') == type).map((c) => c.innerText.trim()).join(', ');
    final composer = creator('composer');
    final lyricist = creator('lyricist');
    final arranger = creator('arranger');
    final rights = _children(ident, 'rights').map((r) => r.innerText.trim()).join(' ');
    // Ohne Titel: grösster zentrierter Text der ersten Seite
    if (title.isEmpty) {
      XmlElement? best;
      double bestSize = 0;
      for (final c in root.findAllElements('credit-words')) {
        final size = double.tryParse(c.getAttribute('font-size') ?? '') ?? 0;
        if (size > bestSize) {
          bestSize = size;
          best = c;
        }
      }
      title = best?.innerText.trim() ?? '';
    }
    return ScoreInfo(
      title: title,
      subtitle: subtitle,
      artist: composer.isNotEmpty ? composer : arranger,
      music: composer,
      words: lyricist,
      copyright: rights,
    );
  }

  List<Track> _part(XmlElement part, String name, bool first) {
    var divisions = 1;
    var time = const TimeSignature(4, 4);
    var key = const KeySignature(0);
    var transposeChromatic = 0;
    var transposeOctave = 0;
    var staffCount = 1;
    final staffs = <int, _StaffInfo>{1: _StaffInfo()};
    // Pro Notenzeile und Stimme: Takte mit Ereignissen
    final events = <int, Map<int, Map<String, List<_Ev>>>>{}; // staff → bar → voice → events
    final clefPerBar = <int, Map<int, Clef>>{};
    var barIndex = 0;
    final measures = _children(part, 'measure').toList();
    for (final m in measures) {
      final bar = barIndex;
      if (first && _masters.length <= bar) _masters.add(_Master(time, key));
      var pos = 0; // Zeit in Teilen (divisions)
      var lastPos = 0;
      int barTicks() => (time.length.toDouble() * 4 * divisions).round();
      final pendingText = <int, List<(int, void Function(_Ev))>>{};
      _Ev? last;
      var wedgeOpen = <int, (Hairpin, int)>{};
      final wedgeRanges = <(int, Hairpin, int, int)>[]; // staff, art, von, bis

      for (final el in m.childElements) {
        switch (el.name.local) {
          case 'attributes':
            divisions = _int(el, 'divisions') ?? divisions;
            final k = _child(el, 'key');
            if (k != null) key = KeySignature(_int(k, 'fifths') ?? 0, minor: _text(k, 'mode') == 'minor');
            final t = _child(el, 'time');
            if (t != null) {
              final beats = int.tryParse(_text(t, 'beats').split('+').first) ?? 4;
              final type = _int(t, 'beat-type') ?? 4;
              time = TimeSignature(beats, type, common: t.getAttribute('symbol') == 'common');
            }
            staffCount = _int(el, 'staves') ?? staffCount;
            for (var s = 1; s <= staffCount; s++) {
              staffs.putIfAbsent(s, _StaffInfo.new);
            }
            for (final c in _children(el, 'clef')) {
              final s = int.tryParse(c.getAttribute('number') ?? '') ?? 1;
              final info = staffs.putIfAbsent(s, _StaffInfo.new);
              final sign = _text(c, 'sign');
              final line = _int(c, 'line');
              final oct = _int(c, 'clef-octave-change') ?? 0;
              info.tab = sign == 'TAB';
              info.clefOctave = oct;
              info.clef = switch (sign) {
                'F' => Clef.bass,
                'C' => line == 4 ? Clef.tenor : Clef.alto,
                'percussion' => Clef.neutral,
                'TAB' => Clef.treble8vb,
                _ => oct == -1 ? Clef.treble8vb : Clef.treble,
              };
              (clefPerBar[s] ??= {})[bar] = info.clef;
            }
            for (final d in _children(el, 'staff-details')) {
              final s = int.tryParse(d.getAttribute('number') ?? '') ?? 1;
              final info = staffs.putIfAbsent(s, _StaffInfo.new);
              final tunings = _children(d, 'staff-tuning').toList();
              if (tunings.isNotEmpty) {
                final lines = _int(d, 'staff-lines') ?? tunings.length;
                final tuning = List<int>.filled(lines, 40);
                for (final st in tunings) {
                  final line = int.tryParse(st.getAttribute('line') ?? '') ?? 1;
                  final step = _steps[_text(st, 'tuning-step')] ?? 0;
                  final alter = (double.tryParse(_text(st, 'tuning-alter')) ?? 0).round();
                  final oct = _int(st, 'tuning-octave') ?? 3;
                  if (line >= 1 && line <= lines) tuning[line - 1] = Pitch(step, alter, oct).midi;
                }
                info.tuning = tuning;
              }
              info.capo = _int(d, 'capo') ?? info.capo;
            }
            final tr = _child(el, 'transpose');
            if (tr != null) {
              transposeChromatic = _int(tr, 'chromatic') ?? 0;
              transposeOctave = _int(tr, 'octave-change') ?? 0;
            }
            if (first) {
              _masters[bar]
                ..time = time
                ..key = key;
            }
          case 'backup':
            pos -= _int(el, 'duration') ?? 0;
            if (pos < 0) pos = 0;
          case 'forward':
            pos += _int(el, 'duration') ?? 0;
          case 'note':
            if (_child(el, 'cue') != null) continue;
            final graceEl = _child(el, 'grace');
            final staff = _int(el, 'staff') ?? 1;
            final voice = '$staff/${_text(el, 'voice').isEmpty ? '1' : _text(el, 'voice')}';
            final dur = _int(el, 'duration') ?? 0;
            final isChord = _child(el, 'chord') != null;
            final voices = ((events[staff] ??= {})[bar] ??= {});
            final list = voices[voice] ??= [];
            _Ev ev;
            if (graceEl != null) {
              // Vorschlagsnote: nimmt keine Zeit, steht vor der nächsten Note
              if (isChord && list.isNotEmpty && list.last.grace != GraceType.none) {
                ev = list.last;
              } else {
                final v = _value(_text(el, 'type')) ?? NoteValue.eighth;
                ev = _Ev(Fraction(pos, divisions * 4), NoteDuration(v), 0)
                  ..grace = graceEl.getAttribute('slash') == 'yes' ? GraceType.beforeBeat : GraceType.onBeat;
                list.add(ev);
              }
              final n = _note(el);
              if (n != null) ev.notes.add(n);
              continue;
            }
            if (isChord && list.isNotEmpty) {
              ev = list.last;
            } else {
              final start = isChord ? lastPos : pos;
              ev = _Ev(Fraction(start, divisions * 4), _duration(el, dur, divisions, time), dur);
              list.add(ev);
              lastPos = start;
              if (!isChord) pos += dur;
              // Wartende Angaben (Akkord, Text, Dynamik) an diesen Schlag hängen
              final waiting = pendingText[staff];
              if (waiting != null) {
                for (final w in waiting.where((w) => w.$1 <= start)) {
                  w.$2(ev);
                }
                waiting.removeWhere((w) => w.$1 <= start);
              }
            }
            last = ev;
            final restEl = _child(el, 'rest');
            if (restEl != null) {
              ev.rest = true;
              if (restEl.getAttribute('measure') == 'yes' || dur >= barTicks()) ev.fullBar = true;
            } else {
              final n = _note(el);
              if (n != null) ev.notes.add(n);
            }
            final notations = _child(el, 'notations');
            if (notations != null && _child(notations, 'fermata') != null) ev.fermata = true;
            final trem = _child(_child(notations, 'ornaments'), 'tremolo');
            if (trem != null && trem.getAttribute('type') != 'start' && trem.getAttribute('type') != 'stop') {
              ev.tremolo = int.tryParse(trem.innerText.trim()) ?? 1;
            }
            for (final ly in _children(el, 'lyric')) {
              final number = int.tryParse(ly.getAttribute('number') ?? '') ?? 1;
              var t = _text(ly, 'text');
              final syl = _text(ly, 'syllabic');
              if (syl == 'begin' || syl == 'middle') t = '$t-';
              if (t.isNotEmpty) ev.lyrics[number] = t;
            }
          case 'harmony':
            final name = _chordName(el);
            if (name.isNotEmpty) {
              final staff = _int(el, 'staff') ?? 1;
              final at = pos + (_int(el, 'offset') ?? 0);
              (pendingText[staff] ??= []).add((at, (ev) => ev.chord ??= name));
            }
          case 'direction':
            final staff = _int(el, 'staff') ?? 1;
            final at = pos + (_int(el, 'offset') ?? 0);
            void attach(void Function(_Ev) f) => (pendingText[staff] ??= []).add((at, f));
            for (final dt in _children(el, 'direction-type')) {
              for (final c in dt.childElements) {
                switch (c.name.local) {
                  case 'words':
                    final w = c.innerText.trim();
                    if (w.isEmpty) break;
                    final dir = _directionFromWords(w);
                    if (dir != null && first) {
                      _masters[bar].directions.add(dir);
                    } else {
                      attach((ev) => ev.text = ev.text == null ? w : '${ev.text} $w');
                    }
                  case 'rehearsal':
                    if (first) _masters[bar].rehearsal = c.innerText.trim();
                  case 'segno':
                    if (first) _masters[bar].directions.add(Direction.segno);
                  case 'coda':
                    if (first) _masters[bar].directions.add(Direction.coda);
                  case 'dynamics':
                    final d = c.childElements.isEmpty ? null : _dynamic(c.childElements.first.name.local);
                    if (d != null) attach((ev) => ev.dynamic = d);
                  case 'wedge':
                    final type = c.getAttribute('type');
                    if (type == 'crescendo' || type == 'diminuendo') {
                      wedgeOpen[staff] = (type == 'crescendo' ? Hairpin.crescendo : Hairpin.decrescendo, at);
                    } else if (type == 'stop') {
                      final open = wedgeOpen.remove(staff);
                      if (open != null) wedgeRanges.add((staff, open.$1, open.$2, at));
                    }
                  case 'metronome':
                    final perMinute = double.tryParse(_text(c, 'per-minute'));
                    if (perMinute != null && first) {
                      final unit = _value(_text(c, 'beat-unit')) ?? NoteValue.quarter;
                      _tempos.add(
                        TempoMark(bar: bar, bpm: perMinute, unit: unit, dotted: _child(c, 'beat-unit-dot') != null),
                      );
                    }
                }
              }
            }
            final sound = _child(el, 'sound');
            final tempo = double.tryParse(sound?.getAttribute('tempo') ?? '');
            if (tempo != null && first && !_tempos.any((t) => t.bar == bar)) {
              _tempos.add(
                TempoMark(
                  bar: bar,
                  bpm: tempo,
                  visible: _children(el, 'direction-type').any((d) => _child(d, 'metronome') != null),
                ),
              );
            }
          case 'sound':
            final tempo = double.tryParse(el.getAttribute('tempo') ?? '');
            if (tempo != null && first && !_tempos.any((t) => t.bar == bar)) {
              _tempos.add(TempoMark(bar: bar, bpm: tempo, visible: false));
            }
          case 'barline':
            if (!first) continue;
            final location = el.getAttribute('location') ?? 'right';
            final rep = _child(el, 'repeat');
            if (rep != null) {
              if (rep.getAttribute('direction') == 'forward') {
                _masters[bar].repeatStart = true;
              } else {
                _masters[bar].repeatEnd = int.tryParse(rep.getAttribute('times') ?? '') ?? 2;
              }
            }
            final ending = _child(el, 'ending');
            if (ending != null) {
              final numbers = (ending.getAttribute('number') ?? '1')
                  .split(RegExp(r'[,\s]+'))
                  .map((x) => int.tryParse(x))
                  .whereType<int>();
              if (ending.getAttribute('type') == 'start' || location == 'left') {
                _masters[bar].endings.addAll(numbers);
                _masters[bar].endingOpen = true;
              }
            }
            final style = _text(el, 'bar-style');
            if (location == 'right' && (style == 'light-light' || style == 'light-heavy') && rep == null) {
              _masters[bar].doubleBar = true;
            }
        }
      }
      // Noch offene Angaben ans Taktende-Ereignis hängen
      for (final entry in pendingText.entries) {
        if (entry.value.isEmpty) continue;
        final voices = events[entry.key]?[bar];
        final ev = voices?.values.expand((l) => l).lastOrNull ?? last;
        if (ev != null) {
          for (final w in entry.value) {
            w.$2(ev);
          }
        }
      }
      // Gabeln auf die Schläge verteilen
      for (final (staff, art, from, to) in wedgeRanges) {
        for (final list in events[staff]?[bar]?.values ?? const <List<_Ev>>[]) {
          for (final ev in list) {
            final t = (ev.onset.toDouble() * 4 * divisions).round();
            if (t >= from && t < (to <= from ? from + 1 : to)) ev.hairpin = art;
          }
        }
      }
      for (final open in wedgeOpen.entries) {
        for (final list in events[open.key]?[bar]?.values ?? const <List<_Ev>>[]) {
          for (final ev in list) {
            final t = (ev.onset.toDouble() * 4 * divisions).round();
            if (t >= open.value.$2) ev.hairpin = open.value.$1;
          }
        }
      }
      // Wiederholungs-Häuser über mehrere Takte fortsetzen
      if (first &&
          bar > 0 &&
          _masters[bar].endings.isEmpty &&
          _masters[bar - 1].endingOpen &&
          !_masters[bar - 1].endingClosed) {
        _masters[bar].endings.addAll(_masters[bar - 1].endings);
        _masters[bar].endingOpen = true;
      }
      if (first) {
        for (final bl in _children(m, 'barline')) {
          final ending = _child(bl, 'ending');
          final type = ending?.getAttribute('type');
          if (type == 'stop' || type == 'discontinue') _masters[bar].endingClosed = true;
        }
      }
      barIndex++;
    }

    // Spuren bauen: Notenzeilen mit Noten; Tabulatur verschmilzt mit der Notenzeile
    final tabStaffs = staffs.entries.where((e) => e.value.tab).map((e) => e.key).toSet();
    final noteStaffs = staffs.keys.where((s) => !tabStaffs.contains(s)).toList()..sort();
    final tracks = <Track>[];
    final useStaffs = noteStaffs.isNotEmpty ? noteStaffs : tabStaffs.toList();
    for (final s in useStaffs) {
      final info = staffs[s]!;
      final tabInfo = tabStaffs.isNotEmpty ? staffs[tabStaffs.first] : null;
      final tuning = info.tuning ?? tabInfo?.tuning;
      final capo = tabInfo?.capo ?? info.capo;
      // Geschrieben = klingend + Halbtöne
      final writtenOffset = -(transposeChromatic + transposeOctave * 12) - (info.tab ? 0 : info.clefOctave * 12);
      var transpose = writtenOffset;
      // Tabulatur allein (Gitarre): eine Oktave höher schreiben wie üblich
      if (info.tab) transpose = 12;
      final bars = <Bar>[];
      for (var b = 0; b < barIndex; b++) {
        final voices = <Voice>[];
        final perVoice = events[s]?[b] ?? const <String, List<_Ev>>{};
        final tabVoices = tabStaffs.isEmpty || noteStaffs.isEmpty ? null : events[tabStaffs.first]?[b];
        final keys = perVoice.keys.toList()..sort();
        for (final v in keys) {
          final evs = perVoice[v]!;
          if (evs.isEmpty) continue;
          voices.add(Voice(_beats(evs, b, tuning, capo, transpose, info.tab, tabVoices)));
        }
        final clef = _clefAt(clefPerBar[s], b) ?? info.clef;
        bars.add(Bar(clef: clef, voices: voices.isEmpty || voices.every((v) => v.beats.isEmpty) ? [] : voices));
      }
      var label = name;
      if (useStaffs.length > 1) label = '$name (${useStaffs.indexOf(s) + 1})';
      final chordIds = <String, int>{};
      final chords = <int, ChordDef>{};
      final withChords = <Bar>[];
      for (final bar in bars) {
        withChords.add(bar);
      }
      // Akkordsymbole bekommen Nummern pro Spur
      for (final bar in withChords) {
        for (final v in bar.voices) {
          for (var i = 0; i < v.beats.length; i++) {
            final b = v.beats[i];
            final name = _pendingChordNames[b];
            if (name == null) continue;
            final id = chordIds.putIfAbsent(name, () {
              final id = chordIds.length;
              chords[id] = ChordDef(name: name);
              return id;
            });
            v.beats[i] = _withChord(b, id);
          }
        }
      }
      tracks.add(
        Track(
          name: label,
          staff: StaffDef(tuning: tuning ?? const [], capo: capo, showTab: tuning != null),
          bars: withChords,
          chords: chords,
          transposeSemitones: transpose,
        ),
      );
    }
    return tracks;
  }

  final _pendingChordNames = Expando<String>();

  Beat _withChord(Beat b, int id) => Beat(
    duration: b.duration,
    notes: b.notes,
    slashed: b.slashed,
    chordId: id,
    text: b.text,
    dynamic: b.dynamic,
    hairpin: b.hairpin,
    lyrics: b.lyrics,
    grace: b.grace,
    fermata: b.fermata,
    pickStroke: b.pickStroke,
    tremolo: b.tremolo,
  );

  Clef? _clefAt(Map<int, Clef>? m, int bar) {
    if (m == null) return null;
    Clef? c;
    for (final e in m.entries) {
      if (e.key <= bar) c = e.value;
    }
    return c;
  }

  /// Ereignisse einer Stimme in Schläge verwandeln; Lücken werden Pausen.
  List<Beat> _beats(
    List<_Ev> evs,
    int bar,
    List<int>? tuning,
    int capo,
    int transpose,
    bool fromTab,
    Map<String, List<_Ev>>? tabVoices,
  ) {
    // Stabil sortieren: Vorschläge bleiben vor ihrer Hauptnote
    final order = {for (var i = 0; i < evs.length; i++) evs[i]: i};
    evs.sort((a, b) {
      final c = a.onset.compareTo(b.onset);
      return c != 0 ? c : order[a]!.compareTo(order[b]!);
    });
    final out = <Beat>[];
    var t = Fraction.zero;
    for (final ev in evs) {
      if (ev.onset < t) continue; // Überlappungen: weglassen
      if (ev.onset > t) {
        for (final d in _fill(ev.onset - t)) {
          out.add(Beat(duration: d));
        }
        t = ev.onset;
      }
      final notes = <Note>[];
      for (final n in ev.notes) {
        var string = n.string;
        var fret = n.fret;
        // Saite und Bund aus der zugehörigen Tabulatur holen
        if ((string == null || fret == null) && tabVoices != null) {
          for (final list in tabVoices.values) {
            for (final te in list) {
              if (te.onset != ev.onset) continue;
              for (final tn in te.notes) {
                if (tn.written.midi == n.written.midi && tn.string != null) {
                  string = tn.string;
                  fret = tn.fret;
                }
              }
            }
          }
        }
        final concert = transpose % 12 == 0
            ? n.written.octaves(-transpose ~/ 12)
            : Pitch.fromMidi(n.written.midi - transpose);
        // MusicXML zählt Saiten von oben (1 = höchste)
        int? stringIndex;
        if (string != null && tuning != null && string >= 1 && string <= tuning.length) {
          stringIndex = tuning.length - string;
        }
        if (stringIndex == null && tuning != null && fret == null) {
          // Lage selbst wählen: tiefste Saite, auf der der Ton liegt (bis Bund 12 bevorzugt)
          for (var si = tuning.length - 1; si >= 0; si--) {
            final f = concert.midi - tuning[si] - capo;
            if (f >= 0 && f <= 12) {
              stringIndex = si;
              fret = f;
            }
          }
          if (stringIndex == null) {
            for (var si = 0; si < tuning.length; si++) {
              final f = concert.midi - tuning[si] - capo;
              if (f >= 0 && f <= 24) {
                stringIndex = si;
                fret = f;
                break;
              }
            }
          }
        }
        notes.add(
          Note(
            pitch: concert,
            written: transpose == 0 ? null : n.written,
            string: stringIndex,
            fret: stringIndex == null ? null : fret,
            tieOrigin: n.tieStart,
            tieDestination: n.tieStop,
            dead: n.dead,
            ghost: n.ghost,
            slide: n.slide,
            hammerOrigin: n.hammer,
            bend: n.bend,
            accent: n.accent,
            harmonic: n.harmonic,
          ),
        );
      }
      final lyrics = <String>[];
      if (ev.lyrics.isNotEmpty) {
        final maxLine = ev.lyrics.keys.reduce((a, b) => a > b ? a : b);
        for (var l = 1; l <= maxLine; l++) {
          lyrics.add(ev.lyrics[l] ?? '');
        }
      }
      final beat = Beat(
        duration: ev.duration,
        notes: ev.rest ? [] : notes,
        text: ev.text,
        dynamic: ev.dynamic,
        hairpin: ev.hairpin,
        lyrics: lyrics,
        fermata: ev.fermata,
        grace: ev.grace,
        tremolo: ev.tremolo,
      );
      if (ev.chord != null) _pendingChordNames[beat] = ev.chord!;
      out.add(beat);
      if (ev.grace == GraceType.none) t = ev.onset + ev.duration.length;
    }
    return out;
  }

  /// Eine Lücke mit möglichst wenigen Pausen füllen.
  List<NoteDuration> _fill(Fraction gap) {
    final out = <NoteDuration>[];
    var rest = gap;
    for (final v in [
      NoteValue.whole,
      NoteValue.half,
      NoteValue.quarter,
      NoteValue.eighth,
      NoteValue.sixteenth,
      NoteValue.thirtySecond,
      NoteValue.sixtyFourth,
    ]) {
      while (rest >= v.length) {
        out.add(NoteDuration(v));
        rest = rest - v.length;
      }
    }
    return out;
  }

  NoteValue? _value(String type) => switch (type) {
    'breve' => NoteValue.doubleWhole,
    'whole' => NoteValue.whole,
    'half' => NoteValue.half,
    'quarter' => NoteValue.quarter,
    'eighth' => NoteValue.eighth,
    '16th' => NoteValue.sixteenth,
    '32nd' => NoteValue.thirtySecond,
    '64th' => NoteValue.sixtyFourth,
    '128th' => NoteValue.hundredTwentyEighth,
    _ => null,
  };

  NoteDuration _duration(XmlElement note, int ticks, int divisions, TimeSignature time) {
    final dots = _children(note, 'dot').length;
    final tm = _child(note, 'time-modification');
    Tuplet? tuplet;
    if (tm != null) {
      final a = _int(tm, 'actual-notes') ?? 1, n = _int(tm, 'normal-notes') ?? 1;
      if (a > 0 && n > 0 && a != n) tuplet = Tuplet(a, n);
    }
    final v = _value(_text(note, 'type'));
    if (v != null) return NoteDuration(v, dots: dots, tuplet: tuplet);
    // Ohne Notenwert (z. B. Ganztaktpause): aus der Länge bestimmen
    final len = Fraction(ticks, divisions * 4);
    if (_child(note, 'rest')?.getAttribute('measure') == 'yes' || len >= time.length) {
      return const NoteDuration(NoteValue.whole);
    }
    for (final cand in NoteValue.values.where((x) => x.log2 >= 0)) {
      if (cand.length == len) return NoteDuration(cand);
      if (NoteDuration(cand, dots: 1).length == len) return NoteDuration(cand, dots: 1);
    }
    return const NoteDuration(NoteValue.quarter);
  }

  _N? _note(XmlElement el) {
    Pitch? written;
    final pitch = _child(el, 'pitch');
    if (pitch != null) {
      final step = _steps[_text(pitch, 'step')] ?? 0;
      final alter = (double.tryParse(_text(pitch, 'alter')) ?? 0).round();
      written = Pitch(step, alter, _int(pitch, 'octave') ?? 4);
    }
    final unpitched = _child(el, 'unpitched');
    if (unpitched != null) {
      written = Pitch(_steps[_text(unpitched, 'display-step')] ?? 6, 0, _int(unpitched, 'display-octave') ?? 4);
    }
    if (written == null) return null;
    final n = _N(written);
    for (final t in _children(el, 'tie')) {
      if (t.getAttribute('type') == 'start') n.tieStart = true;
      if (t.getAttribute('type') == 'stop') n.tieStop = true;
    }
    final head = _text(el, 'notehead');
    if (head == 'x' || head == 'cross') n.dead = true;
    final notations = _child(el, 'notations');
    if (notations != null) {
      for (final t in _children(notations, 'tied')) {
        if (t.getAttribute('type') == 'start') n.tieStart = true;
        if (t.getAttribute('type') == 'stop') n.tieStop = true;
      }
      for (final s in [..._children(notations, 'slide'), ..._children(notations, 'glissando')]) {
        if (s.getAttribute('type') == 'start') n.slide |= 1;
      }
      final tech = _child(notations, 'technical');
      if (tech != null) {
        n.string = _int(tech, 'string');
        n.fret = _int(tech, 'fret');
        for (final h in [..._children(tech, 'hammer-on'), ..._children(tech, 'pull-off')]) {
          if (h.getAttribute('type') == 'start') n.hammer = true;
        }
        if (_child(tech, 'harmonic') != null) n.harmonic = true;
        final bend = _child(tech, 'bend');
        if (bend != null) {
          final alter = double.tryParse(_text(bend, 'bend-alter')) ?? 2;
          final pre = _child(bend, 'pre-bend') != null;
          final release = _child(bend, 'release') != null;
          n.bend = Bend([
            BendPoint(0, pre ? alter.abs() : 0),
            BendPoint(0.5, alter.abs()),
            if (release) const BendPoint(1, 0) else BendPoint(1, alter.abs()),
          ]);
        }
      }
      final art = _child(notations, 'articulations');
      if (art != null) {
        for (final a in art.childElements) {
          n.accent |= switch (a.name.local) {
            'staccato' => 1,
            'strong-accent' => 4,
            'accent' => 8,
            'tenuto' => 16,
            _ => 0,
          };
        }
      }
    }
    if (el.getAttribute('print-object') == 'no') return null;
    return n;
  }

  String _chordName(XmlElement h) {
    final root = _child(h, 'root');
    if (root == null) return _text(h, 'function');
    final step = _text(root, 'root-step');
    final alter = (double.tryParse(_text(root, 'root-alter')) ?? 0).round();
    var name = '$step${alter > 0 ? '#' * alter : (alter < 0 ? 'b' * -alter : '')}';
    final kindEl = _child(h, 'kind');
    final kindText = kindEl?.getAttribute('text');
    final kind = kindEl?.innerText.trim() ?? 'major';
    if (kindText != null) {
      name += kindText;
    } else {
      name += switch (kind) {
        'minor' => 'm',
        'augmented' => '+',
        'diminished' => 'dim',
        'dominant' => '7',
        'major-seventh' => 'maj7',
        'minor-seventh' => 'm7',
        'diminished-seventh' => 'dim7',
        'augmented-seventh' => '+7',
        'half-diminished' => 'm7b5',
        'major-minor' => 'm(maj7)',
        'major-sixth' => '6',
        'minor-sixth' => 'm6',
        'dominant-ninth' => '9',
        'major-ninth' => 'maj9',
        'minor-ninth' => 'm9',
        'dominant-11th' => '11',
        'major-11th' => 'maj11',
        'minor-11th' => 'm11',
        'dominant-13th' => '13',
        'major-13th' => 'maj13',
        'minor-13th' => 'm13',
        'suspended-second' => 'sus2',
        'suspended-fourth' => 'sus4',
        'power' => '5',
        _ => '',
      };
    }
    for (final d in _children(h, 'degree')) {
      final value = _text(d, 'degree-value');
      final alter = (double.tryParse(_text(d, 'degree-alter')) ?? 0).round();
      final type = _text(d, 'degree-type');
      final acc = alter > 0 ? '#' : (alter < 0 ? 'b' : '');
      if (type == 'add') name += 'add$acc$value';
      if (type == 'alter') name += '($acc$value)';
      if (type == 'subtract') name += 'no$value';
    }
    final bass = _child(h, 'bass');
    if (bass != null) {
      final b = _text(bass, 'bass-step');
      final ba = (double.tryParse(_text(bass, 'bass-alter')) ?? 0).round();
      name += '/$b${ba > 0 ? '#' : (ba < 0 ? 'b' : '')}';
    }
    return name;
  }

  Dynamic? _dynamic(String s) => switch (s) {
    'pppp' => Dynamic.pppp,
    'ppp' => Dynamic.ppp,
    'pp' => Dynamic.pp,
    'p' => Dynamic.p,
    'mp' => Dynamic.mp,
    'mf' => Dynamic.mf,
    'f' => Dynamic.f,
    'ff' => Dynamic.ff,
    'fff' => Dynamic.fff,
    'ffff' => Dynamic.ffff,
    _ => null,
  };

  Direction? _directionFromWords(String w) {
    final s = w.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    return switch (s) {
      'fine' => Direction.fine,
      'd.c.' || 'da capo' => Direction.daCapo,
      'd.c. al fine' || 'da capo al fine' => Direction.daCapoAlFine,
      'd.c. al coda' || 'da capo al coda' => Direction.daCapoAlCoda,
      'd.s.' || 'dal segno' => Direction.dalSegno,
      'd.s. al fine' || 'dal segno al fine' => Direction.dalSegnoAlFine,
      'd.s. al coda' || 'dal segno al coda' => Direction.dalSegnoAlCoda,
      'to coda' => Direction.toCoda,
      _ => null,
    };
  }
}

class _Master {
  _Master(this.time, this.key);
  TimeSignature time;
  KeySignature key;
  bool repeatStart = false;
  int repeatEnd = 0;
  final endings = <int>{};
  bool endingOpen = false;
  bool endingClosed = false;
  String? rehearsal;
  bool doubleBar = false;
  final directions = <Direction>{};
}
