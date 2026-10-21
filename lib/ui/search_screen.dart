import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/items.dart';
import '../data/models.dart';
import '../data/moves.dart';
import '../frecency/frecency.dart';
import '../search/search_index.dart';
import '../search/searchable.dart';
import '../trace.dart';
import 'art.dart';
import 'item_page.dart';
import 'move_page.dart';
import 'pokemon_page.dart';
import 'move_tile.dart';
import 'pokemon_tile.dart';

/// Other is moves and items.
enum SearchMode { pokemon, all, other }

/// Live search over Pokémon, moves and items: with nothing typed, recently
/// visited first; once typed, frecent hits first; a mode toggle sits
/// above the field so results never cover it. Frecent rows swipe away with Undo.
/// Keys: `search-mode`, `mode-<mode>`, `search-settings`, `search-field`; Pokémon rows `row-<id>` /
/// `dismiss-<id>`, move rows `move-row-<id>` / `move-dismiss-<id>`, item rows
/// `item-row-<id>` / `item-dismiss-<id>`.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.dex,
    required this.frecency,
    required this.index,
    required this.moves,
    required this.moveFrecency,
    this.items,
    this.itemFrecency,
    this.initialMode = SearchMode.all,
    this.onModeChanged,
    this.focusRequests,
    this.onOpenType,
    this.onOpenSettings,
  });
  final Pokedex dex;
  final FrecencyStore frecency;
  final SearchIndex<PokemonEntry> index;

  /// Loaded in the background; until then move results are simply absent.
  final Future<MoveDex> moves;
  final FrecencyStore moveFrecency;

  /// Like [moves]; null (with [itemFrecency]) leaves items out.
  final Future<ItemDex>? items;
  final FrecencyStore? itemFrecency;
  final SearchMode initialMode;
  final ValueChanged<SearchMode>? onModeChanged;

  /// Each notification focuses the field and shows the keyboard, even if the
  /// field already has focus (e.g. the user dismissed the keyboard).
  final Listenable? focusRequests;

  /// Passed to Pokémon pages: open a tapped type pill in the Type Chart.
  final ValueChanged<String>? onOpenType;

  /// The cog right of the mode toggle; no cog when null.
  final VoidCallback? onOpenSettings;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _precacheCount = 12;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late SearchMode _mode = widget.initialMode;
  SearchIndex<Move>? _moveIndex;
  SearchIndex<Item>? _itemIndex;
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
    assert(
      (widget.items == null) == (widget.itemFrecency == null),
      'items need their frecency store',
    );
    widget.items?.then(
      (items) {
        if (!mounted) return;
        trace('search.items.ready', {'count': items.items.length});
        _itemIndex = SearchIndex(items.items);
        _refresh();
      },
      onError: (Object e) => trace('search.items.load_failed', {
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

  FrecencyStore _storeFor(Searchable e) => switch (e) {
    Move() => widget.moveFrecency,
    Item() => widget.itemFrecency!,
    _ => widget.frecency,
  };

  String _prefixFor(Searchable e) => switch (e) {
    Move() => 'move-',
    Item() => 'item-',
    _ => '',
  };

  List<SearchHit<Searchable>> _search(String q) {
    final sw = Stopwatch()..start();
    final byRecency = isRecencyQuery(q);
    List<SearchHit<Searchable>> other() => mergeHits(
      _moveIndex?.search(q, widget.moveFrecency) ?? const [],
      _itemIndex?.search(q, widget.itemFrecency!) ?? const [],
      byRecency: byRecency,
    );
    final hits = switch (_mode) {
      SearchMode.pokemon => widget.index.search(q, widget.frecency),
      SearchMode.other => other(),
      SearchMode.all => mergeHits(
        widget.index.search(q, widget.frecency),
        other(),
        byRecency: byRecency,
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
      onOpenType: widget.onOpenType,
    ),
    Move() => MovePage(
      move: e,
      frecency: widget.moveFrecency,
      dex: widget.dex,
      moves: widget.moves,
      pokemonFrecency: widget.frecency,
      onOpenType: widget.onOpenType,
    ),
    Item() => ItemPage(item: e, frecency: widget.itemFrecency!),
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
        // An action would otherwise keep it up until dismissed.
        persist: false,
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
    final waitingForOther =
        _mode == SearchMode.other && _moveIndex == null && _itemIndex == null;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Shrinks rather than overflowing the cog at large font sizes.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
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
                            value: SearchMode.other,
                            label: Text('Other', key: Key('mode-other')),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (s) => _setMode(s.single),
                      ),
                    ),
                  ),
                  if (widget.onOpenSettings case final open?)
                    IconButton(
                      key: const Key('search-settings'),
                      tooltip: 'Settings',
                      icon: const Icon(Icons.settings),
                      onPressed: () {
                        trace('search.settings.tap');
                        open();
                      },
                    ),
                ],
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
                    SearchMode.all => 'Search Pokémon, moves and items',
                    SearchMode.other => 'Search moves and items',
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
              child: waitingForOther
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
        PokemonEntry() => PokemonTile(e, onTap: () => _open(e)),
        Move() => MoveTile(e, onTap: () => _open(e)),
        Item() => ItemTile(e, onTap: () => _open(e)),
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
}
