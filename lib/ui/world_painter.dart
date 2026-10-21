import 'dart:math';

import 'package:flutter/material.dart';

import '../game/levels.dart';
import '../game/world.dart';
import 'palette.dart';

/// Maps the fixed 360×640 field into the widget, letterboxed.
class FieldTransform {
  FieldTransform(Size size)
      : scale = min(size.width / World.width, size.height / World.height),
        origin = Offset(
          (size.width - World.width * min(size.width / World.width, size.height / World.height)) / 2,
          (size.height - World.height * min(size.width / World.width, size.height / World.height)) / 2,
        );

  final double scale;
  final Offset origin;

  Rect get rect => origin & const Size(World.width, World.height) * scale;
}

/// Three layers of stars scrolling at different speeds.
class Starfield {
  Starfield([int seed = 7]) {
    final rng = Random(seed);
    for (var i = 0; i < 110; i++) {
      final layer = i % 3;
      _stars.add((rng.nextDouble(), rng.nextDouble(), 12.0 + layer * 26, 0.6 + layer * 0.5));
    }
  }

  final _stars = <(double, double, double, double)>[];

  void paint(Canvas canvas, Rect area, double time, {double speed = 1}) {
    final paint = Paint();
    for (final (x, y, v, r) in _stars) {
      final py = (y * area.height + time * v * speed) % area.height;
      paint.color = Colors.white.withValues(alpha: 0.25 + r * 0.3);
      canvas.drawCircle(Offset(area.left + x * area.width, area.top + py), r, paint);
    }
  }
}

class WorldPainter extends CustomPainter {
  WorldPainter(this.world, this.stars, {required Listenable repaint}) : super(repaint: repaint);

  final World world;
  final Starfield stars;

  static final _glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

