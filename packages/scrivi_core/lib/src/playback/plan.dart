import 'dart:math' as math;

import '../model/score.dart';

/// Ein gespielter Takt in der Abspiel-Reihenfolge.
class PlayBar {
  PlayBar(this.bar, this.start, this.length, this.segments, {this.swing = false});

  /// Nummer des Takts in der Partitur (0 = erster).
  final int bar;

  /// Beginn in Sekunden ab dem Anfang des Stücks.
  final double start;

  /// Länge des Takts in ganzen Noten.
  final double length;

  /// Tempo im Takt: ab Stelle (ganze Noten) so viele Sekunden pro ganze Note.
  final List<(double at, double secondsPerWhole)> segments;

  /// Achtel geswingt: die erste Achtel jedes Viertels lang (2/3), die zweite kurz (1/3).
  final bool swing;

  /// Notierte Stelle → gespielte Stelle (ganze Noten), bei Swing verschoben.
  double _swung(double pos) {
    if (!swing) return pos;
    final q = pos * 4;
    final k = q.floorToDouble();
    final f = q - k;
    final g = f <= 0.5 ? f * 4 / 3 : 2 / 3 + (f - 0.5) * 2 / 3;
    return (k + g) / 4;
  }

  /// Gespielte Stelle → notierte Stelle (Umkehrung von [_swung]).
  double _straight(double pos) {
    if (!swing) return pos;
    final q = pos * 4;
    final k = q.floorToDouble();
    final g = q - k;
    final f = g <= 2 / 3 ? g * 3 / 4 : 0.5 + (g - 2 / 3) * 1.5;
    return (k + f) / 4;
  }

  /// Dauer in Sekunden.
  double get duration => secondsAt(length);

  double get end => start + duration;

  /// Sekunden vom Taktanfang bis zur Stelle [pos] (ganze Noten).
  double secondsAt(double notated) {
    final pos = _swung(notated);
    var t = 0.0;
    for (var i = 0; i < segments.length; i++) {
      final (a, spw) = segments[i];
      final b = i + 1 < segments.length ? segments[i + 1].$1 : double.infinity;
      if (pos <= a) break;
      t += (math.min(pos, b) - a) * spw;
    }
    return t;
  }

  /// Stelle im Takt (ganze Noten) zur Zeit [seconds] ab Taktanfang.
  double positionAt(double seconds) {
    var t = 0.0;
    for (var i = 0; i < segments.length; i++) {
      final (a, spw) = segments[i];
      final b = i + 1 < segments.length ? segments[i + 1].$1 : length;
      final dt = (b - a) * spw;
      if (seconds <= t + dt || i == segments.length - 1) {
        return _straight(math.min(length, a + (seconds - t) / spw));
      }
      t += dt;
    }
    return 0;
  }

  /// Sekunden pro Schlag (Viertel) am Taktanfang.
  double get secondsPerQuarter => segments.first.$2 / 4;
}

/// Ein Ton, wie er gespielt wird.
class PlayNote {
  PlayNote({
    required this.start,
    required this.duration,
    required this.midi,
    this.velocity = 0.8,
    this.string,
    this.bend = const [],
    this.slideTo,
    this.vibrato = false,
    this.palmMuted = false,
    this.dead = false,
    this.harmonic = false,
    this.legato = false,
    this.slideIn = 0,
    this.slideOut = 0,
    this.wideVibrato = false,
    this.fade = 0,
  });

  /// Derselbe Ton zu einer anderen Zeit (zum Rechnen in einem eigenen Puffer).
  PlayNote at(double start) => PlayNote(
    start: start,
    duration: duration,
    midi: midi,
    velocity: velocity,
    string: string,
    bend: bend,
    slideTo: slideTo,
    vibrato: vibrato,
    palmMuted: palmMuted,
    dead: dead,
    harmonic: harmonic,
    legato: legato,
    slideIn: slideIn,
    slideOut: slideOut,
    wideVibrato: wideVibrato,
    fade: fade,
  );

  /// Hineingleiten: −1 von unten, 1 von oben; hinausgleiten: −1 nach unten, 1 nach oben.
  final int slideIn;
  final int slideOut;
  final bool wideVibrato;

  /// Lautstärke im Ton: 1 einblenden, 2 ausblenden, 3 an- und abschwellen.
  final int fade;

  /// Beginn und Dauer in Sekunden.
  final double start;
  double duration;

  /// Klingende Tonhöhe (MIDI).
  final int midi;

