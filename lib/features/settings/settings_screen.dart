import 'package:flutter/material.dart';

import '../../app/device_settings.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../app/version.dart';
import '../../widgets/visuals.dart';
import 'about_page.dart';

/// Einstellungen: Darstellung, Sprache und „Über Scrivi“.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final c = context.scrivi;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Einstellungen', 'Settings'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              SectionCard(
                title: tr('Darstellung', 'Appearance'),
                child: ValueListenableBuilder(
                  valueListenable: s.themeMode,
                  builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: const Icon(Icons.dark_mode_outlined),
                        label: Text(tr('Dunkel', 'Dark')),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: const Icon(Icons.light_mode_outlined),
                        label: Text(tr('Hell', 'Light')),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: const Icon(Icons.brightness_auto_outlined),
                        label: Text(tr('Wie das System', 'Like the system')),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (v) => s.setThemeMode(v.first),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                // Absichtlich zweisprachig: So findet man es auch in der falschen Sprache.
                title: 'Sprache · Language',
                child: ValueListenableBuilder(
                  valueListenable: s.language,
                  builder: (context, lang, _) => SegmentedButton<AppLanguage?>(
                    showSelectedIcon: false,
                    segments: [
                      for (final l in AppLanguage.values) ButtonSegment(value: l, label: Text(l.label)),
                      ButtonSegment(value: null, label: Text(tr('Wie das System', 'Like the system'))),
                    ],
                    selected: {lang},
                    onSelectionChanged: (v) => s.setLanguage(v.first),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: ListTile(
                  leading: const ScriviMark(size: 38),
                  title: Text(tr('Über Scrivi', 'About Scrivi')),
                  subtitle: Text(
                    tr('Version $scriviVersion · Updates · Lizenzen', 'Version $scriviVersion · Updates · Licences'),
                    style: TextStyle(color: c.muted),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
