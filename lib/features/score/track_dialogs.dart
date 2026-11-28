import 'package:flutter/material.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';

/// Klangfarben zur Auswahl (General-MIDI-Nummer, Name de/en), nach Gruppen.
List<(String, List<(int, String)>)> soundGroups() => [
  (
    tr('Gitarre', 'Guitar'),
    [
      (24, tr('Konzertgitarre (Nylon)', 'Classical guitar (nylon)')),
      (25, tr('Westerngitarre (Stahl)', 'Acoustic guitar (steel)')),
      (26, tr('Jazzgitarre', 'Jazz guitar')),
      (27, tr('E-Gitarre clean', 'Electric guitar, clean')),
      (28, tr('E-Gitarre gedämpft', 'Electric guitar, muted')),
      (29, tr('E-Gitarre angezerrt', 'Electric guitar, overdrive')),
      (30, tr('E-Gitarre verzerrt', 'Electric guitar, distortion')),
    ],
  ),
  (
    tr('Bass', 'Bass'),
    [
      (32, tr('Kontrabass', 'Acoustic bass')),
      (33, tr('E-Bass (Finger)', 'Electric bass (finger)')),
      (34, tr('E-Bass (Plektrum)', 'Electric bass (pick)')),
      (35, tr('Bundloser Bass', 'Fretless bass')),
      (36, tr('Slap-Bass', 'Slap bass')),
      (38, tr('Synth-Bass', 'Synth bass')),
    ],
  ),
  (
    tr('Tasten', 'Keys'),
    [(0, tr('Klavier', 'Piano')), (4, tr('E-Piano', 'Electric piano')), (16, tr('Orgel', 'Organ'))],
  ),
  (
    tr('Streicher und Gesang', 'Strings and voice'),
    [
      (40, tr('Geige', 'Violin')),
      (42, tr('Cello', 'Cello')),
      (48, tr('Streicher', 'Strings')),
      (52, tr('Chor', 'Choir')),
    ],
  ),
  (
    tr('Bläser', 'Wind'),
    [
      (56, tr('Trompete', 'Trumpet')),
      (57, tr('Posaune', 'Trombone')),
      (65, tr('Saxofon', 'Saxophone')),
      (73, tr('Flöte', 'Flute')),
    ],
  ),
  (tr('Synthesizer', 'Synth'), [(80, tr('Synth-Lead', 'Synth lead')), (88, tr('Fläche', 'Pad'))]),
];

/// Name einer Klangfarbe (oder „Automatisch“).
String soundName(int program) {
  if (program < 0) return tr('Automatisch', 'Automatic');
  for (final (_, list) in soundGroups()) {
    for (final (p, name) in list) {
      if (p == program) return name;
    }
  }
  // Sonst die Familie (General MIDI: je acht Klänge)
  final families = [
    tr('Klavier', 'Piano'),
    tr('Glocken', 'Chromatic percussion'),
    tr('Orgel', 'Organ'),
    tr('Gitarre', 'Guitar'),
    tr('Bass', 'Bass'),
    tr('Streicher', 'Strings'),
    tr('Ensemble', 'Ensemble'),
    tr('Blechbläser', 'Brass'),
    tr('Holzbläser', 'Reed'),
    tr('Flöte', 'Pipe'),
    tr('Synth-Lead', 'Synth lead'),
    tr('Fläche', 'Pad'),
    tr('Klangeffekt', 'Synth effect'),
    tr('Volksinstrument', 'Ethnic'),
    tr('Schlagwerk', 'Percussive'),
    tr('Geräusch', 'Sound effect'),
  ];
  return '${families[(program ~/ 8).clamp(0, 15)]} ($program)';
}

