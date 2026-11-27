import 'package:flutter/material.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';
import 'score_player.dart';
import 'tools.dart';
import 'track_dialogs.dart';
import 'track_lanes.dart';

/// Eigenschaften rechts: was am Cursor steht (Ton, Takt), die Spur und das
/// Stück. Antippen einer Zeile öffnet das passende Fenster zum Ändern.
class Inspector extends StatelessWidget {
  const Inspector({super.key, required this.host, required this.player, required this.cursorTick});

  final ToolHost host;
  final ScorePlayer? player;
  final Listenable cursorTick;

  static const width = 264.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([cursorTick, ?player]),
      builder: (context, _) {
        final e = host.editor;
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 16),
          children: [..._note(context, e), ..._bar(context, e), ..._track(context, e), ..._piece(context, e)],
        );
      },
    );
  }

  List<Widget> _note(BuildContext context, core.ScoreEditor e) {
    final b = e.currentBeat;
    final t = e.score.tracks[e.track];
    final rows = <Widget>[];
    if (b == null) return rows;
    final value = _valueName(b.duration);
    if (b.isRest) {
      rows.add(_row(context, tr('Pause', 'Rest'), value));
    } else {
      final names = [for (final n in b.notes) _noteName(n, t)].join(' · ');
      rows.add(_row(context, b.notes.length > 1 ? tr('Töne', 'Notes') : tr('Ton', 'Note'), names));
      rows.add(_row(context, tr('Notenwert', 'Value'), value));
      final fretted = [
        for (final n in b.notes)
          if (n.string != null && n.fret != null) '${t.staff.stringCount - n.string!}/${n.fret}',
      ];
      if (fretted.isNotEmpty) rows.add(_row(context, tr('Saite/Bund', 'String/fret'), fretted.join('  ')));
    }
    final chord = e.chordAtCursor();
    rows.add(_row(context, tr('Akkord', 'Chord'), chord.isEmpty ? '–' : chord, onTap: host.editChord));
    if (b.dynamic != null) rows.add(_row(context, tr('Dynamik', 'Dynamics'), b.dynamic!.name));
    return [_title(context, tr('Am Cursor', 'At the cursor')), ...rows];
  }

  List<Widget> _bar(BuildContext context, core.ScoreEditor e) {
    final i = e.cursor.bar;
    final mb = e.score.masterBars[i];
    return [
      _title(context, tr('Takt ${i + 1}', 'Bar ${i + 1}')),
      _row(context, tr('Taktart', 'Time'), '${mb.time.beats}/${mb.time.beatType}', onTap: host.editTimeSignature),
      _row(context, tr('Tonart', 'Key'), keyName(mb.key), onTap: host.editKey),
      _row(context, tr('Tempo', 'Tempo'), '♩ = ${e.tempoAtCursor.round()}', onTap: host.editTempo),
      _row(context, tr('Formteil', 'Section'), mb.section?.label ?? '–', onTap: host.editSection),
      _row(
        context,
        tr('Wiederholung', 'Repeat'),
        mb.hasRepeatEnd ? tr('${mb.repeatEnd}× spielen', 'play ${mb.repeatEnd}×') : '–',
        onTap: host.editRepeatEnd,
      ),
    ];
  }

  List<Widget> _track(BuildContext context, core.ScoreEditor e) {
    final i = e.track;
    final t = e.score.tracks[i];
    final p = player;
    final name = t.name.isEmpty ? tr('Spur ${i + 1}', 'Track ${i + 1}') : t.name;
    return [
      _title(context, tr('Spur', 'Track'), color: trackColor(i)),
      _row(context, tr('Name', 'Name'), name, onTap: () => host.editTrackName(i)),
      _row(context, tr('Klang', 'Sound'), soundName(t.program), onTap: () => host.editTrackSound(i)),
      if (t.staff.isStringed) ...[
        _row(context, tr('Stimmung', 'Tuning'), tuningText(t.staff.tuning), onTap: host.editTuning),
        _row(
          context,
          tr('Kapo', 'Capo'),
          t.staff.capo == 0 ? tr('ohne', 'none') : tr('Bund ${t.staff.capo}', 'fret ${t.staff.capo}'),
          onTap: host.editTuning,
        ),
      ],
      if (p != null && i < p.volume.length) ...[
        _slider(
          context,
          tr('Lautstärke', 'Volume'),
          p.volume[i],
          0,
          1,
          (v) => p.setVolume(i, v),
          '${(p.volume[i] * 100).round()} %',
        ),
        _slider(context, tr('Links/Rechts', 'Pan'), p.pan[i], -1, 1, (v) => p.setPan(i, v), _panText(p.pan[i])),
      ],
    ];
  }

  List<Widget> _piece(BuildContext context, core.ScoreEditor e) {
    final info = e.score.info;
    final p = player;
    return [
      _title(context, tr('Stück', 'Piece')),
      _row(context, tr('Titel', 'Title'), info.title.isEmpty ? '–' : info.title, onTap: host.editTitle),
      _row(context, tr('Interpret', 'Artist'), info.artist.isEmpty ? '–' : info.artist, onTap: host.editTitle),
      _row(context, tr('Takte', 'Bars'), '${e.score.masterBars.length}'),
      if (p != null) _row(context, tr('Dauer', 'Length'), formatTime(p.plan.duration)),
      _row(
        context,
        tr('Spuren', 'Tracks'),
        '${e.score.tracks.length}',
        onTap: host.addTrack,
        action: Icons.add_rounded,
      ),
    ];
  }

  // ───────────────────────── Bausteine ─────────────────────────

  Widget _title(BuildContext context, String text, {Color? color}) {
    final c = context.scrivi;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Row(
        children: [
          if (color != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.muted),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {VoidCallback? onTap, IconData? action}) {
    final c = context.scrivi;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(label, style: TextStyle(fontSize: 13, color: c.muted)),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            if (onTap != null) Icon(action ?? Icons.chevron_right_rounded, size: 18, color: c.muted),
          ],
        ),
      ),
    );
  }

  Widget _slider(
    BuildContext context,
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    String text,
  ) {
    final c = context.scrivi;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 6, 0),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: TextStyle(fontSize: 13, color: c.muted)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(value: value, min: min, max: max, onChanged: onChanged),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(text, style: const TextStyle(fontSize: 12), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  static String _panText(double v) {
    if (v.abs() < 0.05) return tr('Mitte', 'Centre');
    final n = (v.abs() * 100).round();
    return v < 0 ? tr('L $n', 'L $n') : tr('R $n', 'R $n');
  }

  static String _valueName(core.NoteDuration d) {
    final base = switch (d.value) {
      core.NoteValue.doubleWhole => tr('Doppelganze', 'Breve'),
      core.NoteValue.whole => tr('Ganze', 'Whole'),
      core.NoteValue.half => tr('Halbe', 'Half'),
      core.NoteValue.quarter => tr('Viertel', 'Quarter'),
      core.NoteValue.eighth => tr('Achtel', 'Eighth'),
      core.NoteValue.sixteenth => tr('Sechzehntel', 'Sixteenth'),
      core.NoteValue.thirtySecond => tr('32stel', '32nd'),
      core.NoteValue.sixtyFourth => tr('64stel', '64th'),
      core.NoteValue.hundredTwentyEighth => tr('128stel', '128th'),
    };
    final dots = switch (d.dots) {
      0 => '',
      1 => tr('punktiert ', 'dotted '),
      _ => tr('doppelt punktiert ', 'double-dotted '),
    };
    final triplet = d.tuplet != null ? tr(' (Triole)', ' (triplet)') : '';
    return L10n.isEnglish ? '$dots$base$triplet' : '$dots$base$triplet'.replaceFirst('punktiert ', 'punktierte ');
  }

  /// Geschriebener Ton (wie er im Notensystem steht), z. B. „H3“ oder „Fis4“.
  static String _noteName(core.Note n, core.Track t) {
    final w = n.written;
    if (w == null) {
      final midi = n.pitch.midi + t.transposeSemitones;
      return '${stringNoteName(midi)}${midi ~/ 12 - 1}';
    }
    return '${pitchName(w.step, w.alter)}${w.octave}';
  }
}
