import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

/// Optional "bunny" look: a flat, bold-outlined palette (sky blue, grass
/// green, orange) and an original white bunny that peeks out from behind
/// bars and card borders. Drawn in code, no image assets.
class BunnyStyle extends ThemeExtension<BunnyStyle> {
  const BunnyStyle({this.enabled = false});
  final bool enabled;

  static bool of(BuildContext context) =>
      Theme.of(context).extension<BunnyStyle>()?.enabled ?? false;

  @override
  BunnyStyle copyWith({bool? enabled}) =>
      BunnyStyle(enabled: enabled ?? this.enabled);

  @override
  BunnyStyle lerp(BunnyStyle? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

const bunnySky = Color(0xFF1F4E96);
const bunnyGrass = Color(0xFF4A7A2C);
const bunnyOrange = Color(0xFFE8601C);
const bunnyInk = Color(0xFF111111);

ThemeData bunnyTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: bunnyOrange,
    primary: bunnyOrange,
    secondary: bunnySky,
    tertiary: bunnyGrass,
    surface: const Color(0xFFFFFBF5),
  );
  const outline = BorderSide(color: bunnyInk, width: 2);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF4EFE6),
    extensions: const [BunnyStyle(enabled: true)],
    appBarTheme: const AppBarTheme(
      backgroundColor: bunnySky,
      foregroundColor: Colors.white,
      shape: Border(bottom: BorderSide(color: bunnyInk, width: 3)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: bunnyGrass,
      indicatorColor: bunnyOrange,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? Colors.white
              : Colors.white70,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          color: Colors.white,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white70,
      indicatorColor: bunnyOrange,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: outline,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: bunnyOrange,
      foregroundColor: Colors.white,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: outline,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
  );
}

/// Where the bunny peeks out from, relative to the thing it hides behind:
/// over its top edge, or hanging upside down below its bottom edge.
enum Peek {
  none,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  bool get isTop => this == topLeft || this == topRight;
}

/// Height of the bunny above (or below) the edge it hides behind when it
/// leans all the way out: the whole head, the chin just behind the edge.
double bunnyShown(double width) => width * 1.2 * 0.95;

/// How much shows while it hides: just the ear tips.
double bunnyResting(double width) => width * 1.2 * 0.2;

/// Bumped at the moments the bunnies should lean out and wave: a screen
/// shows up, the month changes, something gets saved.
final bunnyCue = ValueNotifier<int>(0);
void cueBunny() => bunnyCue.value++;

/// The bunny's head and ears, facing up, with a paw that can wave. Painted
/// into a 100 × 120 box: the bottom of the head is meant to be hidden
/// behind something.
class BunnyPainter extends CustomPainter {
  const BunnyPainter({
    this.eyesClosed = false,
    this.lookX = 0,
    this.pawUp = 0,
    this.wave = 0,
  });

  final bool eyesClosed;

  /// -1..1: where the eyes look, left to right.
  final double lookX;

  /// 0 = paw down out of sight, 1 = raised beside the head.
  final double pawUp;

