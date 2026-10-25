import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../team/team_analysis.dart';
import '../trace.dart';
import 'art.dart';
import 'tera.dart';
import 'type_badge.dart';
import 'type_style.dart';

/// Your team (left) against theirs (right), as sprites. Tap one to draw a line
/// to each Pokémon on the other side, coloured by how hard you hit them and
/// how hard they hit you. Tiles are `versus-mine-<slot>` /
/// `versus-theirs-<slot>`; the lines are on [VersusLinesPainter]. Each line
/// fans out from the tapped Pokémon like a `{` and runs flat to its target;
/// it's split at its middle, each half coloured by the hit from its end.
///
/// With [mineTera] / [theirsTera] (Gen 9), each side has one Tera Orb
/// (`versus-orb-mine` / `versus-orb-theirs`) tucked beside its first Pokémon: drop it on one
/// of that side's Pokémon with a Tera type to terastallize it (its lines then
/// use its Tera form); drag it off again, anywhere else, to undo.
class VersusView extends StatefulWidget {
  const VersusView({
    super.key,
    required this.mine,
    required this.theirs,
    this.onOpen,
    this.mineTera,
    this.theirsTera,
  });
  final List<TeamMember> mine;
  final List<TeamMember> theirs;

  /// Each side's terastallized members by slot, for those with a Tera type;
  /// null when the game has no Terastal (no orbs then).
  final Map<int, TeamMember>? mineTera;
  final Map<int, TeamMember>? theirsTera;

  /// Long-press or right-click a Pokémon: open its slot (squad index) on
  /// that side.
  final void Function({required bool mine, required int slot})? onOpen;

  static const rowHeight = 56.0;
  static const tileWidth = 48.0;
  static const orbSize = 16.0;
  static const pillHeight = 18.0;

  @override
  State<VersusView> createState() => _VersusViewState();
}

/// What's tapped: a slot on one side.
typedef _Pick = ({bool mine, int slot});

/// One line between your slot and theirs, with the hits each way (null: only
/// status moves, so that half isn't drawn) and the attacks that get them
/// (see [hitWith]).
typedef VersusLine = ({
  int mineSlot,
  int theirSlot,
  double? mineHit,
  double? theirHit,
  List<List<String>> mineVia,
  List<List<String>> theirVia,
});

class _VersusViewState extends State<VersusView> {
  _Pick? _picked;

  /// The slot each side's Tera Orb is on; null while unused.
  int? _orbMine;
  int? _orbTheirs;

  Map<int, TeamMember>? _teraOf(bool mine) =>
      mine ? widget.mineTera : widget.theirsTera;

  /// Null too once that Pokémon has left or lost its Tera type: the orb is
  /// back above its column.
  int? _orbOf(bool mine) {
    final slot = mine ? _orbMine : _orbTheirs;
    if (slot == null || (_teraOf(mine)?.containsKey(slot) ?? false)) {
      return slot;
    }
    trace('versus.orb.gone', {'side': mine ? 'mine' : 'theirs', 'slot': slot});
    return null;
  }

  void _setOrb(bool mine, int? slot) {
    trace(slot == null ? 'versus.orb.back' : 'versus.orb.on', {
      'side': mine ? 'mine' : 'theirs',
      'slot': slot,
    });
    setState(() => mine ? _orbMine = slot : _orbTheirs = slot);
  }

  /// [m] as it battles now: its Tera form while the orb is on it.
  TeamMember _current(TeamMember m, bool mine) =>
      _orbOf(mine) == m.slot ? _teraOf(mine)![m.slot]! : m;

  void _tap(_Pick p) {
    final clear = _picked == p;
    trace(clear ? 'versus.clear' : 'versus.pick', {
      'side': p.mine ? 'mine' : 'theirs',
      'slot': p.slot,
    });
    setState(() => _picked = clear ? null : p);
  }

