import 'package:flutter/material.dart';

import 'art.dart';
import 'type_style.dart';

/// Selectable type button: Scarlet/Violet icon + name. Fills whatever width the
/// parent grid cell gives it, so every tile is the same size. Long-press or
/// right-click calls [onAdd] (adding a second type).
class TypeTile extends StatelessWidget {
  const TypeTile(
    this.type, {
    super.key,
    required this.selected,
    required this.onTap,
    this.onAdd,
  });
  final String type;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

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
        onLongPress: onAdd,
        onSecondaryTap: onAdd,
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
                    color: selected ? typeTextColor(type) : null,
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

/// The 18 types as a 3-column grid of [TypeTile]s keyed `<keyPrefix>-<type>`.
/// Tap calls [onTap]; long-press or right-click calls [onAdd].
class TypeTileGrid extends StatelessWidget {
  const TypeTileGrid({
    super.key,
    required this.order,
    required this.selected,
    required this.keyPrefix,
    required this.onTap,
    required this.onAdd,
  });
  final List<String> order;
  final List<String> selected;
  final String keyPrefix;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) => GridView(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      mainAxisExtent: 40,
    ),
    children: [
      for (final t in order)
        TypeTile(
          t,
          key: Key('$keyPrefix-$t'),
          selected: selected.contains(t),
          onTap: () => onTap(t),
          onAdd: () => onAdd(t),
        ),
    ],
  );
}