  /// Lautstärke 0..1.
  double velocity;

  /// Saite (0 = tiefste) bei Saiteninstrumenten.
  final int? string;

  /// Saitenziehen: (Anteil der Dauer 0..1, Halbtöne).
  List<(double, double)> bend;

  /// Gleiten zum nächsten Ton (MIDI) gegen Ende des Tons.
  int? slideTo;
  final bool vibrato;
  final bool palmMuted;
  final bool dead;
  final bool harmonic;

  /// Gebunden (Hammer-on, Pull-off, Slide): ohne neuen Anschlag.
  final bool legato;

  double get end => start + duration;
}

/// Spur mit ihren Tönen.
class PlayTrack {
  PlayTrack(this.index, this.track, this.notes);
  final int index;
  final Track track;
  final List<PlayNote> notes;
}

/// Metronom-Schlag.
class Click {
  const Click(this.time, {this.accent = false});
  final double time;
  final bool accent;
}

/// Was gespielt wird: Takte in Abspiel-Reihenfolge, Töne pro Spur, Metronom.
///
/// Wiederholungen, Häuser, D.C./D.S., Coda und Fine werden aufgelöst.
/// Nach einem Sprung (D.C., D.S.) gelten die Wiederholungen nicht mehr, und
/// von den Häusern wird das letzte gespielt.
class PlaybackPlan {
  PlaybackPlan._(this.score, this.bars, this.tracks, this.clicks);

  final Score score;
  final List<PlayBar> bars;
  final List<PlayTrack> tracks;
  final List<Click> clicks;

  /// Gesamtdauer in Sekunden.
  double get duration => bars.isEmpty ? 0 : bars.last.end;

  /// Plan erstellen. [tempoFactor] beschleunigt (> 1) oder verlangsamt (< 1).
  factory PlaybackPlan.build(Score score, {double tempoFactor = 1}) {
    final order = playOrder(score);
    final bars = <PlayBar>[];
    var t = 0.0;
    for (final b in order) {
      final mb = score.masterBars[b];
      final len = mb.time.length.toDouble();
      final segs = _segments(score, b, len, tempoFactor);
      final pb = PlayBar(b, t, len, segs, swing: mb.swing && mb.time.beatType == 4);
      bars.add(pb);
      t = pb.end;
    }
    final tracks = <PlayTrack>[
      for (var i = 0; i < score.tracks.length; i++) PlayTrack(i, score.tracks[i], _notes(score, score.tracks[i], bars)),
    ];
    return PlaybackPlan._(score, bars, tracks, _clicks(score, bars));
  }

  /// Takte in der Reihenfolge, in der sie gespielt werden.
  static List<int> playOrder(Score score) {
    final mbs = score.masterBars;
    final n = mbs.length;
    final out = <int>[];
    if (n == 0) return out;
    // Gruppen von Häusern: für jeden Takt die höchste Hausnummer seiner Gruppe
    final lastEnding = List<int>.filled(n, 0);
    var k = 0;
    while (k < n) {
      if (mbs[k].endings.isEmpty) {
        k++;
        continue;
      }
      var j = k;
      while (j + 1 < n && mbs[j + 1].endings.isNotEmpty) {
        j++;
      }
      final maxE = [for (var x = k; x <= j; x++) ...mbs[x].endings].reduce(math.max);
      for (var x = k; x <= j; x++) {
        lastEnding[x] = maxE;
      }
      k = j + 1;
    }
    int? find(bool Function(MasterBar) test) {
      for (var i = 0; i < n; i++) {
        if (test(mbs[i])) return i;
      }
      return null;
    }

    final segno = find((m) => m.directions.contains(Direction.segno));
    final coda = find((m) => m.directions.contains(Direction.coda));
    var i = 0;
    var repeatStart = 0;
    var pass = 1;
    final done = <int, int>{}; // Wiederholungsende → wie oft schon gespielt
    var jumped = false;
    var alFine = false, alCoda = false;
    final limit = n * 32;
    while (i < n && out.length < limit) {
      final mb = mbs[i];
      if (mb.repeatStart && !jumped && i != repeatStart) {
        repeatStart = i;
        pass = 1;
      }
      if (mb.endings.isNotEmpty) {
        final play = jumped ? mb.endings.contains(lastEnding[i]) : mb.endings.contains(pass);
        if (!play) {
          i++;
          continue;
        }
      }
      out.add(i);
      if (jumped && alFine && mb.directions.contains(Direction.fine)) break;
      if (mb.hasRepeatEnd && !jumped) {
        final count = done[i] ?? 1;
        if (count < mb.repeatEnd) {
          done[i] = count + 1;
          pass = count + 1;
          i = repeatStart;
          continue;
        }
        done.remove(i);
        pass = 1;
        repeatStart = i + 1;
      }
      if (!jumped) {
        final d = mb.directions;
        int? target;
        if (d.contains(Direction.daCapo) || d.contains(Direction.daCapoAlFine) || d.contains(Direction.daCapoAlCoda)) {
          target = 0;
        } else if (segno != null &&
            (d.contains(Direction.dalSegno) ||
                d.contains(Direction.dalSegnoAlFine) ||
                d.contains(Direction.dalSegnoAlCoda))) {
          target = segno;
        }
        if (target != null) {
          jumped = true;
          alFine = d.contains(Direction.daCapoAlFine) || d.contains(Direction.dalSegnoAlFine);
          alCoda = d.contains(Direction.daCapoAlCoda) || d.contains(Direction.dalSegnoAlCoda);
          if (!alFine && !alCoda) {
            // „D.C.“ allein: bis Fine, falls es eines gibt, sonst bis zum Ende
            alFine = find((m) => m.directions.contains(Direction.fine)) != null;
          }
          i = target;
          continue;
        }
      } else if (alCoda && coda != null && mb.directions.contains(Direction.toCoda) && coda > i) {
        i = coda;
        continue;
      }
      i++;
    }
    return out;
  }

