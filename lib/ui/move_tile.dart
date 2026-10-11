import 'package:flutter/material.dart';

import '../data/moves.dart';
import 'art.dart';
import 'category_badge.dart';

/// List row for a move: type icon, name, category, and power · accuracy.
class MoveTile extends StatelessWidget {
  const MoveTile(this.move, {super.key, required this.onTap, this.onDetails});
  final Move move;
  final VoidCallback onTap;

  /// Long-press or right-click, e.g. to peek at the move's details.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final m = move;
    final tile = ListTile(
      leading: SizedBox(
        width: 48,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(typeIconPath(m.type), width: 32, height: 32),
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(m.name)),
          const SizedBox(width: 6),
          CategoryIcon(m.category, size: 18),
        ],
      ),
      subtitle: m.inScarlet ? null : const Text('Not in Scarlet'),
      trailing: SizedBox(
        width: 76,
        child: Text(
          style: const TextStyle(fontSize: 14),
          '${m.power ?? '—'} · ${m.accuracy == null ? '—' : '${m.accuracy}%'}',
          textAlign: TextAlign.end,
        ),
      ),
      onTap: onTap,
      onLongPress: onDetails,
    );
    if (onDetails == null) return tile;
    return GestureDetector(onSecondaryTap: onDetails, child: tile);
  }
}
