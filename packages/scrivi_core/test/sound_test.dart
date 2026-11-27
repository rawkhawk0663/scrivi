import 'dart:math' as math;
import 'dart:typed_data';

import 'package:scrivi_core/scrivi_core.dart';
import 'package:test/test.dart';

/// Kleine SoundFont zum Testen: ein Sinus mit 441 Hz (genau 100 Werte pro
/// Schwingung), als Schleife, Grundton A4. Preset 0/27 (E-Gitarre) und
/// ein Schlagzeug (Bank 128) mit nur der Taste 36.
Uint8List _tinySf2() {
  const n = 4410;
  final pcm = Int16List(n);
  for (var i = 0; i < n; i++) {
    pcm[i] = (math.sin(2 * math.pi * i / 100) * 12000).round();
  }
  final b = BytesBuilder();
  void u16(BytesBuilder o, int v) => o.add([v & 255, v >> 8 & 255]);
  void u32(BytesBuilder o, int v) => o.add([v & 255, v >> 8 & 255, v >> 16 & 255, v >> 24 & 255]);
  void name(BytesBuilder o, String s) => o.add([...s.codeUnits, ...List.filled(20 - s.length, 0)]);
  Uint8List chunk(String id, List<int> data) {
    final o = BytesBuilder()..add(id.codeUnits);
    u32(o, data.length);
    o.add(data);
    if (data.length.isOdd) o.addByte(0);
    return o.toBytes();
  }

  Uint8List list(String kind, List<int> data) => chunk('LIST', [...kind.codeUnits, ...data]);

  final smpl = BytesBuilder()
    ..add(pcm.buffer.asUint8List())
    ..add(List.filled(92, 0));
  // Presets: Gitarre (0/27) → Instrument 0, Schlagzeug (128/0) → Instrument 1
  final phdr = BytesBuilder();
  for (final (nm, prog, bank, bag) in [('Gitarre', 27, 0, 0), ('Drums', 0, 128, 1), ('EOP', 0, 0, 2)]) {
    name(phdr, nm);
    u16(phdr, prog);
    u16(phdr, bank);
    u16(phdr, bag);
    u32(phdr, 0);
    u32(phdr, 0);
    u32(phdr, 0);
  }
  final pbag = BytesBuilder();
  for (final g in [0, 1, 2]) {
    u16(pbag, g);
    u16(pbag, 0);
  }
  final pgen = BytesBuilder();
  for (final (op, v) in [(41, 0), (41, 1), (0, 0)]) {
    u16(pgen, op);
    u16(pgen, v);
  }
  final inst = BytesBuilder();
  for (final (nm, bag) in [('Sinus', 0), ('Trommel', 1), ('EOI', 2)]) {
    name(inst, nm);
    u16(inst, bag);
  }
  final ibag = BytesBuilder();
  final igen = BytesBuilder();
  var gi = 0;
  final zones = [
    [(43, 40 | 80 << 8), (54, 1), (38, 0xF830 /* −2000 Zeitcent */), (53, 0)],
    [(43, 36 | 36 << 8), (53, 0)],
  ];
  for (final z in zones) {
    u16(ibag, gi);
    u16(ibag, 0);
    for (final (op, v) in z) {
      u16(igen, op);
      u16(igen, v);
      gi++;
    }
  }
  u16(ibag, gi);
  u16(ibag, 0);
  u16(igen, 0);
  u16(igen, 0);
  final shdr = BytesBuilder();
  name(shdr, 'Sinus');
  for (final v in [0, n, 100, n - 10, 44100]) {
    u32(shdr, v);
  }
  shdr.add([69, 0]);
  u16(shdr, 0);
  u16(shdr, 1);
  name(shdr, 'EOS');
  shdr.add(List.filled(26, 0));
  final mod = List.filled(10, 0);
  final body = [
    ...'sfbk'.codeUnits,
    ...list('INFO', chunk('ifil', [2, 0, 1, 0])),
    ...list('sdta', chunk('smpl', smpl.toBytes())),
    ...list('pdta', [
      ...chunk('phdr', phdr.toBytes()),
      ...chunk('pbag', pbag.toBytes()),
      ...chunk('pmod', mod),
      ...chunk('pgen', pgen.toBytes()),
      ...chunk('inst', inst.toBytes()),
      ...chunk('ibag', ibag.toBytes()),
      ...chunk('imod', mod),
      ...chunk('igen', igen.toBytes()),
      ...chunk('shdr', shdr.toBytes()),
    ]),
  ];
  b.add('RIFF'.codeUnits);
  u32(b, body.length);
  b.add(body);
  return b.toBytes();
}

