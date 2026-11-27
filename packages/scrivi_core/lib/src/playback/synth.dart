import 'dart:math' as math;
import 'dart:typed_data';

import 'plan.dart';
import 'soundfont.dart';

/// Klangfarbe einer Spur.
enum Voicing { guitar, overdrive, nylon, bass, piano, organ, strings, brass, flute, pad, drums }

/// Erzeugt die Tonspur einer Spur (ohne Tondateien, alles gerechnet).
///
/// Saiteninstrumente klingen über eine „schwingende Saite“: ein kurzes
/// Rauschen läuft durch eine Verzögerung, deren Länge die Tonhöhe bestimmt,
/// und wird dabei weicher. Weil die Länge sich während des Tons ändern darf,
/// gehen Saitenziehen, Slides und Vibrato fliessend. Andere Instrumente
/// entstehen aus wenigen Obertönen, das Schlagzeug aus Rauschen und Tönen.
class Synth {
  Synth._();

  static const rate = 44100;

  /// Klangfarbe nach der Klangnummer der Datei, sonst nach der Art der Spur.
  static Voicing voicingFor(PlayTrack t) {
    final tr = t.track;
    if (tr.percussion) return Voicing.drums;
    final p = tr.program;
    if (p >= 0) {
      if (p == 24) return Voicing.nylon;
      if (p == 29 || p == 30) return Voicing.overdrive;
      if (p >= 25 && p <= 31) return Voicing.guitar;
      if (p >= 32 && p <= 39) return Voicing.bass;
      if (p <= 15) return Voicing.piano;
      if (p <= 23) return Voicing.organ;
      if (p >= 40 && p <= 55) return Voicing.strings;
      if (p >= 56 && p <= 71) return Voicing.brass;
      if (p >= 72 && p <= 79) return Voicing.flute;
      if (p >= 80) return Voicing.pad;
    }
    if (tr.staff.isStringed) {
      final low = tr.staff.tuning.reduce(math.min);
      return low < 36 && tr.staff.stringCount <= 6 ? Voicing.bass : Voicing.guitar;
    }
    return Voicing.piano;
  }

  /// Preset der Klangsammlung für die Spur: Schlagzeug, sonst die
  /// Klangnummer, sonst ein Klang aus derselben Familie, sonst nach der Art der Spur.
  static SfPreset? presetFor(PlayTrack t, SoundFont sf) {
    final tr = t.track;
    if (tr.percussion) return sf.preset(128, 0) ?? _first(sf, 128);
    var p = tr.program;
    if (p < 0) {
      p = switch (voicingFor(t)) {
        Voicing.bass => 33,
        Voicing.nylon => 24,
        Voicing.guitar => 25,
        Voicing.overdrive => 29,
        Voicing.organ => 16,
        Voicing.strings => 48,
        Voicing.brass => 61,
        Voicing.flute => 73,
        Voicing.pad => 89,
        _ => 0,
      };
    }
    final exact = sf.preset(0, p);
    if (exact != null) return exact;
    // Gitarren: gedämpft, verzerrt und Flageolett aus der cleanen E-Gitarre
    const near = {28: 27, 29: 27, 30: 27, 31: 27, 36: 33, 37: 34, 39: 38};
    final n = near[p];
    if (n != null && sf.preset(0, n) != null) return sf.preset(0, n);
    // Sonst der nächste Klang derselben Familie (je acht Nummern)
    final base = p ~/ 8 * 8;
    for (var d = 1; d < 8; d++) {
      for (final q in [p - d, p + d]) {
        if (q >= base && q < base + 8) {
          final x = sf.preset(0, q);
          if (x != null) return x;
        }
      }
    }
    return sf.preset(0, 0) ?? _first(sf, 0);
  }

  static SfPreset? _first(SoundFont sf, int bank) {
    for (final p in sf.presets) {
      if (p.bank == bank) return p;
    }
    return null;
  }

