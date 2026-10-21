import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../team/team_analysis.dart';
import '../trace.dart';
import 'art.dart';

/// Your team (left) against theirs (right), as sprites. Tap one to draw a line
/// to each Pokémon on the other side, coloured by how hard you hit them and
/// how hard they hit you. Tiles are `versus-mine-<slot>` /
/// `versus-theirs-<slot>`; the lines are on [VersusLinesPainter]. Each line
/// is split at its midpoint, each half coloured by the hit from its end.
class VersusView extends StatefulWidget {
  const VersusView({super.key, required this.mine, required this.theirs});
  final List<TeamMember> mine;
  final List<TeamMember> theirs;

  static const rowHeight = 56.0;
  static const tileWidth = 48.0;

  @override
  State<VersusView> createState() => _VersusViewState();
}

/// What's tapped: a slot on one side.
typedef _Pick = ({bool mine, int slot});

/// One line between your slot and theirs, with the hits each way (null: only
/// status moves, so that half isn't drawn).
typedef VersusLine = ({
  int mineSlot,
  int theirSlot,
  double? mineHit,
  double? theirHit,
});

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

  @override
  Widget build(BuildContext context) {
    assert(widget.mine.isNotEmpty && widget.theirs.isNotEmpty);
    const h = VersusView.rowHeight;
    const w = VersusView.tileWidth;
    final rows = math.max(widget.mine.length, widget.theirs.length);
    final p = _picked;
    final own = p == null ? null : (p.mine ? widget.mine : widget.theirs);
    final row = own?.indexWhere((m) => m.slot == p!.slot) ?? -1;
    if (p != null && row < 0) trace('versus.pick_gone', {'slot': p.slot});
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        // Line ends: the inner edge of each tile, at its row's centre.
        Offset mineEnd(int r) => Offset(w, r * h + h / 2);
        Offset theirEnd(int r) => Offset(width - w, r * h + h / 2);
        final lines = <(VersusLine, Offset, Offset)>[];
        if (p != null && row >= 0) {
          final other = p.mine ? widget.theirs : widget.mine;
          for (var j = 0; j < other.length; j++) {
            final (mi, ti) = p.mine ? (row, j) : (j, row);
            final (me, them) = (widget.mine[mi], widget.theirs[ti]);
            lines.add((
              (
                mineSlot: me.slot,
                theirSlot: them.slot,
                mineHit: hit(me, them),
                theirHit: hit(them, me),
              ),
              mineEnd(mi),
              theirEnd(ti),
            ));
          }
        }
        return SizedBox(
          height: rows * h,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: VersusLinesPainter(lines)),
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
    return Positioned(
      left: left,
      top: row * VersusView.rowHeight,
      width: VersusView.tileWidth,
      height: VersusView.rowHeight,
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: Key('versus-${mine ? 'mine' : 'theirs'}-${m.slot}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => _tap(pick),
          child: Center(
            child: Image.asset(
              thumbPath(m.entry.id),
              width: 44,
              height: 44,
              semanticLabel: m.entry.name,
            ),
          ),
        ),
      ),
    );
  }
}

/// A hit's colour, from your side: your 2x hits are green and 4x blue, theirs
/// on you red and 4x purple; neutral grey; resisted faded; immune (drawn
/// dashed) faded too.
Color lineColor(double m, {required bool mine}) {
  if (m >= 4) return mine ? Colors.blue : Colors.purple;
  if (m > 1) return mine ? Colors.green : Colors.red;
  if (m == 1) return Colors.grey;
  return Colors.grey.withValues(alpha: 0.35);
}

class VersusLinesPainter extends CustomPainter {
  VersusLinesPainter(this.lines);

  /// Each line and its ends, your side first.
  final List<(VersusLine, Offset, Offset)> lines;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (l, a, b) in lines) {
      final mid = Offset.lerp(a, b, 0.5)!;
      _stroke(canvas, a, mid, l.mineHit, mine: true);
      _stroke(canvas, mid, b, l.theirHit, mine: false);
    }
  }

  void _stroke(
    Canvas canvas,
    Offset a,
    Offset b,
    double? m, {
    required bool mine,
  }) {
    if (m == null) return; // deals no damage
    final paint = Paint()
      ..color = lineColor(m, mine: mine)
      ..strokeWidth = m > 1 ? 3.5 : 2.5
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
  bool shouldRepaint(VersusLinesPainter old) => true;
}
