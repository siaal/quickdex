import 'package:flutter/material.dart';

import '../data/models.dart';
import 'art.dart';
import 'type_badge.dart';

/// List row for a Pokémon: thumbnail, name, dex label and type badges.
class PokemonTile extends StatelessWidget {
  const PokemonTile(this.entry, {super.key, required this.onTap});
  final PokemonEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
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
  );
}
