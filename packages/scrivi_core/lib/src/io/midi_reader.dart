import 'dart:typed_data';

import '../model/pitch.dart';
import '../model/score.dart';
import 'binary.dart';
import 'gp_reader.dart';

/// Liest Standard-MIDI-Dateien (`.mid`). MIDI kennt nur Zeitpunkte, keine
/// Notenwerte: Die Töne werden auf Sechzehntel eingerastet, in Takte geteilt
/// und über Taktstriche mit Haltebögen verbunden.
class MidiReader {
  MidiReader._();

  static bool looksLike(Uint8List b) => b.length >= 14 && b[0] == 0x4D && b[1] == 0x54 && b[2] == 0x68 && b[3] == 0x64;

  static Score read(Uint8List bytes, {String title = ''}) {
    try {
      return _Midi(bytes).parse(title);
    } on ScoreFileException {
      rethrow;
    } catch (e) {
      throw ScoreFileException(ScoreFileProblem.damaged, 'MIDI: $e');
    }
  }
}

class _MNote {
  _MNote(this.channel, this.key, this.start);
  final int channel;
  final int key;
  final int start;
  int end = -1;
}

class _MTrack {
  String name = '';
  int program = -1;
  final notes = <_MNote>[];
}

class _Midi {
  _Midi(this.bytes);
  final Uint8List bytes;
  int division = 480;
  final tempos = <(int, double)>[]; // Tick, Viertel pro Minute
  final times = <(int, int, int)>[]; // Tick, Zähler, Nenner
  final keys = <(int, int, bool)>[]; // Tick, Vorzeichen, Moll
  String title = '';

  int _be16(int at) => (bytes[at] << 8) | bytes[at + 1];
  int _be32(int at) => (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3];

