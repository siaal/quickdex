import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/moves.dart';
import '../frecency/frecency.dart';
import '../trace.dart';
import 'category_badge.dart';
import 'game_scope.dart';
import 'type_badge.dart';
import 'move_learners.dart';
import 'pokemon_page.dart';

class MovePage extends StatefulWidget {
  const MovePage({
    super.key,
    required this.move,
    required this.frecency,
    required this.dex,
    required this.moves,
    required this.pokemonFrecency,
    this.onOpenType,
  });
  final Move move;
  final FrecencyStore frecency;
  final Pokedex dex;
  final Future<MoveDex> moves;
  final FrecencyStore pokemonFrecency;
  final ValueChanged<String>? onOpenType;

  @override
  State<MovePage> createState() => _MovePageState();
}

class _MovePageState extends State<MovePage> {
  @override
  void initState() {
    super.initState();
    // Unlike Pokémon pages there are no forms to switch, so credit on open.
    widget.frecency.visit(widget.move.id);
    trace('move.page.open', {'id': widget.move.id});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MoveDetails(widget.move),
          FutureBuilder<MoveDex>(
            future: widget.moves,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                trace('move.learners.load_failed', {'move': widget.move.id});
                return const Text('Unable to load learners');
              }
              final moves = snapshot.data;
              if (moves == null) {
                trace('move.learners.loading', {'move': widget.move.id});
                return const Text('Loading learners...');
              }
              return MoveLearners(
                move: widget.move,
                moves: moves,
                dex: widget.dex,
                onOpen: (entry) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PokemonPage(
                      dex: widget.dex,
                      initialId: entry.id,
                      frecency: widget.pokemonFrecency,
                      moves: widget.moves,
                      moveFrecency: widget.frecency,
                      onOpenType: widget.onOpenType,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// Bottom sheet with a move's details, without crediting a visit.
Future<void> showMoveDetails(BuildContext context, Move move) {
  trace('move.details.sheet', {'id': move.id});
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        key: const Key('move-details-sheet'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: MoveDetails(move),
      ),
    ),
  );
}

/// A move's name, type, category, stats, properties and texts.
class MoveDetails extends StatelessWidget {
  const MoveDetails(this.move, {super.key});
  final Move move;

  @override
  Widget build(BuildContext context) {
    final m = move;
    final theme = Theme.of(context);
    final stats = [
      ('Power', m.power?.toString() ?? '—'),
      ('Accuracy', m.accuracy == null ? '—' : '${m.accuracy}%'),
      ('PP', m.pp?.toString() ?? '—'),
      if (m.priority != 0)
        ('Priority', m.priority > 0 ? '+${m.priority}' : '${m.priority}'),
      if (m.chance != null) ('Effect', '${m.chance}%'),
    ];
    final properties = [
      m.target,
      m.contact ? 'Makes contact' : 'No contact',
      ...m.flags,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          m.name,
          key: const Key('move-name'),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TypeBadge(m.type, key: const Key('move-type'), icon: true),
            if (!m.inGame) ...[
              const SizedBox(width: 6),
              Container(
                key: const Key('move-not-in-game'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.hintColor),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Not in ${GameScope.of(context).name}',
                  style: TextStyle(color: theme.hintColor),
                ),
              ),
            ],
            // Right-aligned, away from the type, so it isn't read as a second type.
            const Spacer(),
            CategoryBadge(m.category, key: const Key('move-category')),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final (label, value) in stats)
              Expanded(
                key: Key('move-stat-$label'),
                child: Column(
                  children: [
                    Text(label, style: theme.textTheme.labelSmall),
                    Text(value, style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          properties,
          key: const Key('move-properties'),
          style: theme.textTheme.bodyMedium,
        ),
        if (m.text case final text?) ...[
          const SizedBox(height: 16),
          Text(
            text,
            key: const Key('move-text'),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (m.description case final desc?) ...[
          const SizedBox(height: 16),
          Text(desc, key: const Key('move-desc')),
        ],
      ],
    );
  }
}
