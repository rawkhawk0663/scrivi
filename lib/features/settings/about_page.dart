import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/error_log.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../app/version.dart';
import '../../widgets/visuals.dart';
import 'update_section.dart';

/// Über Scrivi: Version, Updates, Fehlerprotokoll, Lizenzen.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Über Scrivi', 'About Scrivi'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              SectionCard(
                child: Row(
                  children: [
                    const ScriviMark(size: 56),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Scrivi', style: Theme.of(context).textTheme.headlineSmall),
                          Text(
                            tr('Version $scriviVersion', 'Version $scriviVersion'),
                            style: TextStyle(color: c.muted),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tr(
                              'Noten, Tabulatur und Partituren schreiben. Open Source unter der Lizenz GPL-3.0.',
                              'Write notation, tablature and scores. Open source under the GPL-3.0 licence.',
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText('github.com/rawkhawk0663/scrivi', style: TextStyle(color: c.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(title: tr('Updates', 'Updates'), child: const UpdateSection()),
              const SizedBox(height: 14),
              SectionCard(
                title: tr('Fehlerprotokoll', 'Error log'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        'Geht etwas schief, schreibt Scrivi es hier auf. Es bleibt auf diesem Gerät, bis du es kopierst und weitergibst.',
                        'If something goes wrong, Scrivi writes it down here. It stays on this device until you copy and share it.',
                      ),
                      style: TextStyle(color: c.muted),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.bug_report_outlined),
                      label: Text(tr('Ansehen', 'View')),
                      onPressed: () => _showLog(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: Text(tr('Lizenzen', 'Licences')),
                  subtitle: Text(tr('Verwendete Programmteile und Schriften', 'Components and fonts used')),
                  onTap: () =>
                      showLicensePage(context: context, applicationName: 'Scrivi', applicationVersion: scriviVersion),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLog(BuildContext context) async {
    final text = await ErrorLog.read();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Fehlerprotokoll', 'Error log')),
        content: SizedBox(
          width: 640,
          height: 420,
          child: text.isEmpty
              ? Center(child: Text(tr('Keine Fehler aufgezeichnet.', 'No errors recorded.')))
              : SingleChildScrollView(
                  child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
        ),
        actions: [
          if (text.isNotEmpty) ...[
            TextButton(
              onPressed: () async {
                await ErrorLog.clear();
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(tr('Leeren', 'Clear')),
            ),
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: text)),
              child: Text(tr('Kopieren', 'Copy')),
            ),
          ],
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Schliessen', 'Close'))),
        ],
      ),
    );
  }
}
