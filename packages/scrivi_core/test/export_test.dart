import 'dart:convert';
import 'dart:io';

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
}
