import 'dart:convert';
import 'dart:math' as math;

import '../io/scrivi_format.dart';
import '../model/fraction.dart';
import '../model/pitch.dart';
import '../model/chord_library.dart';
import '../model/score.dart';
import 'patterns.dart';

/// Stelle, an der geschrieben wird: Takt, Schlag (in Stimme 1) und Saite.
class EditCursor {
  const EditCursor({this.bar = 0, this.beat = 0, this.string = 0});
  final int bar;
  final int beat;

  /// Saite (0 = tiefste) für die Eingabe in der Tabulatur.
  final int string;

  EditCursor copyWith({int? bar, int? beat, int? string}) =>
      EditCursor(bar: bar ?? this.bar, beat: beat ?? this.beat, string: string ?? this.string);

  bool before(EditCursor o) => bar < o.bar || (bar == o.bar && beat < o.beat);

  @override
  bool operator ==(Object other) =>
      other is EditCursor && other.bar == bar && other.beat == beat && other.string == string;

  @override
  int get hashCode => Object.hash(bar, beat, string);
}

/// Spieltechniken zum Ein- und Ausschalten.
enum Technique {
  palmMute,
  letRing,
  dead,
  ghost,
  vibrato,
  harmonic,
  hammer,
  slide,
  bend,
  bendHalf,
  accent,
  staccato,
  tenuto,
  marcato,
  tapping,
}

/// Bearbeitet ein Stück: Cursor, Eingabe, Takte, Rückgängig.
///
/// Geschrieben wird im Überschreib-Modus: Ein Ton ersetzt, was an seiner Stelle
/// stand; was übrig bleibt, wird mit Pausen gefüllt. So ist jeder Takt immer
/// genau voll. Geschrieben wird in Stimme 1 der gewählten Spur.
///
/// Rückgängig: Vor jeder Änderung wird das ganze Stück als Text gemerkt
/// (wie es in der Datei steht). Einfach und sicher, auch bei grossen Änderungen.
class ScoreEditor {
  ScoreEditor(Score score, {this.track = 0}) : _score = score {
    _clampCursor();
  }

  Score _score;
  Score get score => _score;

  /// Spur, in der geschrieben wird.
  int track;

  EditCursor cursor = const EditCursor();

  /// Anfang der Auswahl (null = keine Auswahl).
  EditCursor? anchor;

  /// Notenwert für neue Töne.
  NoteDuration duration = const NoteDuration(NoteValue.quarter);

  /// Zählt jede Änderung am Stück (für Speichern und Neusetzen).
  int revision = 0;

  final _undo = <String>[];
  final _redo = <String>[];
  static const _maxUndo = 200;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Track get _track => _score.tracks[track];
  bool get stringed => _track.staff.isStringed;

  // ───────────────────────── Rückgängig ─────────────────────────

  String _snapshot() => jsonEncode(ScriviFormat.toJson(_score));

  Score _restore(String s) => ScriviFormat.fromJson(jsonDecode(s) as Map<String, dynamic>);

  /// Vor jeder Änderung aufrufen.
  void _begin() {
    _undo.add(_snapshot());
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    _redo.clear();
  }

  void _done() {
    _normalize();
    _clampCursor();
    revision++;
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    _redo.add(_snapshot());
    _score = _restore(_undo.removeLast());
    _clampCursor();
    revision++;
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    _undo.add(_snapshot());
    _score = _restore(_redo.removeLast());
    _clampCursor();
    revision++;
    return true;
  }

  // ───────────────────────── Hilfen ─────────────────────────

  Fraction barLength(int bar) => _score.masterBars[bar].time.length;

  /// Schläge der Stimme 1 im Takt [bar] (bei Bedarf mit Pausen angelegt).
  List<Beat> beatsOf(int bar) {
    final b = _track.bars[bar];
    if (b.voices.isEmpty) b.voices.add(Voice(_rests(barLength(bar))));
    final v = b.voices.first.beats;
    if (v.isEmpty) v.addAll(_rests(barLength(bar)));
    return v;
  }

  /// Schlag unter dem Cursor (null, wenn der Takt leer ist).
  Beat? get currentBeat {
    final beats = beatsOf(cursor.bar);
    return cursor.beat < beats.length ? beats[cursor.beat] : null;
  }

  /// Beginn eines Schlags im Takt (ganze Noten).
  Fraction onsetOf(int bar, int beat) {
    var t = Fraction.zero;
    final beats = beatsOf(bar);
    for (var i = 0; i < beat && i < beats.length; i++) {
      if (beats[i].grace == GraceType.none) t = t + beats[i].duration.length;
    }
    return t;
  }

  /// Beginn des Schlags unter dem Cursor.
  Fraction get cursorOnset => onsetOf(cursor.bar, cursor.beat);

  /// Pausen, die zusammen [length] ergeben (möglichst wenige, auch punktiert).
  static List<Beat> _rests(Fraction length) => [for (final d in durationsFor(length)) Beat(duration: d)];

  /// Pausen ab der Stelle [start] im Takt: zuerst bis zum nächsten Schlag
  /// auffüllen, dann grössere Werte (so wie man Pausen liest).
  static List<Beat> _restsAt(Fraction start, Fraction length) {
    final out = <Beat>[];
    var t = start;
    final end = start + length;
    var guard = 0;
    bool on(Fraction pos, Fraction grid) => (pos / grid).d == 1;
    while (t < end && guard++ < 64) {
      NoteDuration? best;
      for (final v in NoteValue.values) {
        final plain = NoteDuration(v);
        if (plain.length <= end - t && on(t, plain.length) && (best == null || plain.length > best.length)) {
          best = plain;
        }
        final dotted = NoteDuration(v, dots: 1);
        if (dotted.length <= end - t && on(t, v.length.scale(2)) && (best == null || dotted.length > best.length)) {
          best = dotted;
        }
      }
      if (best == null) {
        out.addAll(_rests(end - t));
        break;
      }
      out.add(Beat(duration: best));
      t = t + best.length;
    }
    return out;
  }

  /// Notenwerte, die zusammen [length] ergeben (grösste zuerst).
  static List<NoteDuration> durationsFor(Fraction length) {
    final out = <NoteDuration>[];
    var rest = length;
    var guard = 0;
    while (rest > Fraction.zero && guard++ < 64) {
      NoteDuration? best;
      for (final v in NoteValue.values) {
        for (final dots in const [1, 0]) {
          final d = NoteDuration(v, dots: dots);
          if (d.length <= rest && (best == null || d.length > best.length)) best = d;
        }
      }
      if (best == null) break;
      out.add(best);
      rest = rest - best.length;
    }
    return out;
  }

  /// Grösster Notenwert, der in [space] passt (für zu lange Töne am Taktende).
  static NoteDuration _fit(NoteDuration want, Fraction space) {
    if (want.length <= space) return want;
    final ds = durationsFor(space);
    return ds.isEmpty ? want : ds.first;
  }

  /// Schläge von [from] bis [to] (ganze Noten) durch [insert] ersetzen. Ein
  /// Schlag, der über [to] hinausreicht, wird durch Pausen ergänzt. [from] muss
  /// ein Schlaganfang sein. Gibt den Index des ersten eingefügten Schlags zurück.
  int _replace(int bar, Fraction from, Fraction to, List<Beat> insert) {
    final beats = beatsOf(bar);
    var t = Fraction.zero;
    var first = -1;
    var last = -1;
    var end = Fraction.zero;
    for (var i = 0; i < beats.length; i++) {
      final b = beats[i];
      if (b.grace != GraceType.none) continue;
      final e = t + b.duration.length;
      if (t >= from && t < to) {
        if (first < 0) first = i;
        last = i;
        end = e;
      }
      t = e;
    }
    if (first < 0) {
      // Nichts zu ersetzen (Takt zu kurz): hinten anfügen
      beats.addAll(insert);
      return beats.length - insert.length;
    }
    // Vorschläge vor dem ersten ersetzten Schlag bleiben, die dazwischen gehen mit.
    beats.removeRange(first, last + 1);
    final fill = end > to ? _restsAt(to, end - to) : const <Beat>[];
    beats.insertAll(first, [...insert, ...fill]);
    return first;
  }

  void _clampCursor() {
    final n = _score.masterBars.length;
    final bar = cursor.bar.clamp(0, math.max(0, n - 1)).toInt();
    if (n == 0) {
      cursor = const EditCursor();
      return;
    }
    final beats = beatsOf(bar);
    final beat = cursor.beat.clamp(0, math.max(0, beats.length - 1)).toInt();
    final strings = math.max(1, _track.staff.stringCount);
    cursor = EditCursor(bar: bar, beat: beat, string: cursor.string.clamp(0, strings - 1).toInt());
    final a = anchor;
    if (a != null) {
      final ab = a.bar.clamp(0, n - 1).toInt();
      anchor = a.copyWith(bar: ab, beat: a.beat.clamp(0, math.max(0, beatsOf(ab).length - 1)));
    }
  }

