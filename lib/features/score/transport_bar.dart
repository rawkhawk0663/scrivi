import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import 'score_player.dart';

/// Leiste unten in der Notenansicht: Abspielen, Stelle, Tempo, Einzähler,
/// Metronom, Schleife und Mischpult.
class TransportBar extends StatelessWidget {
  const TransportBar({super.key, required this.player});
  final ScorePlayer player;

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        return Material(
          color: c.card,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: tr('Zum Anfang', 'To the start'),
                      icon: const Icon(Icons.skip_previous_rounded),
                      onPressed: player.rewind,
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: player.preparing
                          ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 3))
                          : IconButton.filled(
                              tooltip: player.playing ? tr('Anhalten', 'Pause') : tr('Abspielen', 'Play'),
                              icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
                              onPressed: player.toggle,
                            ),
                    ),
                    const SizedBox(width: 12),
                    ValueListenableBuilder<double>(
                      valueListenable: player.position,
                      builder: (context, t, _) {
                        final (bar, _) = player.location;
                        return SizedBox(
                          width: 150,
                          child: Text(
                            '${tr('Takt', 'Bar')} ${bar + 1}  ·  ${formatTime(t)} / ${formatTime(player.plan.duration)}',
                            style: TextStyle(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    _chip(
                      context,
                      label: '${tr('Tempo', 'Tempo')} ${(player.tempo * 100).round()} %',
                      selected: player.tempo != 1,
                      onTap: () => _tempoDialog(context),
                    ),
                    _chip(
                      context,
                      label: tr('Einzähler', 'Count-in'),
                      selected: player.countIn,
                      onTap: () => player.setCountIn(!player.countIn),
                    ),
                    _chip(
                      context,
                      label: tr('Metronom', 'Metronome'),
                      selected: player.metronome,
                      onTap: () => player.setMetronome(!player.metronome),
                    ),
                    _chip(
                      context,
                      label: player.loop == null
                          ? tr('Schleife', 'Loop')
                          : '${tr('Schleife', 'Loop')} ${player.loop!.$1 + 1}–${player.loop!.$2 + 1}',
                      selected: player.loop != null,
                      onTap: () => _loopDialog(context),
                    ),
                    IconButton(
                      tooltip: tr('Mischpult', 'Mixer'),
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: () => _mixer(context),
                    ),
                    if (player.error != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Tooltip(
                          message: player.error!,
                          child: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _chip(BuildContext context, {required String label, required bool selected, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: FilterChip(label: Text(label), selected: selected, showCheckmark: false, onSelected: (_) => onTap()),
    );
  }

  Future<void> _tempoDialog(BuildContext context) async {
    var value = player.tempo;
    final result = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr('Tempo', 'Tempo')),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${(value * 100).round()} %', style: Theme.of(context).textTheme.headlineSmall),
                Slider(
                  value: value,
                  min: ScorePlayer.minTempo,
                  max: ScorePlayer.maxTempo,
                  divisions: ((ScorePlayer.maxTempo - ScorePlayer.minTempo) * 20).round(),
                  onChanged: (v) => setState(() => value = v),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in const [0.5, 0.75, 1.0, 1.25])
                      ActionChip(label: Text('${(p * 100).round()} %'), onPressed: () => setState(() => value = p)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, value), child: Text(tr('Übernehmen', 'Apply'))),
          ],
        ),
      ),
    );
    if (result != null) await player.setTempo(result);
  }

  Future<void> _loopDialog(BuildContext context) async {
    final bars = player.score.masterBars.length;
    final (current, _) = player.location;
    final from = TextEditingController(text: '${(player.loop?.$1 ?? current) + 1}');
    final to = TextEditingController(text: '${(player.loop?.$2 ?? (current + 3).clamp(0, bars - 1)) + 1}');
    final result = await showDialog<(int, int)?>(
      context: context,
      builder: (context) {
        Widget field(TextEditingController c, String label) => SizedBox(
          width: 110,
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: label),
          ),
        );
        return AlertDialog(
          title: Text(tr('Schleife', 'Loop')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Diese Takte werden immer wieder gespielt.', 'These bars are played over and over.')),
              const SizedBox(height: 12),
              Row(
                children: [
                  field(from, tr('Von Takt', 'From bar')),
                  const SizedBox(width: 16),
                  field(to, tr('Bis Takt', 'To bar')),
                ],
              ),
            ],
          ),
          actions: [
            if (player.loop != null)
              TextButton(onPressed: () => Navigator.pop(context, (-1, -1)), child: Text(tr('Ausschalten', 'Turn off'))),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: () {
                final a = (int.tryParse(from.text) ?? 1).clamp(1, bars) - 1;
                final b = (int.tryParse(to.text) ?? a + 1).clamp(1, bars) - 1;
                Navigator.pop(context, a <= b ? (a, b) : (b, a));
              },
              child: Text(tr('Übernehmen', 'Apply')),
            ),
          ],
        );
      },
    );
    from.dispose();
    to.dispose();
    if (result == null) return;
    player.setLoop(result.$1 < 0 ? null : result);
  }

  void _mixer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: player,
        builder: (context, _) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(tr('Mischpult', 'Mixer'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (var i = 0; i < player.score.tracks.length; i++)
                Row(
                  children: [
                    SizedBox(
                      width: 160,
                      child: Text(
                        player.score.tracks[i].name.isEmpty
                            ? tr('Spur ${i + 1}', 'Track ${i + 1}')
                            : player.score.tracks[i].name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Slider(value: player.volume[i], onChanged: (v) => player.setVolume(i, v)),
                    ),
                    _toggle(context, 'M', tr('Stumm', 'Mute'), player.muted[i], () => player.toggleMute(i)),
                    const SizedBox(width: 6),
                    _toggle(context, 'S', tr('Solo', 'Solo'), player.solo[i], () => player.toggleSolo(i)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggle(BuildContext context, String letter, String tooltip, bool on, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? scheme.primary : context.scrivi.line),
          ),
          child: Text(
            letter,
            style: TextStyle(fontWeight: FontWeight.w600, color: on ? scheme.onPrimary : null),
          ),
        ),
      ),
    );
  }
}
