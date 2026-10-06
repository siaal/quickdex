import 'package:flutter/material.dart';

import '../data/models.dart';
import '../trace.dart';
import 'art.dart';

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

  static const _maxDepth = 5;

  @override
  Widget build(BuildContext context) {
    final chain = dex.chainFor(current);
    final theme = Theme.of(context);
    if (chain == null || chain.edges.isEmpty) {
      trace('evo.sheet.none', {'id': current.id});
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Does not evolve', key: Key('evo-none')),
        ),
      );
    }
    trace('evo.sheet.show', {'id': current.id, 'edges': chain.edges.length});
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Evolutions', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final root in chain.roots)
              ..._branch(context, chain, root, null, 0),
          ],
        ),
      ),
    );
  }

  List<Widget> _branch(
    BuildContext context,
    EvoChain chain,
    int id,
    String? method,
    int depth,
  ) {
    assert(depth < _maxDepth, 'evolution chain too deep (cycle?) at $id');
    final e = dex[id];
    final theme = Theme.of(context);
    return [
      InkWell(
        key: Key('evo-node-$id'),
        onTap: () => onSelect(id),
        child: Padding(
          padding: EdgeInsets.only(left: depth * 20.0, top: 4, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (method != null)
                Text('↳ $method', style: theme.textTheme.bodySmall),
              Row(
                children: [
                  Image.asset(thumbPath(id), width: 40, height: 40),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      e.name,
                      style: id == current.id
                          ? const TextStyle(fontWeight: FontWeight.bold)
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      for (final edge in chain.from(id))
        ..._branch(context, chain, edge.to, edge.method, depth + 1),
    ];
  }
}