  VoidCallback? _open(_Pick p) {
    final open = widget.onOpen;
    if (open == null) return null;
    return () {
      trace('versus.open', {
        'side': p.mine ? 'mine' : 'theirs',
        'slot': p.slot,
      });
      open(mine: p.mine, slot: p.slot);
    };
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.mine.isNotEmpty && widget.theirs.isNotEmpty);
    const h = VersusView.rowHeight;
    const w = VersusView.tileWidth;
    final rows = math.max(widget.mine.length, widget.theirs.length);
    final mine = [for (final m in widget.mine) _current(m, true)];
    final theirs = [for (final m in widget.theirs) _current(m, false)];
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
          final other = p.mine ? theirs : mine;
          for (var j = 0; j < other.length; j++) {
            final (mi, ti) = p.mine ? (row, j) : (j, row);
            final (me, them) = (mine[mi], theirs[ti]);
            lines.add((
              (
                mineSlot: me.slot,
                theirSlot: them.slot,
                mineHit: hit(me, them),
                theirHit: hit(them, me),
                mineVia: hitWith(me, them),
                theirVia: hitWith(them, me),
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
                child: CustomPaint(
                  painter: VersusLinesPainter(lines, hubMine: p?.mine ?? true),
                ),
              ),
              for (final (l, a, b) in lines) ..._pills(l, a, b, p!.mine),
              if (widget.mineTera != null) _orbHolder(mine: true, left: w + 2),
              if (widget.theirsTera != null)
                _orbHolder(
                  mine: false,
                  left: width - w - 2 - VersusView.orbSize,
                ),
              for (var r = 0; r < widget.mine.length; r++)
                _tile(context, widget.mine[r], mine: true, top: r * h, left: 0),
              for (var r = 0; r < widget.theirs.length; r++)
                _tile(
                  context,
                  widget.theirs[r],
                  mine: false,
                  top: r * h,
                  left: width - w,
                ),
            ],
          ),
        );
      },
    );
  }

  /// Above each half of a line, the types its attacker hits with
  /// (`versus-via-<mine|theirs>-<your slot>-<their slot>`), centred on the
  /// half's flat run and shrunk to fit it.
  List<Widget> _pills(VersusLine l, Offset a, Offset b, bool hubMine) {
    final (hubSpan, farSpan) = hubMine
        ? VersusLinesPainter.flats(a, b)
        : VersusLinesPainter.flats(b, a);
    final (mineSpan, theirSpan) = hubMine
        ? (hubSpan, farSpan)
        : (farSpan, hubSpan);
    final y = hubMine ? b.dy : a.dy;
    Widget? pill(String side, (double, double) span, List<List<String>> via) {
      if (via.isEmpty) return null; // no half drawn
      final (x0, x1) = span;
      return Positioned(
        key: Key('versus-via-$side-${l.mineSlot}-${l.theirSlot}'),
        left: math.min(x0, x1) + 4,
        width: (x1 - x0).abs() - 8,
        top: y - VersusView.pillHeight - 3,
        height: VersusView.pillHeight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            spacing: 4,
            children: [
              for (final attack in via)
                Row(
                  spacing: 1,
                  children: [
                    for (final (i, t) in attack.indexed) ...[
                      if (i > 0)
                        const Text('+', style: TextStyle(fontSize: 11)),
                      TypeBadge(t, compact: true),
                    ],
                  ],
                ),
            ],
          ),
        ),
      );
    }

    return [
      ?pill('mine', mineSpan, l.mineVia),
      ?pill('theirs', theirSpan, l.theirVia),
    ];
  }

  Widget _tile(
    BuildContext context,
    TeamMember m, {
    required bool mine,
    required double top,
    required double left,
  }) {
    final pick = (mine: mine, slot: m.slot);
    final selected = _picked == pick;
    final side = mine ? 'mine' : 'theirs';
    final teraType = _orbOf(mine) == m.slot
        ? (_teraOf(mine)?[m.slot])?.tera
        : null;
    return Positioned(
      left: left,
      top: top,
      width: VersusView.tileWidth,
      height: VersusView.rowHeight,
      child: DragTarget<bool>(
        // Only this side's orb, onto a Pokémon with a Tera type.
        onWillAcceptWithDetails: (d) =>
            d.data == mine && (_teraOf(mine)?.containsKey(m.slot) ?? false),
        onAcceptWithDetails: (_) => _setOrb(mine, m.slot),
        builder: (context, candidates, _) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: _sprite(
                context,
                m,
                pick,
                selected,
                candidates.isNotEmpty,
                teraType,
              ),
            ),
            if (teraType != null)
              Positioned(
                top: 0,
                left: 0,
                child: Tooltip(
                  message: 'Tera ${typeLabel(teraType)}: drag off to undo',
                  child: _orbDraggable(
                    mine,
                    child: TeraOrb(
                      key: Key('versus-tera-$side-${m.slot}'),
                      size: 18,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sprite(
    BuildContext context,
    TeamMember m,
    _Pick pick,
    bool selected,
    bool dropping,
    String? tera,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      // Terastallized, it takes on its Tera type's colour.
      color: selected
          ? scheme.primaryContainer
          : tera != null
          ? typeColors[tera]!.withValues(alpha: 0.6)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: dropping
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        key: Key('versus-${pick.mine ? 'mine' : 'theirs'}-${m.slot}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => _tap(pick),
        onLongPress: _open(pick),
        onSecondaryTap: _open(pick),
        child: Center(
          child: Image.asset(
            thumbPath(m.entry.id),
            width: 44,
            height: 44,
            semanticLabel: m.entry.name,
          ),
        ),
      ),
    );
  }

  /// [child] carries [mine]'s orb: dropped on one of that side's Pokémon it
  /// moves there, anywhere else it goes back beside the column.
  Widget _orbDraggable(bool mine, {required Widget child}) => Draggable<bool>(
    data: mine,
    feedback: const TeraOrb(size: 24),
    childWhenDragging: const SizedBox.shrink(),
    onDragStarted: () =>
        trace('versus.orb.drag', {'side': mine ? 'mine' : 'theirs'}),
    onDraggableCanceled: (_, _) => _setOrb(mine, null),
    child: child,
  );

  /// The unused orb, small, tucked in beside the first Pokémon on the
  /// column's inner side; nothing while it's on a Pokémon.
  Widget _orbHolder({required bool mine, required double left}) {
    final side = mine ? 'mine' : 'theirs';
    if (_orbOf(mine) != null) return const SizedBox.shrink();
    return Positioned(
      left: left,
      top: 2,
      child: Tooltip(
        message: 'Tera Orb: drag onto a Pokémon to terastallize it',
        child: _orbDraggable(
          mine,
          child: TeraOrb(
            key: Key('versus-orb-$side'),
            size: VersusView.orbSize,
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
  VersusLinesPainter(this.lines, {required this.hubMine});

  /// Each line and its ends, your side first.
  final List<(VersusLine, Offset, Offset)> lines;

  /// Whether the picked Pokémon (the end all lines share) is yours.
  final bool hubMine;

  /// How far from the picked Pokémon the lines fan out to their targets'
  /// rows, at most; past that they run flat.
  static const fan = 40.0;

  /// The line from [hub] to [far] as a `{`: an S-bend out to [far]'s row
  /// within [fan], then flat. Its halves split at the middle x, so the bend
  /// is always in the hub's half.
  static (Path, Path) shape(Offset hub, Offset far) {
    final midX = (hub.dx + far.dx) / 2;
    final dir = far.dx > hub.dx ? 1.0 : -1.0;
    final reach = math.min(fan, (midX - hub.dx).abs() * 0.8);
    final bendEnd = Offset(hub.dx + dir * reach, far.dy);
    final hubHalf = Path()
      ..moveTo(hub.dx, hub.dy)
      ..cubicTo(
        hub.dx + dir * reach / 2,
        hub.dy,
        hub.dx + dir * reach / 2,
        far.dy,
        bendEnd.dx,
        bendEnd.dy,
      )
      ..lineTo(midX, far.dy);
    final farHalf = Path()
      ..moveTo(midX, far.dy)
      ..lineTo(far.dx, far.dy);
    return (hubHalf, farHalf);
  }

  /// The x spans of [shape]'s flat runs at [far]'s row: the hub half's
  /// (after its bend) and the far half's.
  static ((double, double), (double, double)) flats(Offset hub, Offset far) {
    final midX = (hub.dx + far.dx) / 2;
    final dir = far.dx > hub.dx ? 1.0 : -1.0;
    final reach = math.min(fan, (midX - hub.dx).abs() * 0.8);
    return ((hub.dx + dir * reach, midX), (midX, far.dx));
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final (l, a, b) in lines) {
      final (hubHalf, farHalf) = hubMine ? shape(a, b) : shape(b, a);
      final (mineHalf, theirHalf) = hubMine
          ? (hubHalf, farHalf)
          : (farHalf, hubHalf);
      _stroke(canvas, mineHalf, l.mineHit, mine: true);
      _stroke(canvas, theirHalf, l.theirHit, mine: false);
    }
  }

  void _stroke(Canvas canvas, Path path, double? m, {required bool mine}) {
    if (m == null) return; // deals no damage
    final paint = Paint()
      ..color = lineColor(m, mine: mine)
      ..strokeWidth = m > 1 ? 3.5 : 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (m > 0) {
      canvas.drawPath(path, paint);
      return;
    }
    // Immune: dashed.
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 16) {
        canvas.drawPath(metric.extractPath(d, d + 8), paint);
      }
    }
  }

  @override
  bool shouldRepaint(VersusLinesPainter old) => true;
}
