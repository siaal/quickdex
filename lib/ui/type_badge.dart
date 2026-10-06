import 'package:flutter/material.dart';

import 'type_style.dart';

class TypeBadge extends StatelessWidget {
  const TypeBadge(this.type, {super.key, this.compact = false});
  final String type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    assert(typeColors.containsKey(type), 'unknown type $type');
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: typeColors[type],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        typeLabel(type),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: compact ? 11 : 13,
        ),
      ),
    );
  }
}