  /// Paw swing in radians.
  final double wave;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 120);
    final ink = Paint()
      ..color = bunnyInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = Colors.white;

    // Long ears, slightly apart, a little rounder at the tips.
    for (final (cx, tilt) in const [(34.0, -0.10), (66.0, 0.10)]) {
      canvas.save();
      canvas.translate(cx, 46);
      canvas.rotate(tilt);
      final ear = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-9, -44, 18, 58),
        const Radius.circular(9),
      );
      canvas.drawRRect(ear, fill);
      canvas.drawRRect(ear, ink);
      canvas.restore();
    }

    // Head: a wide, soft oval.
    final head = Rect.fromCenter(
      center: const Offset(50, 86),
      width: 76,
      height: 62,
    );
    canvas.drawOval(head, fill);
    canvas.drawOval(head, ink);

    // Eyes: dots, or short lines when blinking.
    final dot = Paint()..color = bunnyInk;
    for (final ex in const [37.0, 63.0]) {
      final c = Offset(ex + lookX * 3, 82);
      if (eyesClosed) {
        canvas.drawLine(
          c.translate(-4, 0),
          c.translate(4, 0),
          ink..strokeWidth = 3,
        );
        ink.strokeWidth = 4.5;
      } else {
        canvas.drawOval(Rect.fromCenter(center: c, width: 6.5, height: 8), dot);
      }
    }

    // A small round nose and rosy cheeks.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 93), width: 7, height: 5),
      Paint()..color = const Color(0xFFE88A8A),
    );
    final blush = Paint()..color = const Color(0x33E8601C);
    canvas.drawCircle(const Offset(27, 94), 6, blush);
    canvas.drawCircle(const Offset(73, 94), 6, blush);

    // The waving paw: comes up beside the head and swings from the wrist.
    if (pawUp > 0) {
      canvas.save();
      // Pivot just right of the head, so the raised paw stands clear of it.
      canvas.translate(97, 116);
      canvas.rotate(0.25 + wave);
      final paw = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, -48 * pawUp), width: 18, height: 26),
        const Radius.circular(9),
      );
      canvas.drawRRect(paw, fill);
      canvas.drawRRect(paw, ink..strokeWidth = 4);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(BunnyPainter old) =>
      old.eyesClosed != eyesClosed ||
      old.lookX != lookX ||
      old.pawUp != pawUp ||
      old.wave != wave;
}

/// One appearance of the bunny, for t in 0..1: lean out, wave, blink,
/// glance aside, hide again.
class BunnyPose {
  const BunnyPose({
    required this.out,
    this.pawUp = 0,
    this.wave = 0,
    this.eyesClosed = false,
    this.lookX = 0,
  });

  /// 0 = only the ear tips show, 1 = leaning all the way out.
  final double out;
  final double pawUp;
  final double wave;
  final bool eyesClosed;
  final double lookX;

  static const hidden = BunnyPose(out: 0);

  factory BunnyPose.at(double t) {
    if (t <= 0 || t >= 1) return hidden;
    double span(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
    final out = t < 0.12
        ? Curves.easeOutBack.transform(span(0, 0.12))
        : t < 0.86
        ? 1.0
        : 1 - Curves.easeInCubic.transform(span(0.86, 1));
    final pawUp = t < 0.14
        ? 0.0
        : t < 0.2
        ? Curves.easeOut.transform(span(0.14, 0.2))
        : t < 0.58
        ? 1.0
        : 1 - Curves.easeIn.transform(span(0.58, 0.66));
    // Three swings while the paw is up.
    final wave = t >= 0.2 && t < 0.58
        ? sin(span(0.2, 0.58) * 2 * pi * 3) * 0.45
        : 0.0;
    return BunnyPose(
      out: out,
      pawUp: pawUp,
      wave: wave,
      eyesClosed: t > 0.68 && t < 0.71,
      lookX: t > 0.72 && t < 0.84 ? 1 : 0,
    );
  }
}

/// An [AppBar] (or any app bar) with the bunny hanging upside down below
/// its bottom edge.
class BunnyAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BunnyAppBar({
    super.key,
    required this.appBar,
    this.peek = Peek.bottomRight,
    this.seed = 0,
  });

  final PreferredSizeWidget appBar;
  final Peek peek;
  final int seed;

  @override
  Size get preferredSize => appBar.preferredSize;

  @override
  Widget build(BuildContext context) =>
      PeekingBunny(peek: peek, width: 34, seed: seed, child: appBar);
}

/// The bunny drawn in one [pose].
class Bunny extends StatelessWidget {
  const Bunny({super.key, this.width = 44, this.pose = BunnyPose.hidden});
  final double width;
  final BunnyPose pose;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(width, width * 1.2),
        painter: BunnyPainter(
          eyesClosed: pose.eyesClosed,
          lookX: pose.lookX,
          pawUp: pose.pawUp,
          wave: pose.wave,
        ),
      ),
    );
  }
}

