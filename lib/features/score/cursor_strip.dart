import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import 'tools.dart';

/// Leiste unter der Zeile, in der man schreibt: Reiter für die Gruppen
/// (Wert, Ausdruck, Gitarre, Takt, Text) und darunter deren Werkzeuge. Ein
/// kleiner Pfeil zeigt auf die Stelle des Cursors. So muss man mit Maus oder
/// Stift nicht zur Werkzeugspalte am Rand.
class CursorStrip extends StatefulWidget {
  const CursorStrip({super.key, required this.host, required this.arrowX, required this.above});

  final ToolHost host;

  /// Lage des Pfeils (waagrecht, in der Leiste) und ob die Leiste über der Zeile steht.
  final double arrowX;
  final bool above;

  static const width = 500.0;
  static const height = 104.0;

  /// Zuletzt gewählter Reiter (gilt für alle Stücke, solange Scrivi läuft).
  static ToolGroup group = ToolGroup.duration;

  static const groups = [ToolGroup.duration, ToolGroup.expression, ToolGroup.guitar, ToolGroup.bar, ToolGroup.text];

  @override
  State<CursorStrip> createState() => _CursorStripState();
}

class _CursorStripState extends State<CursorStrip> {
  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final scheme = Theme.of(context).colorScheme;
    final stringed = widget.host.editor.stringed;
    final groups = [
      for (final g in CursorStrip.groups)
        if (g != ToolGroup.guitar || stringed) g,
    ];
    var group = CursorStrip.group;
    if (!groups.contains(group)) group = groups.first;
    final tools = [
      for (final t in allTools)
        if (t.group == group && (!t.stringedOnly || stringed)) t,
    ];
    final arrow = Positioned(
      left: (widget.arrowX - 8).clamp(14.0, CursorStrip.width - 30),
      top: widget.above ? null : -8,
      bottom: widget.above ? -8 : null,
      child: Transform.rotate(
        angle: 0.785398,
        child: Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: c.card,
            border: widget.above
                ? Border(
                    right: BorderSide(color: c.line),
                    bottom: BorderSide(color: c.line),
                  )
                : Border(
                    left: BorderSide(color: c.line),
                    top: BorderSide(color: c.line),
                  ),
          ),
        ),
      ),
    );
    return SizedBox(
      width: CursorStrip.width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: c.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: c.line),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (final g in groups)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 30),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              backgroundColor: g == group ? scheme.primary : null,
                              foregroundColor: g == group ? scheme.onPrimary : scheme.onSurface,
                              textStyle: TextStyle(
                                fontSize: 13,
                                fontWeight: g == group ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                            onPressed: () => setState(() => CursorStrip.group = g),
                            child: Text(g == ToolGroup.duration ? tr('Wert', 'Value') : g.label),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [for (final t in tools) ToolButton(tool: t, host: widget.host)],
                  ),
                ],
              ),
            ),
          ),
          arrow,
        ],
      ),
    );
  }
}
