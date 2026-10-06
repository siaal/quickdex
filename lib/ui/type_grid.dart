import 'package:flutter/material.dart';

import '../data/models.dart';
import '../trace.dart';
import 'type_style.dart';

const gridHighlightBorder = Border.fromBorderSide(
  BorderSide(color: Colors.amber, width: 1.5),
);
const _plainBorder = Border.fromBorderSide(
  BorderSide(color: Colors.black12, width: 0.5),
);

/// Full 18×18 chart: attackers down the left, defenders across the top.
/// Headers live outside the InteractiveViewer and follow its transform on one axis only.
class TypeGrid extends StatefulWidget {
  const TypeGrid({super.key, required this.chart});
  final TypeChart chart;

  @override
  State<TypeGrid> createState() => _TypeGridState();
}

class _TypeGridState extends State<TypeGrid> {
  static const cell = 36.0;
  static const header = 40.0;
  final _controller = TransformationController();
  int? _row;
  int? _col;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _cellColor(double m) => switch (m) {
    0.0 => Colors.grey.shade800,
    0.5 => Colors.red.shade200,
    2.0 => Colors.green.shade300,
    _ => Colors.transparent,
  };

  String _cellText(double m) => switch (m) {
    0.0 => '0',
    0.5 => '½',
    2.0 => '2',
    _ => '',
  };

  Widget _label(String t, double width, double height) => Container(
    width: width,
    height: height,
    color: typeColors[t],
    alignment: Alignment.center,
    child: FittedBox(
      child: Text(
        typeAbbr(t),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );

  Widget _cell(int r, int c) {
    final order = widget.chart.order;
    final m = widget.chart.multiplier(order[r], order[c]);
    final highlighted = _row == r || _col == c;
    return GestureDetector(
      key: Key('grid-cell-${order[r]}-${order[c]}'),
      onTap: () {
        trace('grid.cell.tap', {'atk': order[r], 'def': order[c]});
        setState(() {
          _row = r;
          _col = c;
        });
      },
      child: Container(
        width: cell,
        height: cell,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: highlighted
              ? Color.alphaBlend(
                  Colors.amber.withValues(alpha: 0.25),
                  _cellColor(m),
                )
              : _cellColor(m),
          border: highlighted ? gridHighlightBorder : _plainBorder,
        ),
        child: Text(
          _cellText(m),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.chart.order;
    final n = order.length;
    return Stack(
      children: [
        Positioned(
          left: header,
          top: header,
          right: 0,
          bottom: 0,
          child: ClipRect(
            child: InteractiveViewer(
              key: const Key('grid-viewer'),
              transformationController: _controller,
              constrained: false,
              minScale: 0.6,
              maxScale: 3,
              child: Column(
                children: [
                  for (var r = 0; r < n; r++)
                    Row(children: [for (var c = 0; c < n; c++) _cell(r, c)]),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: header,
          top: 0,
          right: 0,
          height: header,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final s = _controller.value.getMaxScaleOnAxis();
                final tx = _controller.value.getTranslation().x;
                return Stack(
                  children: [
                    for (var i = 0; i < n; i++)
                      Positioned(
                        key: Key('grid-col-${order[i]}'),
                        left: tx + i * cell * s,
                        top: 0,
                        width: cell * s,
                        height: header,
                        child: _label(order[i], cell * s, header),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: header,
          width: header,
          bottom: 0,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final s = _controller.value.getMaxScaleOnAxis();
                final ty = _controller.value.getTranslation().y;
                return Stack(
                  children: [
                    for (var i = 0; i < n; i++)
                      Positioned(
                        key: Key('grid-row-${order[i]}'),
                        left: 0,
                        top: ty + i * cell * s,
                        width: header,
                        height: cell * s,
                        child: _label(order[i], header, cell * s),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const Positioned(
          left: 0,
          top: 0,
          width: header,
          height: header,
          child: Center(
            child: Text(
              'ATK\nDEF',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9),
            ),
          ),
        ),
      ],
    );
  }
}