  /// Tempo im Takt [bar]: Abschnitte (Stelle in ganzen Noten, Sekunden pro ganze Note).
  static List<(double, double)> _segments(Score score, int bar, double len, double factor) {
    double spw(TempoMark t) {
      // Schläge pro Minute → Viertel pro Minute
      var unit = t.unit.length.toDouble();
      if (t.dotted) unit *= 1.5;
      final quarterBpm = t.bpm * unit * 4;
      return 240 / (quarterBpm * factor);
    }

    TempoMark? current;
    final inside = <TempoMark>[];
    for (final t in score.tempos) {
      if (t.bar < bar || (t.bar == bar && t.position <= 0)) {
        current = t;
      } else if (t.bar == bar) {
        inside.add(t);
      }
    }
    final segs = <(double, double)>[(0, current == null ? 240 / (120 * factor) : spw(current))];
    for (final t in inside) {
      segs.add((t.position.clamp(0.0, 1.0) * len, spw(t)));
    }
    return segs;
  }

  static List<Click> _clicks(Score score, List<PlayBar> bars) {
    final out = <Click>[];
    for (final pb in bars) {
      final ts = score.masterBars[pb.bar].time;
      // Zusammengesetzte Taktarten: punktierte Viertel als Schlag
      final step = ts.compound ? 3 / ts.beatType : 1 / ts.beatType;
      final count = (pb.length / step).round();
      for (var k = 0; k < count; k++) {
        out.add(Click(pb.start + pb.secondsAt(k * step), accent: k == 0));
      }
    }
    return out;
  }

  /// Einzähler: ein Takt Klicks vor dem Takt [pb] (negative Zeiten vor dessen Beginn).
  List<Click> countIn(PlayBar pb) {
    final ts = score.masterBars[pb.bar].time;
    final step = ts.compound ? 3 / ts.beatType : 1 / ts.beatType;
    final count = math.max(1, (pb.length / step).round());
    final spb = pb.segments.first.$2 * step;
    return [for (var k = 0; k < count; k++) Click(-(count - k) * spb, accent: k == 0)];
  }

