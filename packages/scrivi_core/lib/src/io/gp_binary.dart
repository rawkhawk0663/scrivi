import 'dart:typed_data';

import '../model/pitch.dart';
import '../model/score.dart';
import 'binary.dart';
import 'gp_reader.dart';

/// Liest ältere Guitar-Pro-Dateien (`.gp3`, `.gp4`, `.gp5`, Binärformat).
class GpBinaryReader {
  GpBinaryReader._(this.r);
  final BinaryReader r;

  late int _major;
  late int _minor;
  int _songKey = 0;
  String _lyricsText = '';
  final _lyrics = <(int, String)>[];
  int _lyricsTrack = 0;

  /// Liest die Datei; wirft [ScoreFileException], wenn sie nicht passt.
  static Score read(Uint8List bytes) {
    final reader = GpBinaryReader._(BinaryReader(bytes));
    try {
      return reader._song();
    } on ScoreFileException {
      rethrow;
    } catch (e) {
      throw ScoreFileException(ScoreFileProblem.damaged, '$e');
    }
  }

  /// Fängt die Datei wie eine ältere Guitar-Pro-Datei an?
  static bool looksLike(Uint8List bytes) {
    if (bytes.length < 31) return false;
    final head = String.fromCharCodes(bytes.sublist(1, 1 + bytes[0].clamp(0, 30)));
    return head.startsWith('FICHIER GUITAR PRO') || head.startsWith('CLIPBOARD');
  }

  bool get _gp5 => _major >= 5;
  bool get _gp4 => _major == 4;
  bool get _gp3 => _major <= 3;
  bool get _v500 => _major == 5 && _minor == 0;

