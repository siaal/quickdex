import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../team/team_analysis.dart';
import '../trace.dart';
import 'art.dart';

/// Your team (left) against theirs (right). Tap a Pokémon to draw a line to
/// each one on the other side, showing how hard you hit them and how hard
/// they hit you. Tiles are `versus-mine-<slot>` / `versus-theirs-<slot>`;
/// each line's labels are `versus-<mine slot>-<their slot>-mine|theirs`.
///
/// Two line styles are on trial: odd lines (1st, 3rd, 5th from the top) are
/// split, each half starting at its attacker; even lines are two parallel
/// lines, yours on top.
class VersusView extends StatefulWidget {
  const VersusView({super.key, required this.mine, required this.theirs});
  final List<TeamMember> mine;
  final List<TeamMember> theirs;

  static const rowHeight = 56.0;
  static const tileWidth = 112.0;

  @override
  State<VersusView> createState() => _VersusViewState();
}

/// What's tapped: a slot on one side.
typedef _Pick = ({bool mine, int slot});

/// One line: the members' row indices, and the hits each way.
typedef _Line = ({int mineRow, int theirRow, double mineHit, double theirHit});

class _VersusViewState extends State<VersusView> {
  _Pick? _picked;

  void _tap(_Pick p) {
    final clear = _picked == p;
    trace(clear ? 'versus.clear' : 'versus.pick', {
      'side': p.mine ? 'mine' : 'theirs',
      'slot': p.slot,
    });
    setState(() => _picked = clear ? null : p);
  }

  /// Lines from the picked tile, top to bottom on the other side; none if the
  /// pick has since left its team.
  List<_Line> _lines() {
    final p = _picked;
    if (p == null) return const [];
    final own = p.mine ? widget.mine : widget.theirs;
    final row = own.indexWhere((m) => m.slot == p.slot);
    if (row < 0) {
      trace('versus.pick_gone', {'slot': p.slot});
      return const [];
    }
    final other = p.mine ? widget.theirs : widget.mine;
    return [
      for (var j = 0; j < other.length; j++)
        if (p.mine)
          (
            mineRow: row,
            theirRow: j,
            mineHit: hit(own[row], other[j]),
            theirHit: hit(other[j], own[row]),
          )
        else
          (
            mineRow: j,
            theirRow: row,
            mineHit: hit(other[j], own[row]),
            theirHit: hit(own[row], other[j]),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.mine.isNotEmpty && widget.theirs.isNotEmpty);
    const h = VersusView.rowHeight;
    const w = VersusView.tileWidth;
    final rows = math.max(widget.mine.length, widget.theirs.length);
    final lines = _lines();
    final picked = _picked;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        // Line ends: the inner edge of each tile, at its row's centre.
        Offset mineEnd(int r) => Offset(w, r * h + h / 2);
        Offset theirEnd(int r) => Offset(width - w, r * h + h / 2);
        // Labels sit 35% / 75% of the way from the tapped tile, so the
        // fanned-in end stays clear; yours is the one nearer your side.
        Offset along(_Line l, bool mineLabel) {
          final (a, b) = (mineEnd(l.mineRow), theirEnd(l.theirRow));
          final fromMine = picked!.mine;
          final t = mineLabel == fromMine ? 0.35 : 0.75;
          return fromMine ? Offset.lerp(a, b, t)! : Offset.lerp(b, a, t)!;
        }

        return SizedBox(
          height: rows * h,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _LinesPainter([
                    for (final l in lines)
                      (
                        l,
                        mineEnd(l.mineRow),
                        theirEnd(l.theirRow),
                        // Odd = split, even = parallel; 1-based from the top.
                        (picked!.mine ? l.theirRow : l.mineRow).isEven,
                      ),
                  ]),
                ),
              ),
              for (var r = 0; r < widget.mine.length; r++)
                _tile(context, widget.mine[r], mine: true, row: r, left: 0),
              for (var r = 0; r < widget.theirs.length; r++)
                _tile(
                  context,
                  widget.theirs[r],
                  mine: false,
                  row: r,
                  left: width - w,
                ),
              for (final l in lines)
                for (final mineLabel in const [true, false])
                  _label(l, mineLabel: mineLabel, at: along(l, mineLabel)),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(
    BuildContext context,
    TeamMember m, {
    required bool mine,
    required int row,
    required double left,
  }) {
    final pick = (mine: mine, slot: m.slot);
    final selected = _picked == pick;
    final scheme = Theme.of(context).colorScheme;
    final thumb = Image.asset(thumbPath(m.entry.id), width: 40, height: 40);
    final name = Expanded(
      child: Text(
        m.entry.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: mine ? TextAlign.left : TextAlign.right,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
    return Positioned(
      left: left,
      top: row * VersusView.rowHeight,
      width: VersusView.tileWidth,
      height: VersusView.rowHeight,
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: Key('versus-${mine ? 'mine' : 'theirs'}-${m.slot}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => _tap(pick),
          child: Row(children: mine ? [thumb, name] : [name, thumb]),
        ),
      ),
    );
  }

  Widget _label(_Line l, {required bool mineLabel, required Offset at}) {
    final m = mineLabel ? l.mineHit : l.theirHit;
    final mineSlot = widget.mine[l.mineRow].slot;
    final theirSlot = widget.theirs[l.theirRow].slot;
    const size = Size(30, 16);
    return Positioned(
      left: at.dx - size.width / 2,
      top: at.dy - size.height / 2,
      width: size.width,
      height: size.height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: lineColor(m, mine: mineLabel)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              multiplierText(m),
              key: Key(
                'versus-$mineSlot-$theirSlot-${mineLabel ? 'mine' : 'theirs'}',
              ),
              style: const TextStyle(fontSize: 10, height: 1),
            ),
          ),
        ),
      ),
    );
  }
}

