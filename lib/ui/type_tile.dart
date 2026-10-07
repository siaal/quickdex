import 'package:flutter/material.dart';

import 'art.dart';
import 'type_style.dart';

/// Selectable type button: Scarlet/Violet icon + name. Fills whatever width the
/// parent grid cell gives it, so every tile is the same size.
class TypeTile extends StatelessWidget {
  const TypeTile(
    this.type, {
    super.key,
    required this.selected,
    required this.onTap,
  });
  final String type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    assert(typeColors.containsKey(type), 'unknown type $type');
    final theme = Theme.of(context);
    final color = typeColors[type]!;
    return Material(
      color: selected ? color : theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset(typeIconPath(type), width: 24, height: 24),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  typeLabel(type),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
