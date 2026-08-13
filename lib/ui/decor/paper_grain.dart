import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../../theme/tiza_theme.dart';

/// Grano sobre el fondo: fibra de papel en claro, polvo de tiza en oscuro.
///
/// Es lo único que separa una superficie de un rectángulo de color. Se pinta una
/// sola vez y queda en caché de raster: el [RepaintBoundary] más
/// `willChange: false` evitan que se recalcule en cada frame.
class PaperGrain extends StatelessWidget {
  const PaperGrain({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.tiza;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _GrainPainter(
                color: palette.ink,
                chalkboard: palette.isChalkboard,
              ),
              isComplex: true,
              willChange: false,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter({required this.color, required this.chalkboard});

  final Color color;
  final bool chalkboard;

  @override
  void paint(Canvas canvas, Size size) {
    // Semilla fija. Con una semilla al azar el grano cambiaría en cada
    // repintado y el fondo titilaría cada vez que se rearma el layout.
    final random = math.Random(20260803);
    final count = (size.width * size.height / 900).clamp(200, 1400).toInt();

    final points = <Offset>[
      for (var i = 0; i < count; i++)
        Offset(random.nextDouble() * size.width, random.nextDouble() * size.height),
    ];

    // La tiza deja una marca más gruesa y más visible que la fibra del papel.
    final paint = Paint()
      ..color = color.withValues(alpha: chalkboard ? 0.055 : 0.035)
      ..strokeWidth = chalkboard ? 1.4 : 1.0
      ..strokeCap = StrokeCap.round;

    canvas.drawPoints(PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(_GrainPainter old) =>
      old.color != color || old.chalkboard != chalkboard;
}
