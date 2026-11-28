import 'dart:convert';
import 'dart:typed_data';

import '../model/chord_library.dart';
import '../model/fraction.dart';
import '../model/pitch.dart';
import '../model/score.dart';

/// Schreibt ein Stück als MusicXML (partwise, Version 4.0), zum Austausch mit
/// anderen Notenprogrammen.
///
/// Jede Spur wird ein Instrument. Geschrieben wird klingend (C-Partitur);
/// Oktav-Instrumente (Gitarre, Bass) wie üblich eine Oktave höher, Gitarren
/// mit 8er-Violinschlüssel. Saiteninstrumente bekommen Stimmung, Saite und Bund.
class MusicXmlWriter {
  MusicXmlWriter._(this.score);

  final Score score;
  final _out = StringBuffer();

  /// Einheiten pro Viertel (teilbar durch 3 für Triolen, reicht bis 128stel).
  static const divisions = 96;

  static Uint8List write(Score score) => Uint8List.fromList(utf8.encode(writeString(score)));

  static String writeString(Score score) {
    final w = MusicXmlWriter._(score);
    w._score();
    return w._out.toString();
  }

  // ───────────────────────── Hilfen ─────────────────────────

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  void _line(int indent, String s) => _out.writeln('${'  ' * indent}$s');

  void _el(int indent, String name, Object value, [String attrs = '']) =>
      _line(indent, '<$name$attrs>${_esc('$value')}</$name>');

  static int _dur(Fraction f) {
    final v = f * Fraction(divisions * 4);
    return (v.n / v.d).round();
  }

  static const _steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

  static String _type(NoteValue v) => switch (v) {
    NoteValue.doubleWhole => 'breve',
    NoteValue.whole => 'whole',
    NoteValue.half => 'half',
    NoteValue.quarter => 'quarter',
    NoteValue.eighth => 'eighth',
    NoteValue.sixteenth => '16th',
    NoteValue.thirtySecond => '32nd',
    NoteValue.sixtyFourth => '64th',
    NoteValue.hundredTwentyEighth => '128th',
  };

  // ───────────────────────── Aufbau ─────────────────────────

  void _score() {
    final info = score.info;
    _line(0, '<?xml version="1.0" encoding="UTF-8" standalone="no"?>');
    _line(
      0,
      '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">',
    );
    _line(0, '<score-partwise version="4.0">');
    if (info.title.isNotEmpty) {
      _line(1, '<work>');
      _el(2, 'work-title', info.title);
      _line(1, '</work>');
    }
    _line(1, '<identification>');
    if (info.artist.isNotEmpty) _el(2, 'creator', info.artist, ' type="composer"');
    if (info.words.isNotEmpty) _el(2, 'creator', info.words, ' type="lyricist"');
    if (info.copyright.isNotEmpty) _el(2, 'rights', info.copyright);
    _line(2, '<encoding>');
    _el(3, 'software', 'Scrivi');
    _line(2, '</encoding>');
    _line(1, '</identification>');
    _line(1, '<part-list>');
    for (var i = 0; i < score.tracks.length; i++) {
      final t = score.tracks[i];
      final id = 'P${i + 1}';
      _line(2, '<score-part id="$id">');
      _el(3, 'part-name', t.name.isEmpty ? 'Spur ${i + 1}' : t.name);
      if (t.percussion) {
        for (final k in _drumKeys(t)) {
          _line(3, '<score-instrument id="$id-I$k">');
          _el(4, 'instrument-name', 'Drum $k');
          _line(3, '</score-instrument>');
        }
        for (final k in _drumKeys(t)) {
          _line(3, '<midi-instrument id="$id-I$k">');
          _el(4, 'midi-channel', 10);
          _el(4, 'midi-unpitched', k + 1);
          _line(3, '</midi-instrument>');
        }
      } else {
        _line(3, '<score-instrument id="$id-I1">');
        _el(4, 'instrument-name', t.name.isEmpty ? 'Instrument' : t.name);
        _line(3, '</score-instrument>');
        _line(3, '<midi-instrument id="$id-I1">');
        _el(4, 'midi-channel', (i % 15) + (i % 15 >= 9 ? 2 : 1));
        if (t.program >= 0) _el(4, 'midi-program', t.program + 1);
        _line(3, '</midi-instrument>');
      }
      _line(2, '</score-part>');
    }
    _line(1, '</part-list>');
    for (var i = 0; i < score.tracks.length; i++) {
      _part(i);
    }
    _line(0, '</score-partwise>');
  }

