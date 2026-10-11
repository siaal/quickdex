import 'package:flutter/material.dart';

import '../data/models.dart';
import '../trace.dart';
import 'type_finder.dart';
import 'type_focus.dart';
import 'type_grid.dart';

class TypeChartScreen extends StatefulWidget {
  const TypeChartScreen({
    super.key,
    required this.dex,
    this.focus,
    this.onOpenPokemon,
  });
  final Pokedex dex;

  /// Opens a Pokémon tapped in the Finder tab.
  final ValueChanged<PokemonEntry>? onOpenPokemon;

  /// Focus tab state; [TypeFocusController.show] brings the Focus tab forward.
  final TypeFocusController? focus;

  @override
  State<TypeChartScreen> createState() => _TypeChartScreenState();
}

class _TypeChartScreenState extends State<TypeChartScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);
  late final _focus = widget.focus ?? TypeFocusController();

  @override
  void initState() {
    super.initState();
    _focus.reveals.addListener(_reveal);
  }

  void _reveal() {
    trace('type_chart.reveal_focus', {'from_tab': _tabs.index});
    _tabs.index = 0;
  }

  @override
  void dispose() {
    _focus.reveals.removeListener(_reveal);
    if (widget.focus == null) _focus.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Type Chart'),
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: 'Focus'),
          Tab(text: 'Grid'),
          Tab(text: 'Finder'),
        ],
      ),
    ),
    body: TabBarView(
      controller: _tabs,
      physics:
          const NeverScrollableScrollPhysics(), // grid pans must not swipe tabs
      children: [
        TypeFocus(chart: widget.dex.types, controller: _focus),
        TypeGrid(chart: widget.dex.types),
        TypeFinder(dex: widget.dex, onOpen: widget.onOpenPokemon),
      ],
    ),
  );
}
