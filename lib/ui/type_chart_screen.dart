import 'package:flutter/material.dart';

import '../data/models.dart';
import 'type_focus.dart';
import 'type_grid.dart';

class TypeChartScreen extends StatelessWidget {
  const TypeChartScreen({super.key, required this.chart});
  final TypeChart chart;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Type Chart'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Focus'),
            Tab(text: 'Grid'),
          ],
        ),
      ),
      body: TabBarView(
        physics:
            const NeverScrollableScrollPhysics(), // grid pans must not swipe tabs
        children: [
          TypeFocus(chart: chart),
          TypeGrid(chart: chart),
        ],
      ),
    ),
  );
}