  static List<int> _drumKeys(Track t) {
    final keys = <int>{};
    for (final b in t.bars) {
      for (final v in b.voices) {
        for (final beat in v.beats) {
          for (final n in beat.notes) {
            keys.add(n.pitch.midi);
          }
        }
      }
    }
    return keys.toList()..sort();
  }

  void _part(int ti) {
    final t = score.tracks[ti];
    _line(1, '<part id="P${ti + 1}">');
    _ottava = 0;
    KeySignature? prevKey;
    TimeSignature? prevTime;
    Clef? prevClef;
    for (var b = 0; b < score.masterBars.length; b++) {
      final mb = score.masterBars[b];
      final bar = b < t.bars.length ? t.bars[b] : null;
      final clef = bar?.clef ?? prevClef ?? Clef.treble;
      _line(2, '<measure number="${b + 1}">');
      // Wiederholungsanfang und Häuser links
      if (mb.repeatStart || (mb.endings.isNotEmpty && (b == 0 || score.masterBars[b - 1].endings != mb.endings))) {
        _line(3, '<barline location="left">');
        if (mb.repeatStart) _el(4, 'bar-style', 'heavy-light');
        if (mb.endings.isNotEmpty && (b == 0 || score.masterBars[b - 1].endings != mb.endings)) {
          final nums = (mb.endings.toList()..sort()).join(', ');
          _line(4, '<ending number="$nums" type="start"/>');
        }
        if (mb.repeatStart) _line(4, '<repeat direction="forward"/>');
        _line(3, '</barline>');
      }
      // Angaben am Taktanfang, wenn sie sich ändern
      if (b == 0 || mb.key != prevKey || mb.time != prevTime || clef != prevClef) {
        _line(3, '<attributes>');
        if (b == 0) _el(4, 'divisions', divisions);
        if (b == 0 || mb.key != prevKey) {
          _line(4, '<key>');
          _el(5, 'fifths', mb.key.fifths);
          _el(5, 'mode', mb.key.minor ? 'minor' : 'major');
          _line(4, '</key>');
        }
        if (b == 0 || mb.time != prevTime) {
          _line(4, mb.time.common ? '<time symbol="${mb.time.beats == 2 ? 'cut' : 'common'}">' : '<time>');
          _el(5, 'beats', mb.time.beats);
          _el(5, 'beat-type', mb.time.beatType);
          _line(4, '</time>');
        }
        if (b == 0 || clef != prevClef) _clef(clef);
        if (b == 0) {
          // Oktav-Instrumente ohne 8er-Schlüssel (z. B. Bass): Transposition angeben
          if (t.transposeSemitones % 12 == 0 && t.transposeSemitones != 0 && clef != Clef.treble8vb) {
            _line(4, '<transpose>');
            _el(5, 'diatonic', 0);
            _el(5, 'chromatic', 0);
            _el(5, 'octave-change', -t.transposeSemitones ~/ 12);
            _line(4, '</transpose>');
          }
          if (t.staff.isStringed) {
            _line(4, '<staff-details>');
            final tuning = t.staff.tuning;
            for (var s = 0; s < tuning.length; s++) {
              // Linien von unten gezählt: Linie 1 = tiefste Saite
              final p = Pitch.fromMidi(tuning[s]);
              _line(5, '<staff-tuning line="${s + 1}">');
              _el(6, 'tuning-step', _steps[p.step]);
              if (p.alter != 0) _el(6, 'tuning-alter', p.alter);
              _el(6, 'tuning-octave', p.octave);
              _line(5, '</staff-tuning>');
            }
            if (t.staff.capo > 0) _el(5, 'capo', t.staff.capo);
            _line(4, '</staff-details>');
          }
        }
        _line(3, '</attributes>');
      }
      prevKey = mb.key;
      prevTime = mb.time;
      prevClef = clef;
      // Formteil, Tempo, Swing
      final section = mb.section;
      if (section != null && section.label.isNotEmpty) {
        _direction('<rehearsal>${_esc(section.label)}</rehearsal>');
      }
      for (final tm in score.tempos.where((x) => x.bar == b)) {
        _line(3, '<direction placement="above">');
        _line(4, '<direction-type>');
        _line(5, '<metronome>');
        _el(6, 'beat-unit', _type(tm.unit));
        if (tm.dotted) _line(6, '<beat-unit-dot/>');
        _el(6, 'per-minute', tm.bpm.round());
        _line(5, '</metronome>');
        _line(4, '</direction-type>');
        final quarters = tm.bpm * (tm.unit.length.toDouble() * 4) * (tm.dotted ? 1.5 : 1);
        _line(4, '<sound tempo="${quarters.toStringAsFixed(2)}"/>');
        _line(3, '</direction>');
      }
      if (mb.swing != (b > 0 && score.masterBars[b - 1].swing)) {
        _direction('<words>${mb.swing ? 'Swing' : 'Straight'}</words>');
      }
      // Stimmen
      final voices = bar == null ? const <Voice>[] : bar.voices.take(bar.shownVoiceCount).toList();
      final len = _dur(mb.time.length);
      if (voices.isEmpty) {
        _line(3, '<note>');
        _line(4, '<rest measure="yes"/>');
        _el(4, 'duration', len);
        _el(4, 'voice', 1);
        _line(3, '</note>');
      }
      for (var v = 0; v < voices.length; v++) {
        if (v > 0) {
          _line(3, '<backup>');
          _el(4, 'duration', len);
          _line(3, '</backup>');
        }
        var used = 0;
        for (final beat in voices[v].beats) {
          used += _beat(t, beat, v + 1, mb);
        }
        // Lücke am Ende der Stimme auffüllen, damit die nächste Stimme passt
        if (used < len && v < voices.length - 1) {
          _line(3, '<forward>');
          _el(4, 'duration', len - used);
          _line(3, '</forward>');
        }
      }
      // Wiederholungsende, Häuser, Doppelstrich rechts
      final last = b == score.masterBars.length - 1;
      final endingStops = mb.endings.isNotEmpty && (last || score.masterBars[b + 1].endings != mb.endings);
      if (mb.hasRepeatEnd || endingStops || mb.doubleBar || last) {
        _line(3, '<barline location="right">');
        _el(4, 'bar-style', mb.hasRepeatEnd || last ? 'light-heavy' : (mb.doubleBar ? 'light-light' : 'regular'));
        if (endingStops) {
          final nums = (mb.endings.toList()..sort()).join(', ');
          _line(4, '<ending number="$nums" type="${mb.hasRepeatEnd ? 'stop' : 'discontinue'}"/>');
        }
        if (mb.hasRepeatEnd) _line(4, '<repeat direction="backward" times="${mb.repeatEnd}"/>');
        _line(3, '</barline>');
      }
      _line(2, '</measure>');
    }
    _line(1, '</part>');
  }

