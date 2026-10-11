import 'dart:math';

import 'package:flutter/material.dart';

import 'domain.dart';

class ParcoursSnapshot extends StatelessWidget {
  const ParcoursSnapshot({
    super.key,
    required this.project,
    required this.selected,
    required this.onToggle,
  });
  final Json project;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final w = number(project['room']['width']),
          h = number(project['room']['height']);
      final scale = min(constraints.maxWidth / w, 220 / h);
      return Center(
        child: SizedBox(
          width: w * scale,
          height: h * scale,
          child: GestureDetector(
            key: const ValueKey('parcours-snapshot'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (event) {
              final x = event.localPosition.dx / scale,
                  y = event.localPosition.dy / scale;
              final polygon = roomPolygon(project['room']);
              if (polygon.isNotEmpty && !inside(Point(x, y), polygon)) {
                return;
              }
              final zones =
                  rows(project, 'items')
                      .where(
                        (i) =>
                            i['kind'] == 'zone' &&
                            x >= number(i['x']) &&
                            x <= number(i['x']) + number(i['w']) &&
                            y >= number(i['y']) &&
                            y <= number(i['y']) + number(i['h']),
                      )
                      .toList()
                    ..sort(
                      (a, b) => (number(a['w']) * number(a['h'])).compareTo(
                        number(b['w']) * number(b['h']),
                      ),
                    );
              if (zones.isNotEmpty) onToggle(zones.first['id']);
            },
            child: CustomPaint(
              painter: _SnapshotPainter(
                project,
                selected,
                scale,
                Theme.of(context).colorScheme,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SnapshotPainter extends CustomPainter {
  const _SnapshotPainter(this.project, this.selected, this.scale, this.colors);
  final Json project;
  final Set<String> selected;
  final double scale;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.surface);
    final zones =
        rows(project, 'items').where((i) => i['kind'] == 'zone').toList()..sort(
          (a, b) => (number(b['w']) * number(b['h'])).compareTo(
            number(a['w']) * number(a['h']),
          ),
        );
    for (final item in [
      ...zones,
      ...rows(
        project,
        'items',
      ).where((i) => i['kind'] != 'zone' && !unplacedTable(project, i)),
    ]) {
      final rect = Rect.fromLTWH(
        number(item['x']) * scale,
        number(item['y']) * scale,
        number(item['w']) * scale,
        number(item['h']) * scale,
      );
      final chosen = selected.contains(item['id']),
          zone = item['kind'] == 'zone';
      final fill = chosen
          ? colors.primaryContainer
          : zone
          ? Color(zoneColors[item['zoneColor']] ?? zoneColors['Bleu']!)
                .withValues(alpha: .3)
          : item['kind'] == 'table'
          ? colors.surfaceContainerHighest
          : colors.secondaryContainer;
      canvas.drawRect(rect, Paint()..color = fill);
      canvas.drawRect(
        rect,
        Paint()
          ..color = chosen ? colors.primary : colors.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = chosen ? 3 : 1,
      );
      if (zone || item['kind'] != 'table') {
        final label = (item['label'] ?? '').toString().trim();
        final text = TextPainter(
          text: TextSpan(
            text: label.isEmpty ? 'Zone' : label,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 11,
              fontFamily: 'Roboto',
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: max(15, rect.width - 4));
        text.paint(
          canvas,
          Offset(
            rect.center.dx - text.width / 2,
            rect.center.dy - text.height / 2,
          ),
        );
      }
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = colors.outline
        ..style = PaintingStyle.stroke,
    );
    final polygon = roomPolygon(project['room']);
    if (polygon.isNotEmpty) {
      final contour = Path()
        ..addPolygon([
          for (final point in polygon) Offset(point.x * scale, point.y * scale),
        ], true);
      final outside = Path()
        ..addRect(Offset.zero & size)
        ..addPath(contour, Offset.zero)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(
        outside,
        Paint()..color = colors.surfaceContainerHighest.withValues(alpha: .8),
      );
      canvas.drawPath(
        contour,
        Paint()
          ..color = colors.outline
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_SnapshotPainter oldDelegate) => true;
}