  /// Index des gespielten Takts zur Zeit [seconds].
  int barAt(double seconds) {
    if (bars.isEmpty) return 0;
    var lo = 0, hi = bars.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (bars[mid].start <= seconds) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Takt (Partitur) und Stelle im Takt (ganze Noten) zur Zeit [seconds].
  (int bar, double position) locate(double seconds) {
    if (bars.isEmpty) return (0, 0);
    final pb = bars[barAt(seconds)];
    return (pb.bar, pb.positionAt(seconds - pb.start));
  }

  /// Erster gespielter Takt mit Partitur-Nummer [bar] ab Index [from].
  int? playIndexOf(int bar, {int from = 0}) {
    for (var i = from; i < bars.length; i++) {
      if (bars[i].bar == bar) return i;
    }
    for (var i = 0; i < from && i < bars.length; i++) {
      if (bars[i].bar == bar) return i;
    }
    return null;
  }

  // ───────────────────────── Töne ─────────────────────────

  static const _graceSeconds = 0.06;

  static double _velocity(Dynamic? d) => switch (d) {
    Dynamic.pppp => 0.25,
    Dynamic.ppp => 0.32,
    Dynamic.pp => 0.4,
    Dynamic.p => 0.5,
    Dynamic.mp => 0.62,
    Dynamic.mf || null => 0.74,
    Dynamic.f => 0.86,
    Dynamic.ff => 0.94,
    Dynamic.fff || Dynamic.ffff => 1.0,
  };

  /// Klingende Tonhöhe eines Flageoletts: natürlicher Oberton nach dem Bund.
  static int _harmonicMidi(Note n) {
    final f = n.fret ?? 12;
    final add = switch (f) {
      12 => 0,
      7 || 19 => 7,
      5 || 24 => 12,
      4 || 9 || 16 => 16,
      3 => 19,
      _ => 0,
    };
    // Offene Saite + Oktave über dem 12. Bund usw.: Ausgang ist die Tonhöhe am 12. Bund
    final open = n.pitch.midi - f;
    return open + 12 + add;
  }

  static List<PlayNote> _notes(Score score, Track track, List<PlayBar> bars) {
    final out = <PlayNote>[];
    final stringed = track.staff.isStringed;
    // Klingende Töne pro Stimme und Saite (bzw. Tonhöhe), für Haltebögen und Slides
    final sounding = <String, PlayNote>{};
    final lastOnString = <int, PlayNote>{};
    final slides = <PlayNote>[];
    var velocity = 0.74;
    // Haltepedal (aus der ersten Stimme): Zeiten, in denen es getreten ist
    final pedalSpans = <(double, double)>[];
    double? pedalDown;
    for (final pb in bars) {
      if (pb.bar >= track.bars.length) continue;
      final bar = track.bars[pb.bar];
      for (var v = 0; v < bar.voices.length; v++) {
        var onset = 0.0;
        final graces = <Beat>[];
        for (final beat in bar.voices[v].beats) {
          if (beat.grace != GraceType.none) {
            graces.add(beat);
            continue;
          }
          final len = beat.duration.length.toDouble();
          final t0 = pb.start + pb.secondsAt(onset);
          var t1 = pb.start + pb.secondsAt(onset + len);
          if (beat.fermata) t1 += (t1 - t0) * 0.5;
          if (beat.dynamic != null) velocity = _velocity(beat.dynamic);
          if (v == 0 && beat.pedal != 0) {
            if (beat.pedal >= 2 && pedalDown != null) pedalSpans.add((pedalDown, t0));
            pedalDown = beat.pedal == 2 ? null : t0;
          }
          // Vorschlagsnoten: kurz vor (bzw. auf) dem Schlag
          var mainStart = t0;
          for (var g = 0; g < graces.length; g++) {
            final gb = graces[g];
            final gs = gb.grace == GraceType.onBeat ? t0 + g * _graceSeconds : t0 - (graces.length - g) * _graceSeconds;
            for (final n in gb.notes) {
              if (n.dead) continue;
              out.add(
                PlayNote(
                  start: math.max(0, gs),
                  duration: _graceSeconds,
                  midi: n.pitch.midi,
                  velocity: velocity * 0.85,
                  string: n.string,
                ),
              );
            }
          }
          if (graces.isNotEmpty && graces.first.grace == GraceType.onBeat) {
            mainStart = t0 + graces.length * _graceSeconds;
          }
          graces.clear();
          // Anschlag: Saiten kurz nacheinander
          final notes = [...beat.notes]..sort((a, b) => (a.string ?? a.pitch.midi).compareTo(b.string ?? b.pitch.midi));
          if (beat.pickStroke < 0 || beat.arpeggio < 0) notes.setAll(0, notes.reversed.toList());
          // Gebrochen: deutlich nacheinander; Rasgueado: sehr schnell; Anschlag: kurz versetzt
          final strum = notes.length < 2
              ? 0.0
              : beat.arpeggio != 0
              ? 0.06
              : beat.rasgueado
              ? 0.011
              : stringed && notes.length >= 3
              ? (beat.pickStroke != 0 ? 0.018 : 0.008)
              : 0.0;
          for (var ni = 0; ni < notes.length; ni++) {
            final n = notes[ni];
            final key = stringed && n.string != null ? '$v/s${n.string}' : '$v/p${n.pitch.midi}';
            // Haltebogen: vorherigen Ton verlängern
            if (n.tieDestination) {
              final prev = sounding[key];
              if (prev != null) {
                prev.duration = t1 - prev.start;
                continue;
              }
            }
            final start = mainStart + ni * strum;
            var dur = t1 - start;
            if (n.accent & 1 != 0) dur *= 0.5; // staccato
            if (n.dead) dur = math.min(dur, 0.06);
            if (n.palmMuted) dur = math.min(dur, math.max(0.12, dur * 0.7));
            if (n.letRing) dur = math.max(dur, 2.5);
            var vel = velocity;
            if (n.ghost) vel *= 0.55;
            if (n.accent & 8 != 0) vel = math.min(1, vel * 1.2);
            if (n.accent & 4 != 0) vel = math.min(1, vel * 1.3);
            if (n.slap || n.pop) vel = math.min(1, vel * 1.2);
            final midi = !n.harmonic
                ? n.pitch.midi
                : switch (n.harmonicType) {
                    1 => n.pitch.midi + 12, // künstlich: eine Oktave über dem gegriffenen Ton
                    2 => n.pitch.midi + 19, // Pinch: Oktave und Quinte
                    _ => _harmonicMidi(n),
                  };
            final b = n.bend;
            // Tremolo-Hebel: kurz hinunter und zurück
            final whammy = beat.whammy != 0 && b == null
                ? [(0.0, 0.0), (0.25, beat.whammy.toDouble()), (0.5, 0.0), (1.0, 0.0)]
                : null;
            // Tremolo-Picking: der Ton wird schnell wiederholt; Triller: im Wechsel mit dem oberen Ton
            final trem = n.trill != 0 ? 3 : beat.tremolo;
            final pieces = trem > 0 ? math.max(1, ((t1 - start) / (pb.secondsAt(1.0 / (4 << trem)))).round()) : 1;
            final pieceLen = (t1 - start) / pieces;
            for (var p = 0; p < pieces; p++) {
              final first = p == 0, last = p == pieces - 1;
              final note = PlayNote(
                start: start + p * pieceLen,
                duration: pieces > 1 ? pieceLen * 0.9 : dur,
                midi: n.trill != 0 && p.isOdd ? midi + n.trill : midi,
                velocity: n.trill != 0 && p > 0 ? vel * 0.85 : vel,
                string: n.string,
                bend: b == null ? (whammy ?? const []) : [for (final pt in b.points) (pt.position, pt.semitones)],
                vibrato: n.vibrato,
                palmMuted: n.palmMuted,
                dead: n.dead,
                harmonic: n.harmonic,
                legato: (p == 0 && n.hammerDestination) || (n.trill != 0 && p > 0),
                slideIn: first ? (n.slide & 16 != 0 ? -1 : (n.slide & 32 != 0 ? 1 : 0)) : 0,
                slideOut: last ? (n.slide & 4 != 0 ? -1 : (n.slide & 8 != 0 ? 1 : 0)) : 0,
                wideVibrato: n.wideVibrato,
                fade: beat.fade,
              );
              out.add(note);
              sounding[key] = note;
              if (n.string != null) {
                // Neuer Ton auf derselben Saite beendet den alten
                final old = lastOnString[n.string!];
                if (old != null && old != note && old.end > note.start && stringed) {
                  old.duration = math.max(0.02, note.start - old.start);
                }
                lastOnString[n.string!] = note;
              }
            }
            // Slide zum nächsten Ton: wird beim nächsten Ton auf derselben Saite eingetragen
            if (n.slide & 3 != 0 && n.string != null) slides.add(out.last);
          }
          onset += len;
        }
      }
    }
    if (pedalDown != null && bars.isNotEmpty) pedalSpans.add((pedalDown, bars.last.end));
    // Unter dem Pedal klingen die Töne bis zum Loslassen (bei Saiteninstrumenten nicht:
    // dort beendet der nächste Ton auf derselben Saite den alten)
    if (!stringed) {
      for (final (a, b) in pedalSpans) {
        for (final n in out) {
          if (n.start >= a - 1e-6 && n.start < b && n.end < b) n.duration = b - n.start;
        }
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    // Slide: Ziel ist der nächste Ton auf derselben Saite
    for (final src in slides) {
      final i = out.indexOf(src);
      for (var k = i + 1; k < out.length; k++) {
        if (out[k].string == src.string) {
          src.slideTo = out[k].midi;
          break;
        }
      }
    }
    return out;
  }
}