  // ───────────────────────── Cursor ─────────────────────────

  /// Einen Schlag weiter (bzw. zurück); am Ende des Stücks kommt ein neuer Takt dazu.
  void moveBeat(int dir, {bool select = false}) {
    _selecting(select);
    var bar = cursor.bar, beat = cursor.beat + dir;
    if (beat >= beatsOf(bar).length) {
      if (bar + 1 >= _score.masterBars.length) {
        if (select) return;
        _begin();
        _insertBarsRaw(bar + 1, 1);
        _done();
      }
      bar++;
      beat = 0;
    } else if (beat < 0) {
      if (bar == 0) return;
      bar--;
      beat = beatsOf(bar).length - 1;
    }
    cursor = cursor.copyWith(bar: bar, beat: beat);
  }

  void moveBar(int dir, {bool select = false}) {
    _selecting(select);
    final bar = (cursor.bar + dir).clamp(0, _score.masterBars.length - 1);
    cursor = cursor.copyWith(bar: bar, beat: 0);
  }

  /// Saite wechseln: +1 = höhere Saite.
  void moveString(int dir) {
    if (!stringed) return;
    cursor = cursor.copyWith(string: (cursor.string + dir).clamp(0, _track.staff.stringCount - 1));
  }

  /// Cursor auf Takt [bar], an den Schlag, der die Stelle [position] (ganze Noten) enthält.
  void setCursor(int bar, double position, {int? string, bool select = false}) {
    _selecting(select);
    final beats = beatsOf(bar);
    var t = 0.0, best = 0;
    for (var i = 0; i < beats.length; i++) {
      if (beats[i].grace != GraceType.none) continue;
      final len = beats[i].duration.length.toDouble();
      if (position >= t - 1e-9) best = i;
      t += len;
      if (position < t) break;
    }
    cursor = EditCursor(bar: bar, beat: best, string: string ?? cursor.string);
    _clampCursor();
  }

  void _selecting(bool select) {
    if (select) {
      anchor ??= cursor;
    } else {
      anchor = null;
    }
  }

  /// Ausgewählter Bereich (Anfang, Ende), beide einschliesslich, oder null.
  (EditCursor, EditCursor)? get selection {
    final a = anchor;
    if (a == null) return null;
    return a.before(cursor) ? (a, cursor) : (cursor, a);
  }

  void selectAll() {
    anchor = const EditCursor();
    final last = _score.masterBars.length - 1;
    cursor = cursor.copyWith(bar: last, beat: beatsOf(last).length - 1);
  }

  /// Alle Schläge (Takt, Index) im Bereich, von vorne nach hinten.
  Iterable<(int, int)> _range((EditCursor, EditCursor) r) sync* {
    final (a, b) = r;
    for (var bar = a.bar; bar <= b.bar; bar++) {
      final n = beatsOf(bar).length;
      final from = bar == a.bar ? a.beat : 0;
      final to = bar == b.bar ? b.beat : n - 1;
      for (var i = from; i <= to && i < n; i++) {
        yield (bar, i);
      }
    }
  }

  /// Schläge, auf die sich ein Befehl bezieht: die Auswahl oder der Schlag unter dem Cursor.
  List<(int, int)> get _targets {
    final s = selection;
    return s == null ? [(cursor.bar, cursor.beat)] : _range(s).toList();
  }

  // ───────────────────────── Tonhöhen ─────────────────────────

  /// Ansicht „transponiert“: so viele Halbtöne zeigt die App die Spur
  /// zusätzlich höher (Instrument in B: 2). Eingaben werden zurückgerechnet.
  int viewShift = 0;

  /// Tonart, wie sie in der Ansicht erscheint.
  KeySignature _viewKey(int bar) => _score.masterBars[bar].key.transposed(viewShift);

  /// Klingende Tonhöhe aus der geschriebenen (wie sie in der Ansicht steht).
  Pitch _concert(Pitch written) {
    if (viewShift != 0) {
      return written.transposedBy(
        -_track.transposeSemitones - viewShift,
        fifths: _score.masterBars[cursor.bar].key.fifths,
      );
    }
    final t = _track.transposeSemitones;
    if (t % 12 == 0) return written.octaves(-t ~/ 12);
    return Pitch.fromMidi(written.midi - t, fifths: _score.masterBars[cursor.bar].key.fifths);
  }

  Pitch _writtenFor(Pitch concert, int fifths) {
    final t = _track.transposeSemitones;
    if (t % 12 == 0) return concert.octaves(t ~/ 12);
    return Pitch.fromMidi(concert.midi + t, fifths: fifths);
  }

  /// Saite und Bund für eine klingende Tonhöhe: möglichst nahe beim zuletzt
  /// gespielten Bund, sonst so tief wie möglich (bis Bund 12).
  (int, int)? _place(int midi, {int? preferString, int? nearFret, Set<int> taken = const {}}) {
    final st = _track.staff;
    if (!st.isStringed) return null;
    if (preferString != null && !taken.contains(preferString)) {
      // Die gewünschte Saite nur, wenn der Bund bequem liegt (nahe beim vorigen bzw. bis Bund 12)
      final f = midi - st.tuning[preferString] - st.capo;
      final comfortable = nearFret != null ? (f - nearFret).abs() <= 4 : f <= 12;
      if (f >= 0 && f <= st.fretCount && comfortable) return (preferString, f);
    }
    (int, int)? best;
    var bestScore = double.infinity;
    for (var s = 0; s < st.stringCount; s++) {
      if (taken.contains(s)) continue;
      final f = midi - st.tuning[s] - st.capo;
      if (f < 0 || f > st.fretCount) continue;
      final score = nearFret != null ? (f - nearFret).abs() + (f == 0 ? 0.5 : 0) : f + (f > 12 ? 20 : 0);
      if (score < bestScore) {
        bestScore = score.toDouble();
        best = (s, f);
      }
    }
    return best;
  }

  /// Letzter Ton vor dem Cursor (für Oktave und Lage).
  Note? _previousNote() {
    for (var bar = cursor.bar; bar >= 0; bar--) {
      final beats = beatsOf(bar);
      final from = bar == cursor.bar ? cursor.beat - 1 : beats.length - 1;
      for (var i = from; i >= 0; i--) {
        final n = beats[i].notes;
        if (n.isNotEmpty) return n.last;
      }
    }
    return null;
  }

  Note _noteForWritten(Pitch written, {int? string, Set<int> taken = const {}}) {
    final concert = _concert(written);
    final prev = _previousNote();
    final place = _place(concert.midi, preferString: string, nearFret: prev?.fret, taken: taken);
    return Note(pitch: concert, written: written == concert ? null : written, string: place?.$1, fret: place?.$2);
  }

  Note _noteForFret(int string, int fret) {
    final st = _track.staff;
    final midi = st.tuning[string] + st.capo + fret;
    final fifths = _score.masterBars[cursor.bar].key.fifths;
    final concert = Pitch.fromMidi(midi, fifths: fifths);
    final written = _writtenFor(concert, fifths);
    return Note(pitch: concert, written: written == concert ? null : written, string: string, fret: fret);
  }

  // ───────────────────────── Eingabe ─────────────────────────

  /// Am Cursor einen Schlag mit [notes] schreiben (Notenwert: [duration]).
  void _writeNotes(List<Note> notes) {
    final bar = cursor.bar;
    final from = cursorOnset;
    final d = _fit(duration, barLength(bar) - from);
    final old = currentBeat;
    final beat = Beat(duration: d, notes: notes, chordId: old?.chordId, text: old?.text, lyrics: old?.lyrics);
    final i = _replace(bar, from, from + d.length, [beat]);
    cursor = cursor.copyWith(beat: i);
  }

  /// Mikrofon: der gehörte (klingende) Ton [midi] mit dem gewählten Notenwert
  /// an den Cursor, Saite und Bund bequem nahe beim vorigen Ton; danach zum
  /// nächsten Schlag (am Ende kommt ein Takt dazu).
  void inputHeard(int midi) {
    if (_track.percussion || midi < 0 || midi > 127) return;
    final fifths = _score.masterBars[cursor.bar].key.fifths;
    _begin();
    final concert = Pitch.fromMidi(midi, fifths: fifths < 0 ? -1 : 1);
    final place = _place(midi, nearFret: _previousNote()?.fret);
    _writeNotes([Note(pitch: concert, string: place?.$1, fret: place?.$2)]);
    final placed = currentBeat?.notes.last.string;
    if (placed != null) cursor = cursor.copyWith(string: placed);
    _done();
    moveBeat(1);
  }

