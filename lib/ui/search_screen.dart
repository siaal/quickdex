import 'package:flutter/material.dart';

import '../frecency/frecency.dart';
import '../search/search_index.dart';
import '../search/searchable.dart';
import '../trace.dart';

/// Live search over [index], frecent hits first. Frecent rows swipe away with Undo.
/// Keys: `${keyPrefix}search-field`, `${keyPrefix}row-<id>`, `${keyPrefix}dismiss-<id>`.
class SearchScreen<T extends Searchable> extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.index,
    required this.frecency,
    required this.hint,
    required this.tileBuilder,
    required this.pageBuilder,
    this.keyPrefix = '',
    this.autofocus = true,
    this.precacheImageFor,
  });
  final SearchIndex<T> index;
  final FrecencyStore frecency;
  final String hint;
  final String keyPrefix;
  final bool autofocus;

  /// Row content; the screen supplies the key and tap handler.
  final ListTile Function(T item, VoidCallback onTap) tileBuilder;

  /// The page opened on tap. It is responsible for crediting the visit.
  final Widget Function(T item) pageBuilder;
  final ImageProvider Function(T item)? precacheImageFor;

  @override
  State<SearchScreen<T>> createState() => _SearchScreenState<T>();
}

class _SearchScreenState<T extends Searchable> extends State<SearchScreen<T>> {
  static const _precacheCount = 12;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late List<SearchHit<T>> _hits = _search('');
  bool _precached = false;

  String get _p => widget.keyPrefix;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final imageFor = widget.precacheImageFor;
    if (_precached || imageFor == null) return;
    _precached = true;
    final frecent = _hits
        .takeWhile((h) => h.frecent)
        .take(_precacheCount)
        .toList();
    trace('lookup.precache', {'prefix': _p, 'count': frecent.length});
    for (final h in frecent) {
      precacheImage(imageFor(h.entry), context);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<SearchHit<T>> _search(String q) {
    final sw = Stopwatch()..start();
    final hits = widget.index.search(q, widget.frecency);
    trace('search.query.done', {
      'prefix': _p,
      'us': sw.elapsedMicroseconds,
      'len': q.length,
      'hits': hits.length,
    });
    return hits;
  }

  void _refresh() => setState(() => _hits = _search(_controller.text));

  Future<void> _open(T e) async {
    trace('lookup.open', {'prefix': _p, 'id': e.id});
    _focus.unfocus();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => widget.pageBuilder(e)));
    if (!mounted) {
      trace('lookup.open.unmounted_after_pop');
      return;
    }
    _controller.clear();
    _refresh();
    _focus.requestFocus();
  }

  void _dismiss(T e) {
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
            trace('lookup.dismiss.undo', {'prefix': _p, 'id': e.id});
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
                key: Key('${_p}search-field'),
                controller: _controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (q) => setState(() => _hits = _search(q)),
                onSubmitted: (_) {
                  if (_hits.isEmpty) {
                    trace('lookup.submit.no_hits', {'prefix': _p});
                    _focus.requestFocus();
                    return;
                  }
                  _open(_hits.first.entry);
                },
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

  Widget _row(SearchHit<T> h) {
    final e = h.entry;
    final tile = KeyedSubtree(
      key: Key('${_p}row-${e.id}'),
      child: widget.tileBuilder(e, () => _open(e)),
    );
    if (!h.frecent) return tile;
    return Dismissible(
      key: Key('${_p}dismiss-${e.id}'),
      background: Container(color: Colors.red.withValues(alpha: 0.25)),
      onDismissed: (_) => _dismiss(e),
      child: tile,
    );
  }
}
