import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ─── The Acalink loading screen ───────────────────────────────────────
///
/// Shown while the app starts and restores the parent's session, in place of a
/// white screen and a spinner. It is one continuous piece of motion:
///
///   • the graduation cap assembles on the logo tile — the board drops in, the
///     body rises to meet it, the tassel swings out and settles;
///   • a band of light sweeps across the tile, over and over;
///   • two rings of light orbit it in opposite directions, each with a bright
///     head, while a soft glow breathes behind;
///   • a field of faint stars drifts upward;
///   • the name types itself in under it, above a slow shimmer of progress.
///
/// It always paints on the dark Acalink background, whatever theme the app is
/// in, so it matches the native launch screen it follows (a dark background with
/// the same tile — see android/.../launch_background.xml and the iOS
/// LaunchScreen) and the web page's own splash. The cap is drawn from the same
/// coordinates as the app icon (tool/generate_icons.py), so the first thing a
/// parent sees and the icon they tapped are visibly the same mark.
///
/// With the system's "reduce motion" setting on, it holds the finished logo
/// still instead of animating.
class AcalinkLoader extends StatefulWidget {
  /// On the web the page's own loader (web/index.html) has already played the
  /// intro by the time Flutter starts, so the app picks up from the finished
  /// logo instead of building it a second time.
  const AcalinkLoader({super.key, this.skipIntro = false});

  final bool skipIntro;

  @override
  State<AcalinkLoader> createState() => _AcalinkLoaderState();
}

class _AcalinkLoaderState extends State<AcalinkLoader> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );

  bool _started = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_started) return;
    _started = true;
    if (_reduceMotion) {
      _intro.value = 1;
    } else if (widget.skipIntro) {
      _intro.value = 1;
      _loop.repeat();
    } else {
      _intro.forward();
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading Acalink',
      child: Scaffold(
        backgroundColor: _Brand.background,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.12),
              radius: 0.95,
              colors: [_Brand.backgroundGlow, _Brand.background],
            ),
          ),
          child: AnimatedBuilder(
            animation: Listenable.merge([_intro, _loop]),
            builder: (context, _) {
              return LayoutBuilder(
                builder: (context, box) {
                  final side = math.min(box.maxWidth, box.maxHeight * 0.62);
                  final stage = side.clamp(220.0, 420.0);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Drifting stars across the whole screen.
                      CustomPaint(painter: _StarsPainter(loop: _loop.value, intro: _intro.value)),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: stage,
                              height: stage,
                              child: CustomPaint(
                                painter: _MarkPainter(intro: _intro.value, loop: _loop.value),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _Wordmark(progress: _intro.value),
                            const SizedBox(height: 22),
                            _Shimmer(phase: _loop.value, progress: _intro.value),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Brand {
  static const Color background = Color(0xFF0D1427);
  static const Color backgroundGlow = Color(0xFF1B2A55);
  static const Color blueA = Color(0xFF4D6BF3);
  static const Color blueB = Color(0xFF3D59DD);
  static const Color light = Color(0xFF9DB4FF);
  static const Color teal = Color(0xFF22D3DE);
}

/// 0→1 across [a, b] of a larger 0→1 timeline.
double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

// ─── The logo ─────────────────────────────────────────────────────────

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.intro, required this.loop});

  final double intro;
  final double loop;

  // The cap, in the 512-unit space the app icon is drawn in.
  static const _top = [Offset(62, 231), Offset(256, 138), Offset(450, 231), Offset(256, 324)];
  static const _body = [
    Offset(148, 283), Offset(256, 338), Offset(364, 283),
    Offset(364, 358), Offset(256, 410), Offset(148, 358),
  ];
  static const _capWidth = 392.0; // 454 - 62
  static const _capCentre = Offset(256, 274);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final tileSide = size.shortestSide * 0.50;
    final angle = loop * 2 * math.pi;

    // Breathing glow behind everything.
    final breathe = 0.5 + 0.5 * math.sin(angle);
    final glowOpacity = _seg(intro, 0.0, 0.5) * (0.30 + 0.16 * breathe);
    canvas.drawCircle(
      centre,
      tileSide * (0.95 + 0.06 * breathe),
      Paint()
        ..shader = RadialGradient(
          colors: [
            _Brand.blueA.withValues(alpha: glowOpacity),
            _Brand.blueA.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: centre, radius: tileSide * 1.0)),
    );

    // Orbiting rings, opposite directions.
    final ringsIn = Curves.easeOut.transform(_seg(intro, 0.25, 0.8));
    _ring(canvas, centre, tileSide * 0.80, angle, 2.6, ringsIn, _Brand.light);
    _ring(canvas, centre, tileSide * 0.97, -angle * 0.7 + 1.9, 1.6, ringsIn * 0.8, _Brand.teal);

    // The tile: pops in with a little overshoot, then floats.
    final pop = Curves.easeOutBack.transform(_seg(intro, 0.0, 0.42));
    final float = math.sin(angle) * tileSide * 0.018;
    final tileScale = 0.55 + 0.45 * pop;
    final tileRect = Rect.fromCenter(
      center: centre.translate(0, float),
      width: tileSide * tileScale,
      height: tileSide * tileScale,
    );
    final tile = RRect.fromRectAndRadius(tileRect, Radius.circular(tileRect.width * 0.2237));
    final tileOpacity = _seg(intro, 0.0, 0.25);

    canvas.drawRRect(
      tile.shift(Offset(0, tileSide * 0.04)),
      Paint()
        ..color = _Brand.blueA.withValues(alpha: 0.35 * tileOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, tileSide * 0.09),
    );
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _Brand.blueA.withValues(alpha: tileOpacity),
            _Brand.blueB.withValues(alpha: tileOpacity),
          ],
        ).createShader(tileRect),
    );

    // The cap, assembling.
    final k = tileRect.width * 0.76 / _capWidth;
    Offset at(Offset p, [Offset shift = Offset.zero]) =>
        tileRect.center + (p - _capCentre) * k + shift;

    final boardT = _seg(intro, 0.14, 0.52);
    final bodyT = _seg(intro, 0.26, 0.62);
    final boardShift = Offset(0, -(1 - Curves.easeOutBack.transform(boardT)) * 120 * k);
    final bodyShift = Offset(0, (1 - Curves.easeOutCubic.transform(bodyT)) * 90 * k);

    canvas.drawPath(
      _poly(_body.map((p) => at(p, bodyShift)).toList()),
      Paint()..color = Colors.white.withValues(alpha: bodyT),
    );
    canvas.drawPath(
      _poly(_top.map((p) => at(p, boardShift)).toList()),
      Paint()..color = Colors.white.withValues(alpha: boardT),
    );

    // The tassel hangs from the right-hand corner of the board and swings out,
    // then keeps a faint sway.
    final tasselT = _seg(intro, 0.50, 0.95);
    if (tasselT > 0) {
      final pivot = at(const Offset(446, 236), boardShift);
      final swing = (1 - Curves.elasticOut.transform(tasselT)) * 1.1 + math.sin(angle * 2) * 0.035 * _seg(intro, 0.9, 1.0);
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(swing);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-8 * k, 0, 16 * k, 112 * k),
          Radius.circular(3 * k),
        ),
        Paint()..color = Colors.white.withValues(alpha: tasselT.clamp(0.0, 1.0)),
      );
      canvas.restore();
    }

    // A band of light sweeping across the tile, once per cycle.
    final sweep = _seg(loop, 0.55, 0.95) * _seg(intro, 0.7, 1.0);
    if (sweep > 0 && sweep < 1) {
      canvas.save();
      canvas.clipRRect(tile);
      final travel = tileRect.width * 1.8;
      canvas.translate(tileRect.left - tileRect.width * 0.4 + travel * Curves.easeInOut.transform(sweep), tileRect.center.dy);
      canvas.rotate(-0.42);
      final band = Rect.fromCenter(center: Offset.zero, width: tileRect.width * 0.26, height: tileRect.height * 2.4);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.34),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(band),
      );
      canvas.restore();
    }
  }

  /// A ring of light: a faint full circle with a bright, fading comet on it.
  void _ring(Canvas canvas, Offset centre, double radius, double head, double width, double opacity, Color colour) {
    if (opacity <= 0) return;
    final rect = Rect.fromCircle(center: centre, radius: radius);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colour.withValues(alpha: 0.10 * opacity),
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          transform: GradientRotation(head),
          colors: [
            colour.withValues(alpha: 0),
            colour.withValues(alpha: 0),
            colour.withValues(alpha: opacity),
          ],
          stops: const [0.0, 0.68, 1.0],
        ).createShader(rect),
    );
    final tip = centre + Offset(math.cos(head), math.sin(head)) * radius;
    canvas.drawCircle(
      tip,
      width * 3.2,
      Paint()
        ..color = colour.withValues(alpha: 0.55 * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 2.4),
    );
    canvas.drawCircle(tip, width * 1.25, Paint()..color = Colors.white.withValues(alpha: opacity));
  }

  Path _poly(List<Offset> points) => Path()..addPolygon(points, true);

  @override
  bool shouldRepaint(_MarkPainter old) => old.intro != intro || old.loop != loop;
}

