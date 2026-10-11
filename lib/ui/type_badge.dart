import 'package:flutter/material.dart';

import 'art.dart';
import 'type_style.dart';

class TypeBadge extends StatelessWidget {
  const TypeBadge(
    this.type, {
    super.key,
    this.compact = false,
    this.icon = false,
    this.onTap,
    this.onAdd,
  });
  final String type;
  final bool compact;

  /// Show the Scarlet type icon before the label (key `type-icon-<type>`).
  final bool icon;

  /// When set, the badge is tappable; long-press or right-click calls [onAdd].
  final VoidCallback? onTap;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    assert(typeColors.containsKey(type), 'unknown type $type');
    final badge = _badge();
    if (onTap == null && onAdd == null) return badge;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onAdd,
        onSecondaryTap: onAdd,
        child: badge,
      ),
    );
  }

  Widget _badge() {
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
          // Shrinks rather than overflows when its column is narrower.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                typeLabel(type),
                style: TextStyle(
                  color: typeTextColor(type),
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 11 : 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
