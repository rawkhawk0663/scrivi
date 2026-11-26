import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../model/pitch.dart';
import '../model/score.dart';

/// Warum sich eine Datei nicht öffnen liess (die App macht daraus einen Text).
enum ScoreFileProblem {
  /// Keine Guitar-Pro-Datei (oder ganz unbekannt).
  unknownFormat,

  /// Älteres Guitar-Pro-Format (.gpx, .gp5 …), kommt mit Etappe 2.
  olderGuitarPro,

  /// Datei ist beschädigt oder unvollständig.
  damaged,
}

class ScoreFileException implements Exception {
  const ScoreFileException(this.problem, [this.detail = '']);
  final ScoreFileProblem problem;
  final String detail;

  @override
  String toString() => 'ScoreFileException(${problem.name}${detail.isEmpty ? '' : ': $detail'})';
}

/// Liest Guitar-Pro-Dateien im neueren Format (`.gp`: eine ZIP-Datei mit
/// `Content/score.gpif`, einer XML-Datei).
class GpReader {
  GpReader._();

  /// Datei-Inhalt lesen. Erkennt das Format am Anfang der Datei.
  static Score read(Uint8List bytes) {
    if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      final Archive zip;
      try {
        zip = ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        throw ScoreFileException(ScoreFileProblem.damaged, 'ZIP: $e');
      }
      final entry = zip.findFile('Content/score.gpif');
      if (entry == null) throw const ScoreFileException(ScoreFileProblem.unknownFormat, 'score.gpif fehlt');
      return readGpif(utf8.decode(entry.content, allowMalformed: true));
    }
    final head = String.fromCharCodes(bytes.take(32));
    if (head.startsWith('BCFZ') || head.startsWith('BCFS')) {
      throw const ScoreFileException(ScoreFileProblem.olderGuitarPro, 'gpx');
    }
    if (head.contains('FICHIER GUITAR PRO') || head.contains('FICHIER GUITAR')) {
      throw const ScoreFileException(ScoreFileProblem.olderGuitarPro, 'gp3/4/5');
    }
    final text = utf8.decode(bytes, allowMalformed: true).trimLeft();
    if (text.startsWith('<?xml') || text.startsWith('<GPIF')) return readGpif(text);
    throw const ScoreFileException(ScoreFileProblem.unknownFormat);
  }

  /// Den XML-Teil (`score.gpif`) lesen.
  static Score readGpif(String xml) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } catch (e) {
      throw ScoreFileException(ScoreFileProblem.damaged, 'XML: $e');
    }
    final root = doc.rootElement;
    if (root.name.local != 'GPIF') throw const ScoreFileException(ScoreFileProblem.unknownFormat, 'kein GPIF');
    try {
      return _Parser(root).parse();
    } on ScoreFileException {
      rethrow;
    } catch (e) {
      throw ScoreFileException(ScoreFileProblem.damaged, '$e');
    }
  }
}

class _Parser {
  _Parser(this.root);
  final XmlElement root;

  XmlElement? _child(XmlElement e, String name) {
    for (final c in e.childElements) {
      if (c.name.local == name) return c;
    }
    return null;
  }

  Iterable<XmlElement> _children(XmlElement? e, String name) =>
      e == null ? const [] : e.childElements.where((c) => c.name.local == name);

  String _text(XmlElement? e, String name) => (e == null ? null : _child(e, name))?.innerText.trim() ?? '';

  List<int> _ints(String s) =>
      s.trim().isEmpty ? [] : s.trim().split(RegExp(r'\s+')).map((x) => int.tryParse(x) ?? -1).toList();

  /// Eigenschaften (`<Properties><Property name="…">`) als Name → Element.
  Map<String, XmlElement> _props(XmlElement e) {
    final m = <String, XmlElement>{};
    for (final p in _children(_child(e, 'Properties'), 'Property')) {
      final n = p.getAttribute('name');
      if (n != null) m[n] = p;
    }
    return m;
  }