// ─── The stars ────────────────────────────────────────────────────────

class _StarsPainter extends CustomPainter {
  _StarsPainter({required this.loop, required this.intro});

  final double loop;
  final double intro;

  /// A repeatable "random" in 0..1, so every frame draws the same stars.
  static double _r(int i, int k) {
    final v = math.sin(i * 127.1 + k * 311.7) * 43758.5453;
    return (v - v.floorToDouble()).abs();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fade = _seg(intro, 0.1, 0.9);
    for (var i = 0; i < 26; i++) {
      final speed = 0.25 + 0.5 * _r(i, 3);
      final x = _r(i, 1) * size.width;
      var y = (_r(i, 2) - loop * speed) % 1.0;
      if (y < 0) y += 1.0;
      final twinkle = 0.5 + 0.5 * math.sin(loop * 2 * math.pi * (1 + (i % 3)) + _r(i, 4) * 6.28);
      final radius = 0.7 + 1.5 * _r(i, 5);
      canvas.drawCircle(
        Offset(x, y * size.height),
        radius,
        Paint()..color = _Brand.light.withValues(alpha: (0.10 + 0.42 * twinkle) * fade * (0.4 + 0.6 * _r(i, 6))),
      );
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => old.loop != loop || old.intro != intro;
}

// ─── The name, and the progress shimmer ───────────────────────────────

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.progress});

  final double progress;

  static const _letters = 'ACALINK';

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _letters.length; i++)
          Builder(
            builder: (context) {
              final t = Curves.easeOutCubic.transform(_seg(progress, 0.45 + i * 0.045, 0.72 + i * 0.045));
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3.5),
                    child: Text(
                      _letters[i],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _Shimmer extends StatelessWidget {
  const _Shimmer({required this.phase, required this.progress});

  final double phase;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final visible = _seg(progress, 0.7, 1.0);
    return Opacity(
      opacity: visible,
      child: SizedBox(
        width: 120,
        height: 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: [
              Container(color: Colors.white.withValues(alpha: 0.10)),
              Align(
                alignment: Alignment(-1.0 + 2.0 * ((phase * 1.0) % 1.0), 0),
                child: FractionallySizedBox(
                  widthFactor: 0.38,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0x004D6BF3), _Brand.light, Color(0x004D6BF3)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
