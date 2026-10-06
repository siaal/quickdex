import 'package:flutter/material.dart';

import '../data/models.dart';

class TypeChartScreen extends StatelessWidget {
  const TypeChartScreen({super.key, required this.chart});
  final TypeChart chart;

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
