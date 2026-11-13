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

/// Height of the bunny that shows above (or below) the edge it hides behind.
double bunnyShown(double width) => width * 1.2 * 0.84;

/// The bunny's head and ears, facing up. Painted into a 100 × 120 box:
/// the bottom of the head is meant to be hidden behind something.
class BunnyPainter extends CustomPainter {
  const BunnyPainter({this.eyesClosed = false, this.lookX = 0});

  final bool eyesClosed;

  /// -1..1: where the eyes look, left to right.
  final double lookX;

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
  }

  @override
  bool shouldRepaint(BunnyPainter old) =>
      old.eyesClosed != eyesClosed || old.lookX != lookX;
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

/// The bunny, blinking now and then and glancing around.
class Bunny extends StatefulWidget {
  const Bunny({super.key, this.width = 44, this.seed = 0});
  final double width;
  final int seed;

  @override
  State<Bunny> createState() => _BunnyState();
}

class _BunnyState extends State<Bunny> {
  late final _rnd = Random(widget.seed);
  Timer? _timer;
  bool _closed = false;
  double _look = 0;

  // Widget tests fail on pending timers: the bunny holds still there.
  static final _animate = !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    if (_animate) _schedule();
  }

  void _schedule() {
    _timer = Timer(Duration(milliseconds: 2500 + _rnd.nextInt(4000)), () {
      if (!mounted) return;
      if (_rnd.nextInt(3) == 0) {
        setState(() => _look = _rnd.nextInt(3) - 1.0);
        _schedule();
        return;
      }
      setState(() => _closed = true);
      _timer = Timer(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        setState(() => _closed = false);
        _schedule();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(widget.width, widget.width * 1.2),
        painter: BunnyPainter(eyesClosed: _closed, lookX: _look),
      ),
    );
  }
}

/// Puts the bunny behind [child], peeking out at [peek]. With the theme
/// off (or [Peek.none]) this is just [child].
class PeekingBunny extends StatelessWidget {
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
  final int seed;

  @override
  Widget build(BuildContext context) {
    if (peek == Peek.none || !BunnyStyle.of(context)) return child;
    // Ears and eyes show, the chin stays behind the edge.
    final shown = bunnyShown(width);
    final bunny = Bunny(width: width, seed: seed);
    final upsideDown = RotatedBox(quarterTurns: 2, child: bunny);
    final Widget positioned = switch (peek) {
      Peek.topRight => Positioned(top: -shown, right: inset, child: bunny),
      Peek.topLeft => Positioned(top: -shown, left: inset, child: bunny),
      Peek.bottomRight => Positioned(
        bottom: -shown,
        right: inset,
        child: upsideDown,
      ),
      Peek.bottomLeft => Positioned(
        bottom: -shown,
        left: inset,
        child: upsideDown,
      ),
      Peek.none => const SizedBox.shrink(),
    };
    // The bunny is painted first, so [child] covers its chin; the part that
    // sticks out past the edge stays visible.
    return Stack(clipBehavior: Clip.none, children: [positioned, child]);
  }
}
