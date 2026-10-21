import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/levels.dart';
import '../game/world.dart';
import '../services/ad_service.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import 'ad_slot.dart';
import 'palette.dart';
import 'services.dart';
import 'world_painter.dart';

enum _Phase { playing, paused, cleared, over }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.startLevel, this.random});

  final int startLevel;

  /// Seeded in tests.
  final Random? random;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late Run _run = _newRun(widget.startLevel);
  late World _world = World(_run, rng: widget.random);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  final _frame = ValueNotifier(0);
  final _stars = Starfield();
  _Phase _phase = _Phase.playing;
  LevelSummary? _summary;
  bool _newBest = false;
  double _lastShootSound = 0;

  late ProgressStore _progress;
  late AdService _ads;
  late SoundService _sound;

  /// A run started past level 1 begins with a stronger gun, so it's fair.
  static Run _newRun(int level) => Run(level: level, weapon: level > 1 ? 2 : 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = Services.of(context);
    _progress = services.progress;
    _ads = services.ads;
    _sound = services.sound;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _phase == _Phase.playing) setState(() => _phase = _Phase.paused);
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _last = elapsed;
    if (_phase != _Phase.playing) return;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final left = keys.contains(LogicalKeyboardKey.arrowLeft) || keys.contains(LogicalKeyboardKey.keyA);
    final right = keys.contains(LogicalKeyboardKey.arrowRight) || keys.contains(LogicalKeyboardKey.keyD);
    _world.steer = (right ? 1.0 : 0.0) - (left ? 1.0 : 0.0);
    _world.update(dt);
    _handleEvents();
    _frame.value++;
  }

  void _handleEvents() {
    for (final e in _world.events) {
      switch (e) {
        case GameEvent.shoot:
          if (_world.time - _lastShootSound > 0.12) {
            _lastShootSound = _world.time;
            _sound.play(Sfx.shoot);
          }
        case GameEvent.enemyHit:
          _sound.play(Sfx.hit);
        case GameEvent.enemyDown:
          _sound.play(Sfx.explode);
        case GameEvent.playerHit:
          _sound.play(Sfx.playerHit);
          HapticFeedback.heavyImpact();
        case GameEvent.shieldHit:
          _sound.play(Sfx.shield);
        case GameEvent.powerUp:
          _sound.play(Sfx.powerUp);
        case GameEvent.bossWarning:
          _sound.play(Sfx.warning);
        case GameEvent.bossDown:
          _sound.play(Sfx.bossDown);
          HapticFeedback.heavyImpact();
        case GameEvent.levelClear:
          _onCleared();
        case GameEvent.gameOver:
          _onOver();
      }
    }
    _world.events.clear();
  }

  void _onCleared() {
    _sound.play(Sfx.levelClear);
    final next = _run.level + 1;
    _progress.reachLevel(next, LevelSpec.checkpointFor(next));
    if (_world.spec.isBoss) _progress.bossBeaten();
    setState(() {
      _summary = _world.finish();
      _phase = _Phase.cleared;
    });
  }

  Future<void> _onOver() async {
    _sound.play(Sfx.gameOver);
    setState(() => _phase = _Phase.over);
    await _progress.reachLevel(_run.level, LevelSpec.checkpointFor(_run.level));
    final best = await _progress.recordScore(_run.score);
    if (mounted) setState(() => _newBest = best);
  }

  bool _advancing = false;

  Future<void> _nextLevel() async {
    if (_phase != _Phase.cleared || _advancing) return;
    _advancing = true;
    await _ads.showInterstitial();
    _advancing = false;
    if (!mounted) return;
    setState(() {
      _run.level++;
      _world = World(_run, rng: widget.random);
      _phase = _Phase.playing;
    });
  }

  Future<void> _revive() async {
    if (!await _ads.showRewarded() || !mounted) return;
    setState(() {
      _run
        ..revived = true
        ..lives = 2;
      _world = World(_run, rng: widget.random);
      _phase = _Phase.playing;
      _newBest = false;
    });
  }

  void _retry() {
    setState(() {
      _run = _newRun(LevelSpec.checkpointFor(_run.level));
      _world = World(_run, rng: widget.random);
      _phase = _Phase.playing;
      _newBest = false;
    });
  }

  void _togglePause() {
    if (_phase == _Phase.playing) {
      setState(() => _phase = _Phase.paused);
    } else if (_phase == _Phase.paused) {
      setState(() => _phase = _Phase.playing);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyP) {
      _togglePause();
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) && _phase == _Phase.cleared) {
      _nextLevel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(builder: (context, constraints) {
          final t = FieldTransform(constraints.biggest);
          return MouseRegion(
            onHover: (e) => _world.targetX = (e.localPosition.dx - t.origin.dx) / t.scale,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => _world.dragBy(d.delta.dx / t.scale * 1.4),
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: WorldPainter(_world, _stars, repaint: _frame))),
                  Positioned.fromRect(
                    rect: t.rect,
                    child: SafeArea(
                      child: ListenableBuilder(listenable: _frame, builder: (context, _) => _hud(t.scale)),
                    ),
                  ),
                  if (_phase != _Phase.playing) Positioned.fill(child: _overlay()),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ---- HUD ----

  Widget _hud(double scale) {
    final w = _world;
    final boss = w.boss;
    final textScale = scale.clamp(0.8, 1.6);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 14 * textScale, color: Colors.white, fontWeight: FontWeight.w800),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        key: const Key('pause'),
                        onPressed: _togglePause,
                        icon: const Icon(Icons.pause_rounded),
                        color: Colors.white70,
                        tooltip: 'Pause',
                      ),
                      Text('${_run.score}', key: const Key('score'), style: neon(20 * textScale, color: Colors.white, spacing: 1)),
                      if (w.multiplier > 1) ...[
                        const SizedBox(width: 6),
                        Text('×${w.multiplier}', style: neon(14 * textScale, color: gold)),
                      ],
                      const Spacer(),
                      Text('LV ${_run.level}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                      const SizedBox(width: 10),
                      for (var i = 0; i < _run.lives; i++)
                        Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Icon(Icons.navigation_rounded, size: 16 * textScale, color: accent),
                        ),
                    ],
                  ),
                  if (boss != null && boss.entered)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 0, 0),
                      child: _bossBar(boss, textScale),
                    ),
                ],
              ),
            ),
            Positioned(left: 12, bottom: 8, child: _powerMeter(textScale)),
            if (_phase == _Phase.playing) _banner(textScale),
          ],
        ),
      ),
    );
  }

  Widget _bossBar(Boss boss, double textScale) {
    final color = bossColors[boss.kind.index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(bossNames[boss.kind]!.toUpperCase(), style: neon(11 * textScale, color: color)),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: boss.hp / boss.maxHp,
            minHeight: 6,
            color: boss.enraged ? hot : color,
            backgroundColor: Colors.white12,
          ),
        ),
      ],
    );
  }

  Widget _powerMeter(double textScale) {
    return Row(
      children: [
        Text('PWR ', style: TextStyle(fontSize: 10 * textScale, color: Colors.white54)),
        for (var i = 1; i <= 4; i++)
          Container(
            width: 9 * textScale,
            height: 9 * textScale,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: i <= _run.weapon ? gold : Colors.white12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        if (_run.shield) ...[
          const SizedBox(width: 6),
          Icon(Icons.shield_rounded, size: 14 * textScale, color: accent),
        ],
      ],
    );
  }

  /// Level intro, or the boss warning.
  Widget _banner(double textScale) {
    final w = _world;
    final spec = w.spec;
    if (spec.isBoss && w.time < World.bossWarning + 0.5) {
      final on = (w.time * 3).floor().isEven;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('WARNING', style: neon(34 * textScale, color: on ? hot : hot.withValues(alpha: 0.3), spacing: 8)),
            const SizedBox(height: 8),
            Text(spec.name.toUpperCase(), style: neon(18 * textScale, color: bossColors[spec.boss!.index], spacing: 4)),
          ],
        ),
      );
    }
    if (spec.isBoss || w.time > 2.2) return const SizedBox.shrink();
    final fade = (w.time < 1.7 ? 1.0 : (2.2 - w.time) / 0.5).clamp(0.0, 1.0);
    return Center(
      child: Opacity(
        opacity: fade,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('LEVEL ${spec.number}', style: neon(34 * textScale, spacing: 6)),
            const SizedBox(height: 6),
            Text(spec.name.toUpperCase(), style: neon(14 * textScale, color: Colors.white70, spacing: 3)),
            if (spec.meteors) ...[
              const SizedBox(height: 6),
              Text('METEOR SHOWER', style: neon(12 * textScale, color: particleColors[4], spacing: 3)),
            ],
          ],
        ),
      ),
    );
  }

  // ---- overlays ----

  Widget _overlay() {
    final panel = switch (_phase) {
      _Phase.paused => _pausePanel(),
      _Phase.cleared => _clearedPanel(),
      _Phase.over => _overPanel(),
      _Phase.playing => const SizedBox.shrink(),
    };
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: panel),
          ),
        ),
      ),
    );
  }

  Widget _pausePanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('PAUSED', textAlign: TextAlign.center, style: neon(32, spacing: 6)),
        const SizedBox(height: 28),
        _button('Resume', _togglePause, primary: true),
        const SizedBox(height: 12),
        _button(_sound.muted ? 'Sound: off' : 'Sound: on', () async {
          await _sound.setMuted(!_sound.muted);
          setState(() {});
        }),
        const SizedBox(height: 12),
        _button('Quit to menu', () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _clearedPanel() {
    final s = _summary!;
    final spec = _world.spec;
    final next = LevelSpec.forLevel(_run.level + 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(spec.isBoss ? 'BOSS DEFEATED' : 'LEVEL ${spec.number} CLEAR',
            textAlign: TextAlign.center, style: neon(26, color: spec.isBoss ? gold : accent, spacing: 4)),
        const SizedBox(height: 16),
        _stat('Kills', '${s.kills}'),
        _stat('Accuracy', '${(s.accuracy * 100).round()}%'),
        if (s.accuracyBonus > 0) _stat('Accuracy bonus', '+${s.accuracyBonus}'),
        if (s.noHitBonus > 0) _stat('Untouched bonus', '+${s.noHitBonus}', color: gold),
        const Divider(color: Colors.white24, height: 20),
        _stat('Score', '${_run.score}', big: true),
        const SizedBox(height: 18),
        const Center(child: AdSlot()),
        const SizedBox(height: 18),
        Text(
          next.isBoss ? 'BOSS AHEAD: ${next.name.toUpperCase()}' : 'NEXT · LEVEL ${next.number} · ${next.name.toUpperCase()}',
          textAlign: TextAlign.center,
          style: neon(12, color: next.isBoss ? hot : Colors.white70, spacing: 2),
        ),
        const SizedBox(height: 12),
        _button('Continue', _nextLevel, primary: true, key: const Key('continue')),
      ],
    );
  }

  Widget _overPanel() {
    final checkpoint = LevelSpec.checkpointFor(_run.level);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('GAME OVER', textAlign: TextAlign.center, style: neon(34, color: hot, spacing: 6)),
        const SizedBox(height: 16),
        _stat('Level reached', '${_run.level}'),
        _stat('Score', '${_run.score}', big: true),
        if (_newBest) Text('NEW BEST', textAlign: TextAlign.center, style: neon(16, color: gold)),
        const SizedBox(height: 24),
        if (!_run.revived) ...[
          _button('Revive · watch an ad', _revive, primary: true, icon: Icons.play_circle_fill_rounded),
          const SizedBox(height: 12),
        ],
        _button('Retry from level $checkpoint', _retry, primary: _run.revived),
        const SizedBox(height: 12),
        _button('Menu', () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _stat(String label, String value, {bool big = false, Color color = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.white60, fontSize: big ? 16 : 14)),
          const Spacer(),
          Text(value, style: big ? neon(22, color: color, spacing: 1) : TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap, {bool primary = false, IconData? icon, Key? key}) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1)),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const padding = EdgeInsets.symmetric(vertical: 16);
    return primary
        ? FilledButton(
            key: key,
            onPressed: onTap,
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black, shape: shape, padding: padding),
            child: child,
          )
        : OutlinedButton(
            key: key,
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white30),
              shape: shape,
              padding: padding,
            ),
            child: child,
          );
  }
}
