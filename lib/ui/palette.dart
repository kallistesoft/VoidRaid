import 'package:flutter/material.dart';

const background = Color(0xFF070712);
const accent = Color(0xFF38E1FF); // player cyan
const hot = Color(0xFFFF3B6B); // enemy fire
const gold = Color(0xFFFFD447);

/// Enemy colours by [EnemyKind] index.
const enemyColors = <Color>[
  Color(0xFFFF4FD8), // drone
  Color(0xFFFF9F43), // gunner
  Color(0xFF4ADE80), // tank
  Color(0xFFFFE14D), // diver
];

/// Particle colours: the four enemy kinds, rock, white-hot, player.
const particleColors = <Color>[
  ...enemyColors,
  Color(0xFFB8A99A),
  Color(0xFFFFF4D6),
  accent,
];

/// Boss colours by [BossKind] index.
const bossColors = <Color>[
  Color(0xFFFF5D5D), // warden
  Color(0xFFFFB020), // hive
  Color(0xFFA77BFF), // vortex
  Color(0xFF5DF2FF), // phantom
  Color(0xFFFF4FD8), // core
];

/// Deep-space tint for a level.
Color levelTint(double hue) => HSVColor.fromAHSV(1, hue, 0.7, 0.22).toColor();

TextStyle neon(double size, {Color color = accent, FontWeight weight = FontWeight.w900, double spacing = 2}) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: size * 0.5)],
    );