  Score parse() {
    final s = _child(root, 'Score');
    final info = ScoreInfo(
      title: _text(s, 'Title'),
      subtitle: _text(s, 'SubTitle'),
      artist: _text(s, 'Artist'),
      album: _text(s, 'Album'),
      words: _text(s, 'Words'),
      music: _text(s, 'Music').isNotEmpty ? _text(s, 'Music') : _text(s, 'WordsAndMusic'),
      copyright: _text(s, 'Copyright'),
      tabber: _text(s, 'Tabber'),
      instructions: _text(s, 'Instructions'),
    );

    final rhythms = <int, NoteDuration>{};
    for (final r in _children(_child(root, 'Rhythms'), 'Rhythm')) {
      rhythms[int.parse(r.getAttribute('id')!)] = _rhythm(r);
    }

    // Spuren zuerst: Sie bestimmen die Transposition der Noten.
    final trackEls = _children(_child(root, 'Tracks'), 'Track').toList();
    final masterTrackOrder = _ints(_text(_child(root, 'MasterTrack'), 'Tracks'));
    final orderedTrackEls = <XmlElement>[];
    for (final id in masterTrackOrder) {
      final el = trackEls.where((t) => t.getAttribute('id') == '$id');
      if (el.isNotEmpty) orderedTrackEls.add(el.first);
    }
    if (orderedTrackEls.isEmpty) orderedTrackEls.addAll(trackEls);

    final noteEls = {for (final n in _children(_child(root, 'Notes'), 'Note')) int.parse(n.getAttribute('id')!): n};
    final beatEls = {for (final b in _children(_child(root, 'Beats'), 'Beat')) int.parse(b.getAttribute('id')!): b};
    final voiceEls = {for (final v in _children(_child(root, 'Voices'), 'Voice')) int.parse(v.getAttribute('id')!): v};
    final barEls = {for (final b in _children(_child(root, 'Bars'), 'Bar')) int.parse(b.getAttribute('id')!): b};

    final masterBarEls = _children(_child(root, 'MasterBars'), 'MasterBar').toList();
    final masterBars = masterBarEls.map(_masterBar).toList();

    final tracks = <Track>[];
    for (var ti = 0; ti < orderedTrackEls.length; ti++) {
      final t = orderedTrackEls[ti];
      // Index der Spur in den <Bars> eines Master-Takts: Reihenfolge in <Tracks>.
      final trackIndex = trackEls.indexOf(t);
      final transpose = _child(t, 'Transpose');
      final chromatic = int.tryParse(_text(transpose, 'Chromatic')) ?? 0;
      final octave = int.tryParse(_text(transpose, 'Octave')) ?? 0;
      final transposeSemitones = -(chromatic + octave * 12);
      final staffEl = _children(_child(t, 'Staves'), 'Staff').firstOrNull;
      final staffProps = staffEl == null ? <String, XmlElement>{} : _props(staffEl);
      final tuning = _ints(staffProps['Tuning'] == null ? '' : _text(staffProps['Tuning'], 'Pitches'));
      final staff = StaffDef(
        tuning: tuning,
        capo: int.tryParse(_text(staffProps['CapoFret'], 'Fret')) ?? 0,
        fretCount: int.tryParse(_text(staffProps['FretCount'], 'Number')) ?? 24,
        tuningName: staffEl == null ? '' : _text(staffEl, 'Name'),
      );
      final chords = <int, ChordDef>{};
      for (final item in _children(_child(staffProps['DiagramCollection'] ?? XmlElement(XmlName('x')), 'Items'), 'Item')) {
        final id = int.tryParse(item.getAttribute('id') ?? '');
        if (id == null) continue;
        chords[id] = ChordDef(name: item.getAttribute('name') ?? '', diagram: _diagram(_child(item, 'Diagram')));
      }
      final hint = _ints(_text(t, 'SystemsLayout'));
      final defaultPerSystem = int.tryParse(_text(t, 'SystemsDefautLayout'));

      final bars = <Bar>[];
      for (var mi = 0; mi < masterBarEls.length; mi++) {
        final ids = _ints(_text(masterBarEls[mi], 'Bars'));
        final barId = trackIndex < ids.length ? ids[trackIndex] : -1;
        final barEl = barEls[barId];
        if (barEl == null) {
          bars.add(Bar(clef: Clef.treble, voices: []));
          continue;
        }
        final voices = <Voice>[];
        for (final vid in _ints(_text(barEl, 'Voices'))) {
          final v = voiceEls[vid];
          if (v == null) continue;
          final beats = <Beat>[];
          for (final bid in _ints(_text(v, 'Beats'))) {
            final b = beatEls[bid];
            if (b != null) beats.add(_beat(b, rhythms, noteEls, transposeSemitones, tuning));
          }
          if (beats.isNotEmpty) voices.add(Voice(beats));
        }
        bars.add(Bar(clef: _clef(_text(barEl, 'Clef'), transposeSemitones), voices: voices));
      }

      tracks.add(
        Track(
          name: _text(t, 'Name'),
          shortName: _text(t, 'ShortName'),
          staff: staff,
          bars: bars,
          chords: chords,
          layoutHint: hint.isNotEmpty && hint.every((x) => x > 0)
              ? hint
              : (defaultPerSystem != null && defaultPerSystem > 0 ? [defaultPerSystem] : null),
          transposeSemitones: transposeSemitones,
        ),
      );
    }

    return Score(info: info, masterBars: masterBars, tracks: tracks, tempos: _tempos());
  }

