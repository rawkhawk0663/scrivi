import 'package:flutter/material.dart';

import '../../app/device_settings.dart';
import '../../app/theme.dart';
import 'tools.dart';

/// Wo die Leiste steht und wohin ihr Pfeil zeigt.
enum StripSide {
  /// Unter dem Cursor (Pfeil oben).
  below,

  /// Über dem Cursor (Pfeil unten).
  above,

  /// Rechts neben dem Cursor (Pfeil links).
  right,

  /// Links neben dem Cursor (Pfeil rechts).
  left,
}

/// Leiste beim Cursor: alle Gruppen (Noten, Ausdruck, Gitarre, Finger, Takt, Text …)
/// untereinander, jede auf- und zuklappbar. Ein kleiner Pfeil zeigt auf die Stelle des
/// Cursors. So muss man mit Maus oder Stift nicht zur Werkzeugspalte am Rand.
class CursorStrip extends StatefulWidget {
  const CursorStrip({
    super.key,
    required this.host,
    required this.side,
    required this.arrowAt,
    required this.maxHeight,
    required this.width,
  });

  final ToolHost host;
  final StripSide side;

  /// Lage des Pfeils entlang der Kante (waagrecht bei unter/über, senkrecht bei neben).
  final double arrowAt;
  final double maxHeight;
  final double width;

  /// Breite unter dem Cursor bzw. daneben.
  static const wideWidth = 560.0;
  static const narrowWidth = 7 * (ToolButton.size + 4) + 20;

  static const groups = [
    ToolGroup.notes,
    ToolGroup.expression,
    ToolGroup.guitar,
    ToolGroup.drums,
    ToolGroup.finger,
    ToolGroup.bar,
    ToolGroup.text,
  ];

  @override
  State<CursorStrip> createState() => _CursorStripState();
}

class _CursorStripState extends State<CursorStrip> {
  /// Ohne Einstellungen (Tests): nur hier gemerkt.
  Set<String> _local = {'notes'};

  DeviceSettings? get _settings => context.getInheritedWidgetOfExactType<SettingsScope>()?.settings;

  Set<String> get _open => _settings?.stripGroups.value ?? _local;

  void _toggle(ToolGroup g) {
    final open = {..._open};
    if (!open.remove(g.name)) open.add(g.name);
    final s = _settings;
    if (s != null) {
      s.setStripGroups(open);
    } else {
      _local = open;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final e = widget.host.editor;
    final groups = [
      for (final g in CursorStrip.groups)
        if (switch (g) {
          ToolGroup.guitar => e.stringed,
          ToolGroup.drums => e.percussion,
          ToolGroup.finger => !e.percussion,
          _ => true,
        })
          g,
    ];
    final open = _open;
    final side = widget.side;
    final vertical = side == StripSide.below || side == StripSide.above;
    final length = vertical ? widget.width : widget.maxHeight;
    final at = widget.arrowAt.clamp(18.0, length - 18);
    final arrow = Positioned(
      left: switch (side) {
        StripSide.right => -8,
        StripSide.left => null,
        _ => at - 8,
      },
      right: side == StripSide.left ? -8 : null,
      top: switch (side) {
        StripSide.below => -8,
        StripSide.above => null,
        _ => at - 8,
      },
      bottom: side == StripSide.above ? -8 : null,
      child: Transform.rotate(
        angle: 0.785398,
        child: Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: c.card,
            border: switch (side) {
              StripSide.below => Border(
                left: BorderSide(color: c.line),
                top: BorderSide(color: c.line),
              ),
              StripSide.above => Border(
                right: BorderSide(color: c.line),
                bottom: BorderSide(color: c.line),
              ),
              StripSide.right => Border(
                left: BorderSide(color: c.line),
                bottom: BorderSide(color: c.line),
              ),
              StripSide.left => Border(
                right: BorderSide(color: c.line),
                top: BorderSide(color: c.line),
              ),
            },
          ),
        ),
      ),
    );
    return SizedBox(
      width: widget.width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: Material(
              color: c.card,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: c.line),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final g in groups) ...[
                      _header(g, open.contains(g.name), c),
                      if (open.contains(g.name))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final t in allTools)
                                if (t.group == g && t.fits(e)) ToolButton(tool: t, host: widget.host),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          arrow,
        ],
      ),
    );
  }

  /// Name der Gruppe mit Pfeil zum Auf- und Zuklappen.
  Widget _header(ToolGroup g, bool open, ScriviColors c) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: () => _toggle(g),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 18, color: c.muted),
          const SizedBox(width: 4),
          Text(
            g.label.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: c.muted),
          ),
        ],
      ),
    ),
  );
}
