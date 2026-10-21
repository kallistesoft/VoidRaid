import 'dart:math';

import 'levels.dart';

enum GameEvent { shoot, enemyHit, enemyDown, playerHit, shieldHit, powerUp, bossWarning, bossDown, levelClear, gameOver }

enum PowerKind { weapon, shield, life, bomb }

/// What carries over from one level to the next.
class Run {
  Run({this.level = 1, this.score = 0, this.lives = 3, this.weapon = 1, this.shield = false});

  int level;
  int score;
  int lives;

  /// 1 = single shot ... 4 = five-way spread.
  int weapon;
  bool shield;

  /// One rewarded revive per run.
  bool revived = false;
}

class Bullet {
  Bullet(this.x, this.y, this.vx, this.vy, {this.r = 4});

  double x, y, vx, vy;
  final double r;
  bool dead = false;
}

enum EnemyState { entering, formation, diving, returning }

class Enemy {
  Enemy({required this.kind, required this.hp, required this.slotX, required this.slotY, required this.x, required this.y, required this.delay});

  final EnemyKind kind;
  int hp;
  final double slotX, slotY;
  double x, y;
  EnemyState state = EnemyState.entering;

  /// Time in the current state.
  double t = 0;

  /// Entry stagger.
  double delay;
  double fromX = 0, fromY = 0;
  double vx = 0;
  bool firedOnDive = false;

  /// Spawned by a boss: not part of a formation, dives once and is gone.
  bool minion = false;

  /// Hit flash, seconds left.
  double flash = 0;
  bool dead = false;

  int get points => switch (kind) {
        EnemyKind.drone => 10,
        EnemyKind.gunner => 20,
        EnemyKind.diver => 30,
        EnemyKind.tank => 40,
      };
}

class Boss {
  Boss(this.kind, this.maxHp) : hp = maxHp;

  final BossKind kind;
  final int maxHp;
  int hp;
  double x = World.width / 2, y = -90;
  double t = 0;
  bool entered = false;
  double flash = 0;

  /// Pattern timers, one per attack.
  final timers = [0.0, 0.0, 0.0];
  double angle = 0;

  bool get enraged => hp < maxHp / 2;

  static const halfW = 56.0, halfH = 34.0;
}

class PowerUp {
  PowerUp(this.kind, this.x, this.y);

  final PowerKind kind;
  double x, y;
  double t = 0;
  bool dead = false;
}

class Meteor {
  Meteor(this.x, this.y, this.vx, this.vy, this.r, this.hp, this.seed);

  double x, y, vx, vy;
  final double r;
  int hp;
  final int seed;
  double spin = 0;
  bool dead = false;
}

class Particle {
  Particle(this.x, this.y, this.vx, this.vy, this.life, this.color) : maxLife = life;

  double x, y, vx, vy, life;
  final double maxLife;

  /// Index into the particle palette.
  final int color;
}

/// End-of-level numbers for the break screen.
class LevelSummary {
  const LevelSummary({required this.kills, required this.accuracy, required this.noHitBonus, required this.accuracyBonus});

  final int kills;
  final double accuracy;
  final int noHitBonus;
  final int accuracyBonus;
  int get bonus => noHitBonus + accuracyBonus;
}

/// One level in play. Pure simulation in a fixed 360×640 field; the UI just
/// feeds input, calls [update] every frame, and draws the state.
class World {
  World(this.run, {Random? rng})
      : spec = LevelSpec.forLevel(run.level),
        rng = rng ?? Random() {
    _setUp();
  }

  static const width = 360.0, height = 640.0;
  static const playerY = 580.0;
  static const _formationY = 175.0;

  final Run run;
  final LevelSpec spec;
  final Random rng;

  double time = 0;
  double playerX = width / 2;
  double invulnerable = 1.5;
  double _fireCooldown = 0.5;

  /// Keyboard input, -1..1.
  double steer = 0;

  /// Mouse position to glide toward, if the pointer is hovering.
  double? targetX;

  final enemies = <Enemy>[];
  final playerBullets = <Bullet>[];
  final enemyBullets = <Bullet>[];
  final powerUps = <PowerUp>[];
  final meteors = <Meteor>[];
  final particles = <Particle>[];
  Boss? boss;

