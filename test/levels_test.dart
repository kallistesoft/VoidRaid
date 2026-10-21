import 'package:flutter_test/flutter_test.dart';
import 'package:void_raid/game/levels.dart';

void main() {
  test('a boss every fifth level, cycling through all five', () {
    for (var n = 1; n <= 50; n++) {
      expect(LevelSpec.forLevel(n).isBoss, n % 5 == 0, reason: 'level $n');
    }
    expect({for (var n = 5; n <= 25; n += 5) LevelSpec.forLevel(n).boss}, BossKind.values.toSet());
  });

  test('regular levels never repeat the previous layout, and stay unique for 30 levels', () {
    final seen = <(Formation, Motion)>{};
    LevelSpec? prev;
    for (var n = 1; n <= 37; n++) {
      final s = LevelSpec.forLevel(n);
      if (s.isBoss) continue;
      expect(seen.add((s.formation, s.motion)), isTrue, reason: 'level $n repeats a layout');
      if (prev != null) {
        expect(s.formation, isNot(prev.formation), reason: 'level $n');
        expect(s.motion, isNot(prev.motion), reason: 'level $n');
      }
      prev = s;
    }
  });

  test('difficulty never goes down', () {
    for (var n = 2; n <= 60; n++) {
      final a = LevelSpec.forLevel(n - 1), b = LevelSpec.forLevel(n);
      expect(b.speed, greaterThanOrEqualTo(a.speed));
      expect(b.fireRate, greaterThanOrEqualTo(a.fireRate));
      expect(b.bulletSpeed, greaterThanOrEqualTo(a.bulletSpeed));
      expect(b.enemyCount, greaterThanOrEqualTo(a.enemyCount));
    }
  });

  test('checkpoints are the level after each boss', () {
    expect([1, 4, 5, 6, 10, 11, 14].map(LevelSpec.checkpointFor), [1, 1, 1, 6, 6, 11, 11]);
  });

  test('every formation fits the playfield at every size', () {
    for (final f in Formation.values) {
      for (var count = 14; count <= 44; count++) {
        for (final orbit in [false, true]) {
          final slots = formationSlots(f, count, orbit: orbit);
          expect(slots, hasLength(count));
          for (final p in slots) {
            if (orbit) {
              expect(p.magnitude, lessThanOrEqualTo(140.01), reason: '$f $count');
            } else {
              expect(p.x.abs(), lessThanOrEqualTo(150.01), reason: '$f $count');
              expect(p.y.abs(), lessThanOrEqualTo(90.01), reason: '$f $count');
            }
          }
          // No two ships stacked on each other.
          for (var i = 0; i < slots.length; i++) {
            for (var j = i + 1; j < slots.length; j++) {
              expect(slots[i].distanceTo(slots[j]), greaterThan(16), reason: '$f $count orbit=$orbit slots $i,$j');
            }
          }
        }
      }
    }
  });
}
