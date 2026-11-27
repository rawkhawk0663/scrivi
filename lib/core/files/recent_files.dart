import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:scrivi_core/scrivi_core.dart';

import '../../app/error_log.dart';
import 'score_files.dart';
import 'thumbnails.dart';

/// Eine Datei in „Zuletzt geöffnet“.
class RecentEntry {
  const RecentEntry({
    required this.path,
    required this.title,
    required this.artist,
    required this.bars,
    required this.size,
    required this.modified,
    required this.opened,
    this.draft = false,
  });

  final String path;
  final String title;
  final String artist;
  final int bars;
  final int size;
  final DateTime modified;

  /// Zuletzt geöffnet bzw. bearbeitet.
  final DateTime opened;

  /// Noch nie gespeichertes Stück (liegt im Ordner „Entwürfe“ von Scrivi).
  final bool draft;

  String get fileName => p.basename(path);
  String get displayTitle => title.isNotEmpty ? title : p.basenameWithoutExtension(path);

  Map<String, dynamic> toJson() => {
    'path': path,
    'title': title,
    'artist': artist,
    'bars': bars,
    'size': size,
    'modified': modified.millisecondsSinceEpoch,
    'opened': opened.millisecondsSinceEpoch,
    if (draft) 'draft': true,
  };

  static RecentEntry fromJson(Map<String, dynamic> j) => RecentEntry(
    path: j['path'] as String,
    title: j['title'] as String? ?? '',
    artist: j['artist'] as String? ?? '',
    bars: (j['bars'] as num?)?.toInt() ?? 0,
    size: (j['size'] as num?)?.toInt() ?? 0,
    modified: DateTime.fromMillisecondsSinceEpoch((j['modified'] as num?)?.toInt() ?? 0),
    opened: DateTime.fromMillisecondsSinceEpoch((j['opened'] as num?)?.toInt() ?? 0),
    draft: j['draft'] == true,
  );
}

/// „Zuletzt geöffnet“, Entwürfe und Vorschaubilder.
///
/// Gerätespezifisch in `<ApplicationSupport>`: `zuletzt.json` (Format
/// `scrivi-recent` v1), `Entwürfe/` (noch nie gespeicherte Stücke, werden
/// laufend gesichert) und `Vorschau/` (Bilder der ersten Seite).
/// Beim ersten Start werden die Stücke der früheren Bibliothek übernommen;
/// ihre Dateien bleiben, wo sie sind.
class RecentFiles extends ChangeNotifier {
  RecentFiles(this.supportDir) : thumbnails = Thumbnails(p.join(supportDir, 'Vorschau'));

  final String supportDir;
  final Thumbnails thumbnails;

  static const maxEntries = 60;

  String get _indexPath => p.join(supportDir, 'zuletzt.json');
  String get draftsDir => p.join(supportDir, 'Entwürfe');

  final List<RecentEntry> _entries = [];
  bool loading = true;

  /// Neueste zuerst.
  List<RecentEntry> get entries => List.unmodifiable(_entries);

  bool isDraft(String path) => p.isWithin(draftsDir, path);

  Future<void> init() async {
    try {
      final f = File(_indexPath);
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        for (final e in (j['files'] as List? ?? const [])) {
          try {
            _entries.add(RecentEntry.fromJson(e as Map<String, dynamic>));
          } catch (_) {}
        }
      } else {
        await _adoptOldLibrary();
      }
      _sort();
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Zuletzt geöffnet lesen');
    }
    loading = false;
    notifyListeners();
  }

  /// Stücke aus der früheren Bibliothek übernehmen (nur beim ersten Start).
  Future<void> _adoptOldLibrary() async {
    final dir = Directory(p.join(supportDir, 'Bibliothek', 'Stücke'));
    if (!await dir.exists()) return;
    Map<String, dynamic> index = {};
    try {
      final f = File(p.join(supportDir, 'Bibliothek', '.scrivi', 'index.json'));
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        index = j['pieces'] as Map<String, dynamic>? ?? {};
      }
    } catch (_) {}
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File || !ScoreFiles.isReadable(e.path)) continue;
      final stat = await e.stat();
      final meta = index[p.basename(e.path)] as Map<String, dynamic>? ?? {};
      _entries.add(
        RecentEntry(
          path: e.path,
          title: meta['title'] as String? ?? '',
          artist: meta['artist'] as String? ?? '',
          bars: (meta['bars'] as num?)?.toInt() ?? 0,
          size: stat.size,
          modified: stat.modified,
          opened: DateTime.fromMillisecondsSinceEpoch(
            (meta['added'] as num?)?.toInt() ?? stat.modified.millisecondsSinceEpoch,
          ),
        ),
      );
    }
    if (_entries.isNotEmpty) await _write();
  }

  void _sort() => _entries.sort((a, b) => b.opened.compareTo(a.opened));

  Future<void> _write() async {
    final data = {
      'format': 'scrivi-recent',
      'version': 1,
      'files': [for (final e in _entries) e.toJson()],
    };
    try {
      await ScoreFiles.writeAtomic(_indexPath, utf8.encode(const JsonEncoder.withIndent(' ').convert(data)));
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Zuletzt geöffnet speichern');
    }
  }

  /// Datei [path] (mit Stück [score]) zuoberst in die Liste setzen bzw. auffrischen.
  Future<void> touch(String path, Score score) async {
    FileStat? stat;
    try {
      stat = await File(path).stat();
    } catch (_) {}
    _entries.removeWhere((e) => p.equals(e.path, path));
    _entries.insert(
      0,
      RecentEntry(
        path: path,
        title: score.info.title,
        artist: score.info.artist,
        bars: score.masterBars.length,
        size: stat?.size ?? 0,
        modified: stat?.modified ?? DateTime.now(),
        opened: DateTime.now(),
        draft: isDraft(path),
      ),
    );
    // Liste kurz halten; Entwürfe nie stillschweigend vergessen
    for (var i = _entries.length - 1; i >= 0 && _entries.length > maxEntries; i--) {
      if (!_entries[i].draft) _entries.removeAt(i);
    }
    await _write();
    notifyListeners();
  }

  /// Aus der Liste entfernen. Entwürfe werden dabei gelöscht (nach Rückfrage in der Oberfläche).
  Future<void> remove(String path) async {
    final e = _entries.where((e) => p.equals(e.path, path)).firstOrNull;
    _entries.removeWhere((e) => p.equals(e.path, path));
    if (e != null && e.draft) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    await _write();
    notifyListeners();
  }

  /// Neuer Entwurf für ein noch nie gespeichertes Stück.
  Future<String> newDraft(Score score) async {
    final name = ScoreFiles.safeName(score.info.title, fallback: 'Neues Stück');
    final path = await ScoreFiles.uniquePath(draftsDir, '$name.scrivi');
    await ScoreFiles.writeScrivi(path, score);
    await touch(path, score);
    return path;
  }

  /// Gibt es die Datei noch?
  bool exists(RecentEntry e) => File(e.path).existsSync();
}

/// Macht [RecentFiles] in der App verfügbar.
class RecentScope extends InheritedNotifier<RecentFiles> {
  const RecentScope({super.key, required RecentFiles recent, required super.child}) : super(notifier: recent);

  static RecentFiles of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<RecentScope>()!.notifier!;

  static RecentFiles? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<RecentScope>()?.notifier;
}
