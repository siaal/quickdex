import 'package:flutter/material.dart';

/// The Tera Orb: one per side in Versus, dragged onto a Pokémon to
/// terastallize it.
class TeraOrb extends StatelessWidget {
  const TeraOrb({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: size / 12),
      gradient: const SweepGradient(
        colors: [
          Color(0xFFE8486C),
          Color(0xFFF5C33B),
          Color(0xFF5BC97A),
          Color(0xFF4A9FE8),
          Color(0xFFA368E0),
          Color(0xFFE8486C),
        ],
      ),
      boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black54)],
    ),
  );
}