  /// Bundzahl auf der Saite des Cursors. Ist am Cursor schon ein Ton, kommt
  /// die Saite dazu (Akkord); sonst entsteht ein neuer Ton.
  void inputFret(int fret) {
    if (!stringed) return;
    final st = _track.staff;
    if (fret < 0 || fret > st.fretCount) return;
    _begin();
    final note = _noteForFret(cursor.string, fret);
    final b = currentBeat;
    if (b != null && !b.isRest && !b.slashed) {
      final notes = [
        for (final n in b.notes)
          if (n.string != cursor.string) n,
        note,
      ]..sort((x, y) => (x.string ?? 0).compareTo(y.string ?? 0));
      beatsOf(cursor.bar)[cursor.beat] = b.copyWith(notes: notes);
    } else {
      _writeNotes([note]);
    }
    _done();
  }

  /// Notenname (Stammton 0 = C … 6 = H). Die Oktave ist die nächste zum vorigen
  /// Ton, das Vorzeichen kommt aus der Tonart. [addToChord]: zum Akkord hinzufügen.
  void inputStep(int step, {bool addToChord = false}) {
    if (_track.percussion) return;
    _begin();
    final key = _viewKey(cursor.bar);
    final alter = key.alterFor(step);
    final prev = _previousNote();
    final shown = prev?.shownFor(_track.transposeSemitones);
    final ref = shown == null
        ? _middleOfStaff()
        : (viewShift == 0 ? shown : shown.transposedBy(viewShift, fifths: key.fifths));
    // Oktave so wählen, dass der Abstand zum vorigen Ton höchstens eine Quarte ist
    var best = Pitch(step, alter, ref.octave);
    for (final o in [ref.octave - 1, ref.octave, ref.octave + 1]) {
      final p = Pitch(step, alter, o);
      if ((p.diatonic - ref.diatonic).abs() < (best.diatonic - ref.diatonic).abs()) best = p;
    }
    _inputWritten(best, addToChord);
    _done();
  }

  /// Note an einer Stelle im Notensystem (mit dem Stift angetippt): geschriebener
  /// Stammton seit C0 gezählt, Vorzeichen aus der Tonart.
  void inputDiatonic(int diatonic, {bool addToChord = false}) {
    if (_track.percussion) return;
    _begin();
    final step = diatonic % 7;
    final alter = _viewKey(cursor.bar).alterFor(step);
    _inputWritten(Pitch(step, alter, diatonic ~/ 7), addToChord);
    _done();
  }

  /// Stift: Note an der Stelle [diatonic] (geschriebener Stammton seit C0, wie
  /// in der Ansicht). Auf einer Pause wird sie geschrieben, auf einem Schlag mit
  /// Noten kommt sie zum Akkord dazu; steht dort schon eine Note, bleibt alles,
  /// wie es ist (nur der Cursor). Gibt zurück, ob sich etwas geändert hat.
  bool penNote(int diatonic) {
    final b = currentBeat;
    if (_track.percussion || b == null) return false;
    if (!b.isRest && b.notes.any((n) => _viewDiatonic(n, cursor.bar) == diatonic)) return false;
    inputDiatonic(diatonic, addToChord: !b.isRest);
    return true;
  }

  /// Geschriebene Lage einer Note in der Ansicht (Stammton seit C0).
  int _viewDiatonic(Note n, int bar) {
    var p = n.shownFor(_track.transposeSemitones);
    if (viewShift != 0) p = p.transposedBy(viewShift, fifths: _score.masterBars[bar].key.fifths);
    return p.diatonic;
  }

  void _inputWritten(Pitch best, bool addToChord) {
    final b = currentBeat;
    if (addToChord && b != null && !b.isRest) {
      final taken = {for (final n in b.notes) ?n.string};
      final note = _noteForWritten(best, taken: taken);
      beatsOf(cursor.bar)[cursor.beat] = b.copyWith(notes: [...b.notes, note]);
    } else {
      _writeNotes([_noteForWritten(best, string: stringed ? cursor.string : null)]);
    }
    final placed = currentBeat?.notes.last.string;
    if (placed != null) cursor = cursor.copyWith(string: placed);
  }

  Pitch _middleOfStaff() => switch (_track.bars[cursor.bar].clef) {
    Clef.bass => const Pitch(1, 0, 3),
    Clef.alto => const Pitch(0, 0, 4),
    Clef.tenor => const Pitch(5, 0, 3),
    _ => const Pitch(6, 0, 4),
  };

  /// Pause am Cursor bzw. alle ausgewählten Schläge zu Pausen machen.
  void toRest() {
    _begin();
    for (final (bar, i) in _targets) {
      final beats = beatsOf(bar);
      final b = beats[i];
      if (stringed && selection == null && b.notes.length > 1 && b.notes.any((n) => n.string == cursor.string)) {
        // Nur den Ton auf der Saite des Cursors entfernen
        beats[i] = b.copyWith(
          notes: [
            for (final n in b.notes)
              if (n.string != cursor.string) n,
          ],
        );
      } else {
        beats[i] = Beat(duration: b.duration, chordId: b.chordId, text: b.text, lyrics: b.lyrics);
      }
    }
    _done();
  }

  /// Notenwert für die Eingabe; ändert auch den Schlag unter dem Cursor.
  void setDuration(NoteValue v) {
    duration = NoteDuration(v, dots: duration.dots, tuplet: duration.tuplet);
    _changeCurrentDuration(NoteDuration(v, dots: currentBeat?.duration.dots ?? 0));
  }

  /// Punkt ein/aus (Eingabe und Schlag unter dem Cursor).
  void toggleDot() {
    final b = currentBeat;
    final dots = (b?.duration.dots ?? duration.dots) > 0 ? 0 : 1;
    duration = NoteDuration(duration.value, dots: dots);
    if (b != null) _changeCurrentDuration(NoteDuration(b.duration.value, dots: dots));
  }

  /// Notenwert des Schlags unter dem Cursor ändern (überschreibt, was folgt).
  void _changeCurrentDuration(NoteDuration d) {
    final b = currentBeat;
    if (b == null || b.duration.tuplet != null) return;
    final bar = cursor.bar;
    final from = cursorOnset;
    final nd = _fit(d, barLength(bar) - from);
    if (nd.length == b.duration.length && nd.value == b.duration.value) return;
    _begin();
    final oldEnd = from + b.duration.length;
    final newEnd = from + nd.length;
    final i = _replace(bar, from, newEnd > oldEnd ? newEnd : oldEnd, [
      b.copyWith(duration: nd),
      if (newEnd < oldEnd) ..._restsAt(newEnd, oldEnd - newEnd),
    ]);
    cursor = cursor.copyWith(beat: i);
    _done();
  }

  /// Triole ein/aus: Aus einem Schlag werden drei Triolen-Werte im Raum von zwei.
  void toggleTriplet() {
    final b = currentBeat;
    if (b == null) return;
    final bar = cursor.bar;
    final beats = beatsOf(bar);
    _begin();
    if (b.duration.tuplet == null) {
      final v = b.duration.value;
      final from = cursorOnset;
      final span = v.length.scale(2);
      if (from + span > barLength(bar)) {
        _undo.removeLast();
        return;
      }
      const t = Tuplet(3, 2);
      final i = _replace(bar, from, from + span, [
        b.copyWith(duration: NoteDuration(v, tuplet: t)),
        Beat(duration: NoteDuration(v, tuplet: t)),
        Beat(duration: NoteDuration(v, tuplet: t)),
      ]);
      cursor = cursor.copyWith(beat: i);
    } else {
      // Ganze Triolen-Gruppe finden und durch normale Werte ersetzen
      final v = b.duration.value;
      final group = v.length.scale(2);
      var start = cursor.beat;
      var t = cursorOnset;
      // Gruppe beginnt dort, wo die Zeit ab Taktanfang ein Vielfaches der Gruppenlänge ist
      while (start > 0 && beats[start - 1].duration.tuplet != null) {
        final probe = t - beats[start - 1].duration.length;
        final ratio = probe / group;
        start--;
        t = probe;
        if (ratio.toDouble() == ratio.toDouble().roundToDouble()) break;
      }
      final first = beats[start];
      final i = _replace(bar, t, t + group, [
        Beat(duration: NoteDuration(v), notes: first.notes, chordId: first.chordId, text: first.text),
        Beat(duration: NoteDuration(v)),
      ]);
      cursor = cursor.copyWith(beat: i);
    }
    _done();
  }

  /// Haltebogen vom vorigen Schlag: Die Töne werden übernommen und gebunden.
  void toggleTie() {
    final b = currentBeat;
    if (b == null) return;
    _begin();
    final beats = beatsOf(cursor.bar);
    if (b.notes.isNotEmpty && b.notes.every((n) => n.tieDestination)) {
      beats[cursor.beat] = b.copyWith(notes: [for (final n in b.notes) n.copyWith(tieDestination: false)]);
    } else {
      final prev = _previousBeat(cursor.bar, cursor.beat);
      if (prev == null || prev.isRest) {
        _undo.removeLast();
        return;
      }
      beats[cursor.beat] = b.copyWith(
        notes: [
          for (final n in prev.notes)
            n.copyWith(tieDestination: true, tieOrigin: false, hammerOrigin: false, hammerDestination: false, slide: 0),
        ],
      );
    }
    _done();
  }

