import 'package:flutter/material.dart';

import '../data/moves.dart';

const _colors = {
  MoveCategory.physical: Color(0xFFEB5628),
  MoveCategory.special: Color(0xFF2260C4),
  MoveCategory.status: Color(0xFF8C888C),
};

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
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: compact ? 11 : 13,
        ),
      ),
    );
  }
}