  /// Tonspur der Spur [t] (mono, −1..1), [seconds] lang. Mit [sounds] klingen
  /// aufgenommene Töne aus der Klangsammlung, sonst gerechnete.
  static Float32List renderTrack(PlayTrack t, double seconds, {Voicing? voicing, SoundFont? sounds}) {
    final v = voicing ?? voicingFor(t);
    final preset = sounds == null ? null : presetFor(t, sounds);
    if (sounds != null && preset != null) return _renderSampled(t, seconds, v, sounds, preset);
    final out = Float32List((seconds * rate).ceil() + 1);
    final rnd = math.Random(t.index + 7);
    for (final n in t.notes) {
      switch (v) {
        case Voicing.guitar || Voicing.overdrive || Voicing.nylon || Voicing.bass:
          _string(out, n, v, rnd);
        case Voicing.drums:
          _drum(out, n, rnd);
        case Voicing.piano:
          _piano(out, n);
        default:
          _sustained(out, n, v);
      }
    }
    if (v == Voicing.overdrive) _overdrive(out);
    _limit(out, v == Voicing.drums ? 0.5 : 0.35);
    return out;
  }

  /// Metronom-Klicks (betonter erster Schlag), um [offset] Sekunden verschoben.
  static Float32List renderClicks(List<Click> clicks, double seconds, {double offset = 0}) {
    final out = Float32List((seconds * rate).ceil() + 1);
    for (final c in clicks) {
      final s0 = ((c.time + offset) * rate).round();
      final f = c.accent ? 1760.0 : 1180.0;
      final len = (0.035 * rate).round();
      for (var i = 0; i < len; i++) {
        final k = s0 + i;
        if (k < 0 || k >= out.length) continue;
        final tt = i / rate;
        out[k] += math.sin(2 * math.pi * f * tt) * math.exp(-tt * 90) * (c.accent ? 0.9 : 0.6);
      }
    }
    return out;
  }

  // ───────────────────────── Aufgenommene Töne ─────────────────────────

  static Float32List _renderSampled(PlayTrack t, double seconds, Voicing v, SoundFont sf, SfPreset preset) {
    final out = Float32List((seconds * rate).ceil() + 1);
    final rnd = math.Random(t.index + 7);
    final drums = t.track.percussion;
    final program = t.track.program;
    final allMuted = program == 28;
    final notes = [...t.notes]..sort((a, b) => a.start.compareTo(b.start));
    // Töne derselben Klasse (Hi-Hat offen/zu) schneiden sich ab
    final cutAt = <PlayNote, double>{};
    if (drums) {
      final last = <int, PlayNote>{};
      for (final n in notes) {
        for (final r in preset.regionsFor(n.midi, _vel(n))) {
          if (r.exclusiveClass == 0) continue;
          final prev = last[r.exclusiveClass];
          if (prev != null && prev != n) cutAt[prev] = n.start;
          last[r.exclusiveClass] = n;
        }
      }
    }
    for (final n in notes) {
      if (n.dead && !drums) {
        _string(out, n, Voicing.guitar, rnd);
        continue;
      }
      if (n.harmonic && !drums) {
        _bell(out, n, math.pow(n.velocity, 1.4).toDouble() * 2.5);
        continue;
      }
      for (final r in preset.regionsFor(n.midi, _vel(n))) {
        _voice(out, sf, r, n, drums: drums, muted: allMuted || n.palmMuted, cut: cutAt[n]);
      }
    }
    if (v == Voicing.overdrive || program == 29 || program == 30) _overdrive(out);
    _limit(out, drums ? 0.9 : 0.8);
    return out;
  }

  static int _vel(PlayNote n) => (n.velocity * 127).round().clamp(1, 127);

