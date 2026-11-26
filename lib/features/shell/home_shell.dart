import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n.dart';
import '../../app/window_buttons.dart';
import '../../widgets/visuals.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';

/// Breite, ab der links eine Leiste statt unten eine Navigation erscheint.
const wideLayout = 840.0;

/// Rahmen der App: Leiste links (Surface, Tablet quer) oder Navigation unten
/// (Handy). Jeder Bereich hat einen eigenen Navigator: Die Leiste bleibt
/// sichtbar, und jeder Bereich behält seine offene Seite beim Wechseln.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _keys = List.generate(2, (_) => GlobalKey<NavigatorState>());

  void _go(int i) {
    // Nochmals auf den gewählten Bereich: zurück zu seiner ersten Seite.
    if (i == _index) {
      _keys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() => _index = i);
  }

  /// Zurück-Taste (Android): zuerst die offene Seite schliessen, dann zur
  /// Bibliothek, erst dann die App verlassen.
  void _back() {
    final nav = _keys[_index].currentState;
    if (nav != null && nav.canPop()) {
      nav.maybePop();
    } else if (_index != 0) {
      _go(0);
    } else {
      SystemNavigator.pop();
    }
  }

  Widget _tab(int i, Widget page) => Navigator(
    key: _keys[i],
    onGenerateRoute: (settings) => MaterialPageRoute<void>(settings: settings, builder: (_) => page),
  );

  @override
  Widget build(BuildContext context) {
    const pages = [LibraryScreen(), SettingsScreen()];
    final items = [
      (Icons.library_music_outlined, Icons.library_music, tr('Bibliothek', 'Library')),
      (Icons.settings_outlined, Icons.settings, tr('Einstellungen', 'Settings')),
    ];
    final page = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: IndexedStack(index: _index, children: [for (var i = 0; i < pages.length; i++) _tab(i, pages[i])]),
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= wideLayout) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _go,
                  labelType: NavigationRailLabelType.all,
                  // Am Logo verschiebt man das Fenster, doppelt antippen maximiert.
                  leading: const WindowDragArea(
                    child: Padding(padding: EdgeInsets.only(top: 12, bottom: 20), child: ScriviMark(size: 40)),
                  ),
                  destinations: [
                    for (final (icon, sel, label) in items)
                      NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(sel), label: Text(label)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: page),
              ],
            ),
          );
        }
        return Scaffold(
          body: page,
          bottomNavigationBar: NavigationBar(
            height: 64,
            selectedIndex: _index,
            onDestinationSelected: _go,
            destinations: [
              for (final (icon, sel, label) in items)
                NavigationDestination(icon: Icon(icon), selectedIcon: Icon(sel), label: label),
            ],
          ),
        );
      },
    );
  }
}
