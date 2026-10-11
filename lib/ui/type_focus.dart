import 'package:flutter/material.dart';

import '../data/defense.dart';
import '../data/models.dart';
import '../trace.dart';
import 'matchup_section.dart';
import 'type_badge.dart';
import 'type_style.dart';
import 'type_tile.dart';

enum FocusMode { attacker, defender }

/// The Focus tab's selection and mode. Outlives [TypeFocus] (which is rebuilt
/// when its tab is shown again) so other screens can drive it via [show].
class TypeFocusController extends ChangeNotifier {
  FocusMode _mode = FocusMode.attacker;
  FocusMode get mode => _mode;

  /// Primary type first; at most two.
  List<String> _selected = const [];
  List<String> get selected => _selected;

  /// Bumped by [show] so the Type Chart screen can bring the Focus tab forward.
  final reveals = ValueNotifier(0);

  set mode(FocusMode m) {
    trace('focus.mode', {'mode': m.name});
    _mode = m;
    notifyListeners();
  }

  /// Focus [t] alone, keeping the mode.
  void pick(String t) {
    trace('focus.type', {'type': t});
    _selected = [t];
    notifyListeners();
  }

  /// Add [t] as the second type (replacing any second); adding a selected
  /// type removes it unless it is the only one.
  void add(String t) {
    final List<String> next;
    if (selected.isEmpty) {
      trace('focus.add.first', {'type': t});
      next = [t];
    } else if (_selected.contains(t)) {
      if (_selected.length == 1) {
        trace('focus.add.only_type_kept', {'type': t});
        return;
      }
      trace('focus.add.remove', {'type': t});
      next = [
        for (final s in _selected)
          if (s != t) s,
      ];
    } else {
      trace('focus.add.second', {
        'primary': _selected.first,
        'type': t,
        'replaced': _selected.length == 2 ? _selected.last : null,
      });
      next = [_selected.first, t];
    }
    assert(
      next.isNotEmpty && next.length <= 2 && next.toSet().length == next.length,
    );
    _selected = next;
    notifyListeners();
  }

  /// Open [t] alone in [mode] from another screen.
  void show(String t, FocusMode mode) {
    trace('focus.show', {'type': t, 'mode': mode.name});
    _mode = mode;
    _selected = [t];
    reveals.value++;
    notifyListeners();
  }

  @override
  void dispose() {
    reveals.dispose();
    super.dispose();
  }
}

/// Tap a type to focus it alone; long-press or right-click another to add it
/// as a second type (dual-type defender, or two-type STAB coverage). Result
/// pills behave the same way and keep the Attacker/Defender mode.
class TypeFocus extends StatefulWidget {
  const TypeFocus({super.key, required this.chart, this.controller});
  final TypeChart chart;

  /// Owns the selection; a private one is used when null.
  final TypeFocusController? controller;

  @override
  State<TypeFocus> createState() => _TypeFocusState();
}

class _TypeFocusState extends State<TypeFocus> {
  TypeFocusController? _own;
  TypeFocusController get _c =>
      widget.controller ?? (_own ??= TypeFocusController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  /// Sections as (label, multipliers). Only non-empty multipliers get a row.
  static const _attackGroups = [
    ('Super effective', [2.0]),
    ('Not very effective', [0.5]),
    ('No effect', [0.0]),
  ];
  static const _defendGroups = [
    ('Weak to', [4.0, 2.0]),
    ('Resistant to', [0.5, 0.25]),
    ('Immune to', [0.0]),
  ];

  Widget _section(String label, List<double> mults, Map<String, double> m) {
    final defending = _c.mode == FocusMode.defender;
    List<String> at(double x) => [
      for (final t in widget.chart.order)
        if (m[t] == x) t,
    ];
    final present = [
      for (final x in mults)
        if (at(x).isNotEmpty) x,
    ];
    return MatchupSection(
      label: label,
      tint: present.isEmpty
          ? Colors.transparent
          : matchupTint(extremeMultiplier(present), defending: defending),
      rows: [
        for (final x in present)
          (
            multLabel(x),
            [
              for (final t in at(x))
                TypeBadge(
                  t,
                  key: Key('focus-result-$label (${multLabel(x)})-$t'),
                  onTap: () => _c.pick(t),
                  onAdd: () => _c.add(t),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _c.selected;
    final mode = _c.mode;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<FocusMode>(
          key: const Key('focus-mode'),
          segments: const [
            ButtonSegment(value: FocusMode.attacker, label: Text('Attacker')),
            ButtonSegment(value: FocusMode.defender, label: Text('Defender')),
          ],
          selected: {mode},
          onSelectionChanged: (s) => _c.mode = s.single,
        ),
        const SizedBox(height: 12),
        TypeTileGrid(
          order: widget.chart.order,
          selected: selected,
          keyPrefix: 'focus-type',
          onTap: _c.pick,
          onAdd: _c.add,
        ),
        const SizedBox(height: 16),
        if (selected.isEmpty)
          const Text('Pick a type')
        else ...[
          Text(
            selected.map(typeLabel).join(' + '),
            key: const Key('focus-selection'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final (label, mults)
              in mode == FocusMode.attacker ? _attackGroups : _defendGroups)
            _section(
              label,
              mults,
              mode == FocusMode.attacker
                  ? widget.chart.coverageFor(selected)
                  : widget.chart.defenseFor(selected),
            ),
        ],
      ],
    );
  }
}
