import 'package:flutter/material.dart';

import '../data/models.dart';

class EvolutionSheet extends StatelessWidget {
  const EvolutionSheet({
    super.key,
    required this.dex,
    required this.current,
    required this.onSelect,
  });
  final Pokedex dex;
  final PokemonEntry current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
