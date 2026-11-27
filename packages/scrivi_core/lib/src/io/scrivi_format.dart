import 'dart:convert';
import 'dart:typed_data';

import '../model/pitch.dart';
import '../model/score.dart';
import 'gp_reader.dart' show ScoreFileException, ScoreFileProblem;

/// Das eigene Dateiformat `.scrivi`: das ganze Stück als lesbarer Text (JSON).
///
/// Aufbau: `{"format": "scrivi", "version": 1, "info": …, "tempos": […],
/// "masterBars": […], "tracks": […]}`. Grundwerte werden weggelassen, damit die
/// Dateien klein bleiben. Unbekannte Felder werden beim Lesen übergangen, so
/// können spätere Versionen Neues ergänzen, ohne dass ältere Dateien unlesbar
/// werden. Schlüssel nie übersetzen.
class ScriviFormat {
  ScriviFormat._();

  static const format = 'scrivi';
  static const version = 1;

  /// Sieht der Inhalt nach einer Scrivi-Datei aus?
  static bool looksLike(Uint8List bytes) {
    final head = String.fromCharCodes(bytes.take(200)).trimLeft();
    return head.startsWith('{') && head.contains('"format"') && head.contains('"scrivi"');
  }

  static Uint8List encode(Score s) =>
      Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(toJson(s))));

  static Score decode(Uint8List bytes) {
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } catch (e) {
      throw ScoreFileException(ScoreFileProblem.damaged, 'scrivi: $e');
    }
    if (j is! Map<String, dynamic> || j['format'] != format) {
      throw const ScoreFileException(ScoreFileProblem.unknownFormat);
    }
    try {
      return fromJson(j);
    } catch (e) {
      throw ScoreFileException(ScoreFileProblem.damaged, 'scrivi: $e');
    }
  }

  // ───────────────────────── Schreiben ─────────────────────────

  static Map<String, dynamic> toJson(Score s) => {
    'format': format,
    'version': version,
    'info': _info(s.info),
    'tempos': [for (final t in s.tempos) _tempo(t)],
    'masterBars': [for (final m in s.masterBars) _masterBar(m)],
    'tracks': [for (final t in s.tracks) _track(t)],
  };

  static Map<String, dynamic> _compact(Map<String, dynamic> m) {
    m.removeWhere(
      (k, v) =>
          v == null || v == false || (v is String && v.isEmpty) || (v is List && v.isEmpty) || (v is Map && v.isEmpty),
    );
    return m;
  }

  static Map<String, dynamic> _info(ScoreInfo i) => _compact({
    'title': i.title,
    'subtitle': i.subtitle,
    'artist': i.artist,
    'album': i.album,
    'words': i.words,
    'music': i.music,
    'copyright': i.copyright,
    'tabber': i.tabber,
    'instructions': i.instructions,
  });

  static Map<String, dynamic> _tempo(TempoMark t) => _compact({
    'bar': t.bar,
    'position': t.position == 0 ? null : t.position,
    'bpm': t.bpm,
    'unit': t.unit == NoteValue.quarter ? null : t.unit.name,
    'dotted': t.dotted,
    'hidden': !t.visible,
  });

  static Map<String, dynamic> _masterBar(MasterBar m) => _compact({
    'time': '${m.time.beats}/${m.time.beatType}${m.time.common ? 'c' : ''}',
    'key': m.key.fifths == 0 && !m.key.minor ? null : '${m.key.fifths}${m.key.minor ? 'm' : ''}',
    'repeatStart': m.repeatStart,
    'repeatEnd': m.repeatEnd == 0 ? null : m.repeatEnd,
    'endings': (m.endings.toList()..sort()),
    'section': m.section == null ? null : _compact({'letter': m.section!.letter, 'text': m.section!.text}),
    'doubleBar': m.doubleBar,
    'freeTime': m.freeTime,
    'directions': [for (final d in m.directions) d.name],
    'swing': m.swing,
  });

  static Map<String, dynamic> _track(Track t) => _compact({
    'name': t.name,
    'shortName': t.shortName,
    'program': t.program < 0 ? null : t.program,
    'transpose': t.transposeSemitones == 0 ? null : t.transposeSemitones,
    'instrumentKey': t.instrumentKey == 0 ? null : t.instrumentKey,
    'layout': t.layoutHint,
    'staff': _compact({
      'tuning': t.staff.tuning,
      'capo': t.staff.capo == 0 ? null : t.staff.capo,
      'frets': t.staff.fretCount == 24 ? null : t.staff.fretCount,
      'hideNotation': !t.staff.showNotation,
      'hideTab': !t.staff.showTab,
      'tuningName': t.staff.tuningName,
    }),
    'chords': {for (final e in t.chords.entries) '${e.key}': _chord(e.value)},
    'bars': [for (final b in t.bars) _bar(b)],
  });

  static Map<String, dynamic> _chord(ChordDef c) {
    final d = c.diagram;
    return _compact({
      'name': c.name,
      'diagram': d == null
          ? null
          : _compact({
              'strings': d.stringCount,
              'base': d.baseFret == 0 ? null : d.baseFret,
              'frets': d.frets,
              'fretCount': d.fretCount == 5 ? null : d.fretCount,
              'barres': [
                for (final b in d.barres) [b.fret, b.from, b.to],
              ],
              'hidden': !d.visible,
            }),
    });
  }

  static Map<String, dynamic> _bar(Bar b) => _compact({
    'clef': b.clef == Clef.treble ? null : b.clef.name,
    'voices': [
      for (final v in b.voices) [for (final beat in v.beats) _beat(beat)],
    ],
  });

  static Map<String, dynamic> _beat(Beat b) {
    final d = b.duration;
    return _compact({
      'd': d.value.name,
      'dots': d.dots == 0 ? null : d.dots,
      'tuplet': d.tuplet == null ? null : [d.tuplet!.actual, d.tuplet!.normal],
      'notes': [for (final n in b.notes) _note(n)],
      'slashed': b.slashed,
      'chord': b.chordId,
      'text': b.text,
      'dynamic': b.dynamic?.name,
      'hairpin': b.hairpin == Hairpin.none ? null : b.hairpin.name,
      'lyrics': b.lyrics.every((l) => l.isEmpty) ? null : b.lyrics,
      'grace': b.grace == GraceType.none ? null : b.grace.name,
      'fermata': b.fermata,
      'stroke': b.pickStroke == 0 ? null : b.pickStroke,
      'letRingText': b.letRingText,
      'tremolo': b.tremolo == 0 ? null : b.tremolo,
    });
  }

  static List<int> _pitch(Pitch p) => [p.step, p.alter, p.octave];

  static Map<String, dynamic> _note(Note n) => _compact({
    'p': _pitch(n.pitch),
    'w': n.written == null ? null : _pitch(n.written!),
    's': n.string,
    'f': n.fret,
    'tieOrigin': n.tieOrigin,
    'tie': n.tieDestination,
    'pm': n.palmMuted,
    'dead': n.dead,
    'ghost': n.ghost,
    'letRing': n.letRing,
    'slide': n.slide == 0 ? null : n.slide,
    'hammer': n.hammerOrigin,
    'hammerTo': n.hammerDestination,
    'bend': n.bend == null
        ? null
        : [
            for (final p in n.bend!.points) [p.position, p.semitones],
          ],
    'accent': n.accent == 0 ? null : n.accent,
    'vibrato': n.vibrato,
    'harmonic': n.harmonic,
    'tapped': n.tapped,
  });

  // ───────────────────────── Lesen ─────────────────────────

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  static List<Object?> _list(Object? v) => v is List ? v : const [];
  static Map<String, dynamic> _map(Object? v) => v is Map<String, dynamic> ? v : const {};
  static int _int(Object? v, [int d = 0]) => v is num ? v.toInt() : d;
  static double _double(Object? v, [double d = 0]) => v is num ? v.toDouble() : d;
  static String _str(Object? v) => v is String ? v : '';
  static bool _bool(Object? v) => v == true;

  static Score fromJson(Map<String, dynamic> j) {
    final info = _map(j['info']);
    return Score(
      info: ScoreInfo(
        title: _str(info['title']),
        subtitle: _str(info['subtitle']),
        artist: _str(info['artist']),
        album: _str(info['album']),
        words: _str(info['words']),
        music: _str(info['music']),
        copyright: _str(info['copyright']),
        tabber: _str(info['tabber']),
        instructions: _str(info['instructions']),
      ),
      tempos: [
        for (final t in _list(j['tempos']).map(_map))
          TempoMark(
            bar: _int(t['bar']),
            position: _double(t['position']),
            bpm: _double(t['bpm'], 120),
            unit: _enum(NoteValue.values, t['unit'], NoteValue.quarter),
            dotted: _bool(t['dotted']),
            visible: !_bool(t['hidden']),
          ),
      ],
      masterBars: [for (final m in _list(j['masterBars']).map(_map)) _readMasterBar(m)],
      tracks: [for (final t in _list(j['tracks']).map(_map)) _readTrack(t)],
    );
  }

  static MasterBar _readMasterBar(Map<String, dynamic> m) {
    final time = RegExp(r'^(\d+)/(\d+)(c?)$').firstMatch(_str(m['time']));
    final key = RegExp(r'^(-?\d+)(m?)$').firstMatch(_str(m['key']));
    final sec = m['section'];
    return MasterBar(
      time: time == null
          ? const TimeSignature(4, 4)
          : TimeSignature(int.parse(time[1]!), int.parse(time[2]!), common: time[3] == 'c'),
      key: key == null ? const KeySignature(0) : KeySignature(int.parse(key[1]!), minor: key[2] == 'm'),
      repeatStart: _bool(m['repeatStart']),
      repeatEnd: _int(m['repeatEnd']),
      endings: {for (final e in _list(m['endings'])) _int(e)},
      section: sec == null ? null : Section(letter: _str(_map(sec)['letter']), text: _str(_map(sec)['text'])),
      doubleBar: _bool(m['doubleBar']),
      freeTime: _bool(m['freeTime']),
      swing: _bool(m['swing']),
      directions: {
        for (final d in _list(m['directions']))
          if (Direction.values.any((x) => x.name == d)) _enum(Direction.values, d, Direction.fine),
      },
    );
  }

  static Track _readTrack(Map<String, dynamic> t) {
    final st = _map(t['staff']);
    final layout = t['layout'];
    return Track(
      name: _str(t['name']),
      shortName: _str(t['shortName']),
      program: _int(t['program'], -1),
      transposeSemitones: _int(t['transpose']),
      instrumentKey: _int(t['instrumentKey']),
      layoutHint: layout is List ? [for (final x in layout) _int(x)] : null,
      staff: StaffDef(
        tuning: [for (final x in _list(st['tuning'])) _int(x)],
        capo: _int(st['capo']),
        fretCount: _int(st['frets'], 24),
        showNotation: !_bool(st['hideNotation']),
        showTab: !_bool(st['hideTab']),
        tuningName: _str(st['tuningName']),
      ),
      chords: {
        for (final e in _map(t['chords']).entries)
          if (int.tryParse(e.key) != null) int.parse(e.key): _readChord(_map(e.value)),
      },
      bars: [for (final b in _list(t['bars']).map(_map)) _readBar(b)],
    );
  }

  static ChordDef _readChord(Map<String, dynamic> c) {
    final d = c['diagram'];
    ChordDiagram? diagram;
    if (d is Map<String, dynamic>) {
      diagram = ChordDiagram(
        stringCount: _int(d['strings'], 6),
        baseFret: _int(d['base']),
        frets: [for (final f in _list(d['frets'])) _int(f, -1)],
        fretCount: _int(d['fretCount'], 5),
        barres: [
          for (final b in _list(d['barres']))
            if (b is List && b.length == 3) ChordBarre(fret: _int(b[0]), from: _int(b[1]), to: _int(b[2])),
        ],
        visible: !_bool(d['hidden']),
      );
    }
    return ChordDef(name: _str(c['name']), diagram: diagram);
  }

  static Bar _readBar(Map<String, dynamic> b) => Bar(
    clef: _enum(Clef.values, b['clef'], Clef.treble),
    voices: [
      for (final v in _list(b['voices'])) Voice([for (final beat in _list(v).map(_map)) _readBeat(beat)]),
    ],
  );

  static Beat _readBeat(Map<String, dynamic> b) {
    final t = b['tuplet'];
    return Beat(
      duration: NoteDuration(
        _enum(NoteValue.values, b['d'], NoteValue.quarter),
        dots: _int(b['dots']),
        tuplet: t is List && t.length == 2 ? Tuplet(_int(t[0], 3), _int(t[1], 2)) : null,
      ),
      notes: [for (final n in _list(b['notes']).map(_map)) _readNote(n)],
      slashed: _bool(b['slashed']),
      chordId: b['chord'] is num ? _int(b['chord']) : null,
      text: b['text'] is String ? b['text'] as String : null,
      dynamic: b['dynamic'] == null ? null : _enum(Dynamic.values, b['dynamic'], Dynamic.mf),
      hairpin: _enum(Hairpin.values, b['hairpin'], Hairpin.none),
      lyrics: [for (final l in _list(b['lyrics'])) _str(l)],
      grace: _enum(GraceType.values, b['grace'], GraceType.none),
      fermata: _bool(b['fermata']),
      pickStroke: _int(b['stroke']),
      letRingText: _bool(b['letRingText']),
      tremolo: _int(b['tremolo']),
    );
  }

  static Pitch _readPitch(Object? v) {
    final l = _list(v);
    if (l.length != 3) return const Pitch(0, 0, 4);
    return Pitch(_int(l[0]).clamp(0, 6), _int(l[1]).clamp(-2, 2), _int(l[2], 4));
  }

  static Note _readNote(Map<String, dynamic> n) {
    final bend = n['bend'];
    return Note(
      pitch: _readPitch(n['p']),
      written: n['w'] == null ? null : _readPitch(n['w']),
      string: n['s'] is num ? _int(n['s']) : null,
      fret: n['f'] is num ? _int(n['f']) : null,
      tieOrigin: _bool(n['tieOrigin']),
      tieDestination: _bool(n['tie']),
      palmMuted: _bool(n['pm']),
      dead: _bool(n['dead']),
      ghost: _bool(n['ghost']),
      letRing: _bool(n['letRing']),
      slide: _int(n['slide']),
      hammerOrigin: _bool(n['hammer']),
      hammerDestination: _bool(n['hammerTo']),
      bend: bend is List
          ? Bend([
              for (final p in bend)
                if (p is List && p.length == 2) BendPoint(_double(p[0]), _double(p[1])),
            ])
          : null,
      accent: _int(n['accent']),
      vibrato: _bool(n['vibrato']),
      harmonic: _bool(n['harmonic']),
      tapped: _bool(n['tapped']),
    );
  }
}