  Score _song() {
    final version = r.byteSizeString(30);
    final m = RegExp(r'(\d)\.(\d\d)').firstMatch(version);
    if (m == null || version.startsWith('CLIPBOARD')) {
      throw ScoreFileException(ScoreFileProblem.unknownFormat, version);
    }
    _major = int.parse(m.group(1)!);
    _minor = int.parse(m.group(2)!);
    if (_major < 3 || _major > 5) throw ScoreFileException(ScoreFileProblem.unknownFormat, version);

    // Angaben
    final title = r.intByteSizeString();
    final subtitle = r.intByteSizeString();
    final artist = r.intByteSizeString();
    final album = r.intByteSizeString();
    final words = r.intByteSizeString();
    final music = _gp5 ? r.intByteSizeString() : words;
    final copyright = r.intByteSizeString();
    final tab = r.intByteSizeString();
    final instructions = r.intByteSizeString();
    final notices = r.i32();
    for (var i = 0; i < notices; i++) {
      r.intByteSizeString();
    }
    final info = ScoreInfo(
      title: title,
      subtitle: subtitle,
      artist: artist,
      album: album,
      words: words,
      music: music,
      copyright: copyright,
      tabber: tab,
      instructions: instructions,
    );

    int tempo;
    if (_gp5) {
      _readLyrics();
      if (_major == 5 && _minor > 0) {
        r.i32();
        r.i32();
        r.skip(11);
      }
      _skipPageSetup();
      r.intByteSizeString(); // Tempo-Name
      tempo = r.i32();
      if (_minor > 0) r.boolean(); // Tempo verstecken
      _songKey = r.i8();
      r.i32(); // Oktave
    } else {
      r.boolean(); // Triolen-Gefühl
      if (_gp4) _readLyrics();
      tempo = r.i32();
      _songKey = r.i32();
      if (_gp4) r.i8(); // Oktave
    }
    final percussionChannels = <int>{};
    for (var i = 0; i < 64; i++) {
      r.i32(); // Instrument
      r.skip(6 + 2);
      if (i % 16 == 9) percussionChannels.add(i);
    }
    final directions = <int, Set<Direction>>{};
    if (_gp5) {
      const targets = [Direction.coda, Direction.doubleCoda, Direction.segno, Direction.segnoSegno, Direction.fine];
      const jumps = [
        Direction.daCapo, Direction.daCapoAlCoda, Direction.daCapoAlCoda, Direction.daCapoAlFine, //
        Direction.dalSegno, Direction.dalSegnoAlCoda, Direction.dalSegnoAlCoda, Direction.dalSegnoAlFine,
        Direction.dalSegno, Direction.dalSegnoAlCoda, Direction.dalSegnoAlCoda, Direction.dalSegnoAlFine,
        Direction.toCoda, Direction.toCoda,
      ];
      for (final d in [...targets, ...jumps]) {
        final bar = r.i16();
        if (bar > 0) (directions[bar - 1] ??= {}).add(d);
      }
      r.i32(); // Hall
    }
    final measureCount = r.i32();
    final trackCount = r.i32();
    if (measureCount < 0 || measureCount > 100000 || trackCount < 0 || trackCount > 128) {
      throw const ScoreFileException(ScoreFileProblem.damaged, 'Anzahl Takte/Spuren');
    }

    final headers = <_Header>[];
    for (var i = 0; i < measureCount; i++) {
      headers.add(_measureHeader(i, headers));
    }
    final tracks = <_Track>[];
    for (var i = 0; i < trackCount; i++) {
      tracks.add(_track(i, percussionChannels));
    }
    if (_gp5) r.skip(_v500 ? 2 : 1);

    final tempos = <TempoMark>[TempoMark(bar: 0, bpm: tempo.toDouble())];
    for (var mi = 0; mi < measureCount; mi++) {
      for (final t in tracks) {
        final voices = <List<_Beat>>[];
        final voiceCount = _gp5 ? 2 : 1;
        for (var v = 0; v < voiceCount; v++) {
          final count = r.i32();
          if (count < 0 || count > 10000) throw const ScoreFileException(ScoreFileProblem.damaged, 'Schläge');
          final beats = <_Beat>[];
          for (var b = 0; b < count; b++) {
            final beat = _beat(t, mi, headers[mi].key);
            if (beat == null) continue;
            if (beat.tempo != null && t == tracks.first && v == 0 && beat.tempo! > 0) {
              if (tempos.last.bar != mi || tempos.length > 1) {
                tempos.add(TempoMark(bar: mi, bpm: beat.tempo!.toDouble()));
              } else {
                tempos[tempos.length - 1] = TempoMark(bar: mi, bpm: beat.tempo!.toDouble());
              }
            }
            beats.add(beat);
          }
          voices.add(beats);
        }
        // Zeilenumbruch (fehlt manchmal ganz am Dateiende)
        if (_gp5 && !r.atEnd) r.u8();
        t.bars.add(voices);
      }
    }
    // Erste Tempoangabe: am Anfang ohne Doppelte
    final cleaned = <TempoMark>[];
    for (final tm in tempos) {
      if (cleaned.isNotEmpty && cleaned.last.bar == tm.bar) {
        cleaned[cleaned.length - 1] = tm;
      } else if (cleaned.isEmpty || cleaned.last.bpm != tm.bpm) {
        cleaned.add(tm);
      }
    }

    // Takt-Angaben
    final masterBars = <MasterBar>[];
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i];
      masterBars.add(
        MasterBar(
          time: TimeSignature(h.num, h.den),
          key: KeySignature(h.key, minor: h.minor),
          repeatStart: h.repeatOpen,
          repeatEnd: h.repeatClose >= 0 ? (h.repeatClose + 1).clamp(2, 99) : 0,
          endings: {
            for (var b = 0; b < 8; b++)
              if (h.endings & (1 << b) != 0) b + 1,
          },
          section: h.marker == null ? null : Section(text: h.marker!),
          doubleBar: h.doubleBar,
          directions: directions[i],
        ),
      );
    }

    _applyLyrics(tracks);
    return Score(
      info: info,
      masterBars: masterBars,
      tracks: [for (final t in tracks) t.build(headers)],
      tempos: cleaned,
    );
  }

  void _readLyrics() {
    _lyricsTrack = r.i32();
    for (var i = 0; i < 5; i++) {
      final start = r.i32();
      final text = r.intSizeString();
      _lyrics.add((start, text));
    }
    _lyricsText = _lyrics.map((l) => l.$2).join();
  }

  void _skipPageSetup() {
    r.skip(4 * 7); // Seitengrösse, Ränder, Grösse
    r.i16(); // Kopf- und Fusszeile
    for (var i = 0; i < 10; i++) {
      r.intByteSizeString();
    }
  }

  _Header _measureHeader(int index, List<_Header> previous) {
    final prev = previous.isEmpty ? null : previous.last;
    if (_gp5 && prev != null) r.skip(1);
    final flags = r.u8();
    final h = _Header();
    h.num = (flags & 0x01) != 0 ? r.i8() : (prev?.num ?? 4);
    h.den = (flags & 0x02) != 0 ? r.i8() : (prev?.den ?? 4);
    if (h.num <= 0) h.num = 4;
    if (h.den <= 0) h.den = 4;
    h.repeatOpen = (flags & 0x04) != 0;
    if ((flags & 0x08) != 0) {
      final v = r.i8();
      h.repeatClose = _gp5 ? v - 1 : v;
      if (h.repeatClose < 1) h.repeatClose = 1;
    }
    int readAlternative() {
      final v = r.u8();
      if (_gp5) return v;
      // GP3/4: Nummer des Hauses → Bitmaske ohne die schon vergebenen
      var existing = 0;
      for (final p in previous.reversed) {
        if (p.repeatOpen) break;
        existing |= p.endings;
      }
      return ((1 << v) - 1) ^ existing;
    }

    if (!_gp5 && (flags & 0x10) != 0) h.endings = readAlternative();
    if ((flags & 0x20) != 0) {
      h.marker = r.intByteSizeString();
      r.skip(4); // Farbe
    }
    if ((flags & 0x40) != 0) {
      h.key = r.i8();
      h.minor = r.i8() != 0;
    } else if (prev != null) {
      h.key = prev.key;
      h.minor = prev.minor;
    } else {
      h.key = (_songKey >= -7 && _songKey <= 7) ? _songKey : 0;
    }
    if (_gp5 && (flags & 0x10) != 0) h.endings = readAlternative();
    h.doubleBar = (flags & 0x80) != 0;
    if (_gp5) {
      if ((flags & 0x03) != 0) r.skip(4); // Balkengruppen
      if ((flags & 0x10) == 0) r.skip(1);
      r.u8(); // Triolen-Gefühl
    }
    return h;
  }

  _Track _track(int index, Set<int> percussionChannels) {
    if (_gp5 && (index == 0 || _v500)) r.skip(1);
    final flags = r.u8();
    final t = _Track();
    t.percussion = (flags & 0x01) != 0;
    t.name = r.byteSizeString(40);
    final stringCount = r.i32();
    final tuning = <int>[];
    for (var i = 0; i < 7; i++) {
      final v = r.i32();
      if (i < stringCount) tuning.add(v);
    }
    t.tuningHighFirst = tuning;
    r.i32(); // Port
    final channel = r.i32() - 1;
    r.i32(); // Effekt-Kanal
    if (percussionChannels.contains(channel)) t.percussion = true;
    t.fretCount = r.i32();
    t.capo = r.i32();
    r.skip(4); // Farbe
    if (_gp5) {
      final flags2 = r.i16();
      t.showTab = (flags2 & 0x0001) != 0 || flags2 == 0;
      t.showNotation = (flags2 & 0x0002) != 0 || flags2 == 0;
      r.u8(); // Akzentuierung
      r.u8(); // Bank
      r.u8(); // Humanize
      r.i32();
      r.i32();
      r.i32();
      r.skip(12);
      r.i32();
      r.i32();
      r.i32();
      if (_v500) {
        r.i16();
        r.skip(1);
      } else {
        r.i32();
      }
      if (_minor > 0) {
        r.skip(4); // Equalizer
        r.intByteSizeString();
        r.intByteSizeString();
      }
    }
    return t;
  }

  _Beat? _beat(_Track t, int bar, int key) {
    final flags = r.u8();
    var status = 1;
    if ((flags & 0x40) != 0) status = r.u8();
    final dur = r.i8();
    final value = switch (dur) {
      -2 => NoteValue.whole,
      -1 => NoteValue.half,
      0 => NoteValue.quarter,
      1 => NoteValue.eighth,
      2 => NoteValue.sixteenth,
      3 => NoteValue.thirtySecond,
      4 => NoteValue.sixtyFourth,
      5 => NoteValue.hundredTwentyEighth,
      _ => NoteValue.quarter,
    };
    Tuplet? tuplet;
    if ((flags & 0x20) != 0) {
      final n = r.i32();
      tuplet = switch (n) {
        3 => const Tuplet(3, 2),
        5 => const Tuplet(5, 4),
        6 => const Tuplet(6, 4),
        7 => const Tuplet(7, 4),
        9 => const Tuplet(9, 8),
        10 => const Tuplet(10, 8),
        11 => const Tuplet(11, 8),
        12 => const Tuplet(12, 8),
        13 => const Tuplet(13, 8),
        _ => null,
      };
    }
    final beat = _Beat(NoteDuration(value, dots: (flags & 0x01) != 0 ? 1 : 0, tuplet: tuplet));
    beat.rest = status == 2;
    if ((flags & 0x02) != 0) beat.chord = _chord(t);
    if ((flags & 0x04) != 0) beat.text = r.intByteSizeString();
    var harmonic = false;
    if ((flags & 0x08) != 0) harmonic = _beatEffects(beat);
    if ((flags & 0x10) != 0) beat.tempo = _mixTable();
    final stringFlags = r.u8();
    final n = t.tuningHighFirst.length;
    for (var s = 1; s <= n; s++) {
      if ((stringFlags & (1 << (7 - s))) != 0) {
        final note = _note(t, n - s);
        if (harmonic) note.harmonic = true;
        beat.notes.add(note);
      }
    }
    if (_gp5) {
      final f2 = r.i16();
      if ((f2 & 0x0800) != 0) r.u8();
    }
    if (status == 0) return null; // leerer Schlag (nimmt keine Zeit)
    if (beat.rest) beat.notes.clear();
    beat.key = key;
    return beat;
  }

  String? _chord(_Track t) {
    final newFormat = r.boolean();
    if (!newFormat) {
      final name = r.intByteSizeString();
      final firstFret = r.i32();
      if (firstFret != 0) {
        for (var i = 0; i < 6; i++) {
          r.i32();
        }
      }
      return name;
    }
    if (_gp3) {
      r.boolean();
      r.skip(3);
      r.i32();
      r.i32();
      r.i32();
      r.i32();
      r.i32();
      r.boolean();
      final name = r.byteSizeString(22);
      r.i32();
      r.i32();
      r.i32();
      r.i32(); // erster Bund
      for (var i = 0; i < 6; i++) {
        r.i32();
      }
      r.i32();
      r.skip(4 * 6);
      r.skip(7);
      r.skip(1);
      return name;
    }
    r.boolean();
    r.skip(3);
    r.u8();
    r.u8();
    r.u8();
    r.i32();
    r.i32();
    r.boolean();
    final name = r.byteSizeString(22);
    r.u8();
    r.u8();
    r.u8();
    r.i32(); // erster Bund
    for (var i = 0; i < 7; i++) {
      r.i32();
    }
    r.u8();
    r.skip(15);
    r.skip(7);
    r.skip(1);
    r.skip(7);
    r.boolean();
    return name;
  }

  /// Schlag-Effekte; gibt zurück, ob alle Noten Flageolett sind (GP3).
  bool _beatEffects(_Beat beat) {
    if (_gp3) {
      final f1 = r.u8();
      if ((f1 & 0x20) != 0) {
        r.u8();
        r.i32();
      }
      if ((f1 & 0x40) != 0) {
        final down = r.i8(), up = r.i8();
        beat.stroke = up > 0 ? -1 : (down > 0 ? 1 : 0);
      }
      return (f1 & 0x0C) != 0;
    }
    final f1 = r.i8();
    final f2 = r.i8();
    if ((f1 & 0x20) != 0) r.i8();
    if ((f2 & 0x04) != 0) _bend();
    if ((f1 & 0x40) != 0) {
      final down = r.i8(), up = r.i8();
      // In GP5 sind die Richtungen vertauscht gespeichert.
      final d = up > 0 ? -1 : (down > 0 ? 1 : 0);
      beat.stroke = _gp5 ? -d : d;
    }
    if ((f2 & 0x02) != 0) {
      final dir = r.i8();
      if (dir == 1) beat.stroke = -1;
      if (dir == 2) beat.stroke = 1;
    }
    return false;
  }

  /// Mischpult-Änderung; gibt ein neues Tempo zurück (oder null).
  int? _mixTable() {
    r.i8(); // Instrument
    if (_gp5) {
      r.i32();
      r.i32();
      r.i32();
      if (_v500) {
        r.i16();
        r.skip(1);
      } else {
        r.i32();
      }
      if (_v500) r.skip(1);
    }
    final values = [r.i8(), r.i8(), r.i8(), r.i8(), r.i8(), r.i8()];
    if (_gp5) r.intByteSizeString();
    final tempo = r.i32();
    for (final v in values) {
      if (v >= 0) r.i8();
    }
    if (tempo >= 0) {
      r.i8();
      if (_gp5 && _minor > 0) r.boolean();
    }
    if (!_gp3) r.i8(); // für alle Spuren
    if (_gp5) {
      r.i8(); // Wah
      if (_minor > 0) {
        r.intByteSizeString();
        r.intByteSizeString();
      }
    }
    return tempo >= 0 ? tempo : null;
  }

  _Note _note(_Track t, int string) {
    final flags = r.u8();
    final n = _Note(string);
    n.ghost = (flags & 0x04) != 0;
    if ((flags & 0x40) != 0) n.accent |= 8;
    if (_gp5 && (flags & 0x02) != 0) n.accent |= 4;
    if ((flags & 0x20) != 0) {
      final type = r.u8();
      n.tie = type == 2;
      n.dead = type == 3;
    }
    if (!_gp5 && (flags & 0x01) != 0) {
      r.i8();
      r.i8();
    }
    if ((flags & 0x10) != 0) r.i8(); // Lautstärke
    if ((flags & 0x20) != 0) n.fret = r.i8();
    if ((flags & 0x80) != 0) {
      r.i8();
      r.i8();
    }
    if (_gp5) {
      if ((flags & 0x01) != 0) r.f64();
      r.u8();
    }
    if ((flags & 0x08) != 0) _noteEffects(n);
    return n;
  }

  void _noteEffects(_Note n) {
    if (_gp3) {
      final f = r.u8();
      n.hammer = (f & 0x02) != 0;
      n.letRing = (f & 0x08) != 0;
      if ((f & 0x01) != 0) n.bend = _bend();
      if ((f & 0x10) != 0) r.skip(4); // Vorschlag
      if ((f & 0x04) != 0) n.slide = 1;
      return;
    }
    final f1 = r.i8();
    final f2 = r.i8();
    n.hammer = (f1 & 0x02) != 0;
    n.letRing = (f1 & 0x08) != 0;
    if ((f2 & 0x01) != 0) n.accent |= 1;
    n.palmMute = (f2 & 0x02) != 0;
    n.vibrato = (f2 & 0x40) != 0;
    if ((f1 & 0x01) != 0) n.bend = _bend();
    if ((f1 & 0x10) != 0) r.skip(_gp5 ? 5 : 4); // Vorschlag
    if ((f2 & 0x04) != 0) r.i8(); // Tremolo-Picking
    if ((f2 & 0x08) != 0) {
      if (_gp5) {
        n.slide = r.u8();
      } else {
        n.slide = switch (r.i8()) {
          1 => 1,
          2 => 2,
          3 => 4,
          4 => 8,
          -1 => 16,
          -2 => 32,
          _ => 0,
        };
      }
    }
    if ((f2 & 0x10) != 0) {
      final type = r.i8();
      n.harmonic = true;
      if (_gp5) {
        if (type == 2) {
          r.u8();
          r.i8();
          r.u8();
        } else if (type == 3) {
          r.u8();
        }
      }
    }
    if ((f2 & 0x20) != 0) {
      r.i8();
      r.i8();
    }
  }

  Bend? _bend() {
    r.i8(); // Art
    r.i32(); // Höhe
    final count = r.i32();
    if (count < 0 || count > 100) throw const ScoreFileException(ScoreFileProblem.damaged, 'Bend');
    final pts = <BendPoint>[];
    for (var i = 0; i < count; i++) {
      final pos = r.i32();
      final value = r.i32();
      r.boolean();
      // Stelle 0..60, Höhe 100 = ein Ganzton
      pts.add(BendPoint(pos / 60, value / 50));
    }
    return pts.isEmpty ? null : Bend(pts);
  }

  void _applyLyrics(List<_Track> tracks) {
    if (_lyricsText.trim().isEmpty || tracks.isEmpty) return;
    final ti = (_lyricsTrack >= 1 && _lyricsTrack <= tracks.length) ? _lyricsTrack - 1 : 0;
    final t = tracks[ti];
    for (var line = 0; line < _lyrics.length; line++) {
      final (start, text) = _lyrics[line];
      if (text.trim().isEmpty) continue;
      // Silben: Leerzeichen trennen Wörter, Bindestriche Silben
      final syllables = <String>[];
      for (final word in text.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final parts = word.split('-');
        for (var k = 0; k < parts.length; k++) {
          if (parts[k].isEmpty) continue;
          syllables.add(k < parts.length - 1 ? '${parts[k]}-' : parts[k]);
        }
      }
      var si = 0;
      for (var bi = (start - 1).clamp(0, t.bars.length); bi < t.bars.length && si < syllables.length; bi++) {
        if (t.bars[bi].isEmpty) continue;
        for (final b in t.bars[bi].first) {
          if (si >= syllables.length) break;
          if (b.rest || b.notes.isEmpty || b.notes.every((n) => n.tie)) continue;
          while (b.lyrics.length <= line) {
            b.lyrics.add('');
          }
          b.lyrics[line] = syllables[si++];
        }
      }
    }
  }
}