  void _clef(Clef c) {
    _line(4, '<clef>');
    switch (c) {
      case Clef.treble:
        _el(5, 'sign', 'G');
        _el(5, 'line', 2);
      case Clef.treble8vb:
        _el(5, 'sign', 'G');
        _el(5, 'line', 2);
        _el(5, 'clef-octave-change', -1);
      case Clef.bass:
        _el(5, 'sign', 'F');
        _el(5, 'line', 4);
      case Clef.alto:
        _el(5, 'sign', 'C');
        _el(5, 'line', 3);
      case Clef.tenor:
        _el(5, 'sign', 'C');
        _el(5, 'line', 4);
      case Clef.neutral:
        _el(5, 'sign', 'percussion');
    }
    _line(4, '</clef>');
  }

  /// Oktavierung der ersten Stimme bis hierher (für Anfang und Ende der Linie).
  int _ottava = 0;

  void _direction(String content) {
    _line(3, '<direction placement="above">');
    _line(4, '<direction-type>');
    _line(5, content);
    _line(4, '</direction-type>');
    _line(3, '</direction>');
  }

  /// Ein Schlag (Note, Akkord oder Pause). Gibt die Dauer zurück.
  int _beat(Track t, Beat beat, int voice, MasterBar mb) {
    final grace = beat.grace != GraceType.none;
    final dur = grace ? 0 : _dur(beat.duration.length);
    if (voice == 1) {
      final id = beat.chordId;
      final chord = id == null ? null : t.chords[id];
      if (chord != null) _harmony(chord.name);
      if (beat.text != null && beat.text!.trim().isNotEmpty) {
        _direction('<words>${_esc(beat.text!)}</words>');
      }
      if (beat.pedal != 0) {
        final types = switch (beat.pedal) {
          1 => ['start'],
          2 => ['stop'],
          _ => ['change'],
        };
        for (final ty in types) {
          _line(3, '<direction placement="below">');
          _line(4, '<direction-type>');
          _line(5, '<pedal type="$ty" line="no"/>');
          _line(4, '</direction-type>');
          _line(3, '</direction>');
        }
      }
      if (beat.grace == GraceType.none && beat.ottava != _ottava) {
        if (_ottava != 0) _direction('<octave-shift type="stop" size="${_ottava.abs() == 2 ? 15 : 8}"/>');
        if (beat.ottava != 0) {
          _direction(
            '<octave-shift type="${beat.ottava > 0 ? 'down' : 'up'}" size="${beat.ottava.abs() == 2 ? 15 : 8}"/>',
          );
        }
        _ottava = beat.ottava;
      }
      final dyn = beat.dynamic;
      if (dyn != null) {
        _line(3, '<direction placement="below">');
        _line(4, '<direction-type>');
        _line(5, '<dynamics><${dyn.name}/></dynamics>');
        _line(4, '</direction-type>');
        _line(3, '</direction>');
      }
    }
    final notes = beat.notes;
    if (notes.isEmpty) {
      if (grace) return 0;
      _line(3, '<note>');
      _line(4, '<rest/>');
      _el(4, 'duration', dur);
      _el(4, 'voice', voice);
      _el(4, 'type', _type(beat.duration.value));
      for (var d = 0; d < beat.duration.dots; d++) {
        _line(4, '<dot/>');
      }
      _timeMod(beat);
      if (beat.fermata) _line(4, '<notations><fermata/></notations>');
      _line(3, '</note>');
      return dur;
    }
    for (var k = 0; k < notes.length; k++) {
      final n = notes[k];
      _line(3, '<note>');
      if (grace) _line(4, beat.grace == GraceType.beforeBeat ? '<grace slash="yes"/>' : '<grace/>');
      if (k > 0) _line(4, '<chord/>');
      if (t.percussion) {
        final (step, octave) = _drumDisplay(n.pitch.midi);
        _line(4, '<unpitched>');
        _el(5, 'display-step', _steps[step]);
        _el(5, 'display-octave', octave);
        _line(4, '</unpitched>');
      } else {
        final p = n.shownFor(t.transposeSemitones);
        _line(4, '<pitch>');
        _el(5, 'step', _steps[p.step]);
        if (p.alter != 0) _el(5, 'alter', p.alter);
        _el(5, 'octave', p.octave);
        _line(4, '</pitch>');
      }
      if (!grace) _el(4, 'duration', dur);
      if (n.tieDestination) _line(4, '<tie type="stop"/>');
      if (n.tieOrigin) _line(4, '<tie type="start"/>');
      if (t.percussion) _line(4, '<instrument id="P${score.tracks.indexOf(t) + 1}-I${n.pitch.midi}"/>');
      _el(4, 'voice', voice);
      _el(4, 'type', _type(beat.duration.value));
      for (var d = 0; d < beat.duration.dots; d++) {
        _line(4, '<dot/>');
      }
      if (n.courtesy && !t.percussion) {
        final p = n.shownFor(t.transposeSemitones);
        _line(4, '<accidental parentheses="yes">${_accidentalName(p.alter)}</accidental>');
      }
      _timeMod(beat);
      if (n.dead) _el(4, 'notehead', 'x');
      _notations(t, beat, n, k == 0);
      if (k == 0 && voice == 1) {
        for (var l = 0; l < beat.lyrics.length; l++) {
          _lyric(l + 1, beat.lyrics[l]);
        }
      }
      _line(3, '</note>');
    }
    return dur;
  }