/// Klangfarbe wählen.
Future<int?> askSound(BuildContext context, int current) {
  return showDialog<int>(
    context: context,
    builder: (context) {
      final c = context.scrivi;
      return AlertDialog(
        title: Text(tr('Klang', 'Sound')),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        content: SizedBox(
          width: 380,
          height: 460,
          child: ListView(
            children: [
              for (final (group, list) in soundGroups()) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Text(
                    group,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.muted),
                  ),
                ),
                for (final (p, name) in list)
                  ListTile(
                    dense: true,
                    selected: p == current,
                    title: Text(name),
                    trailing: p == current ? const Icon(Icons.check_rounded) : null,
                    onTap: () => Navigator.pop(context, p),
                  ),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel')))],
      );
    },
  );
}

/// Name eines Tons für Saiten (C, C♯ … H bzw. B).
String stringNoteName(int midi, {bool flats = false}) {
  const sharp = ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'];
  const flat = ['C', 'D♭', 'D', 'E♭', 'E', 'F', 'G♭', 'G', 'A♭', 'A', 'B♭', 'B'];
  var n = (flats ? flat : sharp)[midi % 12];
  if (!L10n.isEnglish) {
    if (n == 'B') n = 'H';
    if (n == 'B♭' || n == 'A♯') n = 'B';
  }
  return n;
}

/// Stimmung als Text, tiefste Saite zuerst: „E A D G H E“.
String tuningText(List<int> tuning) {
  final flats = tuning.any((m) => const {3, 8, 10}.contains(m % 12));
  return tuning.map((m) => stringNoteName(m, flats: flats)).join(' ');
}

/// Bekannte Stimmungen (tiefste Saite zuerst).
List<(String, List<int>)> tuningPresets(int strings) => switch (strings) {
  4 => [
    (tr('Normal', 'Standard'), const [28, 33, 38, 43]),
    ('Drop D', const [26, 33, 38, 43]),
    (tr('Halbton tiefer', 'Half step down'), const [27, 32, 37, 42]),
  ],
  5 => [
    (tr('Normal (tiefe H-Saite)', 'Standard (low B)'), const [23, 28, 33, 38, 43]),
    (tr('Hohe C-Saite', 'High C'), const [28, 33, 38, 43, 48]),
  ],
  7 => [
    (tr('Normal (tiefe H-Saite)', 'Standard (low B)'), const [35, 40, 45, 50, 55, 59, 64]),
    ('Drop A', const [33, 40, 45, 50, 55, 59, 64]),
  ],
  _ => [
    (tr('Normal', 'Standard'), const [40, 45, 50, 55, 59, 64]),
    ('Drop D', const [38, 45, 50, 55, 59, 64]),
    (tr('Halbton tiefer', 'Half step down'), const [39, 44, 49, 54, 58, 63]),
    (tr('Ganzton tiefer', 'Whole step down'), const [38, 43, 48, 53, 57, 62]),
    ('Drop C', const [36, 43, 48, 53, 57, 62]),
    ('Open G', const [38, 43, 50, 55, 59, 62]),
    ('Open D', const [38, 45, 50, 54, 57, 62]),
    ('Open E', const [40, 47, 52, 56, 59, 64]),
    ('DADGAD', const [38, 45, 50, 55, 57, 62]),
  ],
};

/// Ergebnis des Stimmungs-Dialogs.
class TuningChoice {
  const TuningChoice(this.tuning, this.capo, this.keepFrets);
  final List<int> tuning;
  final int capo;

  /// Die Griffe bleiben (die Töne ändern sich).
  final bool keepFrets;
}

/// Stimmung und Kapo einer Saiten-Spur wählen.
Future<TuningChoice?> askTuning(BuildContext context, core.StaffDef staff) {
  var tuning = List<int>.of(staff.tuning);
  var capo = staff.capo;
  var keepFrets = false;
  return showDialog<TuningChoice>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final c = context.scrivi;
        final presets = tuningPresets(tuning.length);
        return AlertDialog(
          title: Text(tr('Stimmung und Kapo', 'Tuning and capo')),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (name, t) in presets)
                        ChoiceChip(
                          label: Text(name),
                          selected: _same(t, tuning),
                          onSelected: (_) => setState(() => tuning = List.of(t)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    tr('Saiten (tiefste zuerst)', 'Strings (lowest first)'),
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var s = 0; s < tuning.length; s++)
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: c.line),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: tr('Höher', 'Higher'),
                                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                                onPressed: () => setState(() => tuning[s] = (tuning[s] + 1).clamp(16, 80)),
                              ),
                              Text(
                                stringNoteName(tuning[s], flats: tuning.any((m) => const {3, 8, 10}.contains(m % 12))),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: tr('Tiefer', 'Lower'),
                                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                onPressed: () => setState(() => tuning[s] = (tuning[s] - 1).clamp(16, 80)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(tr('Kapo', 'Capo')),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove_rounded),
                        onPressed: capo > 0 ? () => setState(() => capo--) : null,
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          capo == 0 ? tr('ohne', 'none') : tr('Bund $capo', 'fret $capo'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_rounded),
                        onPressed: capo < 12 ? () => setState(() => capo++) : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(tr('Was soll gleich bleiben?', 'What should stay the same?')),
                  RadioGroup<bool>(
                    groupValue: keepFrets,
                    onChanged: (v) => setState(() => keepFrets = v ?? false),
                    child: Column(
                      children: [
                        RadioListTile<bool>(
                          value: false,
                          dense: true,
                          title: Text(tr('Die Töne (Bünde werden angepasst)', 'The notes (frets are adjusted)')),
                        ),
                        RadioListTile<bool>(
                          value: true,
                          dense: true,
                          title: Text(tr('Die Griffe (Töne klingen anders)', 'The fingering (notes sound different)')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: () => Navigator.pop(context, TuningChoice(tuning, capo, keepFrets)),
              child: Text(tr('Übernehmen', 'Apply')),
            ),
          ],
        );
      },
    ),
  );
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Art einer neuen Spur als Text.
String newTrackName(core.NewPieceKind k) => switch (k) {
  core.NewPieceKind.guitarTab => tr('Gitarre mit Tab', 'Guitar with tab'),
  core.NewPieceKind.guitarNotation => tr('Gitarre, nur Noten', 'Guitar, notation only'),
  core.NewPieceKind.bass => tr('Bass', 'Bass'),
  core.NewPieceKind.leadSheet => tr('Melodie (Gesang, Bläser …)', 'Melody (voice, wind …)'),
  core.NewPieceKind.drums => tr('Schlagzeug', 'Drums'),
};

/// Tonart als Name, z. B. „G-Dur“ bzw. „G major“.
String keyName(core.KeySignature k) {
  const de = ['Ces', 'Ges', 'Des', 'As', 'Es', 'B', 'F', 'C', 'G', 'D', 'A', 'E', 'H', 'Fis', 'Cis'];
  const en = ['C♭', 'G♭', 'D♭', 'A♭', 'E♭', 'B♭', 'F', 'C', 'G', 'D', 'A', 'E', 'B', 'F♯', 'C♯'];
  final i = (k.fifths + 7).clamp(0, 14);
  if (k.minor) {
    // Moll: die parallele Molltonart (kleine Terz unter Dur)
    const deM = ['as', 'es', 'b', 'f', 'c', 'g', 'd', 'a', 'e', 'h', 'fis', 'cis', 'gis', 'dis', 'ais'];
    const enM = ['A♭', 'E♭', 'B♭', 'F', 'C', 'G', 'D', 'A', 'E', 'B', 'F♯', 'C♯', 'G♯', 'D♯', 'A♯'];
    return L10n.isEnglish ? '${enM[i]} minor' : '${deM[i]}-Moll';
  }
  return L10n.isEnglish ? '${en[i]} major' : '${de[i]}-Dur';
}

/// Name eines Tons aus Stammton (0 = C … 6 = H) und Vorzeichen: „Fis“, „Es“ bzw. „F♯“, „E♭“.
String pitchName(int step, int alter) {
  if (L10n.isEnglish) {
    const letters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    return letters[step] + (alter > 0 ? '♯' * alter : '♭' * -alter);
  }
  const letters = ['C', 'D', 'E', 'F', 'G', 'A', 'H'];
  if (alter == 0) return letters[step];
  if (alter > 0) return letters[step] + 'is' * alter;
  // b-Namen: B, Es, As, sonst -es
  if (step == 6 && alter == -1) return 'B';
  if (step == 6) return 'Heses';
  final base = letters[step];
  final first = (step == 2 || step == 5) ? '${base}s' : '${base}es';
  return alter == -1 ? first : '${first}es';
}

/// Wie ein Instrument notiert wird: Halbtöne über dem Klang (Ansicht „transponiert“).
List<(int, String)> instrumentKeys() => [
  (0, tr('In C (klingend)', 'In C (concert)')),
  (2, tr('In B (Trompete, Klarinette, Sopransax)', 'In B♭ (trumpet, clarinet, soprano sax)')),
  (14, tr('In B, eine Oktave tiefer (Tenorsax, Bassklarinette)', 'In B♭, an octave lower (tenor sax, bass clarinet)')),
  (9, tr('In Es (Altsax, Es-Klarinette)', 'In E♭ (alto sax, E♭ clarinet)')),
  (21, tr('In Es, eine Oktave tiefer (Baritonsax)', 'In E♭, an octave lower (baritone sax)')),
  (7, tr('In F (Horn, Englischhorn)', 'In F (horn, cor anglais)')),
  (3, tr('In A (A-Klarinette)', 'In A (A clarinet)')),
  (5, tr('In G (Altflöte)', 'In G (alto flute)')),
];

/// Kurzer Name: „in B“, „in Es“ …
String instrumentKeyName(int k) {
  if (k == 0) return tr('in C', 'in C');
  final names = {2: 'B', 14: 'B', 9: 'Es', 21: 'Es', 7: 'F', 3: 'A', 5: 'G', 10: 'D', -2: 'D'};
  final en = {2: 'B♭', 14: 'B♭', 9: 'E♭', 21: 'E♭', 7: 'F', 3: 'A', 5: 'G', 10: 'D', -2: 'D'};
  final n = L10n.isEnglish ? en[k] : names[k];
  return n == null ? '$k' : tr('in $n', 'in $n');
}

/// Notierung eines Instruments wählen. [octaveInClef]: Die Spur ist schon
/// eine Oktave höher geschrieben (z. B. Tenorsax im Violinschlüssel mit 8).
Future<int?> askInstrumentKey(BuildContext context, int current, {int octaveInClef = 0}) {
  // Ist die Oktave schon im Schlüssel, zählen die „Oktave tiefer“-Stimmungen ohne sie
  int toKey(int k) => octaveInClef > 0 && k >= octaveInClef ? k - octaveInClef : k;
  // Häkchen nur bei einer Zeile (mit Oktave im Schlüssel die Oktav-Variante)
  final matches = [
    for (final (k, _) in instrumentKeys())
      if (toKey(k) == current) k,
  ];
  final checked = matches.isEmpty ? null : (octaveInClef > 0 ? matches.last : matches.first);
  return showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('Notiert in', 'Written in')),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            tr(
              'So erscheint die Spur in der Ansicht „transponiert“. Klingend bleibt alles gleich.',
              'This is how the track appears in the “transposed” view. The sound stays the same.',
            ),
            style: TextStyle(fontSize: 12.5, color: context.scrivi.muted),
          ),
        ),
        for (final (k, name) in instrumentKeys())
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, toKey(k)),
            child: Row(
              children: [
                Expanded(child: Text(name)),
                if (k == checked) const Icon(Icons.check_rounded, size: 18),
              ],
            ),
          ),
      ],
    ),
  );
}
