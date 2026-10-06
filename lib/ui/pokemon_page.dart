import 'package:flutter/material.dart';

import '../data/models.dart';
import '../frecency/frecency.dart';

class PokemonPage extends StatelessWidget {
  const PokemonPage({
    super.key,
    required this.dex,
    required this.frecency,
    required this.initialId,
  });
  final Pokedex dex;
  final FrecencyStore frecency;
  final int initialId;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(), body: Text(dex[initialId].name));
}
