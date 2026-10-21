import 'dart:math';

/// Shape the wave lines up in.
enum Formation { grid, wedge, diamond, rings, columns, crescent }

/// How the formation moves once in place.
enum Motion { march, sway, orbit, wave, pulse }

enum EnemyKind { drone, gunner, tank, diver }

enum BossKind { warden, hive, spiral, mirror, core }

const formationNames = {
  Formation.grid: 'Blockade',
  Formation.wedge: 'Spearhead',
  Formation.diamond: 'Prism',
  Formation.rings: 'Halo',
  Formation.columns: 'Pillars',
  Formation.crescent: 'Crescent',
};

const motionNames = {
  Motion.march: 'March',
  Motion.sway: 'Drift',
  Motion.orbit: 'Orbit',
  Motion.wave: 'Ripple',
  Motion.pulse: 'Pulse',
};

const bossNames = {
  BossKind.warden: 'The Warden',
  BossKind.hive: 'Hive Mother',
  BossKind.spiral: 'Vortex',
  BossKind.mirror: 'Phantom',
  BossKind.core: 'The Core',
};

/// Everything that makes one level what it is. Built from the level number
/// alone, so a level plays the same every time.
class LevelSpec {
  const LevelSpec({
    required this.number,
    required this.formation,
    required this.motion,
    required this.enemyCount,
    required this.speed,
    required this.fireRate,
    required this.diveRate,
    required this.bulletSpeed,
    required this.meteors,
    required this.boss,
    required this.hue,
  });

  final int number;
  final Formation formation;
  final Motion motion;
  final int enemyCount;

  /// Formation movement multiplier.
  final double speed;

  /// Enemy shots per second for the whole wave, at full strength.
  final double fireRate;

  /// Dives per second.
  final double diveRate;
  final double bulletSpeed;

  /// Meteors drift through the level.
  final bool meteors;
  final BossKind? boss;

  /// Background tint, in degrees.
  final double hue;

  bool get isBoss => boss != null;

  /// Boss tier: 1 for level 5, 2 for level 10...
  int get tier => (number + 4) ~/ 5;

  String get name => isBoss ? bossNames[boss]! : '${formationNames[formation]} · ${motionNames[motion]}';

  /// Kinds that can appear, unlocked one level at a time.
  List<EnemyKind> get roster => [
        EnemyKind.drone,
        if (number >= 2) EnemyKind.gunner,
        if (number >= 3) EnemyKind.tank,
        if (number >= 4) EnemyKind.diver,
      ];

  int hpFor(EnemyKind kind) => switch (kind) {
        EnemyKind.tank => 3 + number ~/ 8,
        _ => 1 + number ~/ 16,
      };

  /// Level a game over sends you back to: the one after the last boss beaten.
  static int checkpointFor(int level) => ((level - 1) ~/ 5) * 5 + 1;

  // Formations in an order where neighbours look different; motions cycle
  // with a coprime length, so the pair only repeats every 30 levels.
  static const _formationOrder = [
    Formation.grid,
    Formation.wedge,
    Formation.rings,
    Formation.columns,
    Formation.diamond,
    Formation.crescent,
  ];
  static const _motionOrder = [Motion.march, Motion.sway, Motion.wave, Motion.orbit, Motion.pulse];

  factory LevelSpec.forLevel(int n) {
    final d = (n - 1).toDouble();
    final boss = n % 5 == 0 ? BossKind.values[(n ~/ 5 - 1) % BossKind.values.length] : null;
    // Count regular levels only, so bosses don't skip formations.
    final regular = n - n ~/ 5 - 1;
    return LevelSpec(
      number: n,
      formation: _formationOrder[regular % _formationOrder.length],
      motion: n == 1 ? Motion.march : _motionOrder[regular % _motionOrder.length],
      enemyCount: min(14 + (d * 1.6).round(), 44),
      speed: min(1 + d * 0.05, 2.4),
      fireRate: min(0.5 + d * 0.11, 3.2),
      diveRate: n >= 4 ? min(0.12 + d * 0.025, 0.9) : 0,
      bulletSpeed: min(150 + d * 4.5, 290),
      meteors: n >= 7 && n % 5 != 0 && n % 3 == 1,
      boss: boss,
      hue: 180 + (n * 47) % 150.0, // blues through magentas
    );
  }
}

