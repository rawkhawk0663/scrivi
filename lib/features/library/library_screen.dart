import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../widgets/visuals.dart';

/// Die Bibliothek: Hier erscheinen die Stücke. Scrivi verwaltet sie selbst
/// (wie Volti), dazu kommen Import und Export einzelner Dateien.
///
/// Etappe 0: noch leer. Das Einlesen kommt mit Etappe 1.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Bibliothek', 'Library'))),
      body: EmptyState(
        icon: Icons.library_music_outlined,
        title: tr('Noch keine Stücke', 'No pieces yet'),
        text: tr(
          'Hier erscheinen bald deine Stücke. Als Nächstes lernt Scrivi, Guitar-Pro-Dateien zu öffnen und als Noten und Tabulatur zu zeigen.',
          'Your pieces will appear here soon. Next, Scrivi learns to open Guitar Pro files and show them as notation and tablature.',
        ),
      ),
    );
  }
}
