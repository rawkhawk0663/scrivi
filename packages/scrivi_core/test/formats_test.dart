import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:scrivi_core/scrivi_core.dart';
import 'package:test/test.dart';

import 'core_test.dart' show gpif, zipped;

/// Schreibt Binärdaten (Little Endian) für selbst gebaute Testdateien.
class _W {
  final b = BytesBuilder();
  void u8(int v) => b.addByte(v & 0xFF);
  void i32(int v) => b.add((ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List());
  void byteStr(String s, int size) {
    u8(s.length);
    final bytes = latin1.encode(s);
    for (var i = 0; i < size; i++) {
      u8(i < bytes.length ? bytes[i] : 0);
    }
  }

  void intByteStr(String s) {
    i32(s.length + 1);
    u8(s.length);
    b.add(latin1.encode(s));
  }

  Uint8List get bytes => b.toBytes();
}

/// Kleine Guitar-Pro-3-Datei: zwei Takte, eine Gitarre.
Uint8List gp3File() {
  final w = _W();
  w.byteStr('FICHIER GUITAR PRO v3.00', 30);
  for (final s in ['Drei', '', 'Test', '', '', '', '', '']) {
    w.intByteStr(s);
  }
  w.i32(0); // Hinweise
  w.u8(0); // Triolen-Gefühl
  w.i32(100); // Tempo
  w.i32(0); // Tonart
  for (var i = 0; i < 64; i++) {
    w.i32(25);
    for (var k = 0; k < 8; k++) {
      w.u8(0);
    }
  }
  w.i32(2); // Takte
  w.i32(1); // Spuren
  // Takt 1: 4/4, Wiederholungsbeginn, Marke „Intro“
  w.u8(0x01 | 0x02 | 0x04 | 0x20);
  w.u8(4);
  w.u8(4);
  w.intByteStr('Intro');
  w.i32(0); // Farbe
  // Takt 2: Wiederholungsende (einmal wiederholen)
  w.u8(0x08);
  w.u8(1);
  // Spur
  w.u8(0);
  w.byteStr('Gitarre', 40);
  w.i32(6);
  for (final t in [64, 59, 55, 50, 45, 40, 0]) {
    w.i32(t);
  }
  w.i32(1);
  w.i32(1);
  w.i32(2);
  w.i32(24);
  w.i32(0);
  w.i32(0);
  // Takt 1: zwei Halbe
  w.i32(2);
  w.u8(0x04); // mit Text
  w.u8(0xFF); // Halbe (-1)
  w.intByteStr('hallo');
  w.u8(0x40); // höchste Saite
  w.u8(0x20);
  w.u8(1);
  w.u8(3); // Bund 3 → G4
  w.u8(0x00);
  w.u8(0xFF);
  w.u8(0x02); // tiefste Saite
  w.u8(0x20 | 0x08);
  w.u8(1);
  w.u8(0);
  w.u8(0x02); // Hammer-on
  // Takt 2: Pause
  w.i32(1);
  w.u8(0x40);
  w.u8(2); // Pause
  w.u8(0xFE); // Ganze (-2)
  w.u8(0);
  return w.bytes;
}

/// Bits für die gepackte Guitar-Pro-6-Form (höchstes Bit zuerst).
class _Bits {
  final out = <int>[];
  int cur = 0;
  int n = 0;
  void bit(int b) {
    cur = (cur << 1) | b;
    n++;
    if (n == 8) {
      out.add(cur);
      cur = 0;
      n = 0;
    }
  }

  void bits(int v, int count) {
    for (var i = count - 1; i >= 0; i--) {
      bit((v >> i) & 1);
    }
  }

  void bitsReversed(int v, int count) {
    for (var i = 0; i < count; i++) {
      bit((v >> i) & 1);
    }
  }

