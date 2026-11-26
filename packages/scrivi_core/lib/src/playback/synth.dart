import 'dart:math' as math;
import 'dart:typed_data';

import 'plan.dart';

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

  /// Tonspur der Spur [t] (mono, −1..1), [seconds] lang.
  static Float32List renderTrack(PlayTrack t, double seconds, {Voicing? voicing}) {
    final v = voicing ?? voicingFor(t);
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
    final b = ByteData(44 + dataLen);
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
    for (var i = 0; i < samples.length; i++) {
      b.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    return b.buffer.asUint8List();
  }
}