/// Frequenz über Nulldurchgänge (aufwärts) zwischen [from] und [to] Sekunden.
double _freq(Float32List x, double from, double to) {
  final a = (from * 44100).round(), b = (to * 44100).round();
  int? first, last;
  var count = 0;
  for (var i = a + 1; i < b; i++) {
    if (x[i - 1] < 0 && x[i] >= 0) {
      first ??= i;
      last = i;
      count++;
    }
  }
  if (first == null || count < 2) return 0;
  return (count - 1) * 44100 / (last! - first);
}

double _rms(Float32List x, double from, double to) {
  var s = 0.0;
  final a = (from * 44100).round(), b = (to * 44100).round();
  for (var i = a; i < b; i++) {
    s += x[i] * x[i];
  }
  return math.sqrt(s / (b - a));
}

void main() {
  final sf = SoundFont.parse(_tinySf2());
  Track guitar(int program) => Track(
    name: 'G',
    staff: const StaffDef(tuning: [40, 45, 50, 55, 59, 64]),
    bars: [],
    program: program,
  );

  group('Klangsammlung', () {
    test('Presets lesen und passend wählen', () {
      expect(sf.presets.map((p) => p.name), containsAll(['Gitarre', 'Drums']));
      // Verzerrte Gitarre nimmt die cleane, unbekannte Gitarre ebenso
      expect(Synth.presetFor(PlayTrack(0, guitar(30), const []), sf)!.program, 27);
      expect(Synth.presetFor(PlayTrack(0, guitar(25), const []), sf)!.program, 27);
      final drums = Track(
        name: 'D',
        staff: const StaffDef(),
        bars: [Bar(clef: Clef.neutral, voices: [])],
      );
      expect(Synth.presetFor(PlayTrack(0, drums, const []), sf)!.bank, 128);
    });

    test('Tonhöhe, Saitenziehen, Schleife und Ausklingen', () {
      final notes = [
        PlayNote(start: 0, duration: 2.0, midi: 81), // eine Oktave über dem Grundton
        PlayNote(start: 2.5, duration: 1.0, midi: 69, bend: const [(0.0, 0.0), (0.3, 2.0), (1.0, 2.0)]),
      ];
      final pcm = Synth.renderTrack(PlayTrack(0, guitar(27), notes), 4.5, sounds: sf);
      expect(_freq(pcm, 0.2, 0.5), closeTo(882, 6));
      // Die Schleife hält den Ton, obwohl das Sample nur 0,1 s lang ist
      expect(_rms(pcm, 1.6, 1.9), greaterThan(0.05));
      // Nach dem Loslassen klingt er schnell aus
      expect(_rms(pcm, 2.3, 2.45), lessThan(0.01));
      // Ganzton höher gezogen: H4 statt A4
      expect(_freq(pcm, 3.0, 3.4), closeTo(441 * math.pow(2, 2 / 12), 6));
    });

    test('Tasten ausserhalb klingen mit der nächsten Zone, beim Schlagzeug nicht', () {
      expect(sf.preset(0, 27)!.regionsFor(30, 100), hasLength(1));
      expect(sf.preset(128, 0)!.regionsFor(38, 100), isEmpty);
      expect(sf.preset(128, 0)!.regionsFor(36, 100), hasLength(1));
    });

    test('Palm Mute klingt kürzer', () {
      final open = Synth.renderTrack(
        PlayTrack(0, guitar(27), [PlayNote(start: 0, duration: 1, midi: 69)]),
        1.5,
        sounds: sf,
      );
      final muted = Synth.renderTrack(
        PlayTrack(0, guitar(27), [PlayNote(start: 0, duration: 1, midi: 69, palmMuted: true)]),
        1.5,
        sounds: sf,
      );
      expect(_rms(muted, 0.4, 0.6), lessThan(_rms(open, 0.4, 0.6) * 0.2));
    });
  });
}
