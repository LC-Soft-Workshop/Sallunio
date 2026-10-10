import 'package:flutter/material.dart';

import 'domain.dart';

class PlanMarker extends StatelessWidget {
  const PlanMarker({
    super.key,
    required this.name,
    required this.color,
    this.size = 12,
  });
  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _MarkerPainter(planMarkerShape(name), color)),
  );
}

class _MarkerPainter extends CustomPainter {
  const _MarkerPainter(this.shape, this.color);
  final PlanMarkerShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path();
    if (shape == PlanMarkerShape.circle) {
      path.addOval(rect.deflate(.6));
    } else {
      final points = planMarkerVertices(shape);
      path.moveTo(
        .6 + points.first.x * (size.width - 1.2),
        .6 + points.first.y * (size.height - 1.2),
      );
      for (final point in points.skip(1)) {
        path.lineTo(
          .6 + point.x * (size.width - 1.2),
          .6 + point.y * (size.height - 1.2),
        );
      }
      path.close();
    }
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_MarkerPainter oldDelegate) =>
      shape != oldDelegate.shape || color != oldDelegate.color;
}
