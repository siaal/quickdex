import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../trace.dart';
import 'art.dart';

/// Wraps the Evo button: pressing and dragging pops up the evolution line with
/// the current Pokémon under the thumb; releasing on another one selects it.
/// A plain tap still reaches [child].
class EvoDragMenu extends StatefulWidget {
  const EvoDragMenu({
    super.key,
    required this.dex,
    required this.current,
    required this.onSelect,
    required this.child,
  });
  final Pokedex dex;
  final PokemonEntry current;
  final ValueChanged<int> onSelect;
  final Widget child;

  @override
  State<EvoDragMenu> createState() => _EvoDragMenuState();
}

class _EvoDragMenuState extends State<EvoDragMenu> {
  static const itemHeight = 52.0;
  static const width = 220.0;
  static const margin = 8.0;

  final _portal = OverlayPortalController();
  List<int> _ids = const [];
  Offset _origin = Offset.zero; // top-left of the list, in overlay coords
  int? _hovered;

  /// Chain members in tree order (same order as the Evolution sheet).
  List<int> _lineOf(PokemonEntry e) {
    final chain = widget.dex.chainFor(e);
    if (chain == null || chain.edges.isEmpty) return const [];
    final out = <int>[];
    void walk(int id) {
      assert(!out.contains(id), 'evolution cycle at $id');
      out.add(id);
      for (final edge in chain.from(id)) {
        walk(edge.to);
      }
    }

    chain.roots.forEach(walk);
    return out;
  }

  void _start(DragStartDetails d) {
    final ids = _lineOf(widget.current);
    if (ids.isEmpty) {
      trace('evo.drag.none', {'id': widget.current.id});
      return;
    }
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final size = overlay.size;
    final touch = overlay.globalToLocal(d.globalPosition);
    // Current Pokémon's row centred under the thumb, list kept on screen.
    final at = ids.indexOf(widget.current.id);
    assert(at >= 0, 'current ${widget.current.id} not in its own chain');
    final height = ids.length * itemHeight;
    final top = (touch.dy - (at + 0.5) * itemHeight).clamp(
      margin,
      (size.height - height - margin).clamp(margin, double.infinity),
    );
    final left = (touch.dx + 24 - width).clamp(
      margin,
      size.width - width - margin,
    );
    trace('evo.drag.open', {'id': widget.current.id, 'count': ids.length});
    setState(() {
      _ids = ids;
      _origin = Offset(left, top);
      _hovered = at;
    });
    _portal.show();
  }

  int? _indexAt(Offset global) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final p = overlay.globalToLocal(global) - _origin;
    if (p.dx < 0 || p.dx > width || p.dy < 0) return null;
    final i = p.dy ~/ itemHeight;
    return i < _ids.length ? i : null;
  }

  void _update(DragUpdateDetails d) {
    if (_ids.isEmpty) return;
    final i = _indexAt(d.globalPosition);
    if (i == _hovered) return;
    if (i != null) HapticFeedback.selectionClick();
    setState(() => _hovered = i);
  }

  void _end() {
    if (_ids.isEmpty) return;
    final picked = _hovered == null ? null : _ids[_hovered!];
    _portal.hide();
    setState(() {
      _ids = const [];
      _hovered = null;
    });
    if (picked == null || picked == widget.current.id) {
      trace('evo.drag.cancel', {'id': widget.current.id, 'picked': picked});
      return;
    }
    trace('evo.drag.select', {'from': widget.current.id, 'to': picked});
    widget.onSelect(picked);
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: _menu,
    child: RawGestureDetector(
      gestures: {
        _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
          _EagerPan.new,
          (r) => r
            ..onStart = _start
            ..onUpdate = _update
            ..onEnd = ((_) => _end())
            ..onCancel = _end,
        ),
      },
      child: widget.child,
    ),
  );

  Widget _menu(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: _origin.dx,
      top: _origin.dy,
      width: width,
      child: IgnorePointer(
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _ids.length; i++)
                Container(
                  key: Key('evo-drag-item-${_ids[i]}'),
                  height: itemHeight,
                  color: i == _hovered
                      ? theme.colorScheme.primaryContainer
                      : null,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Image.asset(thumbPath(_ids[i]), width: 40, height: 40),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.dex[_ids[i]].name,
                          overflow: TextOverflow.ellipsis,
                          style: _ids[i] == widget.current.id
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pan that wins the arena before the page's vertical scroll does
/// (half the usual touch slop instead of twice it).
class _EagerPan extends PanGestureRecognizer {
  /// Fixed, not derived from the slop: Android's device touch slop (~8 dp) is what
  /// the page's scroll recognizer uses, so half of Flutter's default (9) lost to
  /// it whenever the page could scroll. 3 px still lets a tap through.
  static const _acceptDistance = 3.0;

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved.abs() > _acceptDistance;
}
