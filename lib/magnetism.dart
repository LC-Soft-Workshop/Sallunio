import 'dart:math';

import 'domain.dart';

class SnapGuide {
  final Point<double> start, end;
  const SnapGuide(this.start, this.end);
}

class MagneticSnap {
  final double dx, dy;
  final String? label;
  final List<SnapGuide> guides;
  const MagneticSnap({
    this.dx = 0,
    this.dy = 0,
    this.label,
    this.guides = const [],
  });
  bool get active => label != null;
}

class _Proposal {
  final MagneticSnap snap;
  final int priority;
  const _Proposal(this.snap, this.priority);
  double get distance => sqrt(snap.dx * snap.dx + snap.dy * snap.dy);
}

/// Proposes one rigid translation. Never modifies the project or a fixed object.
MagneticSnap magneticSnap(Json p, Set<String> ids, {double threshold = .14}) {
  final moving = rows(p, 'items').where((i) => ids.contains(i['id'])).toList();
  if (moving.isEmpty || moving.any((i) => i['fixed'] == true)) {
    return const MagneticSnap();
  }
  final stationary = rows(
    p,
    'items',
  ).where((i) => !ids.contains(i['id'])).toList();
  final proposals = <_Proposal>[];
  void propose(
    double dx,
    double dy,
    String label,
    List<SnapGuide> guides, {
    int priority = 2,
  }) {
    if (!dx.isFinite ||
        !dy.isFinite ||
        sqrt(dx * dx + dy * dy) > threshold + .000001) {
      return;
    }
    proposals.add(
      _Proposal(
        MagneticSnap(dx: dx, dy: dy, label: label, guides: guides),
        priority,
      ),
    );
  }

  for (final a in moving) {
    final ax = number(a['x']),
        ay = number(a['y']),
        aw = number(a['w']),
        ah = number(a['h']);
    for (final b in stationary) {
      final name = '${b['label'] ?? ''}'.trim();
      final title = name.isEmpty ? objectLabels[b['kind']] ?? 'Table' : name;
      final bx = number(b['x']),
          by = number(b['y']),
          bw = number(b['w']),
          bh = number(b['h']);
      final pair = a['kind'] == 'table' && b['kind'] == 'table';
      for (final junction in pair ? [true, false] : [true]) {
        for (final side in ['left', 'right', 'top', 'bottom']) {
          final opposite = {
            'left': 'right',
            'right': 'left',
            'top': 'bottom',
            'bottom': 'top',
          }[side]!;
          final gap = pair
              ? (junction
                    ? tableJoinDistance(p, b, side, a, opposite)
                    : eventTableGap(p))
              : 0.0;
          final horizontal = side == 'left' || side == 'right';
          final normal = switch (side) {
            'left' => bx - aw - gap - ax,
            'right' => bx + bw + gap - ax,
            'top' => by - ah - gap - ay,
            _ => by + bh + gap - ay,
          };
          if (normal.abs() > threshold) continue;
          final aligned = horizontal
              ? by + (bh - ah) / 2 - ay
              : bx + (bw - aw) / 2 - ax;
          final tangents = pair && junction
              ? [aligned]
              : [
                  0.0,
                  aligned,
                  horizontal ? by - ay : bx - ax,
                  horizontal ? by + bh - ay - ah : bx + bw - ax - aw,
                ];
          for (final tangent in tangents) {
            final dx = horizontal ? normal : tangent,
                dy = horizontal ? tangent : normal;
            if (sqrt(dx * dx + dy * dy) > threshold + .000001) continue;
            final candidate = {...a, 'x': ax + dx, 'y': ay + dy};
            if (pair && junction && joinedEdges(p, candidate, b) == null) {
              continue;
            }
            final overlap = horizontal
                ? min(ay + dy + ah, by + bh) - max(ay + dy, by)
                : min(ax + dx + aw, bx + bw) - max(ax + dx, bx);
            if (overlap <= .000001) continue;
            final line = horizontal
                ? SnapGuide(
                    Point(side == 'left' ? bx : bx + bw, min(ay + dy, by)),
                    Point(
                      side == 'left' ? bx : bx + bw,
                      max(ay + dy + ah, by + bh),
                    ),
                  )
                : SnapGuide(
                    Point(min(ax + dx, bx), side == 'top' ? by : by + bh),
                    Point(
                      max(ax + dx + aw, bx + bw),
                      side == 'top' ? by : by + bh,
                    ),
                  );
            propose(
              dx,
              dy,
              junction ? 'Accroche : $title' : 'Passage : $title',
              [line],
              priority: pair && junction
                  ? 0
                  : tangent == aligned && tangent != 0
                  ? 1
                  : 2,
            );
          }
        }
      }
    }
  }

  final room = p['room'],
      width = number(room['width']),
      height = number(room['height']);
  final geometry = PlanGeometry(p, rows(p, 'items'));
  double clearance(Json item, String edge) {
    if (item['kind'] != 'table' || item['capacity'] == 0) return 0;
    if (item['shape'] != 'cercle' && wallSides(p).contains(edge)) return 0;
    final e = geometry.bounds(item);
    final seat = switch (edge) {
      'left' => number(item['x']) - number(e['x']),
      'top' => number(item['y']) - number(e['y']),
      'right' =>
        number(e['x']) + number(e['w']) - number(item['x']) - number(item['w']),
      _ =>
        number(e['y']) + number(e['h']) - number(item['y']) - number(item['h']),
    };
    return p['comfort'] == null
        ? max(eventTableGap(p) / 2, seat)
        : max(
            eventWallGap(p),
            seat == 0
                ? 0
                : seat +
                      (p['arrangementMode'] == 'Parcours'
                          ? 0
                          : eventCirculation(p)),
          );
  }

  final polygon = roomPolygon(room);
  if (polygon.isEmpty) {
    final left = moving
        .map((i) => clearance(i, 'left') - number(i['x']))
        .reduce(max);
    final right = moving
        .map(
          (i) =>
              width - clearance(i, 'right') - number(i['x']) - number(i['w']),
        )
        .reduce(min);
    final top = moving
        .map((i) => clearance(i, 'top') - number(i['y']))
        .reduce(max);
    final bottom = moving
        .map(
          (i) =>
              height - clearance(i, 'bottom') - number(i['y']) - number(i['h']),
        )
        .reduce(min);
    final xs = [
      (left, 'Mur gauche', SnapGuide(Point(0, 0), Point(0, height))),
      (right, 'Mur droit', SnapGuide(Point(width, 0), Point(width, height))),
    ];
    final ys = [
      (top, 'Mur haut', SnapGuide(Point(0, 0), Point(width, 0))),
      (bottom, 'Mur bas', SnapGuide(Point(0, height), Point(width, height))),
    ];
    for (final x in xs) {
      propose(x.$1, 0, 'Accroche : ${x.$2}', [x.$3]);
    }
    for (final y in ys) {
      propose(0, y.$1, 'Accroche : ${y.$2}', [y.$3]);
    }
    for (final x in xs) {
      for (final y in ys) {
        propose(x.$1, y.$1, 'Accroche : ${x.$2} / ${y.$2}', [
          x.$3,
          y.$3,
        ], priority: 1);
      }
    }
  } else {
    var area = 0.0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i], b = polygon[(i + 1) % polygon.length];
      area += a.x * b.y - b.x * a.y;
    }
    for (var edge = 0; edge < polygon.length; edge++) {
      final a = polygon[edge], b = polygon[(edge + 1) % polygon.length];
      final vx = b.x - a.x, vy = b.y - a.y, length = a.distanceTo(b);
      if (length < .000001) continue;
      final nx = -vy / length * (area >= 0 ? 1 : -1),
          ny = vx / length * (area >= 0 ? 1 : -1);
      var distance = double.infinity, projection = 0.0;
      for (final item in moving) {
        final x = number(item['x']) - clearance(item, 'left'),
            y = number(item['y']) - clearance(item, 'top');
        final r =
            number(item['x']) + number(item['w']) + clearance(item, 'right');
        final bottom =
            number(item['y']) + number(item['h']) + clearance(item, 'bottom');
        for (final point in [
          Point(x, y),
          Point(r, y),
          Point(r, bottom),
          Point(x, bottom),
        ]) {
          final d = (point.x - a.x) * nx + (point.y - a.y) * ny;
          if (d < distance) {
            distance = d;
            projection = ((point.x - a.x) * vx + (point.y - a.y) * vy) / length;
          }
        }
      }
      if (projection >= 0 && projection <= length) {
        propose(-distance * nx, -distance * ny, 'Accroche : paroi', [
          SnapGuide(a, b),
        ]);
      }
    }
  }

  proposals.sort((a, b) {
    final priority = a.priority.compareTo(b.priority);
    return priority == 0 ? a.distance.compareTo(b.distance) : priority;
  });
  for (final proposal in proposals) {
    final shifted = moving
        .map(
          (item) => {
            ...item,
            'x': number(item['x']) + proposal.snap.dx,
            'y': number(item['y']) + proposal.snap.dy,
          },
        )
        .toList();
    final combined = [...stationary, ...shifted];
    final geo = PlanGeometry(p, combined);
    var valid = true;
    for (final item in shifted) {
      if (item['kind'] == 'table') {
        if (!fits(p, item, combined, geometry: geo)) {
          valid = false;
          break;
        }
      } else {
        if (number(item['x']) < -.000001 ||
            number(item['y']) < -.000001 ||
            number(item['x']) + number(item['w']) > width + .000001 ||
            number(item['y']) + number(item['h']) > height + .000001 ||
            !polygonFits(item, room) ||
            combined.any(
              (other) =>
                  other['id'] != item['id'] &&
                  !(other['kind'] == 'zone' && item['kind'] == 'zone') &&
                  overlaps(item, other),
            )) {
          valid = false;
          break;
        }
      }
    }
    if (valid) return proposal.snap;
  }
  return const MagneticSnap();
}
