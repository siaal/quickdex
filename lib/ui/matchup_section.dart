import 'package:flutter/material.dart';

/// Translucent background for a matchup section, coloured by whether the
/// multiplier is good or bad for the viewer: as a [defending] type, 4×/2× are
/// red; as an attacker, 2× is green. 0× is grey either way, as in the grid.
Color matchupTint(double m, {required bool defending}) {
  final good = defending ? m < 1 : m > 1;
  final strong = m == 4 || m == 0.25;
  if (m == 0) return Colors.grey.withValues(alpha: 0.3);
  if (m == 1) return Colors.transparent;
  return (good ? Colors.green : Colors.red).withValues(
    alpha: strong ? 0.4 : 0.2,
  );
}

/// The multiplier furthest from 1× among [ms] (0× counts as furthest), so a
/// section holding 4× and 2× rows is tinted as 4×.
double extremeMultiplier(Iterable<double> ms) {
  assert(ms.isNotEmpty, 'a section needs at least one multiplier');
  double dist(double m) => m == 0 ? double.infinity : (m >= 1 ? m : 1 / m);
  return ms.reduce((a, b) => dist(b) > dist(a) ? b : a);
}

/// One matchup group (e.g. "Weak to") on a tinted rounded background. Each
/// row is an optional multiplier label (e.g. "4×") in a fixed-width column,
/// then its badges, which wrap within their own column. With no
/// rows it shows "None".
class MatchupSection extends StatelessWidget {
  const MatchupSection({
    super.key,
    required this.label,
    required this.tint,
    required this.rows,
  });
  final String label;
  final Color tint;
  final List<(String?, List<Widget>)> rows;

  /// Fixed so the multiplier column lines up across sections.
  static const multColumnWidth = 30.0;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        if (rows.isEmpty) const Text('None'),
        for (final (mult, badges) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            // Label baseline matches the first line of badge text.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // Its own column, so badges that wrap stay right of it.
                if (mult != null)
                  SizedBox(width: multColumnWidth, child: Text(mult)),
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: badges,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