  Beat? _previousBeat(int bar, int beat) {
    if (beat > 0) return beatsOf(bar)[beat - 1];
    if (bar == 0) return null;
    final b = beatsOf(bar - 1);
    return b.isEmpty ? null : b.last;
  }

  /// Halbtöne höher/tiefer (Auswahl oder Schlag unter dem Cursor).
  void transposeSelection(int semitones) {
    _begin();
    for (final (bar, i) in _targets) {
      final beats = beatsOf(bar);
      final b = beats[i];
      if (b.isRest) continue;
      final fifths = _score.masterBars[bar].key.fifths;
      beats[i] = b.copyWith(notes: [for (final n in b.notes) _shift(n, semitones, fifths)]);
    }
    _done();
  }

  Note _shift(Note n, int semitones, int fifths) {
    final concert = Pitch.fromMidi(
      n.pitch.midi + semitones,
      fifths: fifths < 0 || semitones < 0 && fifths == 0 ? -1 : 1,
    );
    final written = _writtenFor(concert, fifths);
    var out = n.copyWith(pitch: concert, written: written, clearWritten: written == concert);
    if (n.string != null && stringed) {
      final place = _place(concert.midi, preferString: n.string);
      out = place == null ? out : out.copyWith(string: place.$1, fret: place.$2);
    }
    return out;
  }

  /// Technik an den Tönen am Cursor ein/aus (in der Tab: nur die Saite des Cursors, falls dort ein Ton ist).
  void toggleTechnique(Technique t) {
    final targets = _targets;
    _begin();
    var changed = false;
    for (final (bar, i) in targets) {
      final beats = beatsOf(bar);
      final b = beats[i];
      if (b.isRest) continue;
      final onString = selection == null && stringed && b.notes.any((n) => n.string == cursor.string);
      bool hit(Note n) => !onString || n.string == cursor.string;
      final sample = b.notes.firstWhere(hit);
      final on = !_has(sample, t);
      beats[i] = b.copyWith(notes: [for (final n in b.notes) hit(n) ? _set(n, t, on) : n]);
      changed = true;
    }
    if (!changed) {
      _undo.removeLast();
      return;
    }
    _done();
  }

  static bool _has(Note n, Technique t) => switch (t) {
    Technique.palmMute => n.palmMuted,
    Technique.letRing => n.letRing,
    Technique.dead => n.dead,
    Technique.ghost => n.ghost,
    Technique.vibrato => n.vibrato,
    Technique.harmonic => n.harmonic,
    Technique.hammer => n.hammerOrigin,
    Technique.slide => n.slide & 2 != 0,
    Technique.bend => n.bend != null && (n.bend!.maxSemitones - 2).abs() < 0.01,
    Technique.bendHalf => n.bend != null && (n.bend!.maxSemitones - 1).abs() < 0.01,
    Technique.accent => n.accent & 8 != 0,
    Technique.staccato => n.accent & 1 != 0,
    Technique.tenuto => n.accent & 16 != 0,
    Technique.marcato => n.accent & 4 != 0,
    Technique.tapping => n.tapped,
  };

  static Note _set(Note n, Technique t, bool on) => switch (t) {
    Technique.palmMute => n.copyWith(palmMuted: on),
    Technique.letRing => n.copyWith(letRing: on),
    Technique.dead => n.copyWith(dead: on),
    Technique.ghost => n.copyWith(ghost: on),
    Technique.vibrato => n.copyWith(vibrato: on),
    Technique.harmonic => n.copyWith(harmonic: on),
    Technique.hammer => n.copyWith(hammerOrigin: on),
    Technique.slide => n.copyWith(slide: on ? 2 : 0),
    Technique.bend =>
      on
          ? n.copyWith(bend: const Bend([BendPoint(0, 0), BendPoint(0.5, 2), BendPoint(1, 2)]))
          : n.copyWith(clearBend: true),
    Technique.bendHalf =>
      on
          ? n.copyWith(bend: const Bend([BendPoint(0, 0), BendPoint(0.5, 1), BendPoint(1, 1)]))
          : n.copyWith(clearBend: true),
    Technique.accent => n.copyWith(accent: on ? n.accent | 8 : n.accent & ~8),
    Technique.staccato => n.copyWith(accent: on ? n.accent | 1 : n.accent & ~1),
    Technique.tenuto => n.copyWith(accent: on ? n.accent | 16 : n.accent & ~16),
    Technique.marcato => n.copyWith(accent: on ? n.accent | 4 : n.accent & ~4),
    Technique.tapping => n.copyWith(tapped: on),
  };

  /// Gilt die Technik für den Ton am Cursor? (für die Anzeige der Knöpfe)
  bool hasTechnique(Technique t) {
    final b = currentBeat;
    if (b == null || b.isRest) return false;
    final n = b.notes.where((n) => !stringed || n.string == cursor.string).firstOrNull ?? b.notes.first;
    return _has(n, t);
  }

  // ───────────────────────── Akkorde, Text, Liedtext ─────────────────────────

  /// Akkordsymbol am Cursor setzen (leer = entfernen).
  void setChord(String name) {
    final b = currentBeat;
    if (b == null) return;
    _begin();
    final n = name.trim();
    final beats = beatsOf(cursor.bar);
    if (n.isEmpty) {
      beats[cursor.beat] = b.copyWith(clearChord: true);
    } else {
      final chords = _track.chords;
      var id = chords.entries.where((e) => e.value.name == n).map((e) => e.key).firstOrNull;
      if (id == null) {
        id = chords.isEmpty ? 0 : chords.keys.reduce(math.max) + 1;
        chords[id] = ChordDef(name: n);
      }
      beats[cursor.beat] = b.copyWith(chordId: id);
    }
    _done();
  }

  String chordAtCursor() {
    final id = currentBeat?.chordId;
    return id == null ? '' : (_track.chords[id]?.name ?? '');
  }

  /// Text über dem Schlag (leer = entfernen).
  void setText(String text) {
    final b = currentBeat;
    if (b == null) return;
    _begin();
    final t = text.trim();
    beatsOf(cursor.bar)[cursor.beat] = t.isEmpty ? b.copyWith(clearText: true) : b.copyWith(text: t);
    _done();
  }

  /// Liedtext-Silbe (Strophe [line]) am Cursor.
  void setLyric(String syllable, {int line = 0}) {
    final b = currentBeat;
    if (b == null) return;
    _begin();
    final lyrics = [...b.lyrics];
    while (lyrics.length <= line) {
      lyrics.add('');
    }
    lyrics[line] = syllable.trim();
    while (lyrics.isNotEmpty && lyrics.last.isEmpty) {
      lyrics.removeLast();
    }
    beatsOf(cursor.bar)[cursor.beat] = b.copyWith(lyrics: lyrics);
    _done();
  }

  /// Zum nächsten Schlag mit Ton (für die Liedtext-Eingabe).
  void nextNote() {
    var bar = cursor.bar, beat = cursor.beat + 1;
    while (bar < _score.masterBars.length) {
      final beats = beatsOf(bar);
      for (var i = beat; i < beats.length; i++) {
        if (!beats[i].isRest && !beats[i].notes.every((n) => n.tieDestination)) {
          cursor = cursor.copyWith(bar: bar, beat: i);
          anchor = null;
          return;
        }
      }
      bar++;
      beat = 0;
    }
  }

  /// Dynamik am Schlag des Cursors (null = entfernen).
  void setDynamic(Dynamic? d) {
    final b = currentBeat;
    if (b == null) return;
    _begin();
    beatsOf(cursor.bar)[cursor.beat] = d == null ? b.copyWith(clearDynamic: true) : b.copyWith(dynamic: d);
    _done();
  }

  /// Gabel (cresc./decresc.) für die Auswahl bzw. den Schlag am Cursor; gleiche Gabel = ausschalten.
  void toggleHairpin(Hairpin h) {
    final targets = _targets;
    if (targets.isEmpty) return;
    _begin();
    final (b0, i0) = targets.first;
    final off = beatsOf(b0)[i0].hairpin == h;
    for (final (bar, i) in targets) {
      final beats = beatsOf(bar);
      beats[i] = beats[i].copyWith(hairpin: off ? Hairpin.none : h);
    }
    _done();
  }

  /// Anschlag: 1 = abwärts, −1 = aufwärts, gleicher Wert = ausschalten.
  void togglePickStroke(int dir) {
    final b = currentBeat;
    if (b == null) return;
    _begin();
    beatsOf(cursor.bar)[cursor.beat] = b.copyWith(pickStroke: b.pickStroke == dir ? 0 : dir);
    _done();
  }

