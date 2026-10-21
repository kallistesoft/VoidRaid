import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:void_raid/game/world.dart';

/// Plays a level with an invincible ship sweeping side to side.
/// Returns the simulated seconds it took, or null if it never cleared.
double? autoplay(int level, {int weapon = 2, double limit = 240}) {
  final world = World(Run(level: level, weapon: weapon), rng: Random(level));
  const dt = 1 / 60;
  while (world.time < limit) {
    world.invulnerable = 1;
    // Chase the nearest target horizontally, with a slow sweep as fallback.
    final targets = [
      for (final e in world.enemies) e.x,
      if (world.boss != null) world.boss!.x,
    ];
    final goal = targets.isEmpty
        ? World.width / 2
        : targets.reduce((a, b) => (a - world.playerX).abs() < (b - world.playerX).abs() ? a : b) + sin(world.time) * 30;
    world.dragBy((goal - world.playerX).clamp(-4, 4));
    world.update(dt);
    if (world.cleared) return world.time;
    if (world.over) return null;
  }
  return null;
}

void main() {
  test('levels 1–25, bosses included, can all be cleared', () {
    for (var level = 1; level <= 25; level++) {
      final t = autoplay(level, weapon: 1 + min(3, level ~/ 5));
      expect(t, isNotNull, reason: 'level $level never cleared');
    }
  });

  test('getting hit costs a life and a weapon level; shields absorb one hit', () {
    final run = Run(weapon: 3, shield: true);
    final world = World(run, rng: Random(1))..invulnerable = 0;
    world.enemyBullets.add(Bullet(world.playerX, World.playerY, 0, 0));
    world.update(1 / 60);
    expect(run.shield, isFalse);
    expect(run.lives, 3);

    world.invulnerable = 0;
    world.enemyBullets.add(Bullet(world.playerX, World.playerY, 0, 0));
    world.update(1 / 60);
    expect(run.lives, 2);
    expect(run.weapon, 2);
  });

  test('losing the last life ends the game', () {
    final run = Run(lives: 1);
    final world = World(run, rng: Random(1))..invulnerable = 0;
    world.enemyBullets.add(Bullet(world.playerX, World.playerY, 0, 0));
    world.update(1 / 60);
    expect(world.over, isTrue);
    expect(world.events, contains(GameEvent.gameOver));
  });

  test('clearing a level adds the untouched bonus once', () {
    final run = Run();
    final world = World(run, rng: Random(1));
    final before = run.score;
    final s = world.finish();
    expect(s.noHitBonus, 300);
    expect(run.score, before + s.bonus);
  });
}
