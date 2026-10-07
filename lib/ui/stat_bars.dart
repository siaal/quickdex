import 'package:flutter/material.dart';

class StatBars extends StatelessWidget {
  const StatBars({super.key, required this.stats});
  final List<int> stats;

  /// Display order (offence above defence): HP, Atk, SpA, Def, SpD, Spe.
  /// [stats] stays in PokéAPI order (hp, atk, def, spa, spd, spe); [order]
  /// maps each display row to its index in [stats].
  static const labels = ['HP', 'Atk', 'SpA', 'Def', 'SpD', 'Spe'];
  static const order = [0, 1, 3, 2, 4, 5];
  static const maxStat = 255;

  Color _color(int v) => v < 60
      ? Colors.red
      : v < 90
      ? Colors.orange
      : v < 120
      ? Colors.green
      : Colors.teal;

  @override
  Widget build(BuildContext context) {
    assert(stats.length == 6, 'expected 6 stats');
    return Column(
      children: [
        for (final (row, i) in order.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 40, child: Text(labels[row])),
                SizedBox(
                  width: 36,
                  child: Text('${stats[i]}', textAlign: TextAlign.right),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: stats[i] / maxStat,
                      minHeight: 8,
                      color: _color(stats[i]),
                      backgroundColor: Colors.black12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            const SizedBox(width: 40, child: Text('Total')),
            SizedBox(
              width: 36,
              child: Text(
                '${stats.fold(0, (a, b) => a + b)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