  /// Ein aufgenommener Ton: abspielen mit veränderlicher Tonhöhe, Hüllkurve und Tiefpass.
  static void _voice(
    Float32List out,
    SoundFont sf,
    SfRegion r,
    PlayNote n, {
    required bool drums,
    required bool muted,
    double? cut,
  }) {
    final data = sf.samples;
    final s = r.sample;
    final start = r.start, end = math.min(r.end, data.length);
    if (end - start < 4) return;
    final looping = r.loopMode == 1 || r.loopMode == 3;
    final ls = r.loopStart, le = r.loopEnd;
    final canLoop = looping && le > ls + 4 && le <= end && ls >= start;
    final vel = _vel(n);
    // Anschlag → Lautstärke (wie üblich quadratisch), Abschwächung der Zone
    var amp = math.pow(vel / 127, 2).toDouble() * math.pow(10, -r.attenuation * 0.4 / 20).toDouble();
    if (n.legato) amp *= 0.7;
    final s0 = (n.start * rate).round();
    // Loslassen: Schlagzeug spielt aus, sonst am Ende des Tons
    var offSec = drums ? double.infinity : n.duration;
    if (muted) offSec = math.min(offSec, 0.09);
    var relSec = r.release.clamp(0.006, 3.0);
    if (muted) relSec = 0.12;
    if (cut != null) {
      offSec = math.min(offSec, cut - n.start);
      relSec = 0.02;
    }
    // Tiefpass: Grenzfrequenz der Zone, leiser angeschlagen etwas dunkler, gedämpft deutlich
    var fcCents = r.filterFc - 2400 * (1 - vel / 127) * 0.5;
    if (muted) fcCents = math.min(fcCents, 8800); // etwa 1,3 kHz
    final fc = 8.176 * math.pow(2, fcCents / 1200);
    final useFilter = fc < rate * 0.42;
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
    if (useFilter) {
      final q = math.pow(10, r.filterQ / 20).toDouble().clamp(0.5, 12.0) * 0.7071;
      final w = 2 * math.pi * fc / rate;
      final alpha = math.sin(w) / (2 * q);
      final cw = math.cos(w);
      final a0 = 1 + alpha;
      b0 = (1 - cw) / 2 / a0;
      b1 = (1 - cw) / a0;
      b2 = b0;
      a1 = -2 * cw / a0;
      a2 = (1 - alpha) / a0;
    }
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
    final decay = r.decayFor(n.midi);
    final sustain = r.sustainDb;
    final delay = r.delay, attack = r.attack, hold = r.hold;
    final ratio = s.rate / rate;
    var pos = start.toDouble();
    var step = 1.0;
    var db = 0.0; // Abschwächung der Hüllkurve in dB
    double? relFromDb;
    final maxLen = math.min(out.length - s0, ((drums ? 8.0 : n.duration + relSec + 0.05) * rate).ceil());
    for (var i = 0; i < maxLen; i++) {
      final sec = i / rate;
      if ((i & 31) == 0) {
        final x = n.duration > 0 ? (sec / n.duration).clamp(0.0, 1.0) : 0.0;
        final pitch = drums ? n.midi.toDouble() : _pitchAt(n, x, sec);
        final semis = (pitch - r.rootKey) * r.scaleTuning / 100 + r.tune / 100;
        step = math.pow(2, semis / 12) * ratio;
      }
      // Hüllkurve
      double env;
      if (sec < delay) {
        env = 0;
      } else if (sec < delay + attack) {
        env = (sec - delay) / attack;
      } else {
        final t2 = sec - delay - attack - hold;
        if (t2 > 0 && decay > 0) {
          db = math.min(sustain, t2 / decay * 100);
        } else if (t2 > 0) {
          db = sustain;
        }
        env = 1;
      }
      if (sec >= offSec) {
        relFromDb ??= db;
        final rdb = relFromDb + (sec - offSec) / relSec * 100;
        if (rdb > 90) break;
        env *= math.pow(10, -rdb / 20);
      } else if (db > 0) {
        env *= math.pow(10, -db / 20);
      }
      if (muted) env *= math.exp(-sec * 9);
      // Sample lesen (kubisch zwischen den Werten)
      final ip = pos.floor();
      if (ip >= end - 1) break;
      final f = pos - ip;
      final xm1 = data[math.max(start, ip - 1)].toDouble();
      final x0 = data[ip].toDouble();
      final xp1 = data[ip + 1].toDouble();
      final xp2 = data[math.min(end - 1, ip + 2)].toDouble();
      final c1 = 0.5 * (xp1 - xm1);
      final c2 = xm1 - 2.5 * x0 + 2 * xp1 - 0.5 * xp2;
      final c3 = 0.5 * (xp2 - xm1) + 1.5 * (x0 - xp1);
      var y = ((c3 * f + c2) * f + c1) * f + x0;
      y *= 1 / 32768;
      if (useFilter) {
        final yy = b0 * y + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1;
        x1 = y;
        y2 = y1;
        y1 = yy;
        y = yy;
      }
      out[s0 + i] += y * env * amp;
      pos += step;
      if (canLoop && (r.loopMode == 1 || sec < offSec)) {
        while (pos >= le) {
          pos -= le - ls;
        }
      }
    }
  }