  void toggleFermata() {
    final b = currentBeat;
    if (b == null) return;
    _begin();
    beatsOf(cursor.bar)[cursor.beat] = b.copyWith(fermata: !b.fermata);
    _done();
  }

  // ───────────────────────── Takte ─────────────────────────

  void _insertBarsRaw(int at, int count) {
    final ref = _score.masterBars[(at - 1).clamp(0, _score.masterBars.length - 1)];
    for (var k = 0; k < count; k++) {
      _score.masterBars.insert(at, MasterBar(time: ref.time, key: ref.key, swing: ref.swing));
      for (final t in _score.tracks) {
        final clef = t.bars.isEmpty ? Clef.treble : t.bars[(at - 1).clamp(0, t.bars.length - 1)].clef;
        t.bars.insert(at, Bar(clef: clef, voices: [Voice(_rests(ref.time.length))]));
      }
    }
    for (var i = 0; i < _score.tempos.length; i++) {
      final m = _score.tempos[i];
      if (m.bar >= at && !(m.bar == 0 && at == 0)) _score.tempos[i] = _tempoAt(m, m.bar + count);
    }
    _dropLayoutHints();
  }

  static TempoMark _tempoAt(TempoMark m, int bar) =>
      TempoMark(bar: bar, position: m.position, bpm: m.bpm, unit: m.unit, dotted: m.dotted, visible: m.visible);

  /// Die Zeilenaufteilung aus der Datei passt nach Taktänderungen nicht mehr.
  void _dropLayoutHints() {
    for (var i = 0; i < _score.tracks.length; i++) {
      final t = _score.tracks[i];
      if (t.layoutHint == null) continue;
      _score.tracks[i] = Track(
        name: t.name,
        shortName: t.shortName,
        staff: t.staff,
        bars: t.bars,
        chords: t.chords,
        transposeSemitones: t.transposeSemitones,
        program: t.program,
        instrumentKey: t.instrumentKey,
        mix: t.mix,
      );
    }
  }

  /// [count] leere Takte vor (bzw. nach) dem Takt am Cursor einfügen.
  void insertBars({bool after = true, int count = 1}) {
    _begin();
    final at = after ? cursor.bar + 1 : cursor.bar;
    _insertBarsRaw(at, count);
    cursor = EditCursor(bar: at, beat: 0, string: cursor.string);
    anchor = null;
    _done();
  }

  /// Takte der Auswahl (bzw. den Takt am Cursor) löschen. Mindestens ein Takt bleibt.
  void deleteBars() {
    final s = selection;
    final from = s?.$1.bar ?? cursor.bar, to = s?.$2.bar ?? cursor.bar;
    final n = _score.masterBars.length;
    if (to - from + 1 >= n) {
      // Alles löschen hiesse: ein leerer Takt bleibt
      _begin();
      for (var b = 0; b < n; b++) {
        for (final t in _score.tracks) {
          t.bars[b] = Bar(clef: t.bars[b].clef, voices: [Voice(_rests(barLength(b)))]);
        }
      }
      _removeBars(1, n - 1);
      cursor = EditCursor(string: cursor.string);
      anchor = null;
      _done();
      return;
    }
    _begin();
    _removeBars(from, to);
    cursor = EditCursor(bar: math.min(from, _score.masterBars.length - 1), string: cursor.string);
    anchor = null;
    _done();
  }

  void _removeBars(int from, int to) {
    final count = to - from + 1;
    if (count <= 0) return;
    _score.masterBars.removeRange(from, to + 1);
    for (final t in _score.tracks) {
      if (from < t.bars.length) t.bars.removeRange(from, math.min(to + 1, t.bars.length));
    }
    final tempos = <TempoMark>[];
    for (final m in _score.tempos) {
      if (m.bar < from) {
        tempos.add(m);
      } else if (m.bar > to) {
        tempos.add(_tempoAt(m, m.bar - count));
      } else if (m.bar == from) {
        // Tempo im gelöschten Bereich gilt ab der Stelle weiter
        tempos.add(_tempoAt(m, math.min(from, _score.masterBars.length - 1)));
      }
    }
    _score.tempos
      ..clear()
      ..addAll(tempos);
    _dropLayoutHints();
  }

  /// Taktart ab dem Takt am Cursor (bis zum nächsten Wechsel).
  void setTimeSignature(TimeSignature ts) {
    _begin();
    final start = cursor.bar;
    final old = _score.masterBars[start].time;
    for (var b = start; b < _score.masterBars.length; b++) {
      final mb = _score.masterBars[b];
      if (b > start && mb.time != old) break;
      _score.masterBars[b] = mb.copyWith(time: ts);
      for (final t in _score.tracks) {
        if (b < t.bars.length) _refit(t.bars[b], ts.length);
      }
    }
    _done();
  }

  /// Inhalt eines Takts an eine neue Länge anpassen: kürzen bzw. mit Pausen füllen.
  static void _refit(Bar bar, Fraction length) {
    for (final v in bar.voices) {
      var t = Fraction.zero;
      final out = <Beat>[];
      for (final b in v.beats) {
        if (b.grace != GraceType.none) {
          out.add(b);
          continue;
        }
        if (t >= length) break;
        final room = length - t;
        if (b.duration.length <= room) {
          out.add(b);
          t = t + b.duration.length;
        } else {
          final d = _fit(b.duration, room);
          out.add(b.copyWith(duration: d));
          t = t + d.length;
        }
      }
      if (t < length) out.addAll(_restsAt(t, length - t));
      v.beats
        ..clear()
        ..addAll(out);
    }
  }

  /// Tonart ab dem Takt am Cursor (bis zum nächsten Wechsel).
  void setKey(KeySignature key) {
    _begin();
    final start = cursor.bar;
    final old = _score.masterBars[start].key;
    for (var b = start; b < _score.masterBars.length; b++) {
      final mb = _score.masterBars[b];
      if (b > start && mb.key != old) break;
      _score.masterBars[b] = mb.copyWith(key: key);
    }
    _done();
  }

  /// Tempo ab dem Takt am Cursor.
  void setTempo(double bpm) {
    _begin();
    final bar = cursor.bar;
    _score.tempos.removeWhere((t) => t.bar == bar && t.position == 0);
    _score.tempos.add(TempoMark(bar: bar, bpm: bpm));
    _score.tempos.sort((a, b) => a.bar.compareTo(b.bar));
    _done();
  }

  double get tempoAtCursor {
    double bpm = 120;
    for (final t in _score.tempos) {
      if (t.bar <= cursor.bar) bpm = t.bpm;
    }
    return bpm;
  }

  void toggleRepeatStart() {
    _begin();
    final mb = _score.masterBars[cursor.bar];
    _score.masterBars[cursor.bar] = mb.copyWith(repeatStart: !mb.repeatStart);
    _done();
  }

  /// Wiederholungsende: wie oft insgesamt gespielt wird (0 = keines).
  void setRepeatEnd(int times) {
    _begin();
    final mb = _score.masterBars[cursor.bar];
    _score.masterBars[cursor.bar] = mb.copyWith(repeatEnd: times < 2 ? 0 : times);
    _done();
  }

  void toggleDoubleBar() {
    _begin();
    final mb = _score.masterBars[cursor.bar];
    _score.masterBars[cursor.bar] = mb.copyWith(doubleBar: !mb.doubleBar);
    _done();
  }

  /// Häuser (1., 2. …) für den Takt am Cursor; leer = keine.
  void setEndings(Set<int> endings) {
    _begin();
    final mb = _score.masterBars[cursor.bar];
    _score.masterBars[cursor.bar] = mb.copyWith(endings: endings);
    _done();
  }

  /// Swing ein oder aus: für die ausgewählten Takte, sonst ab dem Takt am Cursor bis zum Schluss.
  void setSwing(bool on) {
    _begin();
    final s = selection;
    final from = s?.$1.bar ?? cursor.bar;
    final to = s?.$2.bar ?? _score.masterBars.length - 1;
    for (var b = from; b <= to; b++) {
      _score.masterBars[b] = _score.masterBars[b].copyWith(swing: on);
    }
    _done();
  }

  /// Formteil (z. B. „Refrain“) ab dem Takt am Cursor; leer = entfernen.
  void setSection(String label) {
    _begin();
    final mb = _score.masterBars[cursor.bar];
    final l = label.trim();
    _score.masterBars[cursor.bar] = l.isEmpty
        ? mb.copyWith(clearSection: true)
        : mb.copyWith(section: Section(text: l));
    _done();
  }

  /// Titel, Untertitel und Interpret.
  void setInfo({String? title, String? subtitle, String? artist}) {
    _begin();
    _score = _score.copyWith(
      info: _score.info.copyWith(title: title, subtitle: subtitle, artist: artist),
    );
    _done();
  }

  // ───────────────────────── Transponieren ─────────────────────────

