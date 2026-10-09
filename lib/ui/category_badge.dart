import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/moves.dart';

const _colors = {
  MoveCategory.physical: Color(0xFFEB5628),
  MoveCategory.special: Color(0xFF2260C4),
  MoveCategory.status: Color(0xFF8C888C),
};

/// The in-game category symbol drawn in a coloured rounded square: Physical
/// starburst, Special concentric rings, Status half-filled circle. Key: `cat-<name>`.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon(this.category, {super.key, this.size = 20});
  final MoveCategory category;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: category.name[0].toUpperCase() + category.name.substring(1),
    child: CustomPaint(
      key: Key('cat-${category.name}'),
      size: Size.square(size),
      painter: _CategoryPainter(category),
    ),
  );
}

class _CategoryPainter extends CustomPainter {
  _CategoryPainter(this.category);
  final MoveCategory category;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.2)),
      Paint()..color = _colors[category]!,
    );
    final fill = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.09;
    switch (category) {
      case MoveCategory.physical:
        const points = 8;
        final path = Path();
        for (var i = 0; i < points * 2; i++) {
          final r = s * (i.isEven ? 0.40 : 0.18);
          final a = math.pi * i / points - math.pi / 2;
          final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path..close(), fill);
      case MoveCategory.special:
        canvas.drawCircle(c, s * 0.33, stroke);
        canvas.drawCircle(c, s * 0.18, stroke);
        canvas.drawCircle(c, s * 0.06, fill);
      case MoveCategory.status:
        final r = s * 0.33;
        canvas.drawCircle(c, r, stroke);
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          math.pi / 2,
          math.pi,
          true,
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(_CategoryPainter old) => old.category != category;
}

class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key, this.compact = false});
  final MoveCategory category;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = category.name[0].toUpperCase() + category.name.substring(1);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: _colors[category],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CategoryIcon(category, size: compact ? 13 : 17),
          SizedBox(width: compact ? 2 : 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