  // ───────────────────────── Saiten ─────────────────────────

  static double _freq(double midi) => 440.0 * math.pow(2, (midi - 69) / 12.0);

  /// Tonhöhe (MIDI, mit Bruchteilen) zum Zeitpunkt [x] (0..1 der Dauer) und [sec] Sekunden nach Beginn.
  static double _pitchAt(PlayNote n, double x, double sec) {
    var p = n.midi.toDouble();
    final b = n.bend;
    if (b.isNotEmpty) {
      var semis = b.first.$2;
      for (var i = 0; i + 1 < b.length; i++) {
        final (x0, s0) = b[i];
        final (x1, s1) = b[i + 1];
        if (x >= x0 && x <= x1) {
          semis = x1 > x0 ? s0 + (s1 - s0) * (x - x0) / (x1 - x0) : s1;
          break;
        }
        if (x > x1) semis = s1;
      }
      p += semis;
    }
    final to = n.slideTo;
    if (to != null && x > 0.6) p += (to - n.midi) * ((x - 0.6) / 0.4);
    if (n.vibrato && sec > 0.12) p += 0.22 * math.sin(2 * math.pi * 5.5 * sec);
    return p;
  }

  static void _string(Float32List out, PlayNote n, Voicing v, math.Random rnd) {
    final s0 = (n.start * rate).round();
    // Die Saite klingt leiser als die anderen Klangfarben: angleichen
    final amp = math.pow(n.velocity, 1.4).toDouble() * (n.legato ? 0.7 : 1.0) * 2.5;
    if (n.dead) {
      // Gedämpfter Anschlag: kurzes, dumpfes Geräusch
      final len = (0.05 * rate).round();
      var lp = 0.0;
      for (var i = 0; i < len && s0 + i < out.length; i++) {
        lp += 0.35 * ((rnd.nextDouble() * 2 - 1) - lp);
        out[s0 + i] += lp * amp * 0.6 * math.exp(-i / rate * 60);
      }
      return;
    }
    if (n.harmonic) {
      _bell(out, n, amp);
      return;
    }
    final bass = v == Voicing.bass;
    // Verlust pro Durchlauf und Helligkeit
    var loss = bass ? 0.9985 : (v == Voicing.nylon ? 0.9955 : 0.997);
    var bright = bass ? 0.35 : (v == Voicing.nylon ? 0.42 : 0.5);
    if (n.palmMuted) {
      loss = 0.975;
      bright = 0.3;
    }
    final release = 0.04;
    final total = math.min(n.duration + release, 10.0);
    final len = (total * rate).round();
    const size = 4096;
    final buf = Float32List(size);
    // Anregung: geglättetes Rauschen, eine Periode lang
    final f0 = _freq(n.midi.toDouble());
    final burst = math.max(2, (rate / f0).round());
    var prevNoise = 0.0;
    final soft = n.legato ? 0.25 : (bass ? 0.4 : 0.6);
    var w = 0;
    var lp = 0.0;
    final relStart = (n.duration * rate).round();
    for (var i = 0; i < len; i++) {
      final k = s0 + i;
      if (k >= out.length) break;
      final x = n.duration > 0 ? (i / rate) / n.duration : 0.0;
      final f = _freq(_pitchAt(n, x.clamp(0.0, 1.0), i / rate));
      // Schleifenlänge = Periode minus Verzögerung des Tiefpasses
      final d = rate / f - _lowpassDelay(bright, f);
      // Lesen mit Bruchteil-Verzögerung (lineare Zwischenwerte)
      final r = w - d;
      final ri = r.floor();
      final fr = r - ri;
      final y = buf[ri & (size - 1)] * (1 - fr) + buf[(ri + 1) & (size - 1)] * fr;
      // Tiefpass in der Schleife (Saite wird weicher)
      lp = lp + bright * (y - lp);
      var input = 0.0;
      if (i < burst) {
        final noise = rnd.nextDouble() * 2 - 1;
        prevNoise = prevNoise + soft * (noise - prevNoise);
        input = prevNoise;
      }
      final s = lp * loss + input;
      buf[w & (size - 1)] = s;
      w++;
      var e = s * amp;
      if (i < 32) e *= i / 32;
      if (i > relStart) e *= math.max(0.0, 1 - (i - relStart) / (release * rate));
      out[k] += e;
    }
  }

