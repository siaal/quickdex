import 'package:flutter/material.dart';

import '../data/models.dart';
import '../frecency/frecency.dart';
import '../search/search_index.dart';
import '../trace.dart';
import 'art.dart';
import 'pokemon_page.dart';
import 'type_badge.dart';

class LookupScreen extends StatefulWidget {
  const LookupScreen({
    super.key,
    required this.dex,
    required this.frecency,
    required this.index,
  });
  final Pokedex dex;
  final FrecencyStore frecency;
  final SearchIndex index;

  @override
  State<LookupScreen> createState() => _LookupScreenState();
}

class _LookupScreenState extends State<LookupScreen> {
  static const _precacheCount = 12;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late List<SearchHit> _hits = _search('');
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    final frecent = _hits
        .takeWhile((h) => h.frecent)
        .take(_precacheCount)
        .toList();
    trace('lookup.precache', {'count': frecent.length});
    for (final h in frecent) {
      precacheImage(AssetImage(thumbPath(h.entry.id)), context);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<SearchHit> _search(String q) {
    final sw = Stopwatch()..start();
    final hits = widget.index.search(q, widget.frecency);
    trace('search.query.done', {
      'us': sw.elapsedMicroseconds,
      'len': q.length,
      'hits': hits.length,
    });
    return hits;
  }

  void _refresh() => setState(() => _hits = _search(_controller.text));

  Future<void> _open(PokemonEntry e) async {
    trace('lookup.open', {'id': e.id});
    _focus.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PokemonPage(
          dex: widget.dex,
          frecency: widget.frecency,
          initialId: e.id,
        ),
      ),
    );
    if (!mounted) {
      trace('lookup.open.unmounted_after_pop');
      return;
    }
    _controller.clear();
    _refresh();
    _focus.requestFocus();
  }

  void _dismiss(PokemonEntry e) {
    final removed = widget.frecency.remove(e.id);
    assert(removed != null, 'only frecent rows are dismissible');
    _refresh();
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed ${e.name} from recents'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            trace('lookup.dismiss.undo', {'id': e.id});
            widget.frecency.restore(e.id, removed!);
            if (mounted) _refresh();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                key: const Key('search-field'),
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search Pokémon',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (q) => setState(() => _hits = _search(q)),
              ),
            ),
            Expanded(
              child: ListView.builder(
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

  Widget _row(SearchHit h) {
    final e = h.entry;
    final tile = ListTile(
      key: Key('row-${e.id}'),
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
    if (!h.frecent) return tile;
    return Dismissible(
      key: Key('dismiss-${e.id}'),
      background: Container(color: Colors.red.withValues(alpha: 0.25)),
      onDismissed: (_) => _dismiss(e),
      child: tile,
    );
  }
}
