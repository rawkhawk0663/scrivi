import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Das Scrivi-Zeichen (aus `assets/brand/scrivi_icon.png`, erzeugt mit
/// `tool/make_icon.py`).
class ScriviMark extends StatelessWidget {
  const ScriviMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/scrivi_icon.png',
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    semanticLabel: 'Scrivi',
  );
}

/// Karte mit optionalem Titel – der Grundbaustein der Einstellungsseiten.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.child});
  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = title;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (t != null) ...[Text(t, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 12)],
            child,
          ],
        ),
      ),
    );
  }
}

/// Kleines Quadrat mit Verlauf und weissem Symbol (z. B. in Listen).
class GradientIcon extends StatelessWidget {
  const GradientIcon({super.key, required this.icon, required this.colors, this.size = 38});
  final IconData icon;
  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: colors),
      borderRadius: BorderRadius.circular(size * 0.32),
    ),
    child: Icon(icon, color: Colors.white, size: size * 0.53),
  );
}

/// Leere Seite mit grossem Symbol, Titel und Erklärung.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GradientIcon(icon: icon, colors: c.brand, size: 72),
              const SizedBox(height: 20),
              Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(text, style: TextStyle(color: c.muted, height: 1.4), textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}
