import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/audio_engine.dart';
import '../../app/error_log.dart';
import '../../app/l10n.dart';
import '../../app/screen_awake.dart';

/// Spielt ein Stück ab.
///
/// Jede Spur wird im Hintergrund als Tonspur gerechnet und als eigene Stimme
/// abgespielt; dazu kommt das Metronom als weitere Stimme. So lassen sich
/// Lautstärke, stumm und solo sofort ändern, und alles bleibt genau im Takt.
/// Ein anderes Tempo rechnet die Tonspuren neu (die Tonhöhe bleibt).
class ScorePlayer extends ChangeNotifier {
  ScorePlayer(this._score)
    : volume = List.filled(_score.tracks.length, 1.0, growable: true),
      muted = List.filled(_score.tracks.length, false, growable: true),
      solo = List.filled(_score.tracks.length, false, growable: true),
      pan = List.filled(_score.tracks.length, 0.0, growable: true) {
    _plan = core.PlaybackPlan.build(_score);
  }

  core.Score _score;
  core.Score get score => _score;

  /// Das Stück wurde bearbeitet: Plan neu, Klang beim nächsten Abspielen neu rechnen.
  Future<void> updateScore(core.Score s) async {
    if (_playing) await pause();
    _score = s;
    while (volume.length < s.tracks.length) {
      volume.add(1);
      muted.add(false);
      solo.add(false);
      pan.add(0);
    }
    for (final l in <List>[volume, muted, solo, pan]) {
      if (l.length > s.tracks.length) l.length = s.tracks.length;
    }
    _plan = core.PlaybackPlan.build(s, tempoFactor: _tempo);
    position.value = position.value.clamp(0.0, _plan.duration);
    _updateLoopTimes();
    await _unload();
    _notify();
  }

  late core.PlaybackPlan _plan;

  core.PlaybackPlan get plan => _plan;

  /// Aktuelle Stelle in Sekunden (im Plan beim aktuellen Tempo).
  final position = ValueNotifier<double>(0);

  bool get playing => _playing;
  bool _playing = false;

  /// Klang wird gerade gerechnet.
  bool get preparing => _preparing;
  bool _preparing = false;

  String? error;

  /// Tempo als Faktor (1 = wie notiert).
  double get tempo => _tempo;
  double _tempo = 1;
  static const minTempo = 0.25, maxTempo = 2.0;

  bool get metronome => _metronome;
  bool _metronome = false;

  bool get countIn => _countIn;
  bool _countIn = false;

  /// Schleife über die Takte (Partitur-Nummern) von–bis, null = keine.
  (int, int)? get loop => _loop;
  (int, int)? _loop;
  (double, double)? _loopTimes;

  /// Mischpult pro Spur.
  final List<double> volume;
  final List<bool> muted;
  final List<bool> solo;

  /// Links (−1) bis rechts (+1).
  final List<double> pan;

  /// Eine Spur wurde gelöscht: Mischpult-Werte der übrigen behalten.
  void trackRemoved(int i) {
    for (final l in <List>[volume, muted, solo, pan]) {
      if (i < l.length) l.removeAt(i);
    }
  }

  double gain(int i) {
    final anySolo = solo.any((s) => s);
    final on = anySolo ? solo[i] : !muted[i];
    return on ? volume[i] : 0;
  }

  // Geladene Klänge (zum aktuellen Tempo)
  List<AudioSource>? _tracks;
  AudioSource? _clicks;
  AudioSource? _countSource;
  List<SoundHandle> _handles = const [];
  SoundHandle? _clickHandle;
  SoundHandle? _countHandle;
  Future<void>? _preparingFuture;
  int _generation = 0;
  Timer? _ticker;
  bool _disposed = false;

  /// Einzähler: Die Stimmen zählen die Wartezeit schon als gespielt.
  /// So viel ist ihre Stelle der Musik voraus (bis zum nächsten Springen).
  double _lead = 0;
  double _startedAt = 0;

  SoLoud get _soloud => SoLoud.instance;

