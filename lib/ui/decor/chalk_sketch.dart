import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tiza_theme.dart';

/// Un pizarrón garabateado a mano, para el estado vacío.
///
/// Podría ser un ícono de la fuente Material, pero un ícono perfecto sobre una
/// superficie de papel se delata: el trazo tembloroso es lo que hace que la
/// pantalla se lea como dibujada y no como generada. El temblor tiene semilla
/// fija, así que es el mismo dibujo siempre.
class ChalkSketch extends StatelessWidget {
  const ChalkSketch({super.key, this.size = const Size(148, 112)});

  final Size size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: size,
      painter: _ChalkSketchPainter(color: context.tiza.inkMuted),
    );
  }
}

class _ChalkSketchPainter extends CustomPainter {
  _ChalkSketchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Dos pasadas con semillas distintas: cada una tiembla diferente y juntas
    // dan el borde sucio de un trazo real. Una sola pasada se ve prolija.
    for (final seed in [11, 29]) {
      final random = math.Random(seed);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      // El marco del pizarrón.
      final frame = Rect.fromLTWH(2, 2, size.width - 4, size.height - 26);
      canvas.drawPath(_wobblyRect(frame, random), paint);

      // Tres renglones adentro, decrecientes: sugieren texto sin escribirlo.
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;

      final inset = frame.left + 16;
      final widths = [0.62, 0.44, 0.52];
      for (var i = 0; i < widths.length; i++) {
        final y = frame.top + 22 + i * 18;
        canvas.drawPath(
          _wobblyLine(
            Offset(inset, y),
            Offset(inset + (frame.width - 32) * widths[i], y),
            random,
          ),
          linePaint,
        );
      }

      // Las patas del caballete.
      final legPaint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        _wobblyLine(
          Offset(size.width * 0.3, frame.bottom),
          Offset(size.width * 0.2, size.height - 3),
          random,
        ),
        legPaint,
      );
      canvas.drawPath(
        _wobblyLine(
          Offset(size.width * 0.7, frame.bottom),
          Offset(size.width * 0.8, size.height - 3),
          random,
        ),
        legPaint,
      );
    }
  }

  /// Un rectángulo cuyos cuatro lados tiemblan.
  Path _wobblyRect(Rect rect, math.Random random) {
    final path = Path();
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
      rect.topLeft,
    ];
    path.moveTo(corners.first.dx, corners.first.dy);
    for (var i = 0; i < corners.length - 1; i++) {
      _appendWobble(path, corners[i], corners[i + 1], random);
    }
    return path;
  }

  Path _wobblyLine(Offset from, Offset to, math.Random random) {
    final path = Path()..moveTo(from.dx, from.dy);
    _appendWobble(path, from, to, random);
    return path;
  }

  /// Avanza de [from] a [to] en tramos cortos, desviando cada punto un poco.
  void _appendWobble(Path path, Offset from, Offset to, math.Random random) {
    const step = 14.0;
    const jitter = 1.4;
    final distance = (to - from).distance;
    final steps = math.max(2, (distance / step).round());
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final point = Offset.lerp(from, to, t)!;
      // El último punto no se desvía, para que las esquinas cierren.
      final offset = i == steps ? Offset.zero : Offset(
        (random.nextDouble() - 0.5) * jitter * 2,
        (random.nextDouble() - 0.5) * jitter * 2,
      );
      path.lineTo(point.dx + offset.dx, point.dy + offset.dy);
    }
  }

  @override
  bool shouldRepaint(_ChalkSketchPainter old) => old.color != color;
}
