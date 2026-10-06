import 'package:flutter/material.dart';

class StatBars extends StatelessWidget {
  const StatBars({super.key, required this.stats});
  final List<int> stats;

  static const labels = ['HP', 'Atk', 'Def', 'SpA', 'SpD', 'Spe'];
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
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 40, child: Text(labels[i])),
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