  /// Das ganze Stück um [semitones] Halbtöne transponieren (Tonarten mit).
  void transposeAll(int semitones) {
    if (semitones == 0) return;
    _begin();
    for (var b = 0; b < _score.masterBars.length; b++) {
      final mb = _score.masterBars[b];
      var f = mb.key.fifths + 7 * semitones;
      f = ((f + 6) % 12 + 12) % 12 - 6; // in −6 … +5
      if (f == -6 && semitones > 0) f = 6;
      _score.masterBars[b] = mb.copyWith(key: KeySignature(f, minor: mb.key.minor));
    }
    final saved = track;
    for (var ti = 0; ti < _score.tracks.length; ti++) {
      final t = _score.tracks[ti];
      if (t.percussion) continue;
      track = ti;
      for (var b = 0; b < t.bars.length; b++) {
        final fifths = _score.masterBars[b].key.fifths;
        for (final v in t.bars[b].voices) {
          for (var i = 0; i < v.beats.length; i++) {
            final beat = v.beats[i];
            if (beat.isRest) continue;
            v.beats[i] = beat.copyWith(notes: [for (final n in beat.notes) _shiftSpelled(n, semitones, fifths)]);
          }
        }
      }
      // Akkordsymbole mit
      for (final e in t.chords.entries.toList()) {
        t.chords[e.key] = ChordDef(
          name: transposeChordName(e.value.name, semitones, _score.masterBars.first.key.fifths),
        );
      }
    }
    track = saved;
    _done();
  }

  Note _shiftSpelled(Note n, int semitones, int fifths) {
    final concert = Pitch.fromMidi(n.pitch.midi + semitones, fifths: fifths);
    final written = _writtenFor(concert, fifths);
    var out = n.copyWith(pitch: concert, written: written, clearWritten: written == concert);
    if (n.string != null && stringed) {
      final place = _place(concert.midi, preferString: n.string);
      out = place == null ? out : out.copyWith(string: place.$1, fret: place.$2);
    }
    return out;
  }