  List<TempoMark> _tempos() {
    final list = <TempoMark>[];
    for (final a in _children(_child(_child(root, 'MasterTrack') ?? XmlElement(XmlName('x')), 'Automations'), 'Automation')) {
      if (_text(a, 'Type') != 'Tempo') continue;
      final v = _text(a, 'Value').split(RegExp(r'\s+'));
      final bpm = double.tryParse(v.first) ?? 120;
      final unitCode = v.length > 1 ? int.tryParse(v[1]) ?? 2 : 2;
      // 1 Achtel, 2 Viertel, 3 punktierte Viertel, 4 Halbe, 5 punktierte Halbe
      final (unit, dotted) = switch (unitCode) {
        1 => (NoteValue.eighth, false),
        3 => (NoteValue.quarter, true),
        4 => (NoteValue.half, false),
        5 => (NoteValue.half, true),
        _ => (NoteValue.quarter, false),
      };
      list.add(
        TempoMark(
          bar: int.tryParse(_text(a, 'Bar')) ?? 0,
          position: double.tryParse(_text(a, 'Position')) ?? 0,
          bpm: bpm,
          unit: unit,
          dotted: dotted,
          visible: _text(a, 'Visible') != 'false',
        ),
      );
    }
    list.sort((a, b) => a.bar != b.bar ? a.bar.compareTo(b.bar) : a.position.compareTo(b.position));
    return list;
  }

  NoteDuration _rhythm(XmlElement r) {
    final v = switch (_text(r, 'NoteValue')) {
      'DoubleWhole' => NoteValue.doubleWhole,
      'Whole' => NoteValue.whole,
      'Half' => NoteValue.half,
      'Quarter' => NoteValue.quarter,
      'Eighth' => NoteValue.eighth,
      '16th' => NoteValue.sixteenth,
      '32nd' => NoteValue.thirtySecond,
      '64th' => NoteValue.sixtyFourth,
      '128th' => NoteValue.hundredTwentyEighth,
      _ => NoteValue.quarter,
    };
    final dots = int.tryParse(_child(r, 'AugmentationDot')?.getAttribute('count') ?? '') ?? 0;
    final t = _child(r, 'PrimaryTuplet');
    Tuplet? tuplet;
    if (t != null) {
      final num = int.tryParse(t.getAttribute('num') ?? '') ?? 1;
      final den = int.tryParse(t.getAttribute('den') ?? '') ?? 1;
      if (num > 0 && den > 0 && num != den) tuplet = Tuplet(num, den);
    }
    return NoteDuration(v, dots: dots, tuplet: tuplet);
  }