  Score parse(String fallbackTitle) {
    final headerLen = _be32(4);
    final trackCount = _be16(10);
    final div = _be16(12);
    if (div & 0x8000 != 0) {
      division = 480; // SMPTE-Zeit: selten, wie Viertel behandeln
    } else if (div > 0) {
      division = div;
    }
    var pos = 8 + headerLen;
    final tracks = <_MTrack>[];
    for (var t = 0; t < trackCount && pos + 8 <= bytes.length; t++) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final len = _be32(pos + 4);
      final start = pos + 8;
      final end = (start + len).clamp(0, bytes.length);
      if (id == 'MTrk') tracks.addAll(_track(start, end, t == 0));
      pos = start + len;
    }
    return _build(tracks, title.isNotEmpty ? title : fallbackTitle);
  }

  /// Eine Spur lesen; Noten verschiedener Kanäle werden getrennte Spuren.
  List<_MTrack> _track(int start, int end, bool first) {
    final byChannel = <int, _MTrack>{};
    var name = '';
    final programs = <int, int>{};
    var pos = start;
    var tick = 0;
    var status = 0;
    final open = <int, List<_MNote>>{};
    int vlq() {
      var v = 0;
      for (var i = 0; i < 4 && pos < end; i++) {
        final b = bytes[pos++];
        v = (v << 7) | (b & 0x7F);
        if (b & 0x80 == 0) break;
      }
      return v;
    }

    while (pos < end) {
      tick += vlq();
      if (pos >= end) break;
      var b = bytes[pos];
      if (b & 0x80 != 0) {
        status = b;
        pos++;
      }
      if (status == 0xFF) {
        final type = bytes[pos++];
        final len = vlq();
        final data = bytes.sublist(pos, (pos + len).clamp(0, end));
        pos += len;
        switch (type) {
          case 0x03:
            name = decodeCp1252(data);
            if (first && title.isEmpty) title = name;
          case 0x51 when data.length >= 3:
            final us = (data[0] << 16) | (data[1] << 8) | data[2];
            if (us > 0) tempos.add((tick, 60000000 / us));
          case 0x58 when data.length >= 2:
            times.add((tick, data[0], 1 << data[1]));
          case 0x59 when data.length >= 2:
            final sf = data[0] > 127 ? data[0] - 256 : data[0];
            keys.add((tick, sf.clamp(-7, 7), data[1] == 1));
        }
        continue;
      }
      if (status == 0xF0 || status == 0xF7) {
        final len = vlq();
        pos += len;
        continue;
      }
      final kind = status & 0xF0;
      final ch = status & 0x0F;
      int data1() => pos < end ? bytes[pos++] : 0;
      switch (kind) {
        case 0x80 || 0x90:
          final key = data1();
          final vel = data1();
          final list = open[ch * 128 + key] ??= [];
          if (kind == 0x90 && vel > 0) {
            final n = _MNote(ch, key, tick);
            list.add(n);
            (byChannel[ch] ??= _MTrack()).notes.add(n);
          } else if (list.isNotEmpty) {
            list.removeAt(0).end = tick;
          }
        case 0xA0 || 0xB0 || 0xE0:
          data1();
          data1();
        case 0xC0:
          programs[ch] = data1();
        case 0xD0:
          data1();
        default:
          pos++;
      }
    }
    for (final list in open.values) {
      for (final n in list) {
        if (n.end < 0) n.end = tick;
      }
    }
    final out = <_MTrack>[];
    for (final e in byChannel.entries) {
      final t = e.value
        ..name = byChannel.length > 1 ? '$name (${e.key + 1})' : name
        ..program = e.key == 9 ? -2 : (programs[e.key] ?? 0);
      out.add(t);
    }
    return out;
  }

  Score _build(List<_MTrack> tracks, String title) {
    tracks.removeWhere((t) => t.notes.isEmpty);
    final grid = (division / 4).round().clamp(1, 1 << 20); // Sechzehntel
    int q(int tick) => ((tick / grid).round()) * grid;
    var lastTick = 0;
    for (final t in tracks) {
      for (final n in t.notes) {
        if (n.end > lastTick) lastTick = n.end;
      }
    }
    times.sort((a, b) => a.$1.compareTo(b.$1));
    keys.sort((a, b) => a.$1.compareTo(b.$1));
    tempos.sort((a, b) => a.$1.compareTo(b.$1));
    // Takte aus den Taktarten
    final barStarts = <int>[];
    final barTimes = <TimeSignature>[];
    var tick = 0;
    var ts = const TimeSignature(4, 4);
    var ti = 0;
    while (tick <= lastTick || barStarts.isEmpty) {
      while (ti < times.length && times[ti].$1 <= tick) {
        ts = TimeSignature(times[ti].$2, times[ti].$3);
        ti++;
      }
      barStarts.add(tick);
      barTimes.add(ts);
      tick += (division * 4 * ts.beats / ts.beatType).round();
      if (barStarts.length > 5000) break;
    }
    if (barStarts.length > 1 && barStarts.last >= lastTick && lastTick > 0) {
      barStarts.removeLast();
      barTimes.removeLast();
    }
    KeySignature keyAt(int tick) {
      var k = const KeySignature(0);
      for (final e in keys) {
        if (e.$1 <= tick) k = KeySignature(e.$2, minor: e.$3);
      }
      return k;
    }

    final masterBars = [
      for (var i = 0; i < barStarts.length; i++) MasterBar(time: barTimes[i], key: keyAt(barStarts[i])),
    ];
    final tempoMarks = <TempoMark>[];
    for (final (t, bpm) in tempos) {
      var bar = 0;
      for (var i = 0; i < barStarts.length; i++) {
        if (barStarts[i] <= t) bar = i;
      }
      final mark = TempoMark(bar: bar, bpm: bpm.roundToDouble());
      if (tempoMarks.isNotEmpty && tempoMarks.last.bar == bar) {
        tempoMarks[tempoMarks.length - 1] = mark;
      } else if (tempoMarks.isEmpty || tempoMarks.last.bpm != mark.bpm) {
        tempoMarks.add(mark);
      }
    }

    final out = <Track>[];
    for (final t in tracks) {
      final drums = t.program == -2;
      final guitar = !drums && t.program >= 24 && t.program <= 31;
      final bass = !drums && t.program >= 32 && t.program <= 39;
      final tuning = guitar ? const [40, 45, 50, 55, 59, 64] : (bass ? const [28, 33, 38, 43] : const <int>[]);
      final avg = t.notes.fold(0, (s, n) => s + n.key) / t.notes.length;
      final clef = drums
          ? Clef.neutral
          : (bass || (!guitar && avg < 57) ? Clef.bass : (guitar ? Clef.treble8vb : Clef.treble));
      final transpose = (guitar || bass) ? 12 : 0;

      // Einrasten, dann pro Einsatz ein Akkord
      final byStart = <int, List<_MNote>>{};
      for (final n in t.notes) {
        byStart.putIfAbsent(q(n.start), () => []).add(n);
      }
      final onsets = byStart.keys.toList()..sort();
      // Ereignisse: (Start, Ende, Tonhöhen)
      final evs = <(int, int, List<int>)>[];
      for (var i = 0; i < onsets.length; i++) {
        final s = onsets[i];
        final notes = byStart[s]!;
        var e = notes.map((n) => q(n.end)).reduce((a, b) => a > b ? a : b);
        if (e <= s) e = s + grid;
        if (i + 1 < onsets.length && e > onsets[i + 1]) e = onsets[i + 1];
        evs.add((s, e, (notes.map((n) => n.key).toSet().toList()..sort())));
      }

      final bars = <Bar>[];
      var ei = 0;
      List<int>? carry; // über den Taktstrich gehaltene Töne
      var carryEnd = 0;
      for (var b = 0; b < barStarts.length; b++) {
        final bs = barStarts[b];
        final be = b + 1 < barStarts.length
            ? barStarts[b + 1]
            : bs + (division * 4 * barTimes[b].beats / barTimes[b].beatType).round();
        final key = masterBars[b].key;
        final beats = <Beat>[];
        var cursor = bs;
        void addSpan(int from, int to, List<int>? keysList, {bool tieIn = false, bool tieOut = false}) {
          final parts = _split(to - from, from - bs, grid);
          for (var k = 0; k < parts.length; k++) {
            final d = parts[k];
            final notes = <Note>[];
            if (keysList != null) {
              for (final m in keysList) {
                final p = Pitch.fromMidi(m, fifths: key.fifths);
                int? string, fret;
                if (tuning.isNotEmpty) {
                  for (var si = tuning.length - 1; si >= 0; si--) {
                    final f = m - tuning[si];
                    if (f >= 0 && f <= 12) {
                      string = si;
                      fret = f;
                    }
                  }
                }
                notes.add(
                  Note(
                    pitch: p,
                    written: transpose == 0 ? null : p.octaves(1),
                    string: string,
                    fret: fret,
                    tieDestination: (k > 0) || tieIn,
                    tieOrigin: (k < parts.length - 1) || tieOut,
                  ),
                );
              }
            }
            beats.add(Beat(duration: d, notes: notes));
          }
        }

        if (carry != null) {
          final until = carryEnd < be ? carryEnd : be;
          addSpan(bs, until, carry, tieIn: true, tieOut: carryEnd > be);
          cursor = until;
          if (carryEnd <= be) carry = null;
        }
        while (ei < evs.length && evs[ei].$1 < be) {
          final (s, e, ks) = evs[ei];
          if (s < cursor) {
            ei++;
            continue;
          }
          if (s > cursor) addSpan(cursor, s, null);
          final until = e < be ? e : be;
          addSpan(s, until, ks, tieOut: e > be);
          cursor = until;
          if (e > be) {
            carry = ks;
            carryEnd = e;
          }
          ei++;
        }
        if (cursor < be && carry == null) addSpan(cursor, be, null);
        final allRest = beats.every((x) => x.isRest);
        bars.add(Bar(clef: clef, voices: allRest ? [] : [Voice(beats)]));
      }
      out.add(
        Track(
          name: t.name,
          staff: StaffDef(tuning: tuning),
          bars: bars,
          transposeSemitones: transpose,
        ),
      );
    }
    if (tempoMarks.isEmpty) tempoMarks.add(const TempoMark(bar: 0, bpm: 120, visible: false));
    return Score(
      info: ScoreInfo(title: title),
      masterBars: masterBars,
      tracks: out,
      tempos: tempoMarks,
    );
  }

  /// Eine Länge (in Ticks) ab [offset] im Takt in schreibbare Notenwerte teilen.
  List<NoteDuration> _split(int ticks, int offset, int grid) {
    final out = <NoteDuration>[];
    var rest = ticks;
    var at = offset;
    final quarter = division;
    final values = <(int, NoteDuration)>[
      (quarter * 4, const NoteDuration(NoteValue.whole)),
      (quarter * 3, const NoteDuration(NoteValue.half, dots: 1)),
      (quarter * 2, const NoteDuration(NoteValue.half)),
      (quarter * 3 ~/ 2, const NoteDuration(NoteValue.quarter, dots: 1)),
      (quarter, const NoteDuration(NoteValue.quarter)),
      (quarter * 3 ~/ 4, const NoteDuration(NoteValue.eighth, dots: 1)),
      (quarter ~/ 2, const NoteDuration(NoteValue.eighth)),
      (quarter ~/ 4, const NoteDuration(NoteValue.sixteenth)),
    ];
    while (rest >= grid ~/ 2 && rest > 0) {
      var placed = false;
      for (final (len, d) in values) {
        if (len <= 0 || len > rest) continue;
        // Werte nur auf passenden Zählzeiten beginnen (lange auf ganzen Schlägen)
        final base = d.dots > 0 ? len * 2 ~/ 3 : len;
        final step = len > quarter ? quarter : base;
        if (step > 0 && at % step != 0) continue;
        out.add(d);
        rest -= len;
        at += len;
        placed = true;
        break;
      }
      if (!placed) {
        out.add(const NoteDuration(NoteValue.sixteenth));
        rest -= quarter ~/ 4;
        at += quarter ~/ 4;
      }
    }
    if (out.isEmpty) out.add(const NoteDuration(NoteValue.sixteenth));
    return out;
  }
}
