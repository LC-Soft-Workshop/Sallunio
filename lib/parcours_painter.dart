import 'dart:math';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'parcours.dart';

class ParcoursPainter extends CustomPainter {
  ParcoursPainter(this.project, this.scale, {required this.dark})
    : paths = parcoursPaths(project, allowStale: true),
      stale = !parcoursCurrent(project);
  final Json project;
  final double scale;
  final bool dark;
  final bool stale;
  final List<List<Point<double>>> paths;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dark ? const Color(0xff8bd5ff) : const Color(0xff1565c0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final route in paths) {
      if (route.isEmpty) continue;
      final path = Path()..moveTo(route.first.x * scale, route.first.y * scale);
      for (final point in route.skip(1)) {
        path.lineTo(point.x * scale, point.y * scale);
      }
      if (stale) {
        for (final metric in path.computeMetrics()) {
          for (double offset = 0; offset < metric.length; offset += 12) {
            canvas.drawPath(
              metric.extractPath(offset, min(offset + 7, metric.length)),
              paint,
            );
          }
        }
      } else {
        canvas.drawPath(path, paint);
      }
    }
    if (!parcoursCurrent(project)) return;
    for (final arrow in parcoursArrows(project)) {
      canvas.drawPath(
        Path()
          ..moveTo(arrow[0].x * scale, arrow[0].y * scale)
          ..lineTo(arrow[1].x * scale, arrow[1].y * scale)
          ..lineTo(arrow[2].x * scale, arrow[2].y * scale),
        paint,
      );
    }
    for (final service in project['parcoursPlan']['services'] as List? ?? []) {
      final zones = rows(
        project,
        'items',
      ).where((i) => i['id'] == service['id']);
      if (zones.isEmpty) continue;
      final zone = zones.first;
      canvas.drawRect(
        Rect.fromLTWH(
          number(zone['x']) * scale,
          number(zone['y']) * scale,
          number(zone['w']) * scale,
          number(zone['h']) * scale,
        ).inflate(1.5),
        paint,
      );
    }
    for (final b in project['parcoursPlan']['blocks'] as List) {
      final rect = Rect.fromLTWH(
        number(b['x']) * scale,
        number(b['y']) * scale,
        number(b['w']) * scale,
        number(b['h']) * scale,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = (dark ? Colors.amber.shade100 : Colors.amber.shade900)
              .withValues(alpha: .08),
      );
    }
  }

  @override
  bool shouldRepaint(ParcoursPainter oldDelegate) => true;
}
