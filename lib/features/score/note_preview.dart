import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/audio_engine.dart';
import '../../app/error_log.dart';
import '../../app/sounds.dart';

/// Spielt eingegebene Töne kurz an (zum Mithören beim Schreiben).
///
/// Jeder Klang wird einmal gerechnet und gemerkt (Tonhöhen + Klangfarbe).
class NotePreview {
  final _cache = <String, AudioSource>{};
  bool _ready = false;
  bool _failed = false;
  bool enabled = true;

  Future<void> play(List<int> midis, core.PlayTrack track) async {
    if (!enabled || _failed || midis.isEmpty) return;
    try {
      final soloud = await AudioEngine.use(this);
      _ready = true;
      final voicing = core.Synth.voicingFor(track);
      final sounds = await Sounds.font();
      final key = '${voicing.name}:${track.track.program}:${midis.join(',')}';
      var src = _cache[key];
      if (src == null) {
        // Akkord leicht gebrochen, wie angeschlagen
        final notes = [
          for (var i = 0; i < midis.length; i++)
            core.PlayNote(start: i * 0.012, duration: 0.9, midi: midis[i], velocity: 0.75),
        ];
        final pcm = core.Synth.renderTrack(
          core.PlayTrack(track.index, track.track, notes),
          1.6,
          voicing: voicing,
          sounds: sounds,
        );
        src = await soloud.loadMem('scrivi-vorhoeren-$key.wav', core.Synth.wav(pcm));
        _cache[key] = src;
        if (_cache.length > 64) {
          final old = _cache.keys.first;
          unawaited(soloud.disposeSource(_cache.remove(old)!));
        }
      }
      soloud.play(src, volume: 0.8);
    } catch (e, st) {
      _failed = true;
      ErrorLog.record(e, st, where: 'Ton beim Schreiben');
    }
  }

  void dispose() {
    final s = SoLoud.instance;
    if (s.isInitialized) {
      for (final src in _cache.values) {
        unawaited(s.disposeSource(src));
      }
    }
    _cache.clear();
    if (_ready) AudioEngine.done(this);
  }
}
