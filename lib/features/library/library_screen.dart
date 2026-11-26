import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/library/library_controller.dart';
import '../../core/library/thumbnails.dart';
import '../../widgets/visuals.dart';
import '../score/edit_tools.dart';
import '../score/score_screen.dart';

/// Macht Bibliothek und Vorschaubilder überall erreichbar.
class LibraryScope extends InheritedNotifier<LibraryController> {
  const LibraryScope({super.key, required LibraryController library, required this.thumbnails, required super.child})
    : super(notifier: library);
  final Thumbnails thumbnails;

  static LibraryScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<LibraryScope>()!;
  LibraryController get library => notifier!;
}

/// Die Bibliothek: alle Stücke mit Vorschau, Suche und Import.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  bool _dragging = false;
  bool _busy = false;

  bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _importFiles() async {
    // Auf Android kennt die Dateiauswahl diese Endungen nicht: alles zeigen, danach prüfen.
    final all = XTypeGroup(label: tr('Noten', 'Music'), extensions: LibraryController.readable);
    final files = await openFiles(
      acceptedTypeGroups: Platform.isAndroid ? const [] : [all],
      confirmButtonText: tr('Importieren', 'Import'),
    );
    if (files.isEmpty) return;
    await _import(files.map((f) => f.path).toList());
  }

  Future<void> _importFolder() async {
    final dir = await getDirectoryPath(confirmButtonText: tr('Diesen Ordner importieren', 'Import this folder'));
    if (dir == null) return;
    await _import([dir]);
  }

  Future<void> _import(List<String> paths) async {
    final lib = LibraryScope.of(context).library;
    setState(() => _busy = true);
    final r = await lib.importPaths(paths);
    if (!mounted) return;
    setState(() => _busy = false);
    final parts = <String>[
      if (r.added > 0)
        tr(
          r.added == 1 ? '1 Stück importiert' : '${r.added} Stücke importiert',
          r.added == 1 ? '1 piece imported' : '${r.added} pieces imported',
        ),
      if (r.duplicates > 0) tr('${r.duplicates} schon vorhanden', '${r.duplicates} already there'),
      if (r.later > 0) tr('${r.later} in älterem Format (kommt bald)', '${r.later} in an older format (coming soon)'),
    ];
    if (r.failed.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Nicht alles liess sich importieren', 'Not everything could be imported')),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (parts.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(parts.join(' · '))),
                for (final (name, reason) in r.failed)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.error_outline),
                    title: Text(name),
                    subtitle: Text(reason),
                  ),
              ],
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('OK', 'OK')))],
        ),
      );
    } else if (parts.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(parts.join(' · '))));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Keine Notendateien gefunden.', 'No music files found.'))));
    }
  }

  void _open(Piece piece, {bool edit = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScoreScreen(piece: piece, startEditing: edit),
      ),
    );
  }

  /// Neues, leeres Stück anlegen und gleich zum Schreiben öffnen.
  Future<void> _newPiece() async {
    final lib = LibraryScope.of(context).library;
    final s = await askNewPiece(context);
    if (s == null || !mounted) return;
    final score = core.ScoreEditor.newScore(
      title: s.title,
      artist: s.artist,
      kind: s.kind,
      time: s.time,
      key: s.key,
      tempo: s.tempo,
      bars: s.bars,
    );
    final piece = await lib.create(score);
    if (mounted) _open(piece, edit: true);
  }

  Future<void> _delete(Piece piece) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('In den Papierkorb legen?', 'Move to the bin?')),
        content: Text(
          tr(
            '„${piece.displayTitle}“ verschwindet aus der Bibliothek. Die Datei bleibt im Ordner „Papierkorb“ der Bibliothek erhalten.',
            '“${piece.displayTitle}” is removed from the library. The file is kept in the library’s “Papierkorb” (bin) folder.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('In den Papierkorb', 'Move to bin')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await LibraryScope.of(context).library.delete(piece);
  }

  Future<void> _menu(Piece piece, Offset at) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(
          value: 'open',
          child: ListTile(leading: const Icon(Icons.music_note_outlined), title: Text(tr('Öffnen', 'Open'))),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(tr('In den Papierkorb', 'Move to bin')),
          ),
        ),
      ],
    );
    if (choice == 'open') _open(piece);
    if (choice == 'delete') await _delete(piece);
  }

  @override
  Widget build(BuildContext context) {
    final scope = LibraryScope.of(context);
    final lib = scope.library;
    final q = _search.text.trim().toLowerCase();
    final pieces = lib.pieces
        .where((x) => q.isEmpty || x.displayTitle.toLowerCase().contains(q) || x.artist.toLowerCase().contains(q))
        .toList();

    final importButton = FilledButton.icon(
      onPressed: _busy ? null : _importFiles,
      icon: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.file_download_outlined),
      label: Text(tr('Importieren', 'Import')),
    );

    final newButton = OutlinedButton.icon(
      onPressed: _newPiece,
      icon: const Icon(Icons.add),
      label: Text(tr('Neues Stück', 'New piece')),
    );

    Widget body;
    if (lib.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (lib.pieces.isEmpty) {
      body = EmptyState(
        icon: Icons.library_music_outlined,
        title: tr('Noch keine Stücke', 'No pieces yet'),
        text: _desktop
            ? tr(
                'Importiere Guitar-Pro-Dateien (.gp, .gpx, .gp5, .gp4, .gp3), MusicXML oder MIDI, oder ziehe sie einfach hierher. Auch ganze Ordner gehen. Die Originale bleiben, wo sie sind.',
                'Import Guitar Pro files (.gp, .gpx, .gp5, .gp4, .gp3), MusicXML or MIDI, or simply drag them here. Whole folders work too. The originals stay where they are.',
              )
            : tr(
                'Importiere Guitar-Pro-Dateien, MusicXML oder MIDI. Die Originale bleiben, wo sie sind.',
                'Import Guitar Pro files, MusicXML or MIDI. The originals stay where they are.',
              ),
        action: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            importButton,
            newButton,
            if (_desktop)
              OutlinedButton.icon(
                onPressed: _busy ? null : _importFolder,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(tr('Ordner importieren', 'Import folder')),
              ),
          ],
        ),
      );
    } else {
      body = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Titel oder Interpret suchen', 'Search title or artist'),
                isDense: true,
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _search.clear())),
              ),
            ),
          ),
          Expanded(
            child: pieces.isEmpty
                ? Center(
                    child: Text(
                      tr('Nichts gefunden.', 'Nothing found.'),
                      style: TextStyle(color: context.scrivi.muted),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 240,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.92,
                    ),
                    itemCount: pieces.length,
                    itemBuilder: (context, i) => _PieceCard(
                      piece: pieces[i],
                      thumbnails: scope.thumbnails,
                      onOpen: () => _open(pieces[i]),
                      onMenu: (at) => _menu(pieces[i], at),
                    ),
                  ),
          ),
        ],
      );
    }

    final page = Scaffold(
      appBar: AppBar(
        title: Text(tr('Bibliothek', 'Library')),
        actions: [
          if (lib.pieces.isNotEmpty) ...[
            if (_desktop)
              IconButton(
                tooltip: tr('Ordner importieren', 'Import folder'),
                onPressed: _busy ? null : _importFolder,
                icon: const Icon(Icons.folder_open_outlined),
              ),
            IconButton(tooltip: tr('Neues Stück', 'New piece'), onPressed: _newPiece, icon: const Icon(Icons.add)),
            const SizedBox(width: 4),
            importButton,
            const SizedBox(width: 12),
          ],
        ],
      ),
      body: body,
    );
    if (!_desktop) return page;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        _import(d.files.map((f) => f.path).toList());
      },
      child: Stack(
        children: [
          page,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                  ),
                  child: Center(
                    child: Text(
                      tr('Loslassen, um zu importieren', 'Drop to import'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PieceCard extends StatelessWidget {
  const _PieceCard({required this.piece, required this.thumbnails, required this.onOpen, required this.onMenu});
  final Piece piece;
  final Thumbnails thumbnails;
  final VoidCallback onOpen;
  final void Function(Offset) onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onSecondaryTapDown: (d) => onMenu(d.globalPosition),
        onLongPress: () {
          final box = context.findRenderObject() as RenderBox?;
          onMenu(box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero)));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Colors.white,
                child: FutureBuilder(
                  future: thumbnails.forPiece(piece),
                  builder: (context, snap) {
                    final f = snap.data;
                    if (f == null) {
                      return Center(child: Icon(Icons.music_note_outlined, color: Colors.black26, size: 40));
                    }
                    return Image.file(
                      f,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.medium,
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    piece.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    piece.artist.isEmpty ? tr('${piece.bars} Takte', '${piece.bars} bars') : piece.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
