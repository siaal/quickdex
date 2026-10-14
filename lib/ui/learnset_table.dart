import 'package:flutter/material.dart';

import '../data/game.dart';
import '../data/moves.dart';
import '../trace.dart';
import 'art.dart';
import 'category_badge.dart';

/// Level up | All | TM, keyed `learn-filter`, segments `learn-filter-<name>`.
class LearnFilterToggle extends StatelessWidget {
  const LearnFilterToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final LearnFilter value;
  final ValueChanged<LearnFilter> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<LearnFilter>(
    key: const Key('learn-filter'),
    showSelectedIcon: false,
    style: const ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    segments: [
      for (final (f, label) in const [
        (LearnFilter.levelUp, 'Level up'),
        (LearnFilter.all, 'All'),
        (LearnFilter.tm, 'TM'),
      ])
        ButtonSegment(
          value: f,
          label: Text(label, key: Key('learn-filter-${f.name}')),
        ),
    ],
    selected: {value},
    onSelectionChanged: (s) => onChanged(s.single),
  );
}

/// A Level up | All | TM toggle over level-up moves and TMs (vanilla TMs/HMs
/// by number, or Scrambled's grouped by the badges that unlock them); tapping
/// a move calls [onOpen]. Toggle `learn-filter` (segments `learn-filter-<name>`);
/// row keys `learn-<level>-<move id>`, `tm-<badges>-<move id>`,
/// `machine-<label>`; TM section `tms`, its group headings `tm-badges-<n>`.
class LearnsetTable extends StatefulWidget {
  const LearnsetTable({
    super.key,
    required this.learnset,
    required this.moves,
    required this.onOpen,
  });
  final Learnset learnset;
  final MoveDex moves;
  final ValueChanged<Move> onOpen;

  /// The game's starting filter: All in Scrambled Scarlet (TMs are the main
  /// source of moves there), Level up elsewhere.
  static LearnFilter defaultFilter(GameInfo game) =>
      game.key == 'scrambled' ? LearnFilter.all : LearnFilter.levelUp;

  /// The filter last picked per game, kept until the app restarts.
  static final _chosen = <String, LearnFilter>{};

  @visibleForTesting
  static void resetFilters() => _chosen.clear();

  @override
  State<LearnsetTable> createState() => _LearnsetTableState();
}

class _LearnsetTableState extends State<LearnsetTable> {
  Learnset get learnset => widget.learnset;
  MoveDex get moves => widget.moves;

  LearnFilter get _filter =>
      LearnsetTable._chosen[moves.game.key] ??
      LearnsetTable.defaultFilter(moves.game);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);
    final filter = _filter;
    return Column(
      key: const Key('learnset'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LearnFilterToggle(
          value: filter,
          onChanged: (f) {
            trace('learnset.filter', {
              'game': moves.game.key,
              'filter': f.name,
            });
            setState(() => LearnsetTable._chosen[moves.game.key] = f);
          },
        ),
        if (filter != LearnFilter.tm) ..._levelUp(theme, hint),
        if (filter != LearnFilter.levelUp) ..._tms(context, theme, hint),
      ],
    );
  }

  Widget _columns(TextStyle? hint, String first) => Row(
    children: [
      SizedBox(width: 48, child: Text(first, style: hint)),
      const SizedBox(width: 52),
      Expanded(child: Text('Move', style: hint)),
      SizedBox(
        width: 36,
        child: Text('Pow', style: hint, textAlign: TextAlign.end),
      ),
      SizedBox(
        width: 48,
        child: Text('Acc', style: hint, textAlign: TextAlign.end),
      ),
    ],
  );

  List<Widget> _levelUp(ThemeData theme, TextStyle? hint) => [
    const SizedBox(height: 8),
    Text('Level-up moves', style: theme.textTheme.titleMedium),
    if (learnset.game case final game?)
      Text('From $game', key: const Key('learnset-game'), style: hint),
    const SizedBox(height: 4),
    _columns(hint, 'Lv'),
    for (final (:level, :move) in learnset.moves)
      _row(context, 'learn-$level-$move', level == 0 ? 'Evo' : '$level', move),
  ];

  List<Widget> _tms(BuildContext context, ThemeData theme, TextStyle? hint) {
    if (learnset.machines.isNotEmpty) {
      trace('learnset.machines', {'count': learnset.machines.length});
      return [
        const SizedBox(height: 16),
        Text('TMs', key: const Key('tms'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        _columns(hint, 'TM'),
        for (final (:label, :move) in learnset.machines)
          _row(context, 'machine-$label', label, move),
      ];
    }
    if (learnset.tms.isEmpty) {
      trace('learnset.no_tms', {'game': moves.game.key});
      return [
        const SizedBox(height: 16),
        Text('TMs', key: const Key('tms'), style: theme.textTheme.titleMedium),
        Text('Learns no TMs', key: const Key('no-tms'), style: hint),
      ];
    }
    return _badgeTms(context, theme, hint);
  }

  List<Widget> _badgeTms(
    BuildContext context,
    ThemeData theme,
    TextStyle? hint,
  ) {
    trace('learnset.tms', {'count': learnset.tms.length});
    final out = <Widget>[
      const SizedBox(height: 16),
      Text('TMs', key: const Key('tms'), style: theme.textTheme.titleMedium),
      Text('Sold once you have the badges', style: hint),
    ];
    int? group;
    for (final (:badges, :move) in learnset.tms) {
      assert(group == null || badges >= group, 'TMs not in badge order');
      if (badges != group) {
        group = badges;
        out.add(
          Padding(
            key: Key('tm-badges-$badges'),
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text(
              '$badges ${badges == 1 ? 'badge' : 'badges'}',
              style: theme.textTheme.labelLarge,
            ),
          ),
        );
      }
      out.add(_row(context, 'tm-$badges-$move', '', move));
    }
    return out;
  }

  Widget _row(BuildContext context, String key, String label, int moveId) {
    final m = moves.byId[moveId]!;
    return InkWell(
      key: Key(key),
      onTap: () {
        trace('learnset.open', {'move': moveId, 'row': key});
        widget.onOpen(m);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 48, child: Text(label)),
            CategoryIcon(m.category),
            const SizedBox(width: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(typeIconPath(m.type), width: 20, height: 20),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(m.name)),
            SizedBox(
              width: 36,
              child: Text('${m.power ?? '—'}', textAlign: TextAlign.end),
            ),
            SizedBox(
              width: 48,
              child: Text(
                m.accuracy == null ? '—' : '${m.accuracy}%',
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