  final events = <GameEvent>[];

  // Formation movement.
  double _ox = width / 2, _oy = _formationY;
  double _marchDir = 1;
  int _initialCount = 0;
  double _diveTimer = 2;
  double _fireTimer = 2;
  double _meteorTimer = 3;

  // Score chain: kills close together raise the multiplier.
  int chain = 0;
  double _chainTimer = 0;
  int get multiplier => 1 + min(chain ~/ 6, 4);

  int kills = 0, shots = 0, hits = 0;
  bool hitThisLevel = false;
  double shake = 0;

  /// Seconds since the wave was wiped out; the level ends after a short beat.
  double? _clearTime;
  bool cleared = false;
  bool get over => run.lives <= 0;

  /// Seconds the boss warning stays on screen before the boss enters.
  static const bossWarning = 2.5;

  void _setUp() {
    if (spec.isBoss) {
      final b = spec.boss!;
      final base = switch (b) {
        BossKind.warden => 140,
        BossKind.hive => 170,
        BossKind.spiral => 190,
        BossKind.mirror => 210,
        BossKind.core => 240,
      };
      boss = Boss(b, (base * (1 + 0.7 * (spec.tier - 1))).round());
      events.add(GameEvent.bossWarning);
      return;
    }
    final slots = formationSlots(spec.formation, spec.enemyCount, orbit: spec.motion == Motion.orbit);
    final roster = spec.roster;
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      // Tougher kinds sit at the back (top), gunners and divers spread through.
      final kind = _pickKind(roster, s.y);
      enemies.add(Enemy(
        kind: kind,
        hp: spec.hpFor(kind),
        slotX: s.x,
        slotY: s.y,
        x: width / 2 + s.x + (rng.nextDouble() - 0.5) * 160,
        y: -40 - rng.nextDouble() * 60,
        delay: i * 0.045 + rng.nextDouble() * 0.2,
      )
        ..fromX = width / 2 + s.x * 1.6
        ..fromY = -40);
    }
    _initialCount = enemies.length;
  }

  EnemyKind _pickKind(List<EnemyKind> roster, double slotY) {
    final weights = {
      EnemyKind.drone: 5.0,
      EnemyKind.gunner: 2.0 + spec.number * 0.1,
      EnemyKind.tank: slotY < -20 ? 1.6 + spec.number * 0.05 : 0.3,
      EnemyKind.diver: 1.4 + spec.number * 0.06,
    };
    final total = roster.fold(0.0, (a, k) => a + weights[k]!);
    var r = rng.nextDouble() * total;
    for (final k in roster) {
      r -= weights[k]!;
      if (r <= 0) return k;
    }
    return roster.first;
  }

  // ---- input ----

  /// Relative drag, in field units.
  void dragBy(double dx) {
    targetX = null;
    playerX = (playerX + dx).clamp(16.0, width - 16);
  }

  // ---- simulation ----

  void update(double dt) {
    if (cleared || over) return;
    time += dt;
    shake = max(0, shake - dt * 30);
    invulnerable = max(0, invulnerable - dt);
    if (_chainTimer > 0) {
      _chainTimer -= dt;
      if (_chainTimer <= 0) chain = 0;
    }

    if (steer != 0) dragBy(steer * 300 * dt);
    if (targetX != null) {
      final step = (targetX! - playerX).clamp(-520 * dt, 520 * dt);
      playerX = (playerX + step).clamp(16.0, width - 16);
    }
    _updatePlayerFire(dt);
    _updateFormation(dt);
    for (final e in enemies) {
      _updateEnemy(e, dt);
    }
    if (boss != null) _updateBoss(boss!, dt);
    _updateEnemyFire(dt);
    if (spec.meteors) _updateMeteors(dt);
    _moveBullets(dt);
    _updatePowerUps(dt);
    _collide();
    _updateParticles(dt);

    enemies.removeWhere((e) => e.dead);
    playerBullets.removeWhere((b) => b.dead);
    enemyBullets.removeWhere((b) => b.dead);
    powerUps.removeWhere((p) => p.dead);
    meteors.removeWhere((m) => m.dead);

    if (over) {
      events.add(GameEvent.gameOver);
      return;
    }
    final waveGone = enemies.isEmpty && boss == null;
    if (waveGone && _clearTime == null) {
      _clearTime = 0;
      enemyBullets.clear();
    }
    if (_clearTime != null) {
      _clearTime = _clearTime! + dt;
      if (_clearTime! > 1.4) {
        cleared = true;
        events.add(GameEvent.levelClear);
      }
    }
  }

  void _updatePlayerFire(double dt) {
    _fireCooldown -= dt;
    if (_fireCooldown > 0 || _clearTime != null) return;
    _fireCooldown = run.weapon >= 4 ? 0.19 : 0.22;
    const v = 540.0;
    void shot(double dx, double angleDeg) {
      final a = angleDeg * pi / 180;
      playerBullets.add(Bullet(playerX + dx, playerY - 16, sin(a) * v, -cos(a) * v, r: 3.5));
      shots++;
    }

    switch (run.weapon) {
      case 1:
        shot(0, 0);
      case 2:
        shot(-7, 0);
        shot(7, 0);
      case 3:
        shot(0, 0);
        shot(-6, -7);
        shot(6, 7);
      default:
        shot(-5, 0);
        shot(5, 0);
        shot(-8, -8);
        shot(8, 8);
        shot(-10, -16);
        shot(10, 16);
    }
    events.add(GameEvent.shoot);
  }

  /// Where a formation slot is right now.
  (double, double) _slotPos(Enemy e) {
    final t = time * spec.speed;
    switch (spec.motion) {
      case Motion.march:
        return (_ox + e.slotX, _oy + e.slotY);
      case Motion.sway:
        return (_ox + e.slotX, _oy + e.slotY + sin(t * 1.3 + e.slotX * 0.01) * 6);
      case Motion.orbit:
        final a = t * 0.45;
        final x = e.slotX * cos(a) - e.slotY * sin(a);
        final y = e.slotX * sin(a) + e.slotY * cos(a);
        return (_ox + x, _oy + 30 + y * 0.75);
      case Motion.wave:
        return (_ox + e.slotX, _oy + e.slotY + sin(t * 2.2 + e.slotX * 0.035) * 18);
      case Motion.pulse:
        final s = 1 + 0.2 * sin(t * 1.7);
        return (_ox + e.slotX * s, _oy + e.slotY * s);
    }
  }

  void _updateFormation(double dt) {
    final t = time * spec.speed;
    switch (spec.motion) {
      case Motion.march:
        // Classic: faster as the wave thins out, steps down at each edge.
        if (time < 2) return;
        final alive = enemies.where((e) => !e.minion).toList();
        if (alive.isEmpty) return;
        final thin = 1 - alive.length / max(1, _initialCount);
        _ox += _marchDir * (22 + 40 * thin) * spec.speed * dt;
        final left = alive.map((e) => _ox + e.slotX).reduce(min);
        final right = alive.map((e) => _ox + e.slotX).reduce(max);
        if ((right > width - 18 && _marchDir > 0) || (left < 18 && _marchDir < 0)) {
          _marchDir = -_marchDir;
          _oy += 9;
        }
        final bottom = alive.map((e) => _oy + e.slotY).reduce(max);
        if (bottom > 470) {
          // The wave broke through: costs a life and pushes it back up.
          _oy = _formationY;
          _hitPlayer(force: true);
        }
      case Motion.sway:
        _ox = width / 2 + sin(t * 0.7) * 50;
      case Motion.orbit:
        _ox = width / 2 + sin(t * 0.3) * 14;
      case Motion.wave:
        _ox = width / 2 + sin(t * 0.5) * 30;
      case Motion.pulse:
        _ox = width / 2 + sin(t * 0.9) * 20;
        _oy = _formationY + sin(t * 0.6) * 18;
    }
  }

  void _updateEnemy(Enemy e, double dt) {
    e.flash = max(0, e.flash - dt);
    if (e.delay > 0) {
      e.delay -= dt;
      return;
    }
    e.t += dt;
    switch (e.state) {
      case EnemyState.entering:
      case EnemyState.returning:
        final (tx, ty) = _slotPos(e);
        final p = min(1.0, e.t / 1.3);
        final k = 1 - pow(1 - p, 3).toDouble();
        // Curve in from the side, then settle into the slot.
        e.x = e.fromX + (tx - e.fromX) * k + sin(p * pi) * (e.slotX > 0 ? 60 : -60);
        e.y = e.fromY + (ty - e.fromY) * k;
        if (p >= 1) {
          e.state = EnemyState.formation;
          e.t = 0;
        }
      case EnemyState.formation:
        final (x, y) = _slotPos(e);
        e.x = x;
        e.y = y;
      case EnemyState.diving:
        final speed = (e.minion ? 170.0 : 190.0) * (0.8 + spec.speed * 0.25);
        // Steer toward the player while above them.
        if (e.y < playerY - 80) {
          final want = ((playerX - e.x) * 1.6).clamp(-150.0, 150.0);
          e.vx += (want - e.vx) * min(1, dt * 2.2);
        }
        e.x = (e.x + e.vx * dt).clamp(10.0, width - 10);
        e.y += speed * dt;
        if (!e.firedOnDive && e.y > 260 && e.kind != EnemyKind.drone) {
          e.firedOnDive = true;
          _aimedShot(e.x, e.y + 10, spec.bulletSpeed * 1.1);
        }
        if (e.y > height + 30) {
          if (e.minion) {
            e.dead = true;
          } else {
            e.state = EnemyState.returning;
            e.t = 0;
            e.fromX = e.x;
            e.fromY = -30;
          }
        }
    }
  }

  void _updateEnemyFire(double dt) {
    final inFormation = enemies.where((e) => e.state == EnemyState.formation).toList();
    if (inFormation.isEmpty || _clearTime != null || time < 2.5) return;

    // Firing slows down as the wave thins, so the last few aren't a bullet hose.
    final strength = 0.45 + 0.55 * enemies.length / max(1, _initialCount);
    _fireTimer -= dt;
    if (_fireTimer <= 0) {
      _fireTimer = (0.6 + rng.nextDouble() * 0.8) / (spec.fireRate * strength);
      final shooter = inFormation[rng.nextInt(inFormation.length)];
      switch (shooter.kind) {
        case EnemyKind.gunner:
          _aimedShot(shooter.x, shooter.y + 10, spec.bulletSpeed);
        case EnemyKind.tank:
          for (final dx in [-0.35, 0.0, 0.35]) {
            enemyBullets.add(Bullet(shooter.x, shooter.y + 12, dx * spec.bulletSpeed, spec.bulletSpeed * 0.85, r: 4.5));
          }
        default:
          enemyBullets.add(Bullet(shooter.x, shooter.y + 10, 0, spec.bulletSpeed));
      }
    }

    if (spec.diveRate > 0) {
      _diveTimer -= dt;
      if (_diveTimer <= 0) {
        _diveTimer = (0.6 + rng.nextDouble()) / spec.diveRate;
        final divers = inFormation.where((e) => e.kind == EnemyKind.diver).toList();
        final pool = divers.isNotEmpty && rng.nextDouble() < 0.75 ? divers : inFormation;
        final e = pool[rng.nextInt(pool.length)];
        e.state = EnemyState.diving;
        e.t = 0;
        e.vx = (e.x < width / 2 ? -1 : 1) * 80;
        e.firedOnDive = false;
      }
    }
  }

  void _aimedShot(double x, double y, double speed, {double spread = 0}) {
    final a = atan2(playerY - y, playerX - x) + spread;
    enemyBullets.add(Bullet(x, y, cos(a) * speed, sin(a) * speed));
  }

  void _ring(double x, double y, int n, double speed, {double offset = 0}) {
    for (var i = 0; i < n; i++) {
      final a = offset + 2 * pi * i / n;
      enemyBullets.add(Bullet(x, y, cos(a) * speed, sin(a) * speed, r: 4.5));
    }
  }

  // ---- bosses ----

  void _updateBoss(Boss b, double dt) {
    b.flash = max(0, b.flash - dt);
    if (time < bossWarning) return;
    b.t += dt;
    if (!b.entered) {
      b.y = -90 + min(1, b.t / 2) * 220;
      if (b.t >= 2) {
        b.entered = true;
        b.t = 0;
      }
      return;
    }
    final rage = b.enraged ? 1.45 : 1.0;
    final v = spec.bulletSpeed * (b.enraged ? 1.1 : 1.0);
    for (var i = 0; i < b.timers.length; i++) {
      b.timers[i] += dt * rage;
    }
    bool every(int i, double period) {
      if (b.timers[i] < period) return false;
      b.timers[i] -= period;
      return true;
    }

    switch (b.kind) {
      case BossKind.warden:
        b.x = width / 2 + sin(b.t * 0.7) * 110;
        if (every(0, 1.7)) {
          final n = b.enraged ? 11 : 7;
          for (var i = 0; i < n; i++) {
            final a = pi / 2 + (i - (n - 1) / 2) * 0.17;
            enemyBullets.add(Bullet(b.x, b.y + 30, cos(a) * v, sin(a) * v, r: 4.5));
          }
        }
        if (every(1, 2.9)) {
          for (final s in [-0.12, 0.0, 0.12]) {
            _aimedShot(b.x, b.y + 30, v * 1.3, spread: s);
          }
        }
      case BossKind.hive:
        b.x = width / 2 + sin(b.t * 0.5) * 85;
        if (every(0, 2.3)) _ring(b.x, b.y, b.enraged ? 18 : 12, v * 0.8, offset: b.t);
        if (every(1, 4.2)) {
          for (final dx in [-40.0, 0.0, 40.0]) {
            enemies.add(Enemy(kind: EnemyKind.drone, hp: 1, slotX: 0, slotY: 0, x: b.x + dx, y: b.y + 30, delay: 0)
              ..minion = true
              ..state = EnemyState.diving
              ..vx = dx * 2);
          }
        }
      case BossKind.spiral:
        b.x = width / 2 + sin(b.t * 0.35) * 30;
        b.y = 130 + sin(b.t * 0.8) * 10;
        // Spins for 3.2s, rests for 1.3s while firing aimed shots.
        final cycle = b.t % 4.5;
        if (cycle < 3.2) {
          if (every(0, 0.11)) {
            b.angle += 0.33;
            final arms = b.enraged ? 4 : 2;
            for (var i = 0; i < arms; i++) {
              final a = b.angle + 2 * pi * i / arms;
              enemyBullets.add(Bullet(b.x, b.y, cos(a) * v * 0.75, sin(a) * v * 0.75));
            }
          }
        } else if (every(1, 0.35)) {
          _aimedShot(b.x, b.y + 20, v * 1.2);
        }
      case BossKind.mirror:
        // Teleports, then fires; bullet walls with one gap in between.
        if (every(0, 3.0)) {
          b.x = 70 + rng.nextDouble() * (width - 140);
          b.flash = 0.25;
          for (var i = -2; i <= 2; i++) {
            _aimedShot(b.x, b.y + 30, v * 1.15, spread: i * 0.14);
          }
        }
        if (every(1, b.enraged ? 2.6 : 3.6)) {
          final gap = 50 + rng.nextDouble() * (width - 100);
          for (var x = 10.0; x < width; x += 22) {
            if ((x - gap).abs() > 40) enemyBullets.add(Bullet(x, b.y + 40, 0, v * 0.7, r: 4.5));
          }
        }
      case BossKind.core:
        b.y = 140;
        b.angle += dt * (b.enraged ? 1.8 : 1.1);
        if (every(0, 2.4)) _ring(b.x, b.y, 16, v * 0.75, offset: b.angle);
        if (every(1, 1.1)) _aimedShot(b.x, b.y + 30, v * 1.2);
        if (b.enraged && every(2, 0.16)) {
          final a = -b.angle * 2;
          enemyBullets.add(Bullet(b.x, b.y, cos(a) * v * 0.7, sin(a) * v * 0.7));
        }
    }
  }

  /// The Core's shield orbs, which block shots.
  List<(double, double)> coreOrbs() {
    final b = boss;
    if (b == null || b.kind != BossKind.core) return const [];
    return [for (var i = 0; i < 4; i++) (b.x + cos(b.angle + i * pi / 2) * 78, b.y + sin(b.angle + i * pi / 2) * 78)];
  }

  // ---- meteors ----

  void _updateMeteors(double dt) {
    _meteorTimer -= dt;
    if (_meteorTimer <= 0 && _clearTime == null) {
      _meteorTimer = 2.5 + rng.nextDouble() * 3;
      final r = 12 + rng.nextDouble() * 14;
      final x = rng.nextDouble() * width;
      meteors.add(Meteor(x, -r, (rng.nextDouble() - 0.5) * 60, 60 + rng.nextDouble() * 50, r, r > 20 ? 4 : 2, rng.nextInt(1000)));
    }
    for (final m in meteors) {
      m.x += m.vx * dt;
      m.y += m.vy * dt;
      m.spin += dt;
      if (m.y > height + 40) m.dead = true;
    }
  }

  // ---- bullets, pickups, collisions ----

  void _moveBullets(double dt) {
    for (final b in playerBullets) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      if (b.y < -10 || b.x < -10 || b.x > width + 10) b.dead = true;
    }
    for (final b in enemyBullets) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      if (b.y > height + 10 || b.y < -20 || b.x < -10 || b.x > width + 10) b.dead = true;
    }
  }

  void _updatePowerUps(double dt) {
    for (final p in powerUps) {
      p.t += dt;
      p.y += 75 * dt;
      if (p.y > height + 20) p.dead = true;
      if (!p.dead && (p.x - playerX).abs() < 22 && (p.y - playerY).abs() < 22) {
        p.dead = true;
        _apply(p.kind);
      }
    }
  }

  void _apply(PowerKind kind) {
    events.add(GameEvent.powerUp);
    switch (kind) {
      case PowerKind.weapon:
        if (run.weapon < 4) {
          run.weapon++;
        } else {
          _score(250);
        }
      case PowerKind.shield:
        run.shield = true;
      case PowerKind.life:
        run.lives = min(run.lives + 1, 5);
      case PowerKind.bomb:
        // Clears every bullet on screen and hits every enemy once.
        for (final b in enemyBullets) {
          _burst(b.x, b.y, 2, 3);
        }
        enemyBullets.clear();
        for (final e in [...enemies]) {
          _damage(e, 1);
        }
        shake = 6;
    }
  }

  void _maybeDrop(double x, double y, double chance) {
    if (rng.nextDouble() > chance) return;
    final r = rng.nextDouble();
    final kind = r < 0.5
        ? PowerKind.weapon
        : r < 0.78
            ? PowerKind.shield
            : r < 0.9 && run.lives < 5
                ? PowerKind.life
                : PowerKind.bomb;
    powerUps.add(PowerUp(kind, x, y));
  }

  bool _near(double ax, double ay, double bx, double by, double r) {
    final dx = ax - bx, dy = ay - by;
    return dx * dx + dy * dy < r * r;
  }

  void _collide() {
    final orbs = coreOrbs();
    for (final b in playerBullets) {
      for (final o in orbs) {
        if (_near(b.x, b.y, o.$1, o.$2, 16)) {
          b.dead = true;
          _burst(b.x, b.y, 3, 4);
        }
      }
      if (b.dead) continue;
      for (final e in enemies) {
        if (e.dead || e.delay > 0 || !_near(b.x, b.y, e.x, e.y, 15)) continue;
        b.dead = true;
        hits++;
        _damage(e, 1);
        break;
      }
      if (b.dead) continue;
      final boss = this.boss;
      if (boss != null && boss.entered && (b.x - boss.x).abs() < Boss.halfW && (b.y - boss.y).abs() < Boss.halfH) {
        b.dead = true;
        hits++;
        _damageBoss(boss);
        continue;
      }
      for (final m in meteors) {
        if (!m.dead && _near(b.x, b.y, m.x, m.y, m.r)) {
          b.dead = true;
          if (--m.hp <= 0) {
            m.dead = true;
            _burst(m.x, m.y, 14, 5);
            _score(15);
            _maybeDrop(m.x, m.y, 0.2);
          }
          break;
        }
      }
    }

    if (invulnerable > 0) return;
    for (final b in enemyBullets) {
      if (_near(b.x, b.y, playerX, playerY, b.r + 6)) {
        b.dead = true;
        _hitPlayer();
        return;
      }
    }
    for (final e in enemies) {
      if (e.state == EnemyState.diving && _near(e.x, e.y, playerX, playerY, 20)) {
        _kill(e);
        _hitPlayer();
        return;
      }
    }
    for (final m in meteors) {
      if (_near(m.x, m.y, playerX, playerY, m.r + 8)) {
        m.dead = true;
        _burst(m.x, m.y, 14, 5);
        _hitPlayer();
        return;
      }
    }
  }

  void _damage(Enemy e, int amount) {
    e.hp -= amount;
    e.flash = 0.08;
    if (e.hp <= 0) {
      _kill(e);
    } else {
      events.add(GameEvent.enemyHit);
    }
  }

  void _kill(Enemy e) {
    if (e.dead) return;
    e.dead = true;
    kills++;
    chain++;
    _chainTimer = 1.2;
    _score(e.points * multiplier);
    _burst(e.x, e.y, 16, e.kind.index);
    events.add(GameEvent.enemyDown);
    if (!e.minion) _maybeDrop(e.x, e.y, e.kind == EnemyKind.tank ? 0.18 : 0.06);
  }

  void _damageBoss(Boss b) {
    b.hp--;
    b.flash = 0.05;
    if (b.hp > 0) {
      if (b.hp % 10 == 0) events.add(GameEvent.enemyHit);
      return;
    }
    _score(1000 * spec.tier);
    for (var i = 0; i < 6; i++) {
      _burst(b.x + (rng.nextDouble() - 0.5) * 100, b.y + (rng.nextDouble() - 0.5) * 50, 20, 5);
    }
    for (final e in enemies) {
      _burst(e.x, e.y, 8, 0);
    }
    enemies.clear();
    enemyBullets.clear();
    shake = 12;
    boss = null;
    // A reward for the boss: always a power-up.
    powerUps.add(PowerUp(run.weapon < 4 ? PowerKind.weapon : PowerKind.life, b.x, b.y));
    events.add(GameEvent.bossDown);
  }

  void _hitPlayer({bool force = false}) {
    if (invulnerable > 0 && !force) return;
    hitThisLevel = true;
    invulnerable = 2;
    shake = 8;
    chain = 0;
    _burst(playerX, playerY, 24, 6);
    if (run.shield && !force) {
      run.shield = false;
      invulnerable = 1;
      events.add(GameEvent.shieldHit);
      return;
    }
    run.lives--;
    run.weapon = max(1, run.weapon - 1);
    enemyBullets.clear();
    events.add(GameEvent.playerHit);
  }

  void _score(int points) => run.score += points;

  void _burst(double x, double y, int n, int color) {
    if (particles.length > 500) return;
    for (var i = 0; i < n; i++) {
      final a = rng.nextDouble() * 2 * pi;
      final s = 40 + rng.nextDouble() * 160;
      particles.add(Particle(x, y, cos(a) * s, sin(a) * s, 0.3 + rng.nextDouble() * 0.4, color));
    }
  }

  void _updateParticles(double dt) {
    for (final p in particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 1 - dt * 2;
      p.vy *= 1 - dt * 2;
      p.life -= dt;
    }
    particles.removeWhere((p) => p.life <= 0);
  }

  /// Bonuses for the break screen, added to the score once.
  LevelSummary finish() {
    final accuracy = shots == 0 ? 0.0 : hits / shots;
    final summary = LevelSummary(
      kills: kills,
      accuracy: accuracy,
      noHitBonus: hitThisLevel ? 0 : 300 * spec.number,
      accuracyBonus: (accuracy * 10 * spec.number).round() * 10,
    );
    run.score += summary.bonus;
    return summary;
  }
}
