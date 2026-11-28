import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/device_settings.dart';
import '../../app/error_log.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../app/window_buttons.dart';
import '../../core/files/recent_files.dart';
import '../../core/files/score_files.dart';
import '../../widgets/glyph_tile.dart';
import '../../widgets/visuals.dart';
import '../score/edit_tools.dart';
import '../score/score_tabs.dart';
import '../settings/settings_screen.dart';

/// Startseite: neues Stück (Vorlagen), Datei öffnen, zuletzt geöffnete Stücke.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key, this.initialFile, this.pick = false});

  /// Beim Start mitgegebene Datei (Doppelklick auf eine .scrivi-Datei).
  final String? initialFile;

  /// Nur auswählen (für einen neuen Reiter): gibt den Pfad zurück, statt das Stück zu öffnen.
  final bool pick;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final _search = TextEditingController();
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    final f = widget.initialFile;
    if (f != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(f));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(String path) {
    if (!File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Die Datei gibt es nicht mehr: $path', 'The file no longer exists: $path'))),
      );
      return;
    }
    if (widget.pick) {
      Navigator.of(context).pop(path);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScoreTabs(path: path)));
  }

  Future<void> _openDialog() async {
    final file = await openFile(
      acceptedTypeGroups: [XTypeGroup(label: tr('Notendateien', 'Music files'), extensions: ScoreFiles.readable)],
      confirmButtonText: tr('Öffnen', 'Open'),
    );
    if (file != null && mounted) _open(file.path);
  }

  Future<void> _new(core.Score score) async {
    final recent = RecentScope.of(context);
    try {
      final path = await recent.newDraft(score);
      if (mounted) _open(path);
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Neues Stück');
    }
  }

  void _preset(core.NewPieceKind kind) => _new(_template(core.ScoreEditor.newScore(kind: kind)));

  /// Vorlage für neue Stücke (Seite einrichten, Schriften, Akkordsymbole), falls gespeichert.
  core.Score _template(core.Score score) =>
      context.getInheritedWidgetOfExactType<SettingsScope>()?.settings.applyTemplate(score) ?? score;

  /// Beispielstück öffnen: als neuer Entwurf, damit das Beispiel selbst unverändert bleibt.
  Future<void> _example(String asset) async {
    try {
      final data = await rootBundle.load('assets/examples/$asset');
      final score = core.GpReader.read(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      await _new(score);
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Beispiel öffnen: $asset');
    }
  }

  Future<void> _custom() async {
    final s = await askNewPiece(context);
    if (s == null || !mounted) return;
    await _new(
      _template(
        core.ScoreEditor.newScore(
          title: s.title,
          artist: s.artist,
          kind: s.kind,
          time: s.time,
          key: s.key,
          tempo: s.tempo,
          bars: s.bars,
        ),
      ),
    );
  }

  Future<void> _menu(RecentEntry e, Offset at) async {
    final recent = RecentScope.of(context);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
      items: [
        PopupMenuItem(value: 'open', child: Text(tr('Öffnen', 'Open'))),
        PopupMenuItem(
          value: 'remove',
          child: Text(
            e.draft ? tr('Entwurf löschen …', 'Delete draft …') : tr('Aus der Liste entfernen', 'Remove from the list'),
          ),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'open') {
      _open(e.path);
    } else if (choice == 'remove') {
      if (e.draft) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('Entwurf löschen?', 'Delete draft?')),
            content: Text(
              tr(
                '„${e.displayTitle}“ wurde nie gespeichert und ist danach weg.',
                '“${e.displayTitle}” was never saved and will be gone.',
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Löschen', 'Delete'))),
            ],
          ),
        );
        if (ok != true) return;
      }
      await recent.remove(e.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final theme = Theme.of(context);
    final recent = RecentScope.of(context);
    final q = _search.text.trim().toLowerCase();
    final entries = recent.entries
        .where(
          (e) =>
              q.isEmpty ||
              e.displayTitle.toLowerCase().contains(q) ||
              e.artist.toLowerCase().contains(q) ||
              e.path.toLowerCase().contains(q),
        )
        .toList();

    // Fenster ziehen am Kopf; kein Doppelklick, sonst reagieren die Knöpfe verzögert.
    final header = WindowDragArea(
      doubleTapMaximizes: false,
      child: Container(
        height: 64,
        padding: EdgeInsets.only(left: 20, right: hasWindowButtons ? windowButtonsWidth : 12),
        child: Row(
          children: [
            if (widget.pick) ...[
              IconButton(
                tooltip: tr('Zurück zum Stück', 'Back to the piece'),
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 4),
            ],
            const ScriviMark(size: 34),
            const SizedBox(width: 12),
            Text('Scrivi', style: theme.textTheme.titleLarge),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _openDialog,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(tr('Öffnen …', 'Open …')),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: tr('Einstellungen', 'Settings'),
              icon: const Icon(Icons.settings_outlined),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
            ),
          ],
        ),
      ),
    );

    final presets = <(GlyphTile, String, String, VoidCallback)>[
      (
        const GlyphTile(glyphs: ['gClef8vb', '6stringTabClef']),
        tr('Gitarre', 'Guitar'),
        tr('Noten und Tabulatur', 'Notation and tab'),
        () => _preset(core.NewPieceKind.guitarTab),
      ),
      (
        const GlyphTile(glyphs: ['gClef8vb']),
        tr('Gitarre', 'Guitar'),
        tr('nur Noten', 'notation only'),
        () => _preset(core.NewPieceKind.guitarNotation),
      ),
      (
        const GlyphTile(glyphs: ['fClef', '4stringTabClef']),
        tr('Bass', 'Bass'),
        tr('Noten und Tabulatur', 'Notation and tab'),
        () => _preset(core.NewPieceKind.bass),
      ),
      (
        const GlyphTile(eighthNote: true, label: 'Am'),
        tr('Leadsheet', 'Lead sheet'),
        tr('Melodie mit Akkorden', 'Melody with chords'),
        () => _preset(core.NewPieceKind.leadSheet),
      ),
    ];

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(tr('Neues Stück', 'New piece'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          tr('4/4 · C-Dur · ♩ = 100 · 16 Takte', '4/4 · C major · ♩ = 100 · 16 bars'),
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (tile, title, sub, onTap) in presets)
              _PresetCard(tile: tile, title: title, subtitle: sub, onTap: onTap),
            _PresetCard(
              tile: const GlyphTile(icon: Icons.tune_rounded),
              title: tr('Eigene', 'Custom'),
              subtitle: tr('Taktart, Tonart, Tempo …', 'Time, key, tempo …'),
              onTap: _custom,
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(tr('Beispiele', 'Examples'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          tr(
            'Zum Ausprobieren und Weiterschreiben. Das Beispiel öffnet sich als Entwurf.',
            'To try out and build on. The example opens as a draft.',
          ),
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _PresetCard(
              tile: const GlyphTile(icon: Icons.wb_sunny_outlined),
              title: 'Sonntagmorgen',
              subtitle: tr('Gitarren-Band · 5 Spuren', 'Guitar band · 5 tracks'),
              onTap: () => _example('sonntagmorgen.scrivi'),
            ),
            _PresetCard(
              tile: const GlyphTile(icon: Icons.celebration_outlined),
              title: tr('Ode an die Freude', 'Ode to Joy'),
              subtitle: tr('Orchester · Beethoven', 'Orchestra · Beethoven'),
              onTap: () => _example('ode_an_die_freude.scrivi'),
            ),
            _PresetCard(
              tile: const GlyphTile(icon: Icons.air_rounded),
              title: 'Wüstenwind',
              subtitle: tr('Latin-Jazz mit Swing', 'Latin jazz with swing'),
              onTap: () => _example('wuestenwind.scrivi'),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(child: Text(tr('Zuletzt geöffnet', 'Recently opened'), style: theme.textTheme.titleMedium)),
            if (recent.entries.length > 8)
              SizedBox(
                width: 260,
                height: 40,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: tr('Suchen …', 'Search …'),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (recent.loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (recent.entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
              icon: Icons.history_rounded,
              title: tr('Noch nichts geöffnet', 'Nothing opened yet'),
              text: tr(
                'Lege oben ein neues Stück an oder öffne eine Datei: Scrivi-Dateien, Guitar Pro (.gp, .gpx, .gp5, .gp4, .gp3), MusicXML oder MIDI. Du kannst Dateien auch einfach hierher ziehen.',
                'Create a new piece above or open a file: Scrivi files, Guitar Pro (.gp, .gpx, .gp5, .gp4, .gp3), MusicXML or MIDI. You can also simply drag files here.',
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final cols = (box.maxWidth / 230).floor().clamp(1, 8);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entries.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                itemBuilder: (context, i) {
                  final e = entries[i];
                  return _RecentCard(
                    entry: e,
                    recent: recent,
                    onOpen: () => _open(e.path),
                    onMenu: (at) => _menu(e, at),
                  );
                },
              );
            },
          ),
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (d) {
            setState(() => _dragging = false);
            final f = d.files.map((x) => x.path).where(ScoreFiles.isReadable).firstOrNull;
            if (f != null) _open(f);
          },
          child: Stack(
            children: [
              Column(
                children: [
                  header,
                  Expanded(child: body),
                ],
              ),
              if (_dragging)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: theme.colorScheme.primary.withAlpha(30),
                      alignment: Alignment.center,
                      child: Text(tr('Loslassen zum Öffnen', 'Drop to open'), style: theme.textTheme.titleLarge),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.tile, required this.title, required this.subtitle, required this.onTap});
  final GlyphTile tile;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    return SizedBox(
      width: 190,
      height: 132,
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tile,
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.entry, required this.recent, required this.onOpen, required this.onMenu});
  final RecentEntry entry;
  final RecentFiles recent;
  final VoidCallback onOpen;
  final void Function(Offset) onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final theme = Theme.of(context);
    final exists = recent.exists(entry);
    final where = entry.draft
        ? tr('Entwurf · nicht gespeichert', 'Draft · not saved')
        : (exists ? p.basename(p.dirname(entry.path)) : tr('Datei nicht gefunden', 'File not found'));
    return Opacity(
      opacity: exists ? 1 : 0.5,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: exists ? onOpen : null,
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
                  child: !exists
                      ? const Center(child: Icon(Icons.help_outline, color: Colors.black26, size: 40))
                      : FutureBuilder(
                          future: recent.thumbnails.forPiece(entry),
                          builder: (context, snap) {
                            final f = snap.data;
                            if (f == null) {
                              return const Center(
                                child: Icon(Icons.music_note_outlined, color: Colors.black26, size: 40),
                              );
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
                      entry.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.artist.isEmpty ? where : '${entry.artist} · $where',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: entry.draft ? theme.colorScheme.primary : c.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
