import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../start/start_screen.dart';
import 'score_screen.dart';

/// Mehrere Stücke gleichzeitig offen, je in einem Reiter. Jedes Stück behält
/// Cursor, Ansicht und Klang; nur das sichtbare spielt und hört zu.
/// Die Reiterleiste erscheint erst ab zwei offenen Stücken.
class ScoreTabs extends StatefulWidget {
  const ScoreTabs({super.key, required this.path});

  /// Das zuerst geöffnete Stück.
  final String path;

  @override
  State<ScoreTabs> createState() => _ScoreTabsState();
}

class _Tab {
  _Tab(this.path) : title = p.basenameWithoutExtension(path);
  final String path;
  final key = GlobalKey();
  String title;
}

class _ScoreTabsState extends State<ScoreTabs> {
  final _tabs = <_Tab>[];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _tabs.add(_Tab(widget.path));
  }

  /// Weiteres Stück wählen (Startseite als Auswahl) und als Reiter öffnen.
  Future<void> _open() async {
    final path = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const StartScreen(pick: true)));
    if (path == null || !mounted) return;
    setState(() {
      final i = _tabs.indexWhere((t) => p.equals(t.path, path));
      if (i >= 0) {
        _index = i;
      } else {
        _tabs.add(_Tab(path));
        _index = _tabs.length - 1;
      }
    });
  }

  /// Ein Stück hat sich geschlossen (nach seiner Rückfrage beim Entwurf).
  void _closed(_Tab t) {
    final i = _tabs.indexOf(t);
    if (i < 0) return;
    if (_tabs.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _tabs.removeAt(i);
      if (i < _index || _index >= _tabs.length) _index = (_index - 1).clamp(0, _tabs.length - 1);
    });
  }

  /// Kreuz am Reiter: das Stück fragt selbst nach, wenn es ein Entwurf ist.
  void _close(_Tab t) {
    final i = _tabs.indexOf(t);
    if (i != _index) setState(() => _index = i);
    if (t.key.currentState case final ScoreTab tab) tab.leave();
  }

  void _next(int dir) {
    if (_tabs.length < 2) return;
    setState(() => _index = (_index + dir) % _tabs.length);
  }

  @override
  Widget build(BuildContext context) {
    final bar = _tabs.length > 1 ? _bar(context) : null;
    return IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < _tabs.length; i++)
          ExcludeFocus(
            excluding: i != _index,
            child: TickerMode(
              enabled: i == _index,
              child: ScoreScreen(
                key: _tabs[i].key,
                path: _tabs[i].path,
                active: i == _index,
                tabBar: i == _index ? bar : null,
                onClose: () => _closed(_tabs[i]),
                onTitle: (title) {
                  if (mounted) setState(() => _tabs[i].title = title);
                },
                onOpenPiece: _open,
                onNextTab: _next,
              ),
            ),
          ),
      ],
    );
  }

  Widget _bar(BuildContext context) {
    final c = context.scrivi;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: c.card,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Flexible(
            child: ListView(
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    child: Material(
                      color: i == _index ? scheme.primaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _index = i),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 10, right: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 200),
                                child: Text(
                                  _tabs[i].title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: i == _index ? FontWeight.w600 : FontWeight.w400,
                                    color: i == _index ? scheme.onPrimaryContainer : null,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: tr('Schliessen  (Strg+W)', 'Close  (Ctrl+W)'),
                                visualDensity: VisualDensity.compact,
                                iconSize: 16,
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => _close(_tabs[i]),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Weiteres Stück öffnen  (Strg+O)', 'Open another piece  (Ctrl+O)'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded, size: 20),
            onPressed: _open,
          ),
        ],
      ),
    );
  }
}
