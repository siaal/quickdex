import 'package:flutter/material.dart';

import 'art.dart';
import 'type_style.dart';

class TypeBadge extends StatelessWidget {
  const TypeBadge(
    this.type, {
    super.key,
    this.compact = false,
    this.icon = false,
  });
  final String type;
  final bool compact;

  /// Show the Scarlet type icon before the label (key `type-icon-<type>`).
  final bool icon;

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon) ...[
            Image.asset(
              typeIconPath(type),
              key: Key('type-icon-$type'),
              width: compact ? 13 : 17,
              height: compact ? 13 : 17,
            ),
            SizedBox(width: compact ? 2 : 4),
          ],
          Text(
            typeLabel(type),
            style: TextStyle(
              color: typeTextColor(type),
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