  MasterBar _masterBar(XmlElement m) {
    final key = _child(m, 'Key');
    final timeText = _text(m, 'Time');
    final parts = timeText.split('/');
    final time = parts.length == 2
        ? TimeSignature(int.tryParse(parts[0]) ?? 4, int.tryParse(parts[1]) ?? 4)
        : const TimeSignature(4, 4);
    final rep = _child(m, 'Repeat');
    final sec = _child(m, 'Section');
    final dirs = <Direction>{};
    final d = _child(m, 'Directions');
    if (d != null) {
      for (final c in d.childElements) {
        final dir = switch (c.innerText.trim()) {
          'Segno' => Direction.segno,
          'SegnoSegno' => Direction.segnoSegno,
          'Coda' => Direction.coda,
          'DoubleCoda' => Direction.doubleCoda,
          'Fine' => Direction.fine,
          'DaCapo' => Direction.daCapo,
          'DaCapoAlFine' => Direction.daCapoAlFine,
          'DaCapoAlCoda' || 'DaCapoAlDoubleCoda' => Direction.daCapoAlCoda,
          'DaSegno' || 'DaSegnoSegno' => Direction.dalSegno,
          'DaSegnoAlFine' || 'DaSegnoSegnoAlFine' => Direction.dalSegnoAlFine,
          'DaSegnoAlCoda' || 'DaSegnoAlDoubleCoda' || 'DaSegnoSegnoAlCoda' || 'DaSegnoSegnoAlDoubleCoda' => Direction.dalSegnoAlCoda,
          'DaCoda' || 'DaDoubleCoda' => Direction.toCoda,
          _ => null,
        };
        if (dir != null) dirs.add(dir);
      }
    }
    return MasterBar(
      time: time,
      key: KeySignature(int.tryParse(_text(key, 'AccidentalCount')) ?? 0, minor: _text(key, 'Mode') == 'Minor'),
      repeatStart: rep?.getAttribute('start') == 'true',
      repeatEnd: rep?.getAttribute('end') == 'true' ? (int.tryParse(rep?.getAttribute('count') ?? '') ?? 2).clamp(2, 99) : 0,
      endings: _ints(_text(m, 'AlternateEndings')).where((x) => x > 0).toSet(),
      section: sec == null ? null : Section(letter: _text(sec, 'Letter'), text: _text(sec, 'Text')),
      doubleBar: _child(m, 'DoubleBar') != null,
      freeTime: _child(m, 'FreeTime') != null,
      directions: dirs,
    );
  }

  ChordDiagram? _diagram(XmlElement? d) {
    if (d == null) return null;
    final strings = int.tryParse(d.getAttribute('stringCount') ?? '') ?? 6;
    final frets = List<int>.filled(strings, -1);
    for (final f in _children(d, 'Fret')) {
      final s = int.tryParse(f.getAttribute('string') ?? '');
      final v = int.tryParse(f.getAttribute('fret') ?? '');
      if (s != null && v != null && s >= 0 && s < strings) frets[s] = v;
    }
    return ChordDiagram(
      stringCount: strings,
      baseFret: int.tryParse(d.getAttribute('baseFret') ?? '') ?? 0,
      frets: frets,
      fretCount: int.tryParse(d.getAttribute('fretCount') ?? '') ?? 5,
    );
  }

  Clef _clef(String s, int transpose) => switch (s) {
    'F4' => Clef.bass,
    'C3' => Clef.alto,
    'C4' => Clef.tenor,
    'Neutral' => Clef.neutral,
    // Gitarre: eine Oktave höher geschrieben als sie klingt → Violinschlüssel mit kleiner 8.
    _ => transpose == 12 ? Clef.treble8vb : Clef.treble,
  };

  Beat _beat(XmlElement b, Map<int, NoteDuration> rhythms, Map<int, XmlElement> noteEls, int transpose, List<int> tuning) {
    final rid = int.tryParse(_child(b, 'Rhythm')?.getAttribute('ref') ?? '');
    final notes = <Note>[];
    for (final nid in _ints(_text(b, 'Notes'))) {
      final n = noteEls[nid];
      if (n != null) {
        final note = _note(n, transpose, tuning);
        if (note != null) notes.add(note);
      }
    }
    final props = _props(b);
    final stroke = _text(props['PickStroke'], 'Direction');
    final lyrics = _children(_child(b, 'Lyrics'), 'Line').map((l) => l.innerText.trim()).toList();
    while (lyrics.isNotEmpty && lyrics.last.isEmpty) {
      lyrics.removeLast();
    }
    final text = _text(b, 'FreeText');
    return Beat(
      duration: rhythms[rid] ?? const NoteDuration(NoteValue.quarter),
      notes: notes,
      slashed: _child(b, 'Slashed') != null,
      chordId: int.tryParse(_text(b, 'Chord')),
      text: text.isEmpty ? null : text,
      dynamic: _dynamic(_text(b, 'Dynamic')),
      hairpin: switch (_text(b, 'Hairpin')) {
        'Crescendo' => Hairpin.crescendo,
        'Decrescendo' => Hairpin.decrescendo,
        _ => Hairpin.none,
      },
      lyrics: lyrics,
      grace: switch (_text(b, 'GraceNotes')) {
        'BeforeBeat' => GraceType.beforeBeat,
        'OnBeat' => GraceType.onBeat,
        _ => GraceType.none,
      },
      pickStroke: stroke == 'Down' ? 1 : (stroke == 'Up' ? -1 : 0),
    );
  }

