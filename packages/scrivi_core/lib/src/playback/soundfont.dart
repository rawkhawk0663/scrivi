import 'dart:math' as math;
import 'dart:typed_data';

/// Eine Klangsammlung im SoundFont-Format (SF2): aufgenommene Töne
/// (Samples) und wie sie über die Tasten verteilt sind.
///
/// Gelesen wird nur, was Scrivi zum Abspielen braucht: Presets (Bank und
/// Klangnummer), ihre Zonen mit Tasten- und Anschlagsbereich, Stimmung,
/// Lautstärke-Hüllkurve, Tiefpass und Schleifenpunkte. Modulatoren werden
/// übergangen; Anschlag → Lautstärke gilt wie üblich.
class SoundFont {
  SoundFont._(this.samples, this._presets);

  /// Alle Samples als 16-Bit-Werte hintereinander.
  final Int16List samples;
  final Map<int, SfPreset> _presets;

  /// Preset für Bank [bank] (128 = Schlagzeug) und Klangnummer [program].
  SfPreset? preset(int bank, int program) => _presets[bank << 8 | program];

  Iterable<SfPreset> get presets => _presets.values;

  static SoundFont parse(Uint8List bytes) {
    final d = ByteData.sublistView(bytes);
    String id(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
    if (bytes.length < 12 || id(0) != 'RIFF' || id(8) != 'sfbk') {
      throw const FormatException('Keine SoundFont-Datei');
    }
    final lists = <String, (int, int)>{};
    void chunks(int from, int to, void Function(String id, int off, int size) f) {
      var p = from;
      while (p + 8 <= to) {
        final cid = id(p);
        final size = d.getUint32(p + 4, Endian.little);
        f(cid, p + 8, size);
        var next = p + 8 + size;
        if (size.isOdd && next + 4 <= to) {
          final n = id(next);
          if (n != 'LIST' && n != 'smpl' && n != 'sm24' && n != 'phdr') next++;
        }
        p = next;
      }
    }

    chunks(12, bytes.length, (cid, off, size) {
      if (cid == 'LIST') lists[id(off)] = (off + 4, off + size);
    });
    final sdta = lists['sdta'], pdta = lists['pdta'];
    if (sdta == null || pdta == null) throw const FormatException('SoundFont unvollständig');
    Int16List? smpl;
    chunks(sdta.$1, sdta.$2, (cid, off, size) {
      if (cid != 'smpl') return;
      // Ausgerichtet ansehen, sonst kopieren
      if ((bytes.offsetInBytes + off).isEven) {
        smpl = bytes.buffer.asInt16List(bytes.offsetInBytes + off, size ~/ 2);
      } else {
        smpl = Int16List.sublistView(Uint8List.fromList(bytes.sublist(off, off + size)));
      }
    });
    final pd = <String, (int, int)>{};
    chunks(pdta.$1, pdta.$2, (cid, off, size) => pd[cid] = (off, size));
    if (smpl == null || !pd.containsKey('phdr') || !pd.containsKey('shdr')) {
      throw const FormatException('SoundFont unvollständig');
    }

    int u16(int o) => d.getUint16(o, Endian.little);
    int u32(int o) => d.getUint32(o, Endian.little);
    String name(int o) {
      final end = bytes.indexOf(0, o);
      return String.fromCharCodes(bytes.sublist(o, end < 0 || end > o + 20 ? o + 20 : end)).trim();
    }

    // Samples
    final (so, ss) = pd['shdr']!;
    final sampleHeaders = <SfSample>[];
    for (var i = 0; i < ss ~/ 46 - 1; i++) {
      final o = so + i * 46;
      sampleHeaders.add(
        SfSample(
          name: name(o),
          start: u32(o + 20),
          end: u32(o + 24),
          loopStart: u32(o + 28),
          loopEnd: u32(o + 32),
          rate: u32(o + 36),
          root: bytes[o + 40],
          correction: d.getInt8(o + 41),
        ),
      );
    }

    List<(int, int)> bags(String cid) {
      final (o, s) = pd[cid]!;
      return [for (var i = 0; i < s ~/ 4; i++) (u16(o + i * 4), u16(o + i * 4 + 2))];
    }

    List<(int, int)> gens(String cid) {
      final (o, s) = pd[cid]!;
      return [for (var i = 0; i < s ~/ 4; i++) (u16(o + i * 4), u16(o + i * 4 + 2))];
    }

    /// Zonen eines Eintrags: Generatoren (mit globaler Zone vereinigt) und Ziel.
    List<(Map<int, int>, int)> zones(int bagFrom, int bagTo, List<(int, int)> bg, List<(int, int)> gn, int terminal) {
      final out = <(Map<int, int>, int)>[];
      var global = <int, int>{};
      for (var b = bagFrom; b < bagTo && b + 1 < bg.length; b++) {
        final g0 = bg[b].$1, g1 = bg[b + 1].$1;
        final m = <int, int>{};
        int? target;
        for (var g = g0; g < g1 && g < gn.length; g++) {
          final (op, amt) = gn[g];
          if (op == terminal) {
            target = amt;
          } else {
            m[op] = amt;
          }
        }
        if (target == null) {
          if (b == bagFrom) global = m;
          continue;
        }
        out.add(({...global, ...m}, target));
      }
      return out;
    }

    final ib = bags('ibag'), ig = gens('igen'), pb = bags('pbag'), pg = gens('pgen');
    final (io, isz) = pd['inst']!;
    final instCount = isz ~/ 22;
    final instruments = <List<(Map<int, int>, int)>>[];
    for (var i = 0; i < instCount - 1; i++) {
      instruments.add(zones(u16(io + i * 22 + 20), u16(io + (i + 1) * 22 + 20), ib, ig, 53));
    }
    final (po, psz) = pd['phdr']!;
    final presets = <int, SfPreset>{};
    for (var i = 0; i < psz ~/ 38 - 1; i++) {
      final o = po + i * 38;
      final program = u16(o + 20), bank = u16(o + 22);
      final regions = <SfRegion>[];
      for (final (pgens, inst) in zones(u16(o + 24), u16(o + 38 + 24), pb, pg, 41)) {
        if (inst >= instruments.length) continue;
        for (final (igens, si) in instruments[inst]) {
          if (si >= sampleHeaders.length) continue;
          final r = SfRegion._(sampleHeaders[si], igens, pgens);
          if (r.keyLo <= r.keyHi && r.velLo <= r.velHi) regions.add(r);
        }
      }
      presets[bank << 8 | program] = SfPreset(name(o), bank, program, regions);
    }
    return SoundFont._(smpl!, presets);
  }
}

class SfPreset {
  SfPreset(this.name, this.bank, this.program, this.regions);
  final String name;
  final int bank;
  final int program;
  final List<SfRegion> regions;

