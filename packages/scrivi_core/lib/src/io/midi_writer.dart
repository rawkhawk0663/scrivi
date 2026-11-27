import 'dart:convert';
import 'dart:typed_data';

import '../model/score.dart';
import '../playback/plan.dart';

/// Schreibt ein Stück als Standard-MIDI-Datei (Typ 1), so wie es gespielt wird:
/// Wiederholungen und Sprünge ausgeschrieben, mit Tempo, Taktart, Tonart,
/// Klang pro Spur und Saitenziehen (Pitch-Bend). Schlagzeug auf Kanal 10.
class MidiWriter {
  MidiWriter._();

  /// Ticks pro Viertel.
  static const division = 480;

  static Uint8List write(Score score) {
    final plan = PlaybackPlan.build(score);
    final barTick = <int>[];
    var tick = 0;
    for (final pb in plan.bars) {
      barTick.add(tick);
      tick += (pb.length * 4 * division).round();
    }
    final endTick = tick;

    /// Sekunden → Tick (über die Lage im gespielten Takt, Swing wieder gerade).
    int toTick(double seconds) {
      if (plan.bars.isEmpty) return 0;
      final i = plan.barAt(seconds);
      final pb = plan.bars[i];
      final pos = pb.positionAt(seconds - pb.start);
      return barTick[i] + (pos * 4 * division).round();
    }

    final chunks = <Uint8List>[];
    // Spur 0: Titel, Tempo, Taktart, Tonart
    final conductor = _Events();
    conductor.meta(0, 0x03, utf8.encode(score.info.title.isEmpty ? 'Scrivi' : score.info.title));
    if (score.info.copyright.isNotEmpty) conductor.meta(0, 0x02, utf8.encode(score.info.copyright));
    TimeSignature? time;
    KeySignature? key;
    int? usPrev;
    for (var i = 0; i < plan.bars.length; i++) {
      final pb = plan.bars[i];
      final mb = score.masterBars[pb.bar];
      if (mb.time != time) {
        time = mb.time;
        final denom = switch (time.beatType) {
          1 => 0,
          2 => 1,
          4 => 2,
          8 => 3,
          16 => 4,
          32 => 5,
          _ => 2,
        };
        conductor.meta(barTick[i], 0x58, [time.beats, denom, 24, 8]);
      }
      if (mb.key != key) {
        key = mb.key;
        conductor.meta(barTick[i], 0x59, [key.fifths & 0xFF, key.minor ? 1 : 0]);
      }
      for (final (at, spw) in pb.segments) {
        final us = (spw / 4 * 1e6).round();
        if (us == usPrev) continue;
        usPrev = us;
        conductor.meta(barTick[i] + (at * 4 * division).round(), 0x51, [us >> 16 & 0xFF, us >> 8 & 0xFF, us & 0xFF]);
      }
    }
    conductor.meta(endTick, 0x2F, const []);
    chunks.add(conductor.chunk());

    var next = 0;
    for (final pt in plan.tracks) {
      final t = pt.track;
      final int ch;
      if (t.percussion) {
        ch = 9;
      } else {
        ch = next;
        next = (next + 1) % 16;
        if (next == 9) next = 10;
      }
      final ev = _Events();
      ev.meta(0, 0x03, utf8.encode(t.name.isEmpty ? 'Spur ${pt.index + 1}' : t.name));
      if (!t.percussion) {
        ev.add(0, [0xC0 | ch, t.program.clamp(0, 127)]);
        // Pitch-Bend-Bereich ±12 Halbtöne (für weites Saitenziehen)
        ev.add(0, [0xB0 | ch, 101, 0]);
        ev.add(0, [0xB0 | ch, 100, 0]);
        ev.add(0, [0xB0 | ch, 6, 12]);
        ev.add(0, [0xB0 | ch, 38, 0]);
      }
      for (final n in pt.notes) {
        if (n.midi < 0 || n.midi > 127) continue;
        final a = toTick(n.start);
        // Was eine Fermate über das Stückende hinaus verlängert, endet am Schluss
        if (a >= endTick) continue;
        final b = toTick(n.end).clamp(a + 1, endTick);
        final vel = (n.velocity * 127).round().clamp(1, 127);
        if (n.bend.isNotEmpty && !t.percussion) {
          for (final (f, semis) in n.bend) {
            final at = a + ((b - a) * f).round();
            final v = (8192 + semis / 12 * 8191).round().clamp(0, 16383);
            ev.add(at, [0xE0 | ch, v & 0x7F, v >> 7]);
          }
        }
        ev.add(a, [0x90 | ch, n.midi, vel]);
        ev.add(b, [0x80 | ch, n.midi, 0]);
        if (n.bend.isNotEmpty && !t.percussion) ev.add(b, [0xE0 | ch, 0, 64]);
      }
      ev.meta(endTick, 0x2F, const []);
      chunks.add(ev.chunk());
    }

    final out = BytesBuilder();
    out.add(ascii.encode('MThd'));
    out.add(_be32(6));
    out.add([0, 1, chunks.length >> 8, chunks.length & 0xFF, division >> 8, division & 0xFF]);
    for (final c in chunks) {
      out.add(c);
    }
    return out.toBytes();
  }

  static List<int> _be32(int v) => [v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF];
}

/// Ereignisse einer Spur, beim Schreiben nach Zeit geordnet.
class _Events {
  final _list = <(int tick, int order, List<int> data)>[];

  void add(int tick, List<int> data) => _list.add((tick, _list.length, data));

  void meta(int tick, int type, List<int> data) => add(tick, [0xFF, type, ..._vlq(data.length), ...data]);

  Uint8List chunk() {
    // Bei gleicher Zeit: Note aus vor Note an (sonst verschluckt sich ein
    // wiederholter Ton), Spur-Ende zuletzt.
    int rank((int, int, List<int>) e) {
      final d = e.$3;
      if (d[0] == 0xFF && d[1] == 0x2F) return 3;
      final kind = d[0] & 0xF0;
      if (kind == 0x80) return 0;
      if (kind == 0x90) return 2;
      return 1;
    }

    _list.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      if (c != 0) return c;
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.$2.compareTo(b.$2);
    });
    final body = BytesBuilder();
    var last = 0;
    for (final (tick, _, data) in _list) {
      body.add(_vlq(tick - last));
      body.add(data);
      last = tick;
    }
    final bytes = body.toBytes();
    return Uint8List.fromList([...ascii.encode('MTrk'), ...MidiWriter._be32(bytes.length), ...bytes]);
  }

  static List<int> _vlq(int v) {
    final out = <int>[v & 0x7F];
    v >>= 7;
    while (v > 0) {
      out.insert(0, (v & 0x7F) | 0x80);
      v >>= 7;
    }
    return out;
  }
}