  Dynamic? _dynamic(String s) => switch (s) {
    'PPPP' => Dynamic.pppp,
    'PPP' => Dynamic.ppp,
    'PP' => Dynamic.pp,
    'P' => Dynamic.p,
    'MP' => Dynamic.mp,
    'MF' => Dynamic.mf,
    'F' => Dynamic.f,
    'FF' => Dynamic.ff,
    'FFF' => Dynamic.fff,
    'FFFF' => Dynamic.ffff,
    _ => null,
  };

  int _stepOf(String s) => const {'C': 0, 'D': 1, 'E': 2, 'F': 3, 'G': 4, 'A': 5, 'B': 6}[s.toUpperCase()] ?? 0;

  int _alterOf(String s) => switch (s) {
    '#' => 1,
    '##' || 'x' => 2,
    'b' => -1,
    'bb' => -2,
    _ => 0,
  };

  Note? _note(XmlElement n, int transpose, List<int> tuning) {
    final p = _props(n);
    final string = int.tryParse(_text(p['String'], 'String'));
    final fret = int.tryParse(_text(p['Fret'], 'Fret'));
    var midi = int.tryParse(_text(p['Midi'], 'Number'));
    if (midi == null && string != null && fret != null && string < tuning.length) midi = tuning[string] + fret;
    if (midi == null) {
      // Nur Tonhöhe angegeben (ohne Saite): aus der Schreibweise rechnen.
      final cp = _child(p['ConcertPitch'] ?? XmlElement(XmlName('x')), 'Pitch');
      if (cp == null) return null;
      final step = _stepOf(_text(cp, 'Step'));
      final alter = _alterOf(_text(cp, 'Accidental'));
      final oct = int.tryParse(_text(cp, 'Octave')) ?? 4;
      // In dieser Datei ist C5 das mittlere C (eine Oktave höher gezählt).
      midi = oct * 12 + const [0, 2, 4, 5, 7, 9, 11][step] + alter;
    }
    Pitch spelled(String propName, int m) {
      final el = _child(p[propName] ?? XmlElement(XmlName('x')), 'Pitch');
      if (el == null) return Pitch.fromMidi(m);
      return Pitch.fromMidiSpelled(m, _stepOf(_text(el, 'Step')), _alterOf(_text(el, 'Accidental')));
    }

    final concert = spelled('ConcertPitch', midi);
    Pitch? written;
    if (transpose != 0) {
      final hasWritten = _child(p['TransposedPitch'] ?? XmlElement(XmlName('x')), 'Pitch') != null;
      // Fehlt die geschriebene Tonhöhe: bei ganzen Oktaven die Schreibweise übernehmen.
      written = hasWritten || transpose % 12 != 0 ? spelled('TransposedPitch', midi + transpose) : concert.octaves(transpose ~/ 12);
    }

    final tie = _child(n, 'Tie');
    Bend? bend;
    if (p.containsKey('Bended')) {
      double val(String name) => (double.tryParse(_text(p[name], 'Float')) ?? -1);
      final pts = <BendPoint>[];
      void add(String off, String value) {
        final o = val(off), v = val(value);
        if (o >= 0 && v >= 0) pts.add(BendPoint(o / 100, v / 50));
      }

      add('BendOriginOffset', 'BendOriginValue');
      add('BendMiddleOffset1', 'BendMiddleValue');
      add('BendMiddleOffset2', 'BendMiddleValue');
      add('BendDestinationOffset', 'BendDestinationValue');
      if (pts.isEmpty) pts.addAll([const BendPoint(0, 0), const BendPoint(1, 2)]);
      pts.sort((a, b) => a.position.compareTo(b.position));
      bend = Bend(pts);
    }

    return Note(
      pitch: concert,
      written: written,
      string: string,
      fret: fret,
      tieOrigin: tie?.getAttribute('origin') == 'true',
      tieDestination: tie?.getAttribute('destination') == 'true',
      palmMuted: p.containsKey('PalmMuted'),
      dead: p.containsKey('Muted'),
      ghost: _child(n, 'AntiAccent') != null,
      letRing: _child(n, 'LetRing') != null,
      slide: int.tryParse(_text(p['Slide'], 'Flags')) ?? 0,
      hammerOrigin: p.containsKey('HopoOrigin'),
      hammerDestination: p.containsKey('HopoDestination'),
      bend: bend,
      accent: int.tryParse(_text(n, 'Accent')) ?? 0,
      vibrato: _child(n, 'Vibrato') != null,
      harmonic: p.containsKey('HarmonicType'),
      tapped: p.containsKey('Tapped'),
    );
  }
}