  /// Phasenverzögerung (Samples) des Tiefpasses y += b·(x − y) bei der Frequenz [f].
  static double _lowpassDelay(double b, double f) {
    final w = 2 * math.pi * f / rate;
    final a = 1 - b;
    final phase = math.atan2(a * math.sin(w), 1 - a * math.cos(w));
    return phase / w;
  }

  /// Flageolett: glockenartiger, reiner Ton.
  static void _bell(Float32List out, PlayNote n, double amp) {
    final s0 = (n.start * rate).round();
    final total = math.min(n.duration + 0.6, 6.0);
    final len = (total * rate).round();
    var phase = 0.0;
    for (var i = 0; i < len && s0 + i < out.length; i++) {
      final sec = i / rate;
      final x = n.duration > 0 ? sec / n.duration : 0.0;
      phase += 2 * math.pi * _freq(_pitchAt(n, x.clamp(0.0, 1.0), sec)) / rate;
      final env = math.exp(-sec * 1.6) * math.min(1.0, i / 40);
      out[s0 + i] += (math.sin(phase) + 0.15 * math.sin(2 * phase)) * env * amp * 0.5;
    }
  }

  static void _overdrive(Float32List out) {
    // Weiche Sättigung und etwas Tiefpass gegen Härte
    var lp = 0.0;
    for (var i = 0; i < out.length; i++) {
      final y = _tanh(out[i] * 4.0) * 0.45;
      lp += 0.45 * (y - lp);
      out[i] = lp;
    }
  }

  // ───────────────────────── Klavier und gehaltene Klänge ─────────────────────────

  static void _piano(Float32List out, PlayNote n) {
    final s0 = (n.start * rate).round();
    final f = _freq(n.midi.toDouble());
    final amp = math.pow(n.velocity, 1.4).toDouble() * 0.5;
    final release = 0.12;
    final total = math.min(n.duration + release, 8.0);
    final len = (total * rate).round();
    final relStart = (n.duration * rate).round();
    // Obertöne mit eigener Abklingzeit (höhere klingen schneller ab)
    const harm = [1.0, 0.5, 0.28, 0.16, 0.09, 0.05];
    final decayBase = 0.8 + (n.midi - 60) * 0.03;
    for (var h = 0; h < harm.length; h++) {
      final fh = f * (h + 1) * (1 + 0.0004 * (h + 1) * (h + 1));
      if (fh > rate / 2.2) break;
      final dk = decayBase * (1 + h * 0.6);
      final step = 2 * math.pi * fh / rate;
      for (var i = 0; i < len && s0 + i < out.length; i++) {
        final sec = i / rate;
        var env = math.exp(-sec * dk) * harm[h];
        if (i < 64) env *= i / 64;
        if (i > relStart) env *= math.max(0.0, 1 - (i - relStart) / (release * rate));
        out[s0 + i] += math.sin(step * i) * env * amp;
      }
    }
  }

  static void _sustained(Float32List out, PlayNote n, Voicing v) {
    final s0 = (n.start * rate).round();
    final amp = math.pow(n.velocity, 1.4).toDouble() * 0.35;
    final (harm, attack, release, vib) = switch (v) {
      Voicing.organ => (const [1.0, 0.6, 0.0, 0.4, 0.0, 0.25], 0.01, 0.05, 0.0),
      Voicing.strings => (const [1.0, 0.5, 0.33, 0.25, 0.2, 0.16, 0.12], 0.08, 0.2, 0.12),
      Voicing.brass => (const [1.0, 0.7, 0.5, 0.35, 0.25, 0.15], 0.04, 0.1, 0.08),
      Voicing.flute => (const [1.0, 0.15, 0.05], 0.05, 0.1, 0.1),
      _ => (const [1.0, 0.4, 0.2, 0.1], 0.1, 0.3, 0.05),
    };
    final total = math.min(n.duration + release, 12.0);
    final len = (total * rate).round();
    final relStart = (n.duration * rate).round();
    var phase = 0.0;
    for (var i = 0; i < len && s0 + i < out.length; i++) {
      final sec = i / rate;
      final x = n.duration > 0 ? sec / n.duration : 0.0;
      var p = _pitchAt(n, x.clamp(0.0, 1.0), sec);
      if (vib > 0 && sec > 0.25) p += vib * math.sin(2 * math.pi * 5 * sec);
      phase += 2 * math.pi * _freq(p) / rate;
      var s = 0.0;
      for (var h = 0; h < harm.length; h++) {
        if (harm[h] != 0) s += math.sin(phase * (h + 1)) * harm[h];
      }
      var env = math.min(1.0, sec / attack);
      if (i > relStart) env *= math.max(0.0, 1 - (i - relStart) / (release * rate));
      out[s0 + i] += s * env * amp;
    }
  }

