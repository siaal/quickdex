import 'package:flutter/material.dart';

import '../data/models.dart';
import '../frecency/frecency.dart';
import '../search/search_index.dart';
import 'art.dart';
import 'pokemon_page.dart';
import 'search_screen.dart';
import 'type_badge.dart';

class LookupScreen extends StatelessWidget {
  const LookupScreen({
    super.key,
    required this.dex,
    required this.frecency,
    required this.index,
  });
  final Pokedex dex;
  final FrecencyStore frecency;
  final SearchIndex<PokemonEntry> index;

  @override
  Widget build(BuildContext context) => SearchScreen<PokemonEntry>(
    index: index,
    frecency: frecency,
    hint: 'Search Pokémon',
    precacheImageFor: (e) => AssetImage(thumbPath(e.id)),
    pageBuilder: (e) =>
        PokemonPage(dex: dex, frecency: frecency, initialId: e.id),
    tileBuilder: (e, onTap) => ListTile(
      leading: Image.asset(thumbPath(e.id), width: 48, height: 48),
      title: Text(e.name),
      subtitle: Text(e.dexLabel),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in e.types)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TypeBadge(t, compact: true),
            ),
        ],
      ),
      onTap: onTap,
    ),
  );
}