/// Slot positions relative to the formation centre, at most ±150 wide
/// and ±90 tall (±140 radius for orbiting waves).
List<Point<double>> formationSlots(Formation f, int count, {required bool orbit}) {
  final pts = <Point<double>>[];
  switch (f) {
    case Formation.grid:
      const cols = 8;
      final rows = (count / cols).ceil();
      for (var i = 0; i < count; i++) {
        final r = i ~/ cols, c = i % cols;
        pts.add(Point((c - (cols - 1) / 2) * 38, (r - (rows - 1) / 2) * 32));
      }
    case Formation.wedge:
      // Nested Vs pointing down, 13 ships each: tip, then alternating arms.
      for (var i = 0; i < count; i++) {
        final layer = i ~/ 13, j = i % 13;
        final k = (j + 1) ~/ 2;
        final side = j.isOdd ? -1 : 1;
        pts.add(Point(side * k * 24.0, -k * 18.0 - layer * 34));
      }
    case Formation.diamond:
      pts.add(const Point(0, 0));
      for (var ring = 1; pts.length < count; ring++) {
        for (var k = 0; k < ring * 4 && pts.length < count; k++) {
          final side = k ~/ ring, t = k % ring;
          final corners = [Point(0.0, -ring.toDouble()), Point(ring.toDouble(), 0.0), Point(0.0, ring.toDouble()), Point(-ring.toDouble(), 0.0)];
          final a = corners[side], b = corners[(side + 1) % 4];
          final x = a.x + (b.x - a.x) * t / ring, y = a.y + (b.y - a.y) * t / ring;
          pts.add(Point(x * 34, y * 28));
        }
      }
    case Formation.rings:
      // Concentric rings, ships shared out by circumference.
      final radii = count <= 24 ? [48.0, 105.0] : [40.0, 85.0, 130.0];
      _shareOut(count, radii, (ring, k, n) {
        final a = 2 * pi * k / n + ring * pi / n;
        pts.add(Point(cos(a) * radii[ring], sin(a) * radii[ring] * 0.8));
      });
    case Formation.columns:
      const cols = 5;
      final rows = (count / cols).ceil();
      for (var i = 0; i < count; i++) {
        final c = i % cols, r = i ~/ cols;
        pts.add(Point((c - (cols - 1) / 2) * 68 + (r.isOdd ? 8 : -8), (r - (rows - 1) / 2) * 26));
      }
    case Formation.crescent:
      final radii = count <= 22 ? [150.0, 112.0] : [150.0, 116.0, 82.0];
      _shareOut(count, radii, (row, k, n) {
        final a = pi * (0.1 + 0.8 * (n == 1 ? 0.5 : k / (n - 1)));
        pts.add(Point(-cos(a) * radii[row], -sin(a) * radii[row] * 0.85));
      });
  }
  return _fit(pts, orbit ? 140 : 150, orbit ? 140 : 90, round: orbit);
}

/// Splits [count] ships across rows in proportion to each row's radius,
/// calling [place] with (row, index in row, ships in row).
void _shareOut(int count, List<double> radii, void Function(int row, int k, int n) place) {
  final total = radii.fold(0.0, (a, r) => a + r);
  var left = count;
  for (var row = radii.length - 1; row >= 0; row--) {
    final n = row == 0 ? left : max(1, (count * radii[row] / total).round());
    for (var k = 0; k < n; k++) {
      place(row, k, n);
    }
    left -= n;
  }
}

List<Point<double>> _fit(List<Point<double>> pts, double maxX, double maxY, {required bool round}) {
  // Centre vertically, then shrink to fit the playfield if needed.
  final minY = pts.map((p) => p.y).reduce(min), maxYv = pts.map((p) => p.y).reduce(max);
  final cy = (minY + maxYv) / 2;
  var centred = [for (final p in pts) Point(p.x, p.y - cy)];
  double scale;
  if (round) {
    final r = centred.map((p) => p.magnitude).reduce(max);
    scale = r > maxX ? maxX / r : 1;
  } else {
    final w = centred.map((p) => p.x.abs()).reduce(max);
    final h = centred.map((p) => p.y.abs()).reduce(max);
    scale = min(w > maxX ? maxX / w : 1, h > maxY ? maxY / h : 1);
  }
  return [for (final p in centred) Point(p.x * scale, p.y * scale)];
}