  /// Zonen, die für Taste [key] und Anschlag [velocity] (0..127) klingen.
  /// Liegt die Taste ausserhalb aller Zonen, klingt die nächstgelegene (nur
  /// bei Instrumenten; beim Schlagzeug bleibt eine fehlende Taste stumm).
  List<SfRegion> regionsFor(int key, int velocity) {
    bool vel(SfRegion r) => velocity >= r.velLo && velocity <= r.velHi;
    final hit = [
      for (final r in regions)
        if (key >= r.keyLo && key <= r.keyHi && vel(r)) r,
    ];
    if (hit.isNotEmpty || bank == 128) return hit;
    SfRegion? best;
    var dist = 1 << 30;
    for (final r in regions) {
      if (!vel(r)) continue;
      final d = key < r.keyLo ? r.keyLo - key : key - r.keyHi;
      if (d < dist) {
        dist = d;
        best = r;
      }
    }
    return [?best];
  }
}

class SfSample {
  const SfSample({
    required this.name,
    required this.start,
    required this.end,
    required this.loopStart,
    required this.loopEnd,
    required this.rate,
    required this.root,
    required this.correction,
  });
  final String name;
  final int start;
  final int end;
  final int loopStart;
  final int loopEnd;
  final int rate;
  final int root;
  final int correction;
}

/// Eine Zone: Sample mit allen Werten (Instrument und Preset zusammengerechnet).
class SfRegion {
  SfRegion._(this.sample, Map<int, int> ig, Map<int, int> pg) {
    int s16(int v) => v >= 0x8000 ? v - 0x10000 : v;
    // Instrument: absolute Werte, Preset: wird dazugezählt
    int gen(int op, int def) => s16(ig[op] ?? def) + (pg.containsKey(op) ? s16(pg[op]!) : 0);
    int inst(int op, int def) => s16(ig[op] ?? def);
    (int, int) range(int op) {
      var lo = 0, hi = 127;
      for (final m in [ig, pg]) {
        final v = m[op];
        if (v != null) {
          lo = math.max(lo, v & 0xFF);
          hi = math.min(hi, v >> 8);
        }
      }
      return (lo, hi);
    }

    final k = range(43), v = range(44);
    keyLo = k.$1;
    keyHi = k.$2;
    velLo = v.$1;
    velHi = v.$2;
    start = sample.start + inst(0, 0) + inst(4, 0) * 32768;
    end = sample.end + inst(1, 0) + inst(12, 0) * 32768;
    loopStart = sample.loopStart + inst(2, 0) + inst(45, 0) * 32768;
    loopEnd = sample.loopEnd + inst(3, 0) + inst(50, 0) * 32768;
    loopMode = inst(54, 0) & 3;
    final over = inst(58, -1);
    rootKey = over >= 0 ? over : sample.root;
    tune = gen(51, 0) * 100 + gen(52, 0) + sample.correction;
    scaleTuning = gen(56, 100);
    attenuation = gen(48, 0) / 10.0;
    filterFc = gen(8, 13500);
    filterQ = gen(9, 0) / 10.0;
    delay = _time(gen(33, -12000));
    attack = _time(gen(34, -12000));
    hold = _time(gen(35, -12000));
    decayCents = gen(36, -12000);
    keyToDecay = gen(40, 0);
    sustainDb = (gen(37, 0) / 10.0).clamp(0.0, 144.0);
    release = _time(gen(38, -12000));
    exclusiveClass = inst(57, 0);
  }

  final SfSample sample;
  late final int keyLo, keyHi, velLo, velHi;
  late final int start, end, loopStart, loopEnd;

  /// 0 keine Schleife, 1 Schleife, 3 Schleife bis zum Loslassen.
  late final int loopMode;
  late final int rootKey;

  /// Verstimmung in Cent, Cent pro Halbton.
  late final int tune, scaleTuning;

  /// Abschwächung in dB.
  late final double attenuation;

  /// Tiefpass: Grenzfrequenz in absoluten Cent, Resonanz in dB.
  late final int filterFc;
  late final double filterQ;

  /// Hüllkurve: Sekunden, Abfall in Zeitcent (hängt von der Taste ab), Halten in dB unter voll.
  late final double delay, attack, hold, release, sustainDb;
  late final int decayCents, keyToDecay;

  /// Töne derselben Klasse schneiden sich ab (offene/geschlossene Hi-Hat).
  late final int exclusiveClass;

  double decayFor(int key) => _time(decayCents + keyToDecay * (60 - key));

  static double _time(int timecents) => timecents <= -12000 ? 0 : math.pow(2, timecents / 1200).toDouble();
}