  // ───────────────────────── Schlagzeug ─────────────────────────

  static void _drum(Float32List out, PlayNote n, math.Random rnd) {
    final s0 = (n.start * rate).round();
    final amp = math.pow(n.velocity, 1.2).toDouble();
    final m = n.midi;
    void noise(double seconds, double decay, double hp, double gain) {
      final len = (seconds * rate).round();
      var prev = 0.0, lpv = 0.0;
      for (var i = 0; i < len && s0 + i < out.length; i++) {
        final x = rnd.nextDouble() * 2 - 1;
        // einfacher Hochpass
        lpv += hp * (x - lpv);
        final y = x - lpv;
        prev = y;
        out[s0 + i] += prev * math.exp(-i / rate * decay) * gain * amp;
      }
    }

    void tone(double f0, double f1, double seconds, double decay, double gain) {
      final len = (seconds * rate).round();
      var phase = 0.0;
      for (var i = 0; i < len && s0 + i < out.length; i++) {
        final sec = i / rate;
        final f = f1 + (f0 - f1) * math.exp(-sec * 30);
        phase += 2 * math.pi * f / rate;
        out[s0 + i] += math.sin(phase) * math.exp(-sec * decay) * gain * amp;
      }
    }

    switch (m) {
      case 35 || 36: // Bassdrum
        tone(150, 48, 0.4, 9, 1.0);
      case 37: // Rimshot
        noise(0.03, 120, 0.3, 0.5);
      case 38 || 40: // Snare
        tone(220, 180, 0.15, 25, 0.5);
        noise(0.2, 22, 0.25, 0.55);
      case 42 || 44: // Hi-Hat zu
        noise(0.06, 70, 0.85, 0.35);
      case 46: // Hi-Hat offen
        noise(0.35, 9, 0.85, 0.3);
      case 49 || 52 || 55 || 57: // Becken
        noise(1.4, 2.5, 0.8, 0.3);
      case 51 || 53 || 59: // Ride
        noise(0.7, 5, 0.9, 0.22);
        tone(3200, 3200, 0.6, 5, 0.05);
      case >= 41 && <= 50: // Toms
        final f = 80.0 + (m - 41) * 18;
        tone(f * 1.6, f, 0.5, 8, 0.8);
      default:
        noise(0.05, 60, 0.6, 0.3);
    }
  }

  // ───────────────────────── Hilfen ─────────────────────────

  static double _tanh(double x) {
    if (x > 10) return 1;
    if (x < -10) return -1;
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }

  /// Lautstärke anpassen und Spitzen weich begrenzen.
  static void _limit(Float32List out, double gain) {
    for (var i = 0; i < out.length; i++) {
      final x = out[i] * gain;
      out[i] = x.abs() < 0.8 ? x : _tanh(x);
    }
  }

  /// WAV-Datei (16 Bit, mono) aus Werten zwischen −1 und 1.
  static Uint8List wav(Float32List samples) {
    final dataLen = samples.length * 2;
    final bytes = Uint8List(44 + dataLen);
    final b = ByteData.sublistView(bytes);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + dataLen, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, rate, Endian.little);
    b.setUint32(28, rate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, dataLen, Endian.little);
    // Direkt als 16-Bit-Werte schreiben (44 ist gerade: ausgerichtet)
    final pcm = Int16List.view(bytes.buffer, 44, samples.length);
    final little = Endian.host == Endian.little;
    for (var i = 0; i < samples.length; i++) {
      var v = samples[i] * 32767;
      if (v > 32767) v = 32767;
      if (v < -32767) v = -32767;
      final x = (v >= 0 ? v + 0.5 : v - 0.5).toInt();
      pcm[i] = little ? x : ((x & 0xFF) << 8) | ((x >> 8) & 0xFF);
    }
    return bytes;
  }
}
