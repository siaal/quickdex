import 'package:flutter/material.dart';

import '../data/moves.dart';
import '../frecency/frecency.dart';
import '../search/search_index.dart';
import 'art.dart';
import 'category_badge.dart';
import 'move_page.dart';
import 'search_screen.dart';

class MovesScreen extends StatefulWidget {
  const MovesScreen({super.key, required this.moves, required this.frecency});
  final MoveDex moves;
  final FrecencyStore frecency;

  @override
  State<MovesScreen> createState() => _MovesScreenState();
}

class _MovesScreenState extends State<MovesScreen> {
  late final _index = SearchIndex(widget.moves.moves);

  @override
  Widget build(BuildContext context) => SearchScreen<Move>(
    index: _index,
    frecency: widget.frecency,
    hint: 'Search moves',
    keyPrefix: 'move-',
    pageBuilder: (m) => MovePage(move: m, frecency: widget.frecency),
    tileBuilder: (m, onTap) => ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(typeIconPath(m.type), width: 32, height: 32),
      ),
      title: Text(m.name),
      subtitle: m.inScarlet ? null : const Text('Not in Scarlet'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CategoryBadge(m.category, compact: true),
          SizedBox(
            width: 64,
            child: Text(
              '${m.power ?? '—'} · ${m.accuracy == null ? '—' : '${m.accuracy}%'}',
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
      onTap: onTap,
    ),
  );
}
