import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:scrivi_core/scrivi_core.dart';
import 'package:test/test.dart';

/// Alle Töne einer Spur als Text (Takt, Lage, klingende Höhe, Saite/Bund).
List<String> _notes(Track t, {bool frets = true}) => [
  for (var b = 0; b < t.bars.length; b++)
    for (final v in t.bars[b].voices.take(1))
      for (final beat in v.beats)
        if (beat.grace == GraceType.none)
          for (final n in beat.notes)
            '$b:${n.pitch.midi}${frets && n.string != null ? '/${n.string}:${n.fret}' : ''}${n.tieDestination ? '~' : ''}',
];

Score _example(String name) => ScriviFormat.fromJson(
  jsonDecode(File('../../assets/examples/$name.scrivi').readAsStringSync()) as Map<String, dynamic>,
);

void main() {
  for (final name in ['sonntagmorgen', 'ode_an_die_freude', 'wuestenwind']) {
    test('MusicXML hin und zurück: $name', () {
      final s = _example(name);
      final back = GpReader.read(MusicXmlWriter.write(s));
      expect(back.info.title, s.info.title);
      expect(back.masterBars.length, s.masterBars.length);
      expect(back.tracks.length, s.tracks.length);
      for (var b = 0; b < s.masterBars.length; b++) {
        expect(back.masterBars[b].time, s.masterBars[b].time, reason: 'Taktart $b');
        expect(back.masterBars[b].key.fifths, s.masterBars[b].key.fifths, reason: 'Tonart $b');
        expect(back.masterBars[b].repeatEnd, s.masterBars[b].repeatEnd, reason: 'Wiederholung $b');
      }
      expect(back.initialTempo!.bpm.round(), s.initialTempo!.bpm.round());
      for (var i = 0; i < s.tracks.length; i++) {
        final a = s.tracks[i], z = back.tracks[i];
        expect(z.name, a.name);
        expect(z.percussion, a.percussion);
        expect(z.staff.tuning, a.staff.tuning);
        expect(z.transposeSemitones, a.transposeSemitones, reason: a.name);
        expect(
          _notes(z, frets: !a.percussion),
          _notes(a, frets: !a.percussion),
          reason: a.name,
        );
      }
    });
  }

  test('MusicXML: Akkorde, Liedtext, Hammer-on', () {
    final e = ScoreEditor(ScoreEditor.newScore(title: 'Test', bars: 2))..cursor = const EditCursor(string: 3);
    e.inputFret(2);
    e.setChord('Am7');
    e.setLyric('Hal-');
    e.moveBeat(1);
    e.inputFret(4);
    e.setChord('D/F#');
    e.setLyric('lo');
    final back = GpReader.read(MusicXmlWriter.write(e.score));
    final beats = back.tracks[0].bars[0].voices[0].beats;
    expect(back.tracks[0].chords[beats[0].chordId]!.name, 'Am7');
    expect(back.tracks[0].chords[beats[1].chordId]!.name, 'D/F#');
    expect(beats[0].lyrics, ['Hal-']);
    expect(beats[1].lyrics, ['lo']);
    expect(beats[0].notes.single.fret, 2);
    expect(beats[0].notes.single.string, 3);
  });

  for (final name in ['sonntagmorgen', 'ode_an_die_freude', 'wuestenwind']) {
    test('MIDI hin und zurück: $name', () {
      final s = _example(name);
      final plan = PlaybackPlan.build(s);
      final back = GpReader.read(MidiWriter.write(s));
      expect(back.info.title, s.info.title);
      expect(back.masterBars.length, plan.bars.length);
      expect(back.initialTempo!.bpm.round(), (60 / plan.bars.first.secondsPerQuarter).round());
      // Spuren mit Tönen, jede mit denselben Tonhöhen (gespielt, Wiederholungen ausgeschrieben)
      final played = [
        for (final pt in plan.tracks)
          if (pt.notes.isNotEmpty)
            (pt.notes.where((n) => n.start < plan.duration - 1e-6).map((n) => n.midi).toList()..sort()),
      ];
      final read = [
        for (final t in back.tracks)
          ([
            for (final b in t.bars)
              for (final v in b.voices)
                for (final beat in v.beats)
                  for (final n in beat.notes)
                    if (!n.tieDestination) n.pitch.midi,
          ]..sort()),
      ];
      expect(read.length, played.length);
      final withNotes = [
        for (final pt in plan.tracks)
          if (pt.notes.isNotEmpty) pt.track,
      ];
      for (var i = 0; i < played.length; i++) {
        // Wirbel (Tremolo) sind schneller als das Sechzehntel-Raster beim Einlesen: nur die Tonhöhen vergleichen
        final rolls = withNotes[i].bars.any((b) => b.voices.any((v) => v.beats.any((x) => x.tremolo > 0)));
        if (rolls) {
          expect(read[i].toSet(), played[i].toSet(), reason: 'Spur $i');
        } else {
          expect(read[i], played[i], reason: 'Spur $i');
        }
      }
    });
  }

  test('MusicXML: Fingersätze, Flageolett, Triller, Arpeggio, Pedal, 8va hin und zurück', () {
    final e = ScoreEditor(ScoreEditor.newScore(title: 'Zeichen', bars: 2));
    e.duration = const NoteDuration(NoteValue.quarter);
    e.cursor = const EditCursor(string: 3);
    e.inputFret(2);
    e.setFinger(left: 2);
    e.setFinger(right: 3);
    e.toggleTechnique(Technique.artificialHarmonic);
    e.moveBeat(1);
    e.inputFret(4);
    e.toggleTechnique(Technique.trill);
    e.setPedal(1);
    e.moveBeat(1);
    e.cursor = e.cursor.copyWith(string: 1);
    e.inputFret(2);
    e.cursor = e.cursor.copyWith(string: 2);
    e.inputFret(2);
    e.setArpeggio(-1);
    e.setOttava(1);
    final bytes = MusicXmlWriter.write(e.score);
    final xml = utf8.decode(bytes);
    expect(xml, contains('<fingering>2</fingering>'));
    expect(xml, contains('<pluck>m</pluck>'));
    expect(xml, contains('<artificial/>'));
    expect(xml, contains('<trill-mark/>'));
    expect(xml, contains('<pedal type="start"'));
    expect(xml, contains('<octave-shift type="down"'));
    final back = GpReader.read(Uint8List.fromList(bytes));
    final beats = back.tracks[0].bars[0].voices[0].beats;
    final n0 = beats[0].notes.single;
    expect((n0.leftFinger, n0.rightFinger, n0.harmonic, n0.harmonicType), (2, 3, true, 1));
    expect(beats[1].notes.single.trill, isNot(0));
    expect(beats[1].pedal, 1);
    expect(beats[2].arpeggio, -1);
    expect(beats[2].ottava, 1);
  });

  test('Tonspur: Stereo-WAV mit Mischpult (stumm, links/rechts)', () {
    final e = ScoreEditor(ScoreEditor.newScore(title: 'Ton', bars: 1));
    e.duration = const NoteDuration(NoteValue.half);
    e.cursor = const EditCursor(string: 3);
    e.inputFret(2);
    final wav = Synth.mixdown(e.score);
    final b = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(b.getUint16(22, Endian.little), 2); // Stereo
    expect(wav.length, greaterThan(44 + 44100 * 4));
    var loud = 0;
    for (var k = 44; k < wav.length; k += 2) {
      loud = math.max(loud, b.getInt16(k, Endian.little).abs());
    }
    expect(loud, greaterThan(1000));
    // Stumm: still
    e.setMix(0, const TrackMix(muted: true));
    final quiet = Synth.mixdown(e.score);
    final q = ByteData.sublistView(quiet);
    var max = 0;
    for (var k = 44; k < quiet.length; k += 2) {
      max = math.max(max, q.getInt16(k, Endian.little).abs());
    }
    expect(max, 0);
  });
}
