part of 'main.dart';

class _PlanRotationDrag {
  final List<Json> origins;
  final Offset pivot;
  final List<Offset> frame;
  final double bearing;
  double degrees = 0;
  _PlanRotationDrag(this.origins, this.pivot, this.frame, this.bearing);
}

extension _PlanRotation on _HomeState {
  Offset planPointer(Offset global, double scale) =>
      (planCanvasSurfaceKey.currentContext!.findRenderObject() as RenderBox)
          .globalToLocal(global) /
      scale;
  void finishPlanRotation() {
    rotationDrag = null;
    persist();
  }

  Iterable<Widget> planRotationControls(double scale) sync* {
    if (!rotationModeActive || planReadOnly || measuring) {
      return;
    }
    final ids = selectedPlanIds();
    final items = rows(
      p!,
      'items',
    ).where((i) => ids.contains(i['id'])).toList();
    if (items.isEmpty || items.any((i) => i['fixed'] == true)) return;
    final all = items.expand(furnitureCorners).toList();
    final bounds = Rect.fromLTRB(
      all.map((v) => v.x).reduce(min),
      all.map((v) => v.y).reduce(min),
      all.map((v) => v.x).reduce(max),
      all.map((v) => v.y).reduce(max),
    );
    final pivot =
        rotationDrag?.pivot ??
        (items.length == 1
            ? Offset(
                number(items.single['x']) + number(items.single['w']) / 2,
                number(items.single['y']) + number(items.single['h']) / 2,
              )
            : bounds.center);
    var points = items.length == 1
        ? furnitureCorners(items.single).map((v) => Offset(v.x, v.y)).toList()
        : [
            bounds.topLeft,
            bounds.topRight,
            bounds.bottomRight,
            bounds.bottomLeft,
          ];
    final drag = rotationDrag;
    if (drag != null) {
      final a = drag.degrees * pi / 180;
      points = drag.frame.map((point) {
        final v = point - drag.pivot;
        return drag.pivot +
            Offset(
              v.dx * cos(a) - v.dy * sin(a),
              v.dx * sin(a) + v.dy * cos(a),
            );
      }).toList();
    }
    final midpoint = (points[0] + points[1]) / 2,
        normal = (points[0] + points[1]) / 2 - pivot;
    final top =
        midpoint +
        (normal.distance < .000001
                ? const Offset(0, -1)
                : normal / normal.distance) *
            (28 / scale);
    yield Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          key: const ValueKey('rotation-frame'),
          painter: _RotationFramePainter(
            points.map((v) => v * scale).toList(),
            top * scale,
          ),
        ),
      ),
    );
    for (var n = 0; n < 5; n++) {
      final point = n == 4 ? top : points[n];
      yield Positioned(
        left: point.dx * scale - 12,
        top: point.dy * scale - 12,
        key: ValueKey('rotation-handle-$n'),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Tooltip(
            message: 'Pivoter la sélection — glisser ; Maj : pas de 15°',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onPanStart: (d) {
                checkpoint();
                final pointer = planPointer(d.globalPosition, scale) - pivot;
                rotationDrag = _PlanRotationDrag(
                  [
                    for (final item in items)
                      {
                        for (final k in ['id', 'x', 'y', 'w', 'h', 'angle'])
                          k: item[k],
                      },
                  ],
                  pivot,
                  List.of(points),
                  atan2(pointer.dy, pointer.dx),
                );
              },
              onPanUpdate: (d) {
                final drag = rotationDrag;
                if (drag == null || planReadOnly) return;
                final pointer =
                    planPointer(d.globalPosition, scale) - drag.pivot;
                var degrees =
                    (atan2(pointer.dy, pointer.dx) - drag.bearing) * 180 / pi;
                degrees = HardwareKeyboard.instance.isShiftPressed
                    ? (degrees / 15).round() * 15.0
                    : degrees.roundToDouble();
                refreshMixed(() {
                  if (rotatePlanFromOrigins(
                    p!,
                    drag.origins,
                    Point(drag.pivot.dx, drag.pivot.dy),
                    degrees,
                  )) {
                    drag.degrees = degrees;
                  }
                });
              },
              onPanEnd: (_) => finishPlanRotation(),
              onPanCancel: finishPlanRotation,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xff1565c0), width: 2),
                ),
                child: const Icon(
                  Icons.rotate_right,
                  size: 16,
                  color: Color(0xff1565c0),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }
}

class _RotationFramePainter extends CustomPainter {
  final List<Offset> points;
  final Offset top;
  _RotationFramePainter(this.points, this.top);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xff1565c0),
    );
    canvas.drawLine(
      (points[0] + points[1]) / 2,
      top,
      Paint()
        ..color = const Color(0xff1565c0)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _RotationFramePainter old) => true;
}
