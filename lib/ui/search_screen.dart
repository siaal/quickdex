import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/moves.dart';
import '../frecency/frecency.dart';
import '../search/search_index.dart';
import '../search/searchable.dart';
import '../trace.dart';
import 'art.dart';
import 'category_badge.dart';
import 'move_page.dart';
import 'pokemon_page.dart';
import 'type_badge.dart';

enum SearchMode { pokemon, all, moves }

/// Live search over Pokémon and/or moves, frecent hits first; a mode toggle sits
/// above the field so results never cover it. Frecent rows swipe away with Undo.
/// Keys: `search-mode`, `mode-<mode>`, `search-field`; Pokémon rows `row-<id>` /
/// `dismiss-<id>`, move rows `move-row-<id>` / `move-dismiss-<id>`.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.dex,
    required this.frecency,
    required this.index,
    required this.moves,
    required this.moveFrecency,
    this.initialMode = SearchMode.all,
    this.onModeChanged,
    this.focusRequests,
  });
  final Pokedex dex;
  final FrecencyStore frecency;
  final SearchIndex<PokemonEntry> index;

  /// Loaded in the background; until then move results are simply absent.
  final Future<MoveDex> moves;
  final FrecencyStore moveFrecency;
  final SearchMode initialMode;
  final ValueChanged<SearchMode>? onModeChanged;

  /// Each notification focuses the field and shows the keyboard, even if the
  /// field already has focus (e.g. the user dismissed the keyboard).
  final Listenable? focusRequests;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _precacheCount = 12;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late SearchMode _mode = widget.initialMode;
  SearchIndex<Move>? _moveIndex;
  late List<SearchHit<Searchable>> _hits = _search('');
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    widget.focusRequests?.addListener(_focusField);
    widget.moves.then(
      (moves) {
        if (!mounted) return;
        trace('search.moves.ready', {'count': moves.moves.length});
        _moveIndex = SearchIndex(moves.moves);
        _refresh();
      },
      onError: (Object e) => trace('search.moves.load_failed', {
        'error': e.runtimeType.toString(),
      }),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    final frecent = widget.index
        .search('', widget.frecency)
        .takeWhile((h) => h.frecent)
        .take(_precacheCount)
        .toList();
    trace('lookup.precache', {'count': frecent.length});
    for (final h in frecent) {
      precacheImage(AssetImage(thumbPath(h.entry.id)), context);
    }
  }

  void _focusField() {
    trace('search.focus.request', {'had_focus': _focus.hasFocus});
    if (_focus.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    widget.focusRequests?.removeListener(_focusField);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  FrecencyStore _storeFor(Searchable e) =>
      e is Move ? widget.moveFrecency : widget.frecency;

  String _prefixFor(Searchable e) => e is Move ? 'move-' : '';

  List<SearchHit<Searchable>> _search(String q) {
    final sw = Stopwatch()..start();
    List<SearchHit<Move>> moveHits() =>
        _moveIndex?.search(q, widget.moveFrecency) ?? const [];
    final hits = switch (_mode) {
      SearchMode.pokemon => widget.index.search(q, widget.frecency),
      SearchMode.moves => moveHits(),
      SearchMode.all => mergeHits(
        widget.index.search(q, widget.frecency),
        moveHits(),
      ),
    };
    trace('search.query.done', {
      'mode': _mode.name,
      'us': sw.elapsedMicroseconds,
      'len': q.length,
      'hits': hits.length,
    });
    return hits;
  }

  void _refresh() => setState(() => _hits = _search(_controller.text));

  void _setMode(SearchMode mode) {
    trace('search.mode.change', {'from': _mode.name, 'to': mode.name});
    _mode = mode;
    _refresh();
    widget.onModeChanged?.call(mode);
    _focus.requestFocus();
  }

  Widget _pageFor(Searchable e) => switch (e) {
    PokemonEntry() => PokemonPage(
      dex: widget.dex,
      frecency: widget.frecency,
      initialId: e.id,
      moves: widget.moves,
      moveFrecency: widget.moveFrecency,
    ),
    Move() => MovePage(move: e, frecency: widget.moveFrecency),
    _ => throw StateError('unknown searchable ${e.runtimeType}'),
  };

  Future<void> _open(Searchable e) async {
    trace('lookup.open', {'kind': e.runtimeType.toString(), 'id': e.id});
    _focus.unfocus();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => _pageFor(e)));
    if (!mounted) {
      trace('lookup.open.unmounted_after_pop');
      return;
    }
    _controller.clear();
    _refresh();
    _focus.requestFocus();
  }

  void _dismiss(Searchable e) {
    final store = _storeFor(e);
    final removed = store.remove(e.id);
    assert(removed != null, 'only frecent rows are dismissible');
    _refresh();
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed ${e.name} from recents'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            trace('lookup.dismiss.undo', {'prefix': _prefixFor(e), 'id': e.id});
            store.restore(e.id, removed!);
            if (mounted) _refresh();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final waitingForMoves = _mode == SearchMode.moves && _moveIndex == null;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: SegmentedButton<SearchMode>(
                key: const Key('search-mode'),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(
                    value: SearchMode.pokemon,
                    label: Text('Pokémon', key: Key('mode-pokemon')),
                  ),
                  ButtonSegment(
                    value: SearchMode.all,
                    label: Text('All', key: Key('mode-all')),
                  ),
                  ButtonSegment(
                    value: SearchMode.moves,
                    label: Text('Moves', key: Key('mode-moves')),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => _setMode(s.single),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                key: const Key('search-field'),
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: switch (_mode) {
                    SearchMode.pokemon => 'Search Pokémon',
                    SearchMode.all => 'Search Pokémon and moves',
                    SearchMode.moves => 'Search moves',
                  },
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (q) => setState(() => _hits = _search(q)),
                onSubmitted: (_) {
                  if (_hits.isEmpty) {
                    trace('lookup.submit.no_hits', {'mode': _mode.name});
                    _focus.requestFocus();
                    return;
                  }
                  _open(_hits.first.entry);
                },
              ),
            ),
            Expanded(
              child: waitingForMoves
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: _hits.length,
                      itemBuilder: (context, i) => _row(_hits[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(SearchHit<Searchable> h) {
    final e = h.entry;
    final p = _prefixFor(e);
    final tile = KeyedSubtree(
      key: Key('${p}row-${e.id}'),
      child: switch (e) {
        PokemonEntry() => _pokemonTile(e),
        Move() => _moveTile(e),
        _ => throw StateError('unknown searchable ${e.runtimeType}'),
      },
    );
    if (!h.frecent) return tile;
    return Dismissible(
      key: Key('${p}dismiss-${e.id}'),
      background: Container(color: Colors.red.withValues(alpha: 0.25)),
      onDismissed: (_) => _dismiss(e),
      child: tile,
    );
  }

  Widget _pokemonTile(PokemonEntry e) => ListTile(
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
    onTap: () => _open(e),
  );

  Widget _moveTile(Move m) => ListTile(
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
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            style: const TextStyle(fontSize: 14),
            '${m.power ?? '—'} · ${m.accuracy == null ? '—' : '${m.accuracy}%'}',
            textAlign: TextAlign.end,
          ),
        ),
      ],
    ),
    onTap: () => _open(m),
  );
}