/// "2×", "½×", "0×".
String multiplierText(double m) => switch (m) {
  0.25 => '¼×',
  0.5 => '½×',
  _ => '${m.toInt()}×',
};

/// A hit's colour, from your side: your strong hits are green, theirs on you
/// red; neutral grey; resisted faded; immune (drawn dashed) faded too.
Color lineColor(double m, {required bool mine}) {
  if (m > 1) return mine ? Colors.green : Colors.red;
  if (m == 1) return Colors.grey;
  return Colors.grey.withValues(alpha: 0.35);
}

class _LinesPainter extends CustomPainter {
  _LinesPainter(this.lines);

  /// Each line, its ends (your side first) and whether it's drawn split.
  final List<(_Line, Offset, Offset, bool)> lines;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (l, a, b, split) in lines) {
      if (split) {
        final mid = Offset.lerp(a, b, 0.5)!;
        _stroke(canvas, a, mid, l.mineHit, mine: true);
        _stroke(canvas, mid, b, l.theirHit, mine: false);
      } else {
        final d = b - a;
        // Unit normal pointing up the screen, so yours is the top line.
        var n = Offset(-d.dy, d.dx) / d.distance;
        if (n.dy > 0) n = -n;
        _stroke(canvas, a + n * 3, b + n * 3, l.mineHit, mine: true);
        _stroke(canvas, a - n * 3, b - n * 3, l.theirHit, mine: false);
      }
    }
  }

  void _stroke(
    Canvas canvas,
    Offset a,
    Offset b,
    double m, {
    required bool mine,
  }) {
    final paint = Paint()
      ..color = lineColor(m, mine: mine)
      ..strokeWidth = m == 4 ? 5 : (m > 1 ? 3.5 : 2.5)
      ..strokeCap = StrokeCap.round;
    if (m > 0) {
      canvas.drawLine(a, b, paint);
      return;
    }
    // Immune: dashed.
    final d = b - a;
    final steps = (d.distance / 8).floor();
    for (var i = 0; i < steps; i += 2) {
      canvas.drawLine(a + d * (i / steps), a + d * ((i + 1) / steps), paint);
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) => true;
}
