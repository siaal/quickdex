import 'package:flutter/material.dart';

import '../data/models.dart';
import '../search/normalise.dart';
import '../trace.dart';
import 'pokemon_tile.dart';
import 'type_focus.dart';
import 'type_style.dart';
import 'type_tile.dart';

/// Pick one or two types (tap picks, long-press/right-click adds a second) to
/// list every Pokémon with all of them, in dex order. A name filter and a
/// "Highest evolution only" toggle narrow the list. Keys: `finder-type-<type>`,
/// `finder-search`, `finder-final-only`, rows `finder-row-<id>`.
class TypeFinder extends StatefulWidget {
  const TypeFinder({super.key, required this.dex, this.onOpen});
  final Pokedex dex;

  /// Called with a tapped row; rows aren't tappable when null.
  final ValueChanged<PokemonEntry>? onOpen;

  @override
  State<TypeFinder> createState() => _TypeFinderState();
}

class _TypeFinderState extends State<TypeFinder>
    with AutomaticKeepAliveClientMixin {
  // Only the selection logic is used; the mode is irrelevant here.
  final _types = TypeFocusController();
  final _query = TextEditingController();
  bool _finalOnly = false;

  @override
  bool get wantKeepAlive => true; // keep picks and query across tab switches

  @override
  void initState() {
    super.initState();
    _types.addListener(_changed);
    _query.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _types.dispose();
    _query.dispose();
    super.dispose();
  }

  List<PokemonEntry> _results() {
    final types = _types.selected;
    final q = normalise(_query.text);
    final out = [
      for (final e in widget.dex.entries)
        if (types.every(e.types.contains) &&
            (q.isEmpty || normalise(e.name).contains(q)) &&
            (!_finalOnly || widget.dex.isFinalStage(e)))
          e,
    ];
    trace('finder.results', {
      'types': types,
      'query_len': q.length,
      'final_only': _finalOnly,
      'count': out.length,
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final picked = _types.selected.isNotEmpty || _query.text.isNotEmpty;
    final results = picked ? _results() : const <PokemonEntry>[];
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TypeTileGrid(
            order: widget.dex.types.order,
            selected: _types.selected,
            keyPrefix: 'finder-type',
            onTap: _types.pick,
            onAdd: _types.add,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('finder-search'),
            controller: _query,
            decoration: const InputDecoration(
              hintText: 'Filter by name',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          CheckboxListTile(
            key: const Key('finder-final-only'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Highest evolution only'),
            value: _finalOnly,
            onChanged: (v) {
              trace('finder.final_only', {'on': v});
              setState(() => _finalOnly = v!);
            },
          ),
          if (!picked)
            const Text('Pick a type')
          else
            Text(
              '${_types.selected.isEmpty ? 'Any type' : _types.selected.map(typeLabel).join(' + ')}'
              ' · ${results.length} Pokémon',
              key: const Key('finder-summary'),
              style: theme.textTheme.titleMedium,
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return header;
        final e = results[i - 1];
        return PokemonTile(
          e,
          key: Key('finder-row-${e.id}'),
          onTap: () {
            trace('finder.open', {'id': e.id});
            widget.onOpen?.call(e);
          },
        );
      },
    );
  }
}