  /// Akkordname um [semitones] verschieben (Grundton und Bass), z. B. „D/F#“ → „E/G#“.
  static String transposeChordName(String name, int semitones, int fifths) {
    const sharps = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    const flats = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];
    String shift(String note) {
      const base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11, 'H': 11};
      var pc = base[note[0]]!;
      if (note.length > 1 && (note[1] == '#' || note[1] == '♯')) pc++;
      if (note.length > 1 && (note[1] == 'b' || note[1] == '♭')) pc--;
      pc = (pc + semitones) % 12;
      if (pc < 0) pc += 12;
      final out = (fifths < 0 ? flats : sharps)[pc];
      return note[0] == 'H' && out == 'B' ? 'H' : out;
    }

    return name.replaceAllMapped(RegExp(r'(^|/)([A-H][#b♯♭]?)'), (m) => '${m[1]}${shift(m[2]!)}');
  }

  // ───────────────────────── Kopieren und Einfügen ─────────────────────────

  /// Die ausgewählten Schläge (bzw. den Schlag am Cursor).
  List<Beat> copy() => [for (final (bar, i) in _targets) beatsOf(bar)[i]];

  /// Ausgewählte Schläge kopieren und zu Pausen machen.
  List<Beat> cut() {
    final c = copy();
    toRest();
    return c;
  }

  /// Schläge ab dem Cursor einsetzen (überschreibt; neue Takte am Ende nach Bedarf).
  void paste(List<Beat> beats) {
    if (beats.isEmpty) return;
    _begin();
    anchor = null;
    var bar = cursor.bar;
    var from = cursorOnset;
    for (final b in beats) {
      if (b.grace != GraceType.none) continue;
      if (from >= barLength(bar)) {
        bar++;
        from = Fraction.zero;
        if (bar >= _score.masterBars.length) _insertBarsRaw(bar, 1);
      }
      final d = _fit(b.duration, barLength(bar) - from);
      _replace(bar, from, from + d.length, [b.copyWith(duration: d)]);
      from = from + d.length;
    }
    cursor = cursor.copyWith(bar: bar);
    // Cursor hinter das Eingefügte
    setCursor(bar, from.toDouble() - 1e-6);
    _done();
  }

  // ───────────────────────── Aufräumen ─────────────────────────

  /// Bögen nachführen: Haltebogen-Anfang am Ton vor einem gebundenen Ton,
  /// gebundene Töne mit derselben Tonhöhe, Ziel von Hammer-on/Pull-off.
  void _normalize() {
    final t = _track;
    final last = <String, (int, int, int)>{}; // Saite/Ton → (Takt, Schlag, Note)
    Beat? prevBeat;
    int? prevBar, prevIdx;
    for (var bar = 0; bar < t.bars.length && bar < _score.masterBars.length; bar++) {
      if (t.bars[bar].voices.isEmpty) {
        prevBeat = null;
        continue;
      }
      final beats = t.bars[bar].voices.first.beats;
      for (var i = 0; i < beats.length; i++) {
        final b = beats[i];
        if (b.grace != GraceType.none) continue;
        var notes = b.notes;
        var changed = false;
        final prevNotes = prevBeat?.notes ?? const <Note>[];
        String key(Note n) => n.string != null ? 's${n.string}' : 'p${n.pitch.midi}';
        final newNotes = <Note>[];
        for (final n in notes) {
          var m = n;
          final p =
              prevNotes.where((x) => key(x) == key(n)).firstOrNull ??
              (n.tieDestination ? prevNotes.where((x) => x.pitch.midi == n.pitch.midi).firstOrNull : null);
          if (n.tieDestination && p != null) {
            if (m.pitch != p.pitch || m.fret != p.fret || m.written != p.written) {
              m = m.copyWith(pitch: p.pitch, written: p.written, clearWritten: p.written == null, fret: p.fret);
            }
          } else if (n.tieDestination && p == null) {
            m = m.copyWith(tieDestination: false);
          }
          final shouldHammerTo = p != null && p.hammerOrigin && !n.tieDestination;
          if (m.hammerDestination != shouldHammerTo) m = m.copyWith(hammerDestination: shouldHammerTo);
          if (!identical(m, n)) changed = true;
          newNotes.add(m);
        }
        if (changed) {
          notes = newNotes;
          beats[i] = b.copyWith(notes: notes);
        }
        // Haltebogen-Anfang am vorigen Schlag nachführen
        if (prevBeat != null && prevBar != null && prevIdx != null) {
          final pb = t.bars[prevBar].voices.first.beats;
          final pv = pb[prevIdx];
          var pChanged = false;
          final fixed = <Note>[
            for (final x in pv.notes)
              () {
                final tied = notes.any((n) => n.tieDestination && key(n) == key(x));
                if (x.tieOrigin != tied) {
                  pChanged = true;
                  return x.copyWith(tieOrigin: tied);
                }
                return x;
              }(),
          ];
          if (pChanged) pb[prevIdx] = pv.copyWith(notes: fixed);
        }
        prevBeat = beats[i];
        prevBar = bar;
        prevIdx = i;
      }
    }
    last.clear();
  }

  // ───────────────────────── Schnell-Eingaben ─────────────────────────

  /// Nummer des Akkords [name] in der Spur (neu angelegt, wenn nötig).
  int _chordId(String name) {
    final chords = _track.chords;
    final id = chords.entries.where((e) => e.value.name == name).map((e) => e.key).firstOrNull;
    if (id != null) return id;
    final next = chords.isEmpty ? 0 : chords.keys.reduce(math.max) + 1;
    chords[next] = ChordDef(name: name);
    return next;
  }

  /// Index des Schlags, der in [bar] genau bei [onset] beginnt. Liegt dort
  /// mitten in einer Pause, wird sie geteilt; mitten in einem Ton gilt dieser.
  int _beatStartingAt(int bar, Fraction onset) {
    final beats = beatsOf(bar);
    var t = Fraction.zero;
    for (var i = 0; i < beats.length; i++) {
      final b = beats[i];
      if (b.grace != GraceType.none) continue;
      final e = t + b.duration.length;
      if (t == onset) return i;
      if (onset > t && onset < e) {
        if (!b.isRest) return i;
        final before = _restsAt(t, onset - t);
        // Akkord, Text usw. der geteilten Pause bleiben am ersten Teil
        if (before.isNotEmpty) before[0] = b.copyWith(duration: before[0].duration);
        final first = _replace(bar, t, e, [...before, ..._restsAt(onset, e - onset)]);
        return first + before.length;
      }
      t = e;
    }
    return math.max(0, beats.length - 1);
  }

  /// Akkordzeile zerlegen: Takte mit `|` getrennt, darin die Akkorde mit
  /// Leerzeichen; `%` wiederholt den vorigen Takt, `-` oder `.` hält einen
  /// Platz frei. Ohne `|` ist jeder Akkord ein Takt.
  static List<List<String>> parseChordLine(String text) {
    final t = text.trim();
    if (t.isEmpty) return const [];
    final bars = <List<String>>[];
    final parts = t.contains('|') ? t.split(RegExp(r'[|\n]')) : t.split(RegExp(r'\s+'));
    for (final part in parts) {
      final words = part.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.isEmpty) continue;
      if (words.length == 1 && words.first == '%') {
        bars.add(bars.isEmpty ? const ['-'] : [...bars.last]);
      } else {
        bars.add(words);
      }
    }
    return bars;
  }

  /// Akkorde ab dem Takt am Cursor setzen, ein Eintrag von [parseChordLine]
  /// pro Takt, die Akkorde eines Takts gleichmässig auf die Schläge verteilt.
  /// Fehlen Takte, kommen leere dazu. Gibt den ersten und letzten Takt zurück.
  (int, int)? setChordLine(String text) {
    final bars = parseChordLine(text);
    if (bars.isEmpty) return null;
    _begin();
    final from = cursor.bar;
    final missing = from + bars.length - _score.masterBars.length;
    if (missing > 0) _insertBarsRaw(_score.masterBars.length, missing);
    for (var k = 0; k < bars.length; k++) {
      final bar = from + k;
      final beats = beatsOf(bar);
      for (var i = 0; i < beats.length; i++) {
        if (beats[i].chordId != null) beats[i] = beats[i].copyWith(clearChord: true);
      }
      final slots = bars[k];
      final len = barLength(bar);
      final unit = Fraction(1, _score.masterBars[bar].time.beatType);
      for (var j = 0; j < slots.length; j++) {
        final name = slots[j];
        if (name == '-' || name == '.' || name == '%') continue;
        // Gleichmässig verteilt, auf den Schlag abgerundet
        final exact = len.scale(j, slots.length);
        final onset = unit.scale((exact / unit).n ~/ (exact / unit).d);
        final i = _beatStartingAt(bar, onset);
        final b = beatsOf(bar)[i];
        beatsOf(bar)[i] = b.copyWith(chordId: _chordId(name));
      }
    }
    final to = from + bars.length - 1;
    _done();
    return (from, to);
  }

  /// Akkord, der bei [bar]/[onset] gilt (der letzte davor, auch aus früheren Takten).
  String? chordAt(int bar, Fraction onset) {
    for (var b = bar; b >= 0; b--) {
      final beats = beatsOf(b);
      var t = Fraction.zero;
      String? last;
      for (final beat in beats) {
        if (beat.grace != GraceType.none) continue;
        if (b == bar && t > onset) break;
        final id = beat.chordId;
        if (id != null) last = _track.chords[id]?.name ?? last;
        t = t + beat.duration.length;
      }
      if (last != null) return last;
    }
    return null;
  }

  Note _fretNote(int bar, int string, int fret) {
    final st = _track.staff;
    final fifths = _score.masterBars[bar].key.fifths;
    final concert = Pitch.fromMidi(st.tuning[string] + st.capo + fret, fifths: fifths);
    final written = _writtenFor(concert, fifths);
    return Note(pitch: concert, written: written == concert ? null : written, string: string, fret: fret);
  }

  /// Begleitung nach dem Muster [p] in die Takte [fromBar] bis [toBar]
  /// schreiben (Stimme 1 der Spur am Cursor), mit den Griffen der Akkorde,
  /// die dort stehen. Takte ohne Akkord bleiben, wie sie sind.
  void applyPattern(StrumPattern p, int fromBar, int toBar) {
    if (!stringed) return;
    _begin();
    final st = _track.staff;
    final voicings = <String, List<int>?>{};
    final steps = p.steps.split('');
    for (var bar = fromBar; bar <= toBar && bar < _score.masterBars.length; bar++) {
      final len = barLength(bar);
      final step = len.scale(1, steps.length);
      // Akkordwechsel in diesem Takt (Stelle → Name)
      final changes = <(Fraction, String)>[];
      var t = Fraction.zero;
      for (final b in beatsOf(bar)) {
        if (b.grace != GraceType.none) continue;
        final id = b.chordId;
        if (id != null && _track.chords[id] != null) changes.add((t, _track.chords[id]!.name));
        t = t + b.duration.length;
      }
      if (chordAt(bar, len) == null) continue;
      // Schritte zu Ereignissen zusammenfassen (− hält); bei einem
      // Akkordwechsel mitten im Ereignis wird geteilt und neu angeschlagen.
      final events = <(Fraction, Fraction, String)>[];
      for (var k = 0; k < steps.length; k++) {
        final c = steps[k];
        if (c == '-' && events.isNotEmpty) {
          final (s0, l, tok) = events.removeLast();
          events.add((s0, l + step, tok));
        } else {
          events.add((step.scale(k), step, c == '-' ? '.' : c));
        }
      }
      for (final (at, _) in changes) {
        for (var e = 0; e < events.length; e++) {
          final (s0, l, tok) = events[e];
          if (at > s0 && at < s0 + l) {
            events
              ..removeAt(e)
              ..insertAll(e, [(s0, at - s0, tok), (at, s0 + l - at, tok)]);
            break;
          }
        }
      }
      final out = <Beat>[];
      final usedChange = <int>{};
      for (final (onset, length, tok) in events) {
        final name = chordAt(bar, onset);
        final frets = name == null
            ? null
            : voicings.putIfAbsent(name, () => ChordLibrary.voicing(name, st.tuning, capo: st.capo));
        final played = <int>[
          if (frets != null)
            for (var s = 0; s < frets.length && s < st.stringCount; s++)
              if (frets[s] >= 0) s,
        ];
        List<int> strings;
        if (played.isEmpty) {
          strings = const [];
        } else {
          strings = switch (tok) {
            'D' => played,
            'U' => played.sublist(math.max(1, played.length - 4)),
            'B' => [played.first],
            'A' => [played.length > 1 ? played[1] : played.first],
            _ when int.tryParse(tok) != null => [
              played[math.max(played.length > 1 ? 1 : 0, played.length - int.parse(tok))],
            ],
            _ => const [],
          };
        }
        // Akkordsymbol an das Ereignis, in dem der Wechsel liegt
        int? chordId;
        for (var c = 0; c < changes.length; c++) {
          final (at, nm) = changes[c];
          if (!usedChange.contains(c) && at >= onset && at < onset + length) {
            usedChange.add(c);
            chordId = _chordId(nm);
            break;
          }
        }
        if (strings.isEmpty) {
          final rests = _restsAt(onset, length);
          if (chordId != null && rests.isNotEmpty) rests[0] = rests[0].copyWith(chordId: chordId);
          out.addAll(rests);
          continue;
        }
        final notes = [for (final s in strings) _fretNote(bar, s, frets![s])];
        final parts = durationsFor(length);
        for (var i = 0; i < parts.length; i++) {
          final tied = [
            for (final note in notes)
              note.copyWith(tieDestination: i > 0, tieOrigin: i < parts.length - 1, letRing: p.picked),
          ];
          out.add(
            Beat(
              duration: parts[i],
              notes: tied,
              chordId: i == 0 ? chordId : null,
              pickStroke: p.picked || i > 0 ? 0 : (tok == 'U' ? -1 : (tok == 'D' ? 1 : 0)),
            ),
          );
        }
      }
      final beats = beatsOf(bar);
      beats
        ..clear()
        ..addAll(out);
    }
    _done();
  }

  /// Liedtext in Silben: Wörter mit Leerzeichen, Silben mit `-` getrennt
  /// („Son-nen-schein“); `_` lässt eine Note aus (Silbe wird gehalten).
  static List<String> parseLyrics(String text) {
    final out = <String>[];
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      if (word == '_') {
        out.add('_');
        continue;
      }
      final parts = word.split('-');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isEmpty) continue;
        out.add(i < parts.length - 1 ? '${parts[i]}-' : parts[i]);
      }
    }
    return out;
  }

  /// Liedtext ab dem Cursor auf die Noten verteilen (eine Silbe pro Ton,
  /// übergebundene Töne und Pausen werden übersprungen). Gibt die Anzahl
  /// verteilter Silben zurück.
  int setLyricsText(String text, {int line = 0}) {
    final syl = parseLyrics(text);
    if (syl.isEmpty) return 0;
    _begin();
    var k = 0;
    var beat = cursor.beat;
    for (var bar = cursor.bar; bar < _score.masterBars.length && k < syl.length; bar++) {
      final beats = beatsOf(bar);
      for (; beat < beats.length && k < syl.length; beat++) {
        final b = beats[beat];
        if (b.isRest || b.grace != GraceType.none || b.notes.every((n) => n.tieDestination)) continue;
        final s = syl[k++];
        if (s == '_') continue;
        final lyrics = [...b.lyrics];
        while (lyrics.length <= line) {
          lyrics.add('');
        }
        lyrics[line] = s;
        beats[beat] = b.copyWith(lyrics: lyrics);
      }
      beat = 0;
    }
    _done();
    return k;
  }

  /// Formteile des Stücks: Name, erster und letzter Takt.
  List<(String, int, int)> get sections {
    final out = <(String, int, int)>[];
    final mbs = _score.masterBars;
    for (var i = 0; i < mbs.length; i++) {
      final s = mbs[i].section;
      if (s == null) continue;
      if (out.isNotEmpty) {
        final (n, a, _) = out.removeLast();
        out.add((n, a, i - 1));
      }
      out.add((s.label.isEmpty ? '?' : s.label, i, mbs.length - 1));
    }
    return out;
  }

  /// Die Takte [from] bis [to] (alle Spuren, mit Tempo) kopieren und vor
  /// dem Takt [at] einfügen. Der Cursor geht an den Anfang der Kopie.
  void copyBars(int from, int to, int at) {
    final n = _score.masterBars.length;
    if (from < 0 || to >= n || from > to || at < 0 || at > n) return;
    _begin();
    // Tiefe Kopie über das Dateiformat
    final copy = _restore(_snapshot());
    final count = to - from + 1;
    for (var k = 0; k < count; k++) {
      _score.masterBars.insert(at + k, copy.masterBars[from + k]);
      for (var ti = 0; ti < _score.tracks.length; ti++) {
        _score.tracks[ti].bars.insert(at + k, copy.tracks[ti].bars[from + k]);
      }
    }
    final old = [..._score.tempos];
    _score.tempos
      ..clear()
      ..addAll([
        for (final m in old) m.bar >= at && !(m.bar == 0 && at == 0) ? _tempoAt(m, m.bar + count) : m,
        for (final m in old)
          if (m.bar >= from && m.bar <= to) _tempoAt(m, at + m.bar - from),
      ])
      ..sort((a, b) => a.bar != b.bar ? a.bar.compareTo(b.bar) : a.position.compareTo(b.position));
    _dropLayoutHints();
    cursor = EditCursor(bar: at, string: cursor.string);
    anchor = null;
    _done();
  }

  // ───────────────────────── Spuren ─────────────────────────

  static Track _copyTrack(Track t, {String? name, StaffDef? staff, int? program, int? instrumentKey, TrackMix? mix}) =>
      Track(
        name: name ?? t.name,
        shortName: t.shortName,
        staff: staff ?? t.staff,
        bars: t.bars,
        chords: t.chords,
        layoutHint: t.layoutHint,
        transposeSemitones: t.transposeSemitones,
        program: program ?? t.program,
        instrumentKey: instrumentKey ?? t.instrumentKey,
        mix: mix ?? t.mix,
      );

  /// Hall beim Abspielen (0..1). Wie das Mischpult ohne Rückgängig-Schritt.
  void setReverb(double v) {
    final r = v.clamp(0.0, 1.0);
    if (r == _score.reverb) return;
    _score.reverb = r;
    revision++;
  }

  /// Mischpult der Spur [index]. Kein Schritt zum Rückgängigmachen, aber das
  /// Stück gilt als geändert (wird gespeichert).
  void setMix(int index, TrackMix mix) {
    if (index < 0 || index >= _score.tracks.length || _score.tracks[index].mix == mix) return;
    _score.tracks[index] = _copyTrack(_score.tracks[index], mix: mix);
    revision++;
  }

  /// Name und Klangfarbe (General-MIDI-Nummer) der Spur [index].
  void setTrackInfo(int index, {String? name, int? program, int? instrumentKey}) {
    if (index < 0 || index >= _score.tracks.length) return;
    _begin();
    _score.tracks[index] = _copyTrack(
      _score.tracks[index],
      name: name?.trim(),
      program: program,
      instrumentKey: instrumentKey,
    );
    _done();
  }

  /// Neue Stimmung (tiefste Saite zuerst, MIDI) und Kapo für die Spur am Cursor.
  ///
  /// [keepFrets]: Die Griffe (Saite und Bund) bleiben, die Töne klingen mit der
  /// neuen Stimmung anders. Sonst bleiben die Töne gleich und Saite und Bund
  /// werden neu bestimmt, wo es nötig ist.
  void setTuning(List<int> tuning, {int capo = 0, bool keepFrets = false}) {
    final t = _track;
    if (!t.staff.isStringed || tuning.isEmpty) return;
    _begin();
    final st = t.staff;
    _score.tracks[track] = _copyTrack(
      t,
      staff: StaffDef(
        tuning: List.of(tuning),
        capo: capo,
        fretCount: st.fretCount,
        showNotation: st.showNotation,
        showTab: st.showTab,
      ),
    );
    final max = st.fretCount;
    for (var b = 0; b < _track.bars.length; b++) {
      final fifths = _score.masterBars[b].key.fifths;
      for (final v in _track.bars[b].voices) {
        for (var i = 0; i < v.beats.length; i++) {
          final beat = v.beats[i];
          if (beat.isRest) continue;
          final taken = <int>{};
          final notes = <Note>[];
          for (final n in beat.notes) {
            var out = n;
            final s = n.string;
            if (keepFrets && s != null && n.fret != null && s < tuning.length) {
              final concert = Pitch.fromMidi(tuning[s] + capo + n.fret!, fifths: fifths);
              final written = _writtenFor(concert, fifths);
              out = n.copyWith(pitch: concert, written: written, clearWritten: written == concert);
            } else if (s != null) {
              final f = s < tuning.length ? n.pitch.midi - tuning[s] - capo : -1;
              if (f >= 0 && f <= max && !taken.contains(s)) {
                out = n.copyWith(fret: f);
              } else {
                final place = _place(n.pitch.midi, preferString: s.clamp(0, tuning.length - 1), taken: taken);
                if (place != null) out = n.copyWith(string: place.$1, fret: place.$2);
              }
            }
            if (out.string != null) taken.add(out.string!);
            notes.add(out);
          }
          v.beats[i] = beat.copyWith(notes: notes);
        }
      }
    }
    _done();
  }

  /// Neue, leere Spur am Ende; der Cursor wechselt dorthin.
  void addTrack(NewPieceKind kind) {
    _begin();
    final mbs = _score.masterBars;
    final (name, tuning, clef, transpose, program) = _kindDefaults(kind);
    _score.tracks.add(
      Track(
        name: name,
        staff: StaffDef(tuning: tuning, showTab: kind != NewPieceKind.guitarNotation && tuning.isNotEmpty),
        program: program,
        transposeSemitones: transpose,
        bars: [
          for (final mb in mbs) Bar(clef: clef, voices: [Voice(_rests(mb.time.length))]),
        ],
      ),
    );
    track = _score.tracks.length - 1;
    cursor = EditCursor(bar: cursor.bar);
    anchor = null;
    _done();
  }

  /// Spur [index] löschen (die letzte Spur bleibt immer).
  void removeTrack(int index) {
    if (_score.tracks.length <= 1 || index < 0 || index >= _score.tracks.length) return;
    _begin();
    _score.tracks.removeAt(index);
    if (track >= _score.tracks.length || track > index) track = math.max(0, track - 1);
    anchor = null;
    _done();
  }

  static (String, List<int>, Clef, int, int) _kindDefaults(NewPieceKind kind) => switch (kind) {
    NewPieceKind.guitarTab ||
    NewPieceKind.guitarNotation => ('Gitarre', const [40, 45, 50, 55, 59, 64], Clef.treble8vb, 12, 25),
    NewPieceKind.bass => ('Bass', const [28, 33, 38, 43], Clef.bass, 12, 33),
    NewPieceKind.leadSheet => ('Melodie', const <int>[], Clef.treble, 0, 0),
  };

  // ───────────────────────── Neues Stück ─────────────────────────

  /// Leeres Stück: [kind] bestimmt Instrument und Ansicht.
  static Score newScore({
    String title = '',
    String artist = '',
    NewPieceKind kind = NewPieceKind.guitarTab,
    TimeSignature time = const TimeSignature(4, 4),
    KeySignature key = const KeySignature(0),
    double tempo = 100,
    int bars = 16,
  }) {
    final n = math.max(1, bars);
    final (name, tuning, clef, transpose, program) = _kindDefaults(kind);
    final staff = StaffDef(tuning: tuning, showTab: kind != NewPieceKind.guitarNotation && tuning.isNotEmpty);
    return Score(
      info: ScoreInfo(title: title, artist: artist),
      tempos: [TempoMark(bar: 0, bpm: tempo)],
      masterBars: [for (var i = 0; i < n; i++) MasterBar(time: time, key: key)],
      tracks: [
        Track(
          name: name,
          staff: staff,
          program: program,
          transposeSemitones: transpose,
          bars: [
            for (var i = 0; i < n; i++) Bar(clef: clef, voices: [Voice(_rests(time.length))]),
          ],
        ),
      ],
    );
  }
}

/// Art eines neuen Stücks.
enum NewPieceKind { guitarTab, guitarNotation, bass, leadSheet }