/// Puts the bunny behind [child], peeking out at [peek]. Most of the time
/// only its ear tips show; when cued (see [cueBunny]), or now and then on
/// its own, it leans out, waves and hides again. With the theme off (or
/// [Peek.none]) this is just [child].
class PeekingBunny extends StatefulWidget {
  const PeekingBunny({
    super.key,
    required this.child,
    this.peek = Peek.topRight,
    this.width = 40,
    this.inset = 24,
    this.seed = 0,
  });

  final Widget child;
  final Peek peek;
  final double width;

  /// Distance from the corner along the edge.
  final double inset;

  /// Varies the bunnies on one screen: who comes out first, when each one
  /// shows up on its own.
  final int seed;

  @override
  State<PeekingBunny> createState() => _PeekingBunnyState();
}

class _PeekingBunnyState extends State<PeekingBunny>
    with SingleTickerProviderStateMixin {
  static const _show = Duration(milliseconds: 3600);

  // Widget tests fail on pending timers: no unprompted visits there.
  static final _idle = !Platform.environment.containsKey('FLUTTER_TEST');

  late final _rnd = Random(widget.seed);

  /// Bunnies on one screen come out one after another, not all at once.
  late final int _delayMs = (widget.seed.abs() % 4) * 300;
  late final _ctrl = AnimationController(
    vsync: this,
    duration: _show + Duration(milliseconds: _delayMs),
  );
  Timer? _visit;

  @override
  void initState() {
    super.initState();
    bunnyCue.addListener(_onCue);
    // Say hello when the screen first shows up.
    _onCue();
    _scheduleVisit();
  }

  @override
  void dispose() {
    bunnyCue.removeListener(_onCue);
    _visit?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  // The cue often comes with a rebuild (new tab, new month): check after
  // the frame whether this bunny is on screen at all.
  void _onCue() => WidgetsBinding.instance.addPostFrameCallback((_) => _play());

  void _play() {
    if (!mounted || _ctrl.isAnimating) return;
    if (!BunnyStyle.of(context) || !TickerMode.valuesOf(context).enabled) {
      return;
    }
    _ctrl.forward(from: 0);
  }

  void _scheduleVisit() {
    if (!_idle) return;
    _visit = Timer(Duration(seconds: 25 + _rnd.nextInt(35)), () {
      _play();
      _scheduleVisit();
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    if (w.peek == Peek.none || !BunnyStyle.of(context)) return w.child;
    final full = bunnyShown(w.width);
    final travel = full - bunnyResting(w.width);
    final total = _ctrl.duration!.inMilliseconds;
    final bunny = AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = (_ctrl.value * total - _delayMs) / _show.inMilliseconds;
        final pose = BunnyPose.at(t);
        // Slides back towards its chin (inside the rotation for the
        // upside-down ones); the bar or card in front hides whatever has
        // not come out yet.
        final dy = (1 - pose.out) * travel;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Bunny(width: w.width, pose: pose),
        );
      },
    );
    final upsideDown = RotatedBox(quarterTurns: 2, child: bunny);
    final Widget positioned = switch (w.peek) {
      Peek.topRight => Positioned(top: -full, right: w.inset, child: bunny),
      Peek.topLeft => Positioned(top: -full, left: w.inset, child: bunny),
      Peek.bottomRight => Positioned(
        bottom: -full,
        right: w.inset,
        child: upsideDown,
      ),
      Peek.bottomLeft => Positioned(
        bottom: -full,
        left: w.inset,
        child: upsideDown,
      ),
      Peek.none => const SizedBox.shrink(),
    };
    // The bunny is painted first, so [child] covers what is still behind
    // the edge.
    return Stack(clipBehavior: Clip.none, children: [positioned, w.child]);
  }
}