  static String _accidentalName(int alter) => switch (alter) {
    2 => 'double-sharp',
    1 => 'sharp',
    -1 => 'flat',
    -2 => 'flat-flat',
    _ => 'natural',
  };

  void _timeMod(Beat beat) {
    final tu = beat.duration.tuplet;
    if (tu == null) return;
    _line(4, '<time-modification>');
    _el(5, 'actual-notes', tu.actual);
    _el(5, 'normal-notes', tu.normal);
    _line(4, '</time-modification>');
  }

  void _notations(Track t, Beat beat, Note n, bool first) {
    final parts = <String>[];
    if (n.tieDestination) parts.add('<tied type="stop"/>');
    if (n.tieOrigin) parts.add('<tied type="start"/>');
    if (first && beat.fermata) parts.add('<fermata/>');
    if (n.slide & 3 != 0) parts.add('<slide type="start"/>');
    if (beat.arpeggio != 0) parts.add(beat.arpeggio < 0 ? '<arpeggiate direction="down"/>' : '<arpeggiate/>');
    final tech = <String>[];
    if (first && beat.pickStroke > 0) tech.add('<down-bow/>');
    if (first && beat.pickStroke < 0) tech.add('<up-bow/>');
    if (n.hammerOrigin) tech.add('<hammer-on type="start">H</hammer-on>');
    if (n.harmonic) {
      tech.add(n.harmonicType == 0 ? '<harmonic><natural/></harmonic>' : '<harmonic><artificial/></harmonic>');
    }
    if (n.tapped) tech.add('<tap/>');
    if (n.leftFinger != 0) tech.add('<fingering>${n.leftFinger == 5 ? 0 : n.leftFinger}</fingering>');
    if (n.rightFinger != 0) tech.add('<pluck>${const ['', 'p', 'i', 'm', 'a', 'c'][n.rightFinger]}</pluck>');
    final bend = n.bend;
    if (bend != null && bend.maxSemitones > 0) {
      tech.add(
        '<bend><bend-alter>${bend.maxSemitones}</bend-alter>${bend.preBent ? '<pre-bend/>' : ''}${bend.releases ? '<release/>' : ''}</bend>',
      );
    }
    if (n.string != null && n.fret != null && t.staff.isStringed) {
      tech.add('<string>${t.staff.stringCount - n.string!}</string>');
      tech.add('<fret>${n.fret}</fret>');
    }
    if (tech.isNotEmpty) parts.add('<technical>${tech.join()}</technical>');
    final arts = <String>[];
    if (n.accent & 1 != 0) arts.add('<staccato/>');
    if (n.accent & 8 != 0) arts.add('<accent/>');
    if (n.accent & 4 != 0) arts.add('<strong-accent/>');
    if (n.accent & 16 != 0) arts.add('<tenuto/>');
    if (arts.isNotEmpty) parts.add('<articulations>${arts.join()}</articulations>');
    final orn = <String>[
      if (n.trill != 0) '<trill-mark/>',
      if ((n.vibrato || n.wideVibrato) && n.trill == 0) '<wavy-line type="start"/>',
      if (first && beat.tremolo > 0) '<tremolo type="single">${beat.tremolo}</tremolo>',
    ];
    if (orn.isNotEmpty) parts.add('<ornaments>${orn.join()}</ornaments>');
    if (parts.isEmpty) return;
    _line(4, '<notations>${parts.join()}</notations>');
  }

