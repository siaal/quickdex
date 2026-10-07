import 'package:flutter/material.dart';

import '../data/models.dart';
import '../frecency/frecency.dart';
import '../trace.dart';
import 'ability_line.dart';
import 'art.dart';
import 'defense_table.dart';
import 'evo_drag_menu.dart';
import 'evolution_sheet.dart';
import 'stat_bars.dart';
import 'type_badge.dart';

class PokemonPage extends StatefulWidget {
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
  State<PokemonPage> createState() => _PokemonPageState();
}

class _PokemonPageState extends State<PokemonPage> with WidgetsBindingObserver {
  late int _id = widget.initialId;
  int? _creditedId;

  @override
  void initState() {
    super.initState();
    assert(widget.dex.byId.containsKey(_id), 'unknown entry $_id');
    WidgetsBinding.instance.addObserver(this);
    trace('page.open', {'id': _id});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _credit('paused');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _credit('leave');
    super.dispose();
  }

  /// A visit is credited to whatever entry is on screen when the user leaves.
  void _credit(String reason) {
    if (_creditedId == _id) {
      trace('page.credit.skip_already', {'id': _id, 'reason': reason});
      return;
    }
    _creditedId = _id;
    trace('page.credit', {'id': _id, 'reason': reason});
    widget.frecency.visit(_id);
  }

  void _show(int id, String via) {
    assert(widget.dex.byId.containsKey(id), 'unknown entry $id');
    trace('page.swap', {'from': _id, 'to': id, 'via': via});
    setState(() => _id = id);
  }

  void _openEvolutions() {
    final e = widget.dex[_id];
    trace('page.evo.open', {'id': e.id, 'chain': e.chain});
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => EvolutionSheet(
        dex: widget.dex,
        current: e,
        onSelect: (id) {
          Navigator.of(sheetContext).pop();
          _show(id, 'evolution');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.dex[_id];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Image.asset(
                fullPath(e.id),
                key: Key('portrait-${e.id}'),
                width: 160,
                height: 160,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text.rich(
                    key: const Key('name-line'),
                    TextSpan(
                      children: [
                        TextSpan(
                          text: e.name,
                          style: theme.textTheme.headlineSmall,
                        ),
                        TextSpan(
                          text: '  ${e.dexLabel}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                EvoDragMenu(
                  dex: widget.dex,
                  current: e,
                  onSelect: (id) => _show(id, 'evo-drag'),
                  child: TextButton.icon(
                    key: const Key('evo-button'),
                    onPressed: _openEvolutions,
                    icon: const Icon(Icons.account_tree_outlined, size: 18),
                    label: const Text('Evo'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [for (final t in e.types) TypeBadge(t)]),
            AbilityLine(entry: e, abilities: widget.dex.abilities),
            if (e.forms.length > 1) ...[
              const SizedBox(height: 12),
              Wrap(
                key: const Key('form-chips'),
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in e.forms)
                    ChoiceChip(
                      key: Key('form-chip-$id'),
                      label: Text(widget.dex[id].chipLabel),
                      selected: id == e.id,
                      onSelected: (_) => _show(id, 'form_chip'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            StatBars(stats: e.stats),
            const SizedBox(height: 16),
            DefenseTable(
              defense: e.defense,
              order: widget.dex.types.order,
              guard: e.guard,
            ),
            const SizedBox(height: 16),
            Text(
              'Catch rate ${e.catchRate} · Weight ${e.weightKg} kg',
              key: const Key('misc-line'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