class _Header {
  int num = 4;
  int den = 4;
  bool repeatOpen = false;
  int repeatClose = -1;
  int endings = 0;
  String? marker;
  int key = 0;
  bool minor = false;
  bool doubleBar = false;
}

class _Note {
  _Note(this.string);
  final int string;
  int fret = 0;
  bool tie = false;
  bool dead = false;
  bool ghost = false;
  int accent = 0;
  bool hammer = false;
  bool letRing = false;
  bool palmMute = false;
  bool vibrato = false;
  bool harmonic = false;
  int slide = 0;
  Bend? bend;
  bool tieOrigin = false;
}

class _Beat {
  _Beat(this.duration);
  final NoteDuration duration;
  final notes = <_Note>[];
  final lyrics = <String>[];
  bool rest = false;
  String? chord;
  String? text;
  int? tempo;
  int stroke = 0;
  int key = 0;
}

class _Track {
  String name = '';
  bool percussion = false;
  List<int> tuningHighFirst = const [];
  int fretCount = 24;
  int capo = 0;
  bool showTab = true;
  bool showNotation = true;

  /// Pro Takt: Stimmen mit Schlägen.
  final bars = <List<List<_Beat>>>[];

  Track build(List<_Header> headers) {
    final tuning = tuningHighFirst.reversed.toList();
    final stringed = !percussion && tuning.isNotEmpty;
    final lowest = tuning.isEmpty ? 40 : tuning.reduce((a, b) => a < b ? a : b);
    final bass = stringed && lowest < 36;
    final transpose = stringed ? 12 : 0;
    final clef = percussion ? Clef.neutral : (bass ? Clef.bass : (stringed ? Clef.treble8vb : Clef.treble));

    // Haltebögen: Vorgänger auf derselben Saite (in derselben Stimme) bekommt den Anfang.
    final voiceCount = bars.fold(0, (m, b) => b.length > m ? b.length : m);
    for (var v = 0; v < voiceCount; v++) {
      final last = <int, _Note>{};
      for (final bar in bars) {
        if (v >= bar.length) continue;
        for (final b in bar[v]) {
          for (final n in b.notes) {
            if (n.tie) {
              final prev = last[n.string];
              if (prev != null) {
                n.fret = prev.fret;
                prev.tieOrigin = true;
              }
            }
            last[n.string] = n;
          }
        }
      }
    }

    final chords = <int, ChordDef>{};
    final chordIds = <String, int>{};
    final out = <Bar>[];
    for (var i = 0; i < bars.length; i++) {
      final voices = <Voice>[];
      for (final v in bars[i]) {
        if (v.isEmpty) continue;
        final beats = <Beat>[];
        for (final b in v) {
          int? chordId;
          final name = b.chord?.trim();
          if (name != null && name.isNotEmpty) {
            chordId = chordIds.putIfAbsent(name, () {
              final id = chordIds.length;
              chords[id] = ChordDef(name: name);
              return id;
            });
          }
          final notes = <Note>[];
          for (final n in b.notes) {
            final midi = stringed && n.string < tuning.length ? tuning[n.string] + capo + n.fret : n.fret;
            final pitch = Pitch.fromMidi(midi, fifths: b.key);
            notes.add(
              Note(
                pitch: pitch,
                written: transpose == 0 ? null : pitch.octaves(transpose ~/ 12),
                string: stringed ? n.string : null,
                fret: stringed ? n.fret : null,
                tieOrigin: n.tieOrigin,
                tieDestination: n.tie,
                palmMuted: n.palmMute,
                dead: n.dead,
                ghost: n.ghost,
                letRing: n.letRing,
                slide: n.slide,
                hammerOrigin: n.hammer,
                bend: n.bend,
                accent: n.accent,
                vibrato: n.vibrato,
                harmonic: n.harmonic,
              ),
            );
          }
          beats.add(
            Beat(
              duration: b.duration,
              notes: notes,
              chordId: chordId,
              text: (b.text?.trim().isEmpty ?? true) ? null : b.text!.trim(),
              lyrics: b.lyrics,
              pickStroke: b.stroke,
            ),
          );
        }
        voices.add(Voice(beats));
      }
      out.add(Bar(clef: clef, voices: voices));
    }
    // Hälse gleich verteilt? Nicht bekannt: keine Zeilenvorgabe.
    return Track(
      name: name,
      staff: StaffDef(
        tuning: stringed ? tuning : const [],
        capo: capo,
        fretCount: fretCount,
        showNotation: showNotation,
        showTab: showTab,
      ),
      bars: out,
      chords: chords,
      transposeSemitones: transpose,
    );
  }
}