  void _lyric(int number, String text) {
    if (text.isEmpty) return;
    final hyphen = text.endsWith('-');
    final t = hyphen ? text.substring(0, text.length - 1) : text;
    _line(4, '<lyric number="$number">');
    _el(5, 'syllabic', hyphen ? 'begin' : 'single');
    _el(5, 'text', t);
    _line(4, '</lyric>');
  }

  /// Akkordsymbol: Grundton, Art und Bassnote.
  void _harmony(String name) {
    final c = ChordLibrary.parse(name);
    const roots = [(0, 0), (0, 1), (1, 0), (2, -1), (2, 0), (3, 0), (3, 1), (4, 0), (5, -1), (5, 0), (6, -1), (6, 0)];
    if (c == null) {
      // Unbekannte Art: als Text
      _direction('<words>${_esc(name)}</words>');
      return;
    }
    final kind = switch (c.quality) {
      'm' => 'minor',
      '7' => 'dominant',
      'm7' => 'minor-seventh',
      'maj7' => 'major-seventh',
      'sus4' => 'suspended-fourth',
      'sus2' => 'suspended-second',
      '5' => 'power',
      'dim' => 'diminished',
      'dim7' => 'diminished-seventh',
      'm7b5' => 'half-diminished',
      'aug' => 'augmented',
      '6' => 'major-sixth',
      'm6' => 'minor-sixth',
      '9' => 'dominant-ninth',
      'm9' => 'minor-ninth',
      'maj9' => 'major-ninth',
      _ => 'major',
    };
    // Der Name, wie er geschrieben wurde, als Text der Art
    final slash = name.indexOf('/');
    final rootLen = name.length > 1 && '#b♯♭'.contains(name[1]) ? 2 : 1;
    final suffix = (slash > 0 ? name.substring(0, slash) : name).substring(rootLen);
    final (rs, ra) = roots[c.root];
    _line(3, '<harmony>');
    _line(4, '<root>');
    _el(5, 'root-step', _steps[rs]);
    if (ra != 0) _el(5, 'root-alter', ra);
    _line(4, '</root>');
    _el(4, 'kind', kind, ' text="${_esc(suffix)}"');
    final bass = c.bass;
    if (bass != null) {
      final (bs, ba) = roots[bass];
      _line(4, '<bass>');
      _el(5, 'bass-step', _steps[bs]);
      if (ba != 0) _el(5, 'bass-alter', ba);
      _line(4, '</bass>');
    }
    _line(3, '</harmony>');
  }

  /// Lage im Schlagzeug-System (Stammton, Oktave) wie im Notensatz.
  static (int, int) _drumDisplay(int key) => switch (key) {
    35 || 36 => (3, 4), // F4 Bassdrum
    38 || 40 || 37 || 39 => (0, 5), // C5 Snare
    41 => (4, 4),
    43 => (5, 4),
    45 || 47 => (1, 5),
    48 || 50 => (2, 5),
    44 => (1, 4),
    49 || 57 || 52 || 55 => (5, 5),
    51 || 59 || 53 => (3, 5),
    _ => (4, 5), // G5 Hi-Hat und Rest
  };
}