  List<int> finish() {
    if (n > 0) out.add(cur << (8 - n));
    return out;
  }
}

/// Guitar-Pro-6-Datei (BCFZ) mit score.gpif darin, nur mit „rohen“ Blöcken gepackt.
Uint8List gpxFile(String xml) {
  const sector = 0x1000;
  final content = utf8.encode(xml);
  final blocks = (content.length + sector - 1) ~/ sector;
  final fs = Uint8List(sector * (2 + blocks));
  final v = ByteData.sublistView(fs);
  v.setInt32(sector, 2, Endian.little);
  final name = ascii.encode('score.gpif');
  fs.setRange(sector + 4, sector + 4 + name.length, name);
  v.setInt32(sector + 0x8C, content.length, Endian.little);
  for (var k = 0; k < blocks; k++) {
    v.setInt32(sector + 0x94 + 4 * k, 2 + k, Endian.little);
  }
  fs.setRange(sector * 2, sector * 2 + content.length, content);
  final raw = [...ascii.encode('BCFS'), ...fs];
  final bits = _Bits();
  for (var i = 0; i < raw.length; i += 3) {
    final chunk = raw.sublist(i, i + 3 > raw.length ? raw.length : i + 3);
    bits.bit(0);
    bits.bitsReversed(chunk.length, 2);
    for (final c in chunk) {
      bits.bits(c, 8);
    }
  }
  return Uint8List.fromList([
    ...ascii.encode('BCFZ'),
    ...(ByteData(4)..setInt32(0, raw.length, Endian.little)).buffer.asUint8List(),
    ...bits.finish(),
  ]);
}

const musicXml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <work><work-title>Kleines Lied</work-title></work>
  <identification><creator type="composer">Jemand</creator><rights>frei</rights></identification>
  <part-list><score-part id="P1"><part-name>Gitarre</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <key><fifths>1</fifths></key>
        <time><beats>3</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef>
        <staff-details><staff-lines>6</staff-lines>
          <staff-tuning line="1"><tuning-step>E</tuning-step><tuning-octave>2</tuning-octave></staff-tuning>
          <staff-tuning line="2"><tuning-step>A</tuning-step><tuning-octave>2</tuning-octave></staff-tuning>
          <staff-tuning line="3"><tuning-step>D</tuning-step><tuning-octave>3</tuning-octave></staff-tuning>
          <staff-tuning line="4"><tuning-step>G</tuning-step><tuning-octave>3</tuning-octave></staff-tuning>
          <staff-tuning line="5"><tuning-step>B</tuning-step><tuning-octave>3</tuning-octave></staff-tuning>
          <staff-tuning line="6"><tuning-step>E</tuning-step><tuning-octave>4</tuning-octave></staff-tuning>
        </staff-details>
      </attributes>
      <barline location="left"><repeat direction="forward"/></barline>
      <direction><direction-type><rehearsal>A</rehearsal></direction-type></direction>
      <direction placement="above"><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>72</per-minute></metronome></direction-type></direction>
      <harmony><root><root-step>G</root-step></root><kind>major</kind></harmony>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type>
        <lyric number="1"><syllabic>begin</syllabic><text>Lie</text></lyric>
        <notations><technical><string>1</string><fret>3</fret></technical></notations></note>
      <note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type>
        <lyric number="1"><syllabic>end</syllabic><text>be</text></lyric></note>
      <note><pitch><step>E</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type>
        <tie type="start"/><notations><tied type="start"/></notations></note>
    </measure>
    <measure number="2">
      <harmony><root><root-step>D</root-step></root><kind>dominant</kind><bass><bass-step>F</bass-step><bass-alter>1</bass-alter></bass></harmony>
      <note><pitch><step>E</step><octave>4</octave></pitch><duration>4</duration><voice>1</voice><type>half</type>
        <tie type="stop"/><notations><tied type="stop"/></notations></note>
      <note><rest/><duration>2</duration><voice>1</voice><type>quarter</type></note>
      <barline location="right"><bar-style>light-heavy</bar-style><repeat direction="backward" times="3"/></barline>
    </measure>
  </part>
</score-partwise>''';

/// Standard-MIDI-Datei: 3/4, Tempo 90, Melodie mit einer Note über den Taktstrich.
Uint8List midiFile() {
  List<int> vlq(int v) {
    final out = [v & 0x7F];
    v >>= 7;
    while (v > 0) {
      out.insert(0, 0x80 | (v & 0x7F));
      v >>= 7;
    }
    return out;
  }

  List<int> track(List<(int, List<int>)> events) {
    events.sort((a, b) => a.$1.compareTo(b.$1));
    final data = <int>[];
    var last = 0;
    for (final (t, ev) in events) {
      data
        ..addAll(vlq(t - last))
        ..addAll(ev);
      last = t;
    }
    data.addAll([0, 0xFF, 0x2F, 0]);
    return [...ascii.encode('MTrk'), ...(ByteData(4)..setUint32(0, data.length)).buffer.asUint8List(), ...data];
  }

  const d = 480;
  final meta = <(int, List<int>)>[
    (0, [0xFF, 0x03, 4, ...ascii.encode('Midi')]),
    (0, [0xFF, 0x51, 3, 0x0A, 0x2C, 0x2B]), // 666667 µs = 90 pro Minute
    (0, [0xFF, 0x58, 4, 3, 2, 24, 8]),
  ];
  final mel = <(int, List<int>)>[];
  for (final (s, l, k) in [
    (0, d, 67),
    (d, d, 69),
    (2 * d, 2 * d, 71),
    (4 * d, d ~/ 2, 72),
    (4 * d + d ~/ 2, d ~/ 2, 74),
    (5 * d, d, 76),
  ]) {
    mel
      ..add((s, [0x90, k, 90]))
      ..add((s + l, [0x80, k, 0]));
  }
  final head = [...ascii.encode('MThd'), 0, 0, 0, 6, 0, 1, 0, 2, d >> 8, d & 0xFF];
  return Uint8List.fromList([...head, ...track(meta), ...track(mel)]);
}

void main() {
  test('Guitar Pro 3: Angaben, Takte, Noten, Techniken', () {
    final s = GpReader.read(gp3File());
    expect(s.info.title, 'Drei');
    expect(s.info.artist, 'Test');
    expect(s.initialTempo!.bpm, 100);
    expect(s.masterBars.length, 2);
    expect(s.masterBars[0].repeatStart, isTrue);
    expect(s.masterBars[0].section!.label, 'Intro');
    expect(s.masterBars[1].repeatEnd, 2);
    final t = s.tracks.single;
    expect(t.name, 'Gitarre');
    expect(t.staff.tuning, [40, 45, 50, 55, 59, 64]);
    expect(t.transposeSemitones, 12);
    final beats = t.bars[0].voices.single.beats;
    expect(beats.length, 2);
    expect(beats[0].text, 'hallo');
    expect(beats[0].duration.value, NoteValue.half);
    expect(beats[0].notes.single.string, 5);
    expect(beats[0].notes.single.pitch.midi, 67);
    expect(beats[1].notes.single.string, 0);
    expect(beats[1].notes.single.hammerOrigin, isTrue);
    expect(t.bars[1].voices.single.beats.single.isRest, isTrue);
    expect(Engraver(s).layout().pages, isNotEmpty);
  });

  test('Guitar Pro 6: entpacken und lesen', () {
    final s = GpReader.read(gpxFile(gpif()));
    expect(s.info.title, 'Testlied');
    expect(s.masterBars.length, 2);
    expect(s.tracks.single.bars.first.voices.single.beats.length, 5);
  });

  test('MusicXML: Takte, Noten, Akkorde, Text, Bögen, Tabulatur', () {
    final s = GpReader.read(Uint8List.fromList(utf8.encode(musicXml)));
    expect(s.info.title, 'Kleines Lied');
    expect(s.info.artist, 'Jemand');
    expect(s.info.copyright, 'frei');
    expect(s.masterBars.length, 2);
    expect(s.masterBars[0].time, const TimeSignature(3, 4));
    expect(s.masterBars[0].key.fifths, 1);
    expect(s.masterBars[0].repeatStart, isTrue);
    expect(s.masterBars[0].section!.letter, 'A');
    expect(s.masterBars[1].repeatEnd, 3);
    expect(s.initialTempo!.bpm, 72);
    final t = s.tracks.single;
    expect(t.name, 'Gitarre');
    expect(t.transposeSemitones, 12);
    expect(t.bars[0].clef, Clef.treble8vb);
    expect(t.staff.tuning, [40, 45, 50, 55, 59, 64]);
    final b0 = t.bars[0].voices.single.beats;
    expect(b0.length, 3);
    expect(t.chords[b0[0].chordId]!.name, 'G');
    expect(b0[0].lyrics, ['Lie-']);
    expect(b0[1].lyrics, ['be']);
    // geschrieben G4, klingend G3; Saite 1 von oben = höchste = Index 5
    expect(b0[0].notes.single.written.toString(), 'G4');
    expect(b0[0].notes.single.pitch.toString(), 'G3');
    expect(b0[0].notes.single.string, 5);
    expect(b0[0].notes.single.fret, 3);
    expect(b0[1].notes.single.written.toString(), 'F#4');
    expect(b0[2].notes.single.tieOrigin, isTrue);
    final b1 = t.bars[1].voices.single.beats;
    expect(t.chords[b1[0].chordId]!.name, 'D7/F#');
    expect(b1[0].notes.single.tieDestination, isTrue);
    expect(b1[1].isRest, isTrue);
    expect(Engraver(s).layout().pages, isNotEmpty);
  });

  test('MusicXML gepackt (.mxl)', () {
    final container =
        '<?xml version="1.0"?><container><rootfiles><rootfile full-path="lied.musicxml"/></rootfiles></container>';
    final a = Archive()
      ..add(ArchiveFile.bytes('META-INF/container.xml', utf8.encode(container)))
      ..add(ArchiveFile.bytes('lied.musicxml', utf8.encode(musicXml)));
    final s = GpReader.read(Uint8List.fromList(ZipEncoder().encodeBytes(a)));
    expect(s.info.title, 'Kleines Lied');
  });

  test('MIDI: Takte, Tempo, eingerastete Notenwerte, Bogen über den Taktstrich', () {
    final s = GpReader.read(midiFile());
    expect(s.info.title, 'Midi');
    expect(s.initialTempo!.bpm, 90);
    expect(s.masterBars.first.time, const TimeSignature(3, 4));
    expect(s.masterBars.length, 2);
    final bar0 = s.tracks.single.bars[0].voices.single.beats;
    expect(bar0.map((b) => b.duration.value).toList(), [NoteValue.quarter, NoteValue.quarter, NoteValue.quarter]);
    expect(bar0.last.notes.single.pitch.midi, 71);
    expect(bar0.last.notes.single.tieOrigin, isTrue);
    final bar1 = s.tracks.single.bars[1].voices.single.beats;
    expect(bar1.first.notes.single.tieDestination, isTrue);
    expect(bar1[1].duration.value, NoteValue.eighth);
    expect(Engraver(s).layout().pages, isNotEmpty);
  });

  test('Guitar Pro (neu): Fingersätze, Flageolett-Art, weites Vibrato, Arpeggio, Ein-/Ausblenden, 8va', () {
    var xml = gpif();
    xml = xml.replaceFirst(
      '<Beat id="4"><Rhythm ref="3"/>',
      '<Beat id="4"><Rhythm ref="3"/><Arpeggio>Down</Arpeggio><Fadding>FadeIn</Fadding><Ottavia>8va</Ottavia>'
          '<Properties><Property name="Rasgueado"><Rasgueado>ii_1</Rasgueado></Property></Properties>',
    );
    xml = xml.replaceFirst(
      '<Note id="4"><Properties>',
      '<Note id="4"><Vibrato>Wide</Vibrato><LeftFingering>M</LeftFingering><RightFingering>I</RightFingering>'
          '<Properties><Property name="HarmonicType"><HType>Pinch</HType></Property>'
          '<Property name="Slapped"><Enable/></Property>',
    );
    final s = GpReader.read(zipped(xml));
    final beat = s.tracks[0].bars[1].voices[0].beats.first;
    expect((beat.arpeggio, beat.fade, beat.ottava, beat.rasgueado), (-1, 1, 1, true));
    final n = beat.notes.single;
    expect((n.wideVibrato, n.vibrato, n.leftFinger, n.rightFinger), (true, false, 2, 2));
    expect((n.harmonic, n.harmonicType, n.slap), (true, 2, true));
  });
}