  @override
  void paint(Canvas canvas, Size size) {
    final w = world;
    final tint = levelTint(w.spec.hue);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint, background, background],
          stops: const [0, 0.6, 1],
        ).createShader(Offset.zero & size),
    );
    stars.paint(canvas, Offset.zero & size, w.time, speed: w.spec.isBoss ? 0.5 : 1 + w.spec.speed * 0.3);

    final t = FieldTransform(size);
    canvas.save();
    canvas.translate(t.origin.dx, t.origin.dy);
    canvas.scale(t.scale);
    if (w.shake > 0) {
      final r = Random(w.time.hashCode);
      canvas.translate((r.nextDouble() - 0.5) * w.shake, (r.nextDouble() - 0.5) * w.shake);
    }
    canvas.clipRect(const Rect.fromLTWH(-20, -20, World.width + 40, World.height + 40));

    for (final m in w.meteors) {
      _meteor(canvas, m);
    }
    for (final p in w.powerUps) {
      _powerUp(canvas, p);
    }
    for (final e in w.enemies) {
      if (e.delay > 0) continue;
      _enemy(canvas, e, w.time);
    }
    if (w.boss != null) _boss(canvas, w.boss!, w);
    _particles(canvas);
    _playerBullets(canvas);
    if (!w.over && (w.invulnerable == 0 || (w.time * 12).floor().isEven)) _player(canvas);
    _enemyBullets(canvas);
    canvas.restore();
  }

  void _particles(Canvas canvas) {
    final paint = Paint();
    for (final p in world.particles) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      paint.color = particleColors[p.color].withValues(alpha: a);
      canvas.drawRect(Rect.fromCenter(center: Offset(p.x, p.y), width: 2.5 + a * 2, height: 2.5 + a * 2), paint);
    }
  }

  void _playerBullets(Canvas canvas) {
    final glow = Paint()
      ..color = accent.withValues(alpha: 0.45)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final core = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final b in world.playerBullets) {
      final tail = Offset(b.x - b.vx * 0.02, b.y - b.vy * 0.02);
      canvas.drawLine(tail, Offset(b.x, b.y), glow);
      canvas.drawLine(tail, Offset(b.x, b.y), core);
    }
  }

  void _enemyBullets(Canvas canvas) {
    final glow = Paint()..color = hot.withValues(alpha: 0.35);
    final ring = Paint()..color = hot;
    final core = Paint()..color = const Color(0xFFFFE0E8);
    for (final b in world.enemyBullets) {
      final c = Offset(b.x, b.y);
      canvas.drawCircle(c, b.r * 2, glow);
      canvas.drawCircle(c, b.r, ring);
      canvas.drawCircle(c, b.r * 0.5, core);
    }
  }

  void _player(Canvas canvas) {
    final x = world.playerX, y = World.playerY;
    canvas.save();
    canvas.translate(x, y);
    // Engine flame.
    final flicker = 8 + sin(world.time * 40) * 3;
    final flame = Path()
      ..moveTo(-5, 12)
      ..lineTo(0, 12 + flicker)
      ..lineTo(5, 12)
      ..close();
    canvas.drawPath(flame, Paint()..color = gold);
    final ship = Path()
      ..moveTo(0, -18)
      ..lineTo(7, -4)
      ..lineTo(16, 8)
      ..lineTo(16, 13)
      ..lineTo(5, 9)
      ..lineTo(0, 13)
      ..lineTo(-5, 9)
      ..lineTo(-16, 13)
      ..lineTo(-16, 8)
      ..lineTo(-7, -4)
      ..close();
    canvas.drawPath(ship, _glow..color = accent.withValues(alpha: 0.7));
    canvas.drawPath(ship, Paint()..color = const Color(0xFF0B3F55));
    canvas.drawPath(
      ship,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -3), width: 5, height: 9), Paint()..color = Colors.white);
    if (world.run.shield) {
      final pulse = 0.5 + 0.2 * sin(world.time * 6);
      canvas.drawCircle(
        Offset.zero,
        26,
        Paint()
          ..color = accent.withValues(alpha: pulse)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(Offset.zero, 26, Paint()..color = accent.withValues(alpha: 0.08));
    }
    canvas.restore();
  }

  void _enemy(Canvas canvas, Enemy e, double time) {
    final color = e.flash > 0 ? Colors.white : enemyColors[e.kind.index];
    canvas.save();
    canvas.translate(e.x, e.y);
    final path = switch (e.kind) {
      EnemyKind.drone => _drone(time + e.slotX),
      EnemyKind.gunner => _gunner(),
      EnemyKind.tank => _hexagon(13),
      EnemyKind.diver => _diver(),
    };
    if (e.state == EnemyState.diving && e.kind == EnemyKind.diver) {
      canvas.rotate((e.vx / 400).clamp(-0.5, 0.5));
    }
    canvas.drawPath(path, _glow..color = color.withValues(alpha: 0.55));
    canvas.drawPath(path, Paint()..color = Color.lerp(color, Colors.black, 0.65)!);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    // Eyes / cores.
    final eye = Paint()..color = e.flash > 0 ? color : Colors.white;
    switch (e.kind) {
      case EnemyKind.drone:
        canvas.drawCircle(const Offset(-4, -1), 2, eye);
        canvas.drawCircle(const Offset(4, -1), 2, eye);
      case EnemyKind.gunner:
        canvas.drawCircle(Offset.zero, 4, eye);
        canvas.drawCircle(Offset.zero, 2, Paint()..color = hot);
      case EnemyKind.tank:
        canvas.drawPath(_hexagon(6), Paint()..color = color);
        // Remaining armour pips.
        for (var i = 0; i < min(e.hp, 6); i++) {
          canvas.drawCircle(Offset(-7.5 + i * 3, 17), 1.1, Paint()..color = color);
        }
      case EnemyKind.diver:
        canvas.drawCircle(const Offset(0, -2), 2.5, eye);
    }
    canvas.restore();
  }

  Path _drone(double t) {
    final leg = sin(t * 6) * 2;
    return Path()
      ..moveTo(-8, -7)
      ..lineTo(8, -7)
      ..lineTo(12, -2)
      ..lineTo(14, 6 + leg)
      ..lineTo(9, 3)
      ..lineTo(5, 8)
      ..lineTo(-5, 8)
      ..lineTo(-9, 3)
      ..lineTo(-14, 6 - leg)
      ..lineTo(-12, -2)
      ..close();
  }

  Path _gunner() => Path()
    ..moveTo(0, -12)
    ..lineTo(12, 0)
    ..lineTo(0, 13)
    ..lineTo(-12, 0)
    ..close();

  Path _hexagon(double r) {
    final p = Path();
    for (var i = 0; i < 6; i++) {
      final a = pi / 6 + i * pi / 3;
      i == 0 ? p.moveTo(cos(a) * r, sin(a) * r) : p.lineTo(cos(a) * r, sin(a) * r);
    }
    return p..close();
  }

  Path _diver() => Path()
    ..moveTo(0, 14)
    ..lineTo(12, -10)
    ..lineTo(4, -5)
    ..lineTo(0, -12)
    ..lineTo(-4, -5)
    ..lineTo(-12, -10)
    ..close();

  void _boss(Canvas canvas, Boss b, World w) {
    final base = bossColors[b.kind.index];
    final color = b.flash > 0 ? Colors.white : base;
    final dark = Paint()..color = Color.lerp(base, Colors.black, 0.7)!;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    final t = b.t;

    for (final (ox, oy) in w.coreOrbs()) {
      canvas.drawCircle(Offset(ox, oy), 15, _glow..color = base.withValues(alpha: 0.6));
      canvas.drawCircle(Offset(ox, oy), 11, dark);
      canvas.drawCircle(Offset(ox, oy), 11, line);
    }

    canvas.save();
    canvas.translate(b.x, b.y);
    if (b.kind == BossKind.mirror && b.flash > 0) canvas.scale(1 + b.flash, 1 - b.flash * 2);
    final Path body;
    switch (b.kind) {
      case BossKind.warden:
        body = Path()
          ..moveTo(0, 34)
          ..lineTo(22, 18)
          ..lineTo(56, 26)
          ..lineTo(48, -6)
          ..lineTo(26, -26)
          ..lineTo(0, -34)
          ..lineTo(-26, -26)
          ..lineTo(-48, -6)
          ..lineTo(-56, 26)
          ..lineTo(-22, 18)
          ..close();
      case BossKind.hive:
        body = Path()..addOval(Rect.fromCenter(center: Offset.zero, width: 112, height: 66));
      case BossKind.spiral:
        body = Path();
        for (var i = 0; i < 6; i++) {
          final a = t * 2 + i * pi / 3;
          body
            ..moveTo(cos(a) * 18, sin(a) * 18)
            ..quadraticBezierTo(cos(a + 0.6) * 52, sin(a + 0.6) * 44, cos(a + 1.1) * 54, sin(a + 1.1) * 34)
            ..lineTo(cos(a + 0.5) * 18, sin(a + 0.5) * 18)
            ..close();
        }
        body.addOval(Rect.fromCircle(center: Offset.zero, radius: 22));
      case BossKind.mirror:
        body = Path()
          ..moveTo(0, -38)
          ..lineTo(54, 0)
          ..lineTo(0, 38)
          ..lineTo(-54, 0)
          ..close()
          ..moveTo(0, -20)
          ..lineTo(26, 0)
          ..lineTo(0, 20)
          ..lineTo(-26, 0)
          ..close();
        body.fillType = PathFillType.evenOdd;
      case BossKind.core:
        body = Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 40));
    }
    canvas.drawPath(body, _glow..color = base.withValues(alpha: 0.7));
    canvas.drawPath(body, dark);
    canvas.drawPath(body, line);

    // Details.
    switch (b.kind) {
      case BossKind.warden:
        canvas.drawRect(const Rect.fromLTWH(-14, -6, 28, 6), fill);
        canvas.drawCircle(const Offset(-30, 8), 4, fill);
        canvas.drawCircle(const Offset(30, 8), 4, fill);
      case BossKind.hive:
        for (var i = -2; i <= 2; i++) {
          final open = (sin(t * 3 + i) + 1) / 2;
          canvas.drawCircle(Offset(i * 19.0, 4), 5 + open * 3, fill);
        }
      case BossKind.spiral:
        canvas.drawCircle(Offset.zero, 10 + sin(t * 8) * 2, Paint()..color = Colors.white);
      case BossKind.mirror:
        canvas.drawCircle(Offset.zero, 7, Paint()..color = Colors.white);
      case BossKind.core:
        canvas.drawCircle(Offset.zero, 22 + sin(t * 4) * 4, fill);
        canvas.drawCircle(Offset.zero, 11, Paint()..color = Colors.white);
    }
    if (b.enraged) {
      canvas.drawCircle(Offset.zero, 62 + sin(t * 10) * 3, line..color = hot.withValues(alpha: 0.5));
    }
    canvas.restore();
  }

  void _meteor(Canvas canvas, Meteor m) {
    final rng = Random(m.seed);
    final p = Path();
    for (var i = 0; i < 9; i++) {
      final a = m.spin + i * 2 * pi / 9;
      final r = m.r * (0.75 + rng.nextDouble() * 0.3);
      i == 0 ? p.moveTo(m.x + cos(a) * r, m.y + sin(a) * r) : p.lineTo(m.x + cos(a) * r, m.y + sin(a) * r);
    }
    p.close();
    canvas.drawPath(p, Paint()..color = const Color(0xFF3B332D));
    canvas.drawPath(
      p,
      Paint()
        ..color = particleColors[4]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  static const _powerColors = {
    PowerKind.weapon: gold,
    PowerKind.shield: accent,
    PowerKind.life: Color(0xFF4ADE80),
    PowerKind.bomb: hot,
  };
  static const _powerLabels = {PowerKind.weapon: 'P', PowerKind.shield: 'S', PowerKind.life: '+', PowerKind.bomb: 'B'};
  static final _labelCache = <PowerKind, TextPainter>{};

  void _powerUp(Canvas canvas, PowerUp p) {
    final color = _powerColors[p.kind]!;
    final c = Offset(p.x, p.y);
    final pulse = 1 + 0.12 * sin(p.t * 8);
    canvas.drawCircle(c, 14 * pulse, _glow..color = color.withValues(alpha: 0.6));
    canvas.drawCircle(c, 11, Paint()..color = Color.lerp(color, Colors.black, 0.6)!);
    canvas.drawCircle(
      c,
      11,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final label = _labelCache.putIfAbsent(
      p.kind,
      () => TextPainter(
        text: TextSpan(text: _powerLabels[p.kind], style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    label.paint(canvas, c - Offset(label.width / 2, label.height / 2));
  }

  @override
  bool shouldRepaint(WorldPainter old) => old.world != world;
}