  /// Takt (Partitur) und Stelle (ganze Noten) zur aktuellen Zeit.
  (int, double) get location => _plan.locate(position.value);

  // ───────────────────────── Bedienung ─────────────────────────

  Future<void> toggle() => _playing ? pause() : play();

  Future<void> play() async {
    if (_playing) return;
    try {
      await _prepare();
      if (_disposed || _tracks == null) return;
      if (position.value >= _plan.duration - 0.05) position.value = 0;
      if (_loopTimes != null && (position.value < _loopTimes!.$1 || position.value >= _loopTimes!.$2)) {
        position.value = _loopTimes!.$1;
      }
      var from = position.value;
      // Einzählen immer ab Taktanfang
      if (_countIn && _plan.bars.isNotEmpty) from = _plan.bars[_plan.barAt(from)].start;
      position.value = from;
      await _start(from, withCountIn: _countIn);
      _playing = true;
      unawaited(ScreenAwake.set(true));
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 30), (_) => _tick());
      _notify();
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Abspielen');
      error = tr(
        'Der Ton liess sich nicht starten. Ist ein Lautsprecher oder Kopfhörer angeschlossen?',
        'Sound could not be started. Are speakers or headphones connected?',
      );
      _notify();
    }
  }

  Future<void> pause() async {
    if (!_playing) return;
    _readPosition();
    _stopVoices();
    _playing = false;
    _ticker?.cancel();
    unawaited(ScreenAwake.set(false));
    _notify();
  }

  /// Zurück zum Anfang (bzw. zum Anfang der Schleife).
  void rewind() => seek(_loopTimes?.$1 ?? 0);

  /// An die Stelle [seconds] springen.
  void seek(double seconds) {
    final t = seconds.clamp(0.0, _plan.duration);
    position.value = t;
    if (_playing) {
      for (final h in _allMusicHandles) {
        try {
          _soloud.seek(h, _dur(t));
        } catch (_) {}
      }
      _lead = 0;
      _startedAt = t;
    }
  }

  /// An Takt [bar], Stelle [onset] (ganze Noten) springen: im Durchgang, der der
  /// aktuellen Stelle am nächsten liegt (bei Wiederholungen).
  void seekTo(int bar, double onset) {
    final here = _plan.barAt(position.value);
    int? best;
    for (var i = 0; i < _plan.bars.length; i++) {
      if (_plan.bars[i].bar != bar) continue;
      if (best == null || (i - here).abs() < (best - here).abs()) best = i;
    }
    if (best == null) return;
    final pb = _plan.bars[best];
    seek(pb.start + pb.secondsAt(onset));
  }

  /// Zum Takt [bar] springen: zum nächsten Durchgang ab der aktuellen Stelle.
  void seekToBar(int bar) {
    final from = _plan.barAt(position.value);
    final i = _plan.playIndexOf(bar, from: from);
    if (i != null) seek(_plan.bars[i].start);
  }

  Future<void> setTempo(double f) async {
    final t = (f.clamp(minTempo, maxTempo) * 20).round() / 20;
    if (t == _tempo) return;
    final wasPlaying = _playing;
    if (wasPlaying) await pause();
    // Stelle über Takt und Position mitnehmen
    final idx = _plan.barAt(position.value);
    final pb = _plan.bars.isEmpty ? null : _plan.bars[idx];
    final within = pb == null ? 0.0 : pb.positionAt(position.value - pb.start);
    _tempo = t;
    _plan = core.PlaybackPlan.build(_score, tempoFactor: t);
    if (pb != null && idx < _plan.bars.length) {
      final nb = _plan.bars[idx];
      position.value = nb.start + nb.secondsAt(within);
    }
    _updateLoopTimes();
    await _unload();
    _notify();
    if (wasPlaying) await play();
  }

  void setMetronome(bool on) {
    _metronome = on;
    final h = _clickHandle;
    if (h != null) _setVol(h, on ? 0.8 : 0);
    _notify();
  }

  void setCountIn(bool on) {
    _countIn = on;
    _notify();
  }

  void setLoop((int, int)? range) {
    _loop = range;
    _updateLoopTimes();
    if (_loopTimes != null && _playing) {
      final p = position.value;
      if (p < _loopTimes!.$1 || p >= _loopTimes!.$2) seek(_loopTimes!.$1);
    }
    _notify();
  }

  void setVolume(int i, double v) {
    volume[i] = v.clamp(0.0, 1.0);
    _applyMix();
  }

  void toggleMute(int i) {
    muted[i] = !muted[i];
    _applyMix();
  }

  void toggleSolo(int i) {
    solo[i] = !solo[i];
    _applyMix();
  }

  void setPan(int i, double v) {
    pan[i] = v.clamp(-1.0, 1.0);
    if (i < _handles.length && _soloud.isInitialized) {
      try {
        _soloud.setPan(_handles[i], pan[i]);
      } catch (_) {}
    }
    _notify();
  }

  // ───────────────────────── intern ─────────────────────────

  static Duration _dur(double s) => Duration(microseconds: (s * 1e6).round());

  void _updateLoopTimes() {
    final l = _loop;
    if (l == null) {
      _loopTimes = null;
      return;
    }
    // Der Durchgang, in dem man gerade ist: letzter Anfangstakt bis hierher, sonst der nächste
    final here = _plan.barAt(position.value);
    int? from;
    for (var i = math.min(here, _plan.bars.length - 1); i >= 0; i--) {
      if (_plan.bars[i].bar == l.$1) {
        from = i;
        break;
      }
    }
    from ??= _plan.playIndexOf(l.$1, from: here);
    if (from == null) {
      _loopTimes = null;
      return;
    }
    var to = from;
    for (var i = from; i < _plan.bars.length; i++) {
      if (_plan.bars[i].bar == l.$2) {
        to = i;
        break;
      }
    }
    _loopTimes = (_plan.bars[from].start, _plan.bars[to].end);
  }

  void _applyMix() {
    for (var i = 0; i < _handles.length; i++) {
      _setVol(_handles[i], gain(i));
    }
    _notify();
  }

  void _setVol(SoundHandle h, double v) {
    try {
      if (_soloud.isInitialized) _soloud.setVolume(h, v);
    } catch (_) {}
  }

  List<SoundHandle> get _allMusicHandles => [..._handles, ?_clickHandle];

  /// Tonspuren rechnen (im Hintergrund) und laden.
  Future<void> _prepare() {
    if (_tracks != null) return Future.value();
    return _preparingFuture ??= _doPrepare().whenComplete(() => _preparingFuture = null);
  }

  Future<void> _doPrepare() async {
    final gen = ++_generation;
    _preparing = true;
    error = null;
    _notify();
    try {
      final soloud = await AudioEngine.use(this);
      final s = _score, tempo = _tempo;
      final wavs = await Isolate.run(() => _render(s, tempo));
      if (gen != _generation || _disposed) return;
      final tracks = <AudioSource>[];
      for (var i = 0; i < wavs.length - 1; i++) {
        tracks.add(await soloud.loadMem('scrivi-$gen-$i.wav', wavs[i]));
      }
      final clicks = await soloud.loadMem('scrivi-$gen-klick.wav', wavs.last);
      if (gen != _generation || _disposed) {
        for (final t in [...tracks, clicks]) {
          await soloud.disposeSource(t);
        }
        return;
      }
      _tracks = tracks;
      _clicks = clicks;
    } finally {
      if (gen == _generation) {
        _preparing = false;
        _notify();
      }
    }
  }

  /// Läuft in einem eigenen Isolate: alle Spuren und das Metronom als WAV.
  static List<Uint8List> _render(core.Score score, double tempo) {
    final plan = core.PlaybackPlan.build(score, tempoFactor: tempo);
    final len = plan.duration + 2.5;
    return [
      for (final t in plan.tracks) core.Synth.wav(core.Synth.renderTrack(t, len)),
      core.Synth.wav(core.Synth.renderClicks(plan.clicks, len)),
    ];
  }

  Future<void> _start(double from, {required bool withCountIn}) async {
    _stopVoices();
    final tracks = _tracks!;
    final handles = <SoundHandle>[];
    for (var i = 0; i < tracks.length; i++) {
      final h = _soloud.play(tracks[i], paused: true, volume: gain(i), pan: i < pan.length ? pan[i] : 0);
      if (from > 0) _soloud.seek(h, _dur(from));
      handles.add(h);
    }
    final ch = _soloud.play(_clicks!, paused: true, volume: _metronome ? 0.8 : 0);
    if (from > 0) _soloud.seek(ch, _dur(from));
    _handles = handles;
    _clickHandle = ch;
    _lead = 0;
    _startedAt = from;
    final all = [...handles, ch];
    // Einzähler: Klicks vor dem Takt, die Musik setzt genau danach ein
    if (withCountIn) {
      final pb = _plan.bars[_plan.barAt(from)];
      final clicks = _plan.countIn(pb);
      final lead = -clicks.first.time;
      final pcm = core.Synth.renderClicks(clicks, lead + 0.1, offset: lead);
      final old = _countSource;
      _countSource = await _soloud.loadMem(
        'scrivi-einzaehler-${DateTime.now().microsecondsSinceEpoch}.wav',
        core.Synth.wav(pcm),
      );
      if (old != null) unawaited(_soloud.disposeSource(old));
      final delay = (lead * core.Synth.rate).round();
      _lead = lead;
      for (final h in all) {
        _soloud.setDelaySamples(h, delay);
      }
      _countHandle = _soloud.play(_countSource!, paused: true, volume: 0.8);
      all.add(_countHandle!);
    }
    // Alle zusammen starten
    final g = _soloud.createVoiceGroup();
    _soloud.addVoicesToGroup(g, all);
    _soloud.setPause(g, false);
    _soloud.destroyVoiceGroup(g);
  }

  /// Stelle der Musik: Stelle der Stimme minus Einzähl-Vorsprung.
  double _voicePosition(SoundHandle h) => math.max(_startedAt, _soloud.getPosition(h).inMicroseconds / 1e6 - _lead);

  void _readPosition() {
    final h = _handles.isEmpty ? _clickHandle : _handles.first;
    if (h != null && _soloud.isInitialized && _soloud.getIsValidVoiceHandle(h)) {
      position.value = _voicePosition(h);
    }
  }

  void _tick() {
    if (!_playing) return;
    final h = _handles.isEmpty ? _clickHandle : _handles.first;
    if (h == null || !_soloud.getIsValidVoiceHandle(h)) {
      _finished();
      return;
    }
    final p = _voicePosition(h);
    final lt = _loopTimes;
    if (lt != null && p >= lt.$2) {
      seek(lt.$1);
      return;
    }
    // Ausklingen lassen, die Markierung bleibt am Ende stehen
    if (p >= _plan.duration + 1.5) {
      _finished();
      return;
    }
    position.value = math.min(p, _plan.duration);
  }

  void _finished() {
    _stopVoices();
    _playing = false;
    _ticker?.cancel();
    position.value = _loopTimes?.$1 ?? 0;
    unawaited(ScreenAwake.set(false));
    _notify();
  }

  void _stopVoices() {
    if (_soloud.isInitialized) {
      for (final h in [..._handles, ?_clickHandle, ?_countHandle]) {
        try {
          _soloud.stop(h);
        } catch (_) {}
      }
    }
    _handles = const [];
    _clickHandle = null;
    _countHandle = null;
  }

  Future<void> _unload() async {
    _generation++;
    _stopVoices();
    final all = [...?_tracks, ?_clicks, ?_countSource];
    _tracks = null;
    _clicks = null;
    _countSource = null;
    if (_soloud.isInitialized) {
      for (final s in all) {
        try {
          await _soloud.disposeSource(s);
        } catch (_) {}
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    if (_playing) unawaited(ScreenAwake.set(false));
    _playing = false;
    unawaited(_unload().whenComplete(() => AudioEngine.done(this)));
    position.dispose();
    super.dispose();
  }
}

/// „1:05“.
String formatTime(double seconds) {
  final s = math.max(0, seconds.floor());
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
