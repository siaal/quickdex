import 'package:flutter/material.dart';

import '../data/models.dart';
import 'art.dart';
import 'type_badge.dart';

/// List row for a Pokémon: thumbnail, name, dex label and type badges.
class PokemonTile extends StatelessWidget {
  const PokemonTile(this.entry, {super.key, required this.onTap, this.onHold});
  final PokemonEntry entry;
  final VoidCallback onTap;

  /// Long-press or right-click; nothing when null.
  final VoidCallback? onHold;

  @override
  Widget build(BuildContext context) =>
      GestureDetector(onSecondaryTap: onHold, child: _tile());

  Widget _tile() => ListTile(
    leading: Image.asset(thumbPath(entry.id), width: 48, height: 48),
    title: Text(entry.name),
    subtitle: Text(entry.dexLabel),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in entry.types)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: TypeBadge(t, compact: true),
          ),
      ],
    ),
    onTap: onTap,
    onLongPress: onHold,
  );
}
