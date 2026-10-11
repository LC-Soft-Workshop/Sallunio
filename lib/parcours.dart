import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'domain.dart';

const parcoursCirculations = ['Fermé', 'Ouvert'];
bool parcoursClosed(Json p) {
  final settings = p['parcoursSettings'] as Map? ?? {};
  if (settings['circulation'] != null) {
    return settings['circulation'] == 'Fermé';
  }
  final accesses = rows(
    p,
    'items',
  ).where((i) => i['kind'] == 'entry' || i['kind'] == 'exit').toList();
  return settings['imposedLoop'] == true &&
      accesses.length == 1 &&
      accesses.single['kind'] == 'entry';
}

const parcoursClosures = ['À l’extérieur', 'Entre les rangées'];
const parcoursOrientations = ['Automatique', 'Horizontale', 'Verticale'];
const parcoursWallLayouts = ['Automatique', 'Alterné', 'Même mur (en peigne)'];
const parcoursZoneAccess = ['À exclure', 'À desservir'];
bool parcoursZoneTraversable(Json zone) =>
    zone['kind'] == 'zone' &&
    zone['parcoursPassage'] == 'Oui' &&
    zone['parcoursAccess'] != 'À desservir';
bool parcoursAvailable(Json p) =>
    ['Personnalisé', 'Marché de Noël', 'Brocante'].contains(eventActivity(p));
bool parcoursActive(Json p) =>
    parcoursAvailable(p) && p['arrangementMode'] == 'Parcours';

double _largestJoinGap(Json p) => tables(
  p,
).fold<double>(0, (v, t) => max(v, number(tableJoinSettings(p, t)['joinGap'])));

Json _rowOrientation(Json t, {bool upright = false}) {
  final q = clone(t),
      long = max(number(t['w']), number(t['h'])),
      short = min(number(t['w']), number(t['h']));
  final swapped = upright
      ? number(t['w']) > number(t['h'])
      : number(t['w']) < number(t['h']);
  q['rotation'] =
      ((t['rotation'] as int? ?? (number(t['w']) < number(t['h']) ? 90 : 0)) +
          (swapped ? 90 : 0)) %
      360;
  q['w'] = upright ? short : long;
  q['h'] = upright ? long : short;
  return q;
}

double _rowJoinGap(Json p, Json a, Json b, {bool upright = false}) =>
    tableJoinDistance(
      p,
      _rowOrientation(a, upright: upright),
      upright ? 'bottom' : 'right',
      _rowOrientation(b, upright: upright),
      upright ? 'top' : 'left',
    );

double _pairJoinGap(Json p, (Json, Json) a, (Json, Json) b) =>
    max(_rowJoinGap(p, a.$1, b.$1), _rowJoinGap(p, a.$2, b.$2));

double _pairSpan(Json p, List<(Json, Json)> pairs) {
  var span = 0.0;
  for (var i = 0; i < pairs.length; i++) {
    span += max(number(pairs[i].$1['w']), number(pairs[i].$1['h']));
    if (i > 0) span += _pairJoinGap(p, pairs[i - 1], pairs[i]);
  }
  return span;
}

String parcoursSignature(Json p) => jsonEncode([
  p['room'],
  p['aisle'],
  if (p['comfort'] != null) p['comfort'],
  if (p['comfort'] != null) eventHasPmr(p),
  p['wallSupport'],
  p['activity'],
  p['parcoursSettings'],
  p['joinGap'],
  p['joinGapSides'],
  for (final t in rows(p, 'types')) [t['id'], t['joinGap'], t['joinGapSides']],
  for (final i in rows(p, 'items'))
    [
      i['id'],
      i['kind'],
      i['x'],
      i['y'],
      i['w'],
      i['h'],
      i['fixed'],
      i['capacity'],
      i['seatSide'],
      i['joinGap'],
      i['joinGapSides'],
      i['parcoursBlock'],
      i['parcoursAccess'],
      i['parcoursPassage'],
    ],
]);
bool parcoursCurrent(Json p) =>
    parcoursActive(p) &&
    validParcoursPlan(p['parcoursPlan']) &&
    p['parcoursPlan']['signature'] == parcoursSignature(p);

bool validParcoursPlan(dynamic plan) {
  if (plan is! Map ||
      plan['signature'] is! String ||
      plan['paths'] is! List ||
      plan['blocks'] is! List ||
      plan['warnings'] is! List ||
      !(plan['warnings'] as List).every((v) => v is String)) {
    return false;
  }
  for (final path in plan['paths']) {
    if (path is! List ||
        path.length > 10000 ||
        !path.every(
          (v) =>
              v is List &&
              v.length == 2 &&
              v.every((n) => n is num && n.isFinite),
        )) {
      return false;
    }
  }
  for (final block in plan['blocks']) {
    if (block is! Map ||
        ![
          'x',
          'y',
          'w',
          'h',
        ].every((key) => block[key] is num && (block[key] as num).isFinite)) {
      return false;
    }
  }
  if (plan['services'] != null) {
    if (plan['services'] is! List ||
        !(plan['services'] as List).every(
          (service) =>
              service is Map &&
              service['id'] is String &&
              service['point'] is List &&
              service['point'].length == 2 &&
              (service['point'] as List).every((v) => v is num && v.isFinite),
        )) {
      return false;
    }
  }
  return true;
}

List<String> parcoursWarnings(Json p) {
  if (!parcoursActive(p) || p['parcoursPlan'] == null) return [];
  if (!parcoursCurrent(p)) {
    return [
      'Parcours : plan modifié, relancer Disposer tables pour vérifier les accès.',
    ];
  }
  final warnings = (p['parcoursPlan']['warnings'] as List)
      .cast<String>()
      .toList();
  if (!warnings.any((w) => w.contains('hors du passage visiteurs'))) {
    final missing = parcoursUnservedTables(p);
    if (missing.isNotEmpty) warnings.add(_coverageMessage(missing));
  }
  return warnings;
}

List<List<Point<double>>> parcoursPaths(Json p, {bool allowStale = false}) =>
    !(allowStale
        ? parcoursActive(p) && validParcoursPlan(p['parcoursPlan'])
        : parcoursCurrent(p))
    ? []
    : [
        for (final path in p['parcoursPlan']['paths'] as List)
          [
            for (final point in path as List)
              Point(number(point[0]), number(point[1])),
          ],
      ];

List<List<Point<double>>> parcoursArrows(Json p) => [
  for (final route in parcoursPaths(p))
    for (var i = 1; i < route.length; i++)
      if (route[i].distanceTo(route[i - 1]) >= eventCirculation(p))
        ...(() {
          final a = route[i - 1], b = route[i], distance = a.distanceTo(b);
          final dx = (b.x - a.x) / distance, dy = (b.y - a.y) / distance;
          final center = Point((a.x + b.x) / 2, (a.y + b.y) / 2),
              size = min(.20, distance / 5);
          return [
            [
              Point(
                center.x - dx * size - dy * size / 2,
                center.y - dy * size + dx * size / 2,
              ),
              center,
              Point(
                center.x - dx * size + dy * size / 2,
                center.y - dy * size - dx * size / 2,
              ),
            ],
          ];
        })(),
];

/// Only the private back-to-back strip and actual end contacts waive the public aisle.
/// Physical overlap is still tested separately by fits and preparation checks.
bool parcoursInternalContact(Json p, Json a, Json b) {
  if (parcoursActive(p) &&
      a['parcoursMaze'] == true &&
      b['parcoursMaze'] == true &&
      (['spine', 'wall'].contains(a['parcoursRole']) ||
          ['spine', 'wall'].contains(b['parcoursRole']))) {
    final gx =
        max(number(a['x']), number(b['x'])) -
        min(number(a['x']) + number(a['w']), number(b['x']) + number(b['w']));
    final gy =
        max(number(a['y']), number(b['y'])) -
        min(number(a['y']) + number(a['h']), number(b['y']) + number(b['h']));
    if (['spine', 'wall'].contains(a['parcoursRole']) &&
        ['spine', 'wall'].contains(b['parcoursRole'])) {
      return (gx >= -.00001 &&
              gx <= _largestJoinGap(p) + .00001 &&
              gy < .00001) ||
          (gy >= -.00001 && gy <= _largestJoinGap(p) + .00001 && gx < .00001);
    }
    final spine = ['spine', 'wall'].contains(a['parcoursRole']) ? a : b;
    return spine['parcoursAxis'] == 'Verticale'
        ? gy >= -.00001 && gy <= _largestJoinGap(p) + .00001
        : gx >= -.00001 && gx <= _largestJoinGap(p) + .00001;
  }
  if (!parcoursActive(p) ||
      a['parcoursBlock'] == null ||
      a['parcoursBlock'] != b['parcoursBlock']) {
    return false;
  }
  final vertical = a['parcoursAxis'] == 'Verticale';
  double x(Json t) => number(t[vertical ? 'y' : 'x']);
  double y(Json t) => number(t[vertical ? 'x' : 'y']);
  double w(Json t) => number(t[vertical ? 'h' : 'w']);
  double h(Json t) => number(t[vertical ? 'w' : 'h']);
  bool near(double v) => v.abs() < .00001;
  final ar = a['parcoursRole'], br = b['parcoursRole'];
  final gx = max(x(a), x(b)) - min(x(a) + w(a), x(b) + w(b));
  final gy = max(y(a), y(b)) - min(y(a) + h(a), y(b) + h(b));
  if (ar == br && (ar == 'upper' || ar == 'lower')) {
    return gx >= -.00001 &&
        gx <= _largestJoinGap(p) + .00001 &&
        gy <= .00001 &&
        (ar == 'upper' ? near(y(a) - y(b)) : near(y(a) + h(a) - y(b) - h(b)));
  }
  if ((ar == 'upper' && br == 'lower') || (ar == 'lower' && br == 'upper')) {
    return gx < -.00001 && gy >= number(a['parcoursGap']) - .00001;
  }
  if (ar == 'cap' || br == 'cap') {
    return (gx >= -.00001 &&
            gx <= _largestJoinGap(p) + .00001 &&
            gy <= .00001) ||
        (near(gy) && gx < -.00001);
  }
  return false;
}

void clearParcoursLayout(Json p) {
  for (final t in tables(p)) {
    final saved = t.remove('parcoursOriginal');
    if (saved is Map && t['fixed'] != true && t['capacity'] != 0) {
      for (final key in ['w', 'h', 'rotation', 'sides', 'seatSide']) {
        if (saved.containsKey(key)) {
          t[key] = saved[key];
        } else {
          t.remove(key);
        }
      }
    }
    for (final key in [
      'parcoursMaze',
      'parcoursBlock',
      'parcoursRole',
      'parcoursGap',
      'parcoursAxis',
      'parcoursUnplacedReason',
    ]) {
      t.remove(key);
    }
  }
  p.remove('parcoursPlan');
}

Json _transpose(Json p) {
  final q = clone(p), room = q['room'];
  final polygon = roomPolygon(room);
  final width = room['width'];
  room['width'] = room['height'];
  room['height'] = width;
  if (polygon.isNotEmpty) {
    room['polygon'] = polygon.map((v) => '${v.y},${v.x}').join(';');
  }
  for (final i in rows(q, 'items')) {
    final x = i['x'], w = i['w'];
    i['x'] = i['y'];
    i['y'] = x;
    i['w'] = i['h'];
    i['h'] = w;
    if (i['seatSide'] != null) i['seatSide'] = _transposeSide(i['seatSide']);
  }
  q['wallSupport'] = switch (q['wallSupport']) {
    'Mur gauche' => 'Mur haut',
    'Mur droit' => 'Mur bas',
    'Mur haut' => 'Mur gauche',
    'Mur bas' => 'Mur droit',
    'Gauche + droit' => 'Haut + bas',
    'Haut + bas' => 'Gauche + droit',
    _ => q['wallSupport'],
  };
  return q;
}

String _transposeSide(String side) =>
    const {
      'Haut': 'Gauche',
      'Bas': 'Droite',
      'Gauche': 'Haut',
      'Droite': 'Bas',
    }[side] ??
    side;

class _Layout {
  _Layout(this.project, this.blocks, this.vertical);
  final Json project;
  final List<Json> blocks;
  final bool vertical;
  int get count =>
      tables(project).where((t) => t['parcoursBlock'] != null).length;
}

Json _reflectProject(Json source, bool vertical) {
  final p = clone(source),
      extent = number(p['room'][vertical ? 'height' : 'width']);
  for (final item in rows(p, 'items')) {
    final coordinate = vertical ? 'y' : 'x', size = vertical ? 'h' : 'w';
    item[coordinate] = extent - number(item[coordinate]) - number(item[size]);
    if (number(item[coordinate]).abs() < .00001) item[coordinate] = 0.0;
    if (item['seatSide'] != null) {
      item['seatSide'] = switch (item['seatSide']) {
        'Gauche' when !vertical => 'Droite',
        'Droite' when !vertical => 'Gauche',
        'Haut' when vertical => 'Bas',
        'Bas' when vertical => 'Haut',
        _ => item['seatSide'],
      };
    }
  }
  final polygon = roomPolygon(p['room']);
  if (polygon.isNotEmpty) {
    p['room']['polygon'] = polygon
        .map(
          (v) => vertical ? '${v.x},${extent - v.y}' : '${extent - v.x},${v.y}',
        )
        .join(';');
  }
  p['wallSupport'] = switch (p['wallSupport']) {
    'Mur gauche' when !vertical => 'Mur droit',
    'Mur droit' when !vertical => 'Mur gauche',
    'Mur haut' when vertical => 'Mur bas',
    'Mur bas' when vertical => 'Mur haut',
    _ => p['wallSupport'],
  };
  return p;
}

_Layout _reflectLayout(_Layout layout) {
  final p = _reflectProject(layout.project, layout.vertical);
  final extent = number(p['room'][layout.vertical ? 'height' : 'width']);
  final coordinate = layout.vertical ? 'y' : 'x',
      size = layout.vertical ? 'h' : 'w';
  return _Layout(p, [
    for (final b in layout.blocks)
      {...b, coordinate: extent - number(b[coordinate]) - number(b[size])},
  ], layout.vertical);
}

List<(Json, Json)> _packPairs(
  Json p,
  List<Json> candidates,
  double available,
  double gap,
  int limit,
) {
  final groups = <String, List<Json>>{};
  for (final t in candidates) {
    final oriented = _rowOrientation(t);
    final key =
        '${max(number(t['w']), number(t['h'])).toStringAsFixed(6)}:${min(number(t['w']), number(t['h'])).toStringAsFixed(6)}:'
        '${tableJoinEdgeGap(p, oriented, 'left')}:${tableJoinEdgeGap(p, oriented, 'right')}';
    groups.putIfAbsent(key, () => []).add(t);
  }
  final options = <(Json, Json)>[];
  for (final bucket in groups.values) {
    bucket.sort(
      (a, b) =>
          seatEnvelope(comfortTable(p, a))
              .compareTo(seatEnvelope(comfortTable(p, b))),
    );
    for (var i = 0; i + 1 < bucket.length; i += 2) {
      if (seatEnvelope(comfortTable(p, bucket[i])) +
              seatEnvelope(comfortTable(p, bucket[i + 1])) <=
          gap + .000001) {
        options.add((bucket[i], bucket[i + 1]));
      }
    }
  }
  var states = <String, (double, List<(Json, Json)>)>{'0:0': (0, [])};
  for (final option in options) {
    final length = max(number(option.$1['w']), number(option.$1['h']));
    final next = {...states};
    for (final state in states.values) {
      final span =
              state.$1 +
              length +
              (state.$2.isEmpty ? 0 : _pairJoinGap(p, state.$2.last, option)),
          count = state.$2.length + 1;
      if (span <= available + .000001 && count <= limit) {
        next.putIfAbsent(
          '$count:${span.toStringAsFixed(6)}',
          () => (span, [...state.$2, option]),
        );
      }
    }
    if (next.length > 2000) {
      final retained = next.entries.toList()
        ..sort((a, b) {
          final count = b.value.$2.length.compareTo(a.value.$2.length);
          return count != 0 ? count : a.value.$1.compareTo(b.value.$1);
        });
      states = {
        for (final entry in retained.take(2000)) entry.key: entry.value,
      };
    } else {
      states = next;
    }
  }
  final ranked = states.values.toList()
    ..sort((a, b) {
      final count = b.$2.length.compareTo(a.$2.length);
      return count != 0 ? count : b.$1.compareTo(a.$1);
    });
  return ranked.first.$2;
}

_Layout _build(
  Json source,
  bool vertical,
  int pairLimit,
  int wallPattern, {
  bool maze = false,
  bool accessHead = false,
  int? tableLimit,
}) {
  if (maze) {
    final sides = wallSides(vertical ? _transpose(source) : source);
    if (!sides.contains('right') && sides.contains('left')) {
      return _reflectLayout(
        _build(
          _reflectProject(source, vertical),
          vertical,
          pairLimit,
          wallPattern,
          maze: true,
        ),
      );
    }
  }
  final p = vertical ? _transpose(source) : clone(source);
  final settings = p['parcoursSettings'] as Map? ?? {};
  final gap = eventExhibitorGap(p);
  final outside = settings['closure'] != 'Entre les rangées';
  final aisle = eventCirculation(p);
  final singleEntrance = rows(
    p,
    'items',
  ).where((i) => i['kind'] == 'entry' || i['kind'] == 'exit').toList();
  final loop =
      singleEntrance.length == 1 && singleEntrance.single['kind'] == 'entry';
  final width = number(p['room']['width']),
      height = number(p['room']['height']);
  final movable = tables(p)
      .where((t) => t['fixed'] != true && t['capacity'] != 0)
      .toList();
  final pool = movable
      .where((t) => t['shape'] != 'cercle')
      .take(tableLimit ?? movable.length)
      .toList();
  for (final t in movable) {
    t['unplacedByArrangement'] = true;
  }
  if (pool.isEmpty) return _Layout(p, [], vertical);
  final depth = pool
      .map((t) => min(number(t['w']), number(t['h'])))
      .reduce(max);
  final strip = depth * 2 + gap;
  final joinReserve = _largestJoinGap(p);
  final obstacles = rows(p, 'items')
      .where(
        (i) => i['kind'] != 'table' || i['fixed'] == true || i['capacity'] == 0,
      )
      .toList();
  final destinations = obstacles
      .where((i) => i['kind'] == 'zone' && i['parcoursAccess'] == 'À desservir')
      .toList();
  obstacles.addAll([
    for (final zone in destinations)
      {
        ...zone,
        'id': 'parcours-buffer-${zone['id']}',
        'parcoursBuffer': true,
        'x': number(zone['x']) - aisle,
        'y': number(zone['y']) - aisle,
        'w': number(zone['w']) + 2 * aisle,
        'h': number(zone['h']) + 2 * aisle,
      },
  ]);
  final placed = <Json>[...obstacles], blocks = <Json>[];
  final walls = wallSides(p);
  double spineEnd = height - aisle, spineEdge = 0, rightEdge = width;
  final vendorDepth = pool
      .map(
        (t) => adaptedPlaces(comfortTable(p, t)).fold<double>(
          seatEnvelope(comfortTable(p, t)),
          (value, place) => max(value, number(place['depth'])),
        ),
      )
      .reduce(max);
  final wallSeatGap = max(
    eventWallGap(p),
    max(vendorDepth, max(gap / 2, aisle / 2)),
  );
  var spineX = maze && walls.contains('left')
      ? depth + wallSeatGap + aisle
      : aisle;
  // The entrance can be resized into the return passage. Keep the connecting
  // row beyond its footprint instead of abandoning the imposed layout.
  if (maze) {
    for (final access in singleEntrance) {
      if (number(access['x']) <= aisle) {
        spineX = max(spineX, number(access['x']) + number(access['w']) + aisle);
      }
    }
    // The outer return must also pass perimeter zones and obstacles. Keeping
    // only the entrance clear can leave a narrow choke point behind the spine.
    for (final obstacle in obstacles) {
      if (parcoursZoneTraversable(obstacle) ||
          obstacle['parcoursBuffer'] == true) {
        continue;
      }
      if (number(obstacle['x']) <= aisle) {
        spineX = max(
          spineX,
          number(obstacle['x']) + number(obstacle['w']) + aisle,
        );
      }
    }
  }
  bool placeSingle(
    Json t,
    double x,
    double y,
    String role,
    String side,
    String id,
  ) {
    final long = max(number(t['w']), number(t['h'])),
        short = min(number(t['w']), number(t['h']));
    final q = clone(t)
      ..addAll({
        'x': x,
        'y': y,
        'w': short,
        'h': long,
        'sides': 'Un côté',
        'seatSide': side,
        'parcoursBlock': id,
        'parcoursRole': role,
        'parcoursAxis': 'Horizontale',
        'parcoursMaze': true,
      });
    q.remove('unplacedByArrangement');
    if (role == 'wall' &&
        rows(p, 'items')
            .where((i) => ['entry', 'exit', 'door'].contains(i['kind']))
            .any((i) => overlaps(q, i, aisle))) {
      return false;
    }
    if (!fits(p, q, [...placed, q])) return false;
    t
      ..clear()
      ..addAll(q);
    pool.remove(t);
    placed.add(t);
    if (role == 'wall') {
      blocks.add({
        'id': id,
        'role': 'wall',
        'x': 0.0,
        'y': y,
        'w': x + short,
        'h': long,
      });
    }
    return true;
  }

  if (maze) {
    if (!walls.contains('right')) return _Layout(p, [], vertical);
    final spineStart = singleEntrance
        .where((a) => number(a['y']) <= aisle)
        .fold<double>(
          aisle,
          (v, a) => max(
            v,
            number(a['y']) + number(a['h']) > aisle
                ? number(a['y']) + number(a['h']) + aisle
                : aisle,
          ),
        );
    var y = spineStart;
    final available = [...pool]
      ..sort(
        (a, b) => max(
          number(b['w']),
          number(b['h']),
        ).compareTo(max(number(a['w']), number(a['h']))),
      );
    Json? previous;
    for (final t in available) {
      final long = max(number(t['w']), number(t['h'])),
          short = min(number(t['w']), number(t['h']));
      final seam = previous == null
          ? 0.0
          : _rowJoinGap(p, previous, t, upright: true);
      if (y + seam + long > spineEnd + .00001 || pool.length < 4) continue;
      final q = clone(t)
        ..addAll({
          'x': spineX + depth - short,
          'y': y + seam,
          'w': short,
          'h': long,
          'sides': 'Un côté',
          'seatSide': 'Droite',
          'parcoursBlock': 'parcours-spine',
          'parcoursRole': 'spine',
          'parcoursAxis': 'Horizontale',
          'parcoursMaze': true,
        });
      q.remove('unplacedByArrangement');
      final all = [...placed, q];
      if (!fits(p, q, all)) break;
      t
        ..clear()
        ..addAll(q);
      pool.remove(t);
      placed.add(t);
      y += seam + long;
      previous = t;
    }
    if (y - spineStart < strip) return _Layout(p, [], vertical);
    spineEnd = y;
    spineEdge = spineX + depth;
    blocks.add({
      'id': 'parcours-spine',
      'role': 'spine',
      'x': spineX,
      'y': spineStart,
      'w': depth,
      'h': y - spineStart,
      'returnAxis': spineX - aisle / 2,
      'rightAxis': rightEdge - aisle / 2,
    });
  }
  var band = 0;
  final bandStart = maze
      ? number(blocks.firstWhere((b) => b['role'] == 'spine')['y'])
      : aisle;
  final ys =
      <double>{
            for (
              var y = bandStart;
              y + strip <= (maze ? spineEnd : height - aisle) + .000001;
              y += strip + aisle
            )
              y,
            if (!maze)
              for (final obstacle in obstacles) ...[
                number(obstacle['y']) +
                    number(obstacle['h']) +
                    (parcoursZoneTraversable(obstacle) ||
                            obstacle['parcoursBuffer'] == true
                        ? 0
                        : aisle),
                number(obstacle['y']) -
                    strip -
                    (parcoursZoneTraversable(obstacle) ||
                            obstacle['parcoursBuffer'] == true
                        ? 0
                        : aisle),
              ],
          }
          .where(
            (y) =>
                y >= aisle - .000001 &&
                y + strip <= (maze ? spineEnd : height - aisle) + .000001,
          )
          .toList()
        ..sort();
  for (final y in ys) {
    if (pool.length < 3) break;
    final beforeBlocks = blocks.length;
    var intervals = <(double, double)>[(0.0, width)];
    for (final obstacle in [
      ...obstacles,
      if (maze)
        ...placed.where((t) => ['spine', 'wall'].contains(t['parcoursRole'])),
    ]) {
      if (number(obstacle['y']) >= y + strip ||
          number(obstacle['y']) + number(obstacle['h']) <= y) {
        continue;
      }
      const reserve = 0.0;
      final lo = number(obstacle['x']) - reserve,
          hi = number(obstacle['x']) + number(obstacle['w']) + reserve;
      final next = <(double, double)>[];
      for (final segment in intervals) {
        if (hi <= segment.$1 || lo >= segment.$2) {
          next.add(segment);
          continue;
        }
        if (lo > segment.$1) next.add((segment.$1, min(segment.$2, lo)));
        if (hi < segment.$2) next.add((max(segment.$1, hi), segment.$2));
      }
      intervals = next;
    }
    for (final interval in intervals) {
      final splitPublic =
          intervals.length > 1 && obstacles.any(parcoursZoneTraversable);
      final headAccess = accessHead && band < 2
          ? singleEntrance
                .where((i) => i['kind'] == 'entry' && number(i['y']) <= y)
                .firstOrNull
          : null;
      final reserveHead =
          headAccess != null && number(headAccess['x']) > aisle * 2;
      final attachLeft =
          !reserveHead &&
          (maze
              ? band.isEven && (interval.$1 - spineEdge).abs() < .00001
              : !loop &&
                    wallPattern & 1 != 0 &&
                    (wallPattern == 1 || band.isEven || splitPublic) &&
                    interval.$1 == 0 &&
                    walls.contains('left'));
      final attachRight = maze
          ? band.isOdd && (interval.$2 - rightEdge).abs() < .00001
          : !loop &&
                wallPattern & 2 != 0 &&
                (wallPattern == 2 || band.isOdd || splitPublic) &&
                interval.$2 == width &&
                walls.contains('right');
      if (maze && !(attachLeft || attachRight)) continue;
      final capsNeeded = attachLeft || attachRight ? 1 : 2;
      if (pool.length < capsNeeded + 2) continue;
      final compatibleCaps = pool.where((t) {
        final length = max(number(t['w']), number(t['h']));
        return outside
            ? length >= gap - .000001 && length <= strip + .000001
            : (length - gap).abs() < .00001;
      }).toList();
      String sizeKey(Json t) =>
          '${max(number(t['w']), number(t['h'])).toStringAsFixed(6)}:${min(number(t['w']), number(t['h'])).toStringAsFixed(6)}';
      final caps = <Json>[];
      for (var ci = 0; ci < capsNeeded && compatibleCaps.isNotEmpty; ci++) {
        final counts = <String, int>{};
        for (final t in pool.where((t) => !caps.contains(t))) {
          counts.update(sizeKey(t), (n) => n + 1, ifAbsent: () => 1);
        }
        compatibleCaps.sort((a, b) {
          final parity = ((counts[sizeKey(b)] ?? 0) % 2).compareTo(
            (counts[sizeKey(a)] ?? 0) % 2,
          );
          if (parity != 0) return parity;
          final depth = min(
            number(a['w']),
            number(a['h']),
          ).compareTo(min(number(b['w']), number(b['h'])));
          return depth != 0
              ? depth
              : a['id'].toString().compareTo(b['id'].toString());
        });
        caps.add(compatibleCaps.removeAt(0));
      }
      if (caps.length != capsNeeded) continue;
      var capWidth = caps
          .map((t) => min(number(t['w']), number(t['h'])))
          .reduce(max);
      bool publicEdge(double edge, bool left) => obstacles.any(
        (zone) =>
            (parcoursZoneTraversable(zone) || zone['parcoursBuffer'] == true) &&
            ((left
                            ? number(zone['x']) + number(zone['w'])
                            : number(zone['x'])) -
                        edge)
                    .abs() <
                .00001 &&
            number(zone['y']) < y + strip &&
            number(zone['y']) + number(zone['h']) > y,
      );
      var lo =
          interval.$1 +
          (attachLeft
              ? (maze ? joinReserve : 0)
              : (publicEdge(interval.$1, true) ? 0 : aisle * (loop ? 2 : 1)) +
                    (outside ? capWidth + joinReserve : 0));
      var hi =
          interval.$2 -
          (attachRight
              ? 0
              : (publicEdge(interval.$2, false) ? 0 : aisle) +
                    (outside ? capWidth + joinReserve : 0));
      if (reserveHead) {
        lo = max(lo, number(headAccess['x']) + aisle + capWidth + joinReserve);
      }
      final candidates = pool.where((t) => !caps.contains(t)).toList();
      candidates.sort(
        (a, b) => max(
          number(b['w']),
          number(b['h']),
        ).compareTo(max(number(a['w']), number(a['h']))),
      );
      final pairs = _packPairs(p, candidates, hi - lo, gap, pairLimit);
      if (pairs.isEmpty) continue;
      double pairDepth((Json, Json) pair) =>
          min(number(pair.$1['w']), number(pair.$1['h']));
      pairs.sort((a, b) => pairDepth(b).compareTo(pairDepth(a)));
      if (attachLeft) {
        pairs.add(pairs.removeAt(0));
      } else if (!attachRight && pairs.length > 1) {
        pairs.add(pairs.removeAt(1));
      }
      while (pairs.isNotEmpty && _pairSpan(p, pairs) > hi - lo + .00001) {
        pairs.removeLast();
      }
      if (pairs.isEmpty) continue;
      final span = _pairSpan(p, pairs);
      final paired = {
        for (final pair in pairs) pair.$1,
        for (final pair in pairs) pair.$2,
      };
      bool fitCap((Json, Json) pair, int index) {
        final required = strip - 2 * pairDepth(pair);
        bool suitable(Json cap) {
          final length = max(number(cap['w']), number(cap['h']));
          return outside
              ? length >= required - .00001 && length <= strip + .00001
              : (length - required).abs() < .00001;
        }

        if (suitable(caps[index])) return true;
        final replacement = pool
            .where(
              (t) => !paired.contains(t) && !caps.contains(t) && suitable(t),
            )
            .firstOrNull;
        if (replacement == null) return false;
        caps[index] = replacement;
        return true;
      }

      var capIndex = 0;
      if (!attachLeft && !fitCap(pairs.first, capIndex++)) continue;
      if (!attachRight && !fitCap(pairs.last, capIndex)) continue;
      final actualCapWidth = caps
          .map((t) => min(number(t['w']), number(t['h'])))
          .reduce(max);
      final additional = max(0.0, actualCapWidth - capWidth);
      if (outside) {
        if (!attachLeft) lo += additional;
        if (!attachRight) hi -= additional;
      }
      if (span > hi - lo + .00001) continue;
      capWidth = actualCapWidth;
      final block = 'parcours-${blocks.length + 1}';
      var x = attachRight
          ? hi - span
          : attachLeft
          ? lo
          : (lo + hi - span) / 2;
      final start = x, end = x + span;
      final proposal = <Json>[];
      Json oriented(
        Json t,
        String role,
        double tx,
        double ty,
        bool across,
        String side,
      ) {
        final q = _rowOrientation(t, upright: !across),
            length = max(number(t['w']), number(t['h'])),
            short = min(number(t['w']), number(t['h']));
        q.addAll({
          'x': tx,
          'y': ty,
          'w': across ? length : short,
          'h': across ? short : length,
          'sides': 'Un côté',
          'seatSide': side,
          'parcoursBlock': block,
          'parcoursRole': role,
          'parcoursGap': gap,
          'parcoursAxis': 'Horizontale',
          if (maze) 'parcoursMaze': true,
        });
        q.remove('unplacedByArrangement');
        return q;
      }

      for (var pi = 0; pi < pairs.length; pi++) {
        final pair = pairs[pi];
        if (pi > 0) x += _pairJoinGap(p, pairs[pi - 1], pair);
        final short = min(number(pair.$1['w']), number(pair.$1['h']));
        proposal.add(oriented(pair.$1, 'upper', x, y, true, 'Bas'));
        proposal.add(
          oriented(pair.$2, 'lower', x, y + strip - short, true, 'Haut'),
        );
        x += max(number(pair.$1['w']), number(pair.$1['h']));
      }
      var ci = 0;
      for (final left in [true, false]) {
        if (left ? attachLeft : attachRight) continue;
        final cap = caps[ci++],
            long = max(number(cap['w']), number(cap['h'])),
            short = min(number(cap['w']), number(cap['h']));
        final capQ = _rowOrientation(cap, upright: true);
        final endPair = left ? pairs.first : pairs.last;
        final capGap = max(
          tableJoinDistance(
            p,
            capQ,
            left ? 'right' : 'left',
            _rowOrientation(endPair.$1),
            left ? 'left' : 'right',
          ),
          tableJoinDistance(
            p,
            capQ,
            left ? 'right' : 'left',
            _rowOrientation(endPair.$2),
            left ? 'left' : 'right',
          ),
        );
        final tx = outside
            ? (left ? start - short - capGap : end + capGap)
            : (left ? start : end - short);
        proposal.add(
          oriented(
            cap,
            'cap',
            tx,
            y + depth + (gap - long) / 2,
            false,
            left ? 'Droite' : 'Gauche',
          ),
        );
      }
      final combined = [...placed, ...proposal],
          geo = PlanGeometry(p, combined);
      if (proposal.any((t) => !fits(p, t, combined, geometry: geo))) continue;
      for (final q in proposal) {
        final original = pool.firstWhere((t) => t['id'] == q['id']);
        original.clear();
        original.addAll(q);
        pool.remove(original);
        placed.add(original);
      }
      final blockLeft = attachLeft
          ? interval.$1
          : proposal.map((t) => number(t['x'])).reduce(min);
      final blockRight = attachRight
          ? interval.$2
          : proposal.map((t) => number(t['x']) + number(t['w'])).reduce(max);
      blocks.add({
        'id': block,
        if (reserveHead) 'accessHead': true,
        'x': blockLeft,
        'y': y,
        'w': blockRight - blockLeft,
        'h': strip,
      });
    }
    if (blocks.length > beforeBlocks) band++;
  }
  if (maze && walls.contains('left')) {
    var y = aisle;
    Json? previous;
    for (final t in [...pool]) {
      final long = max(number(t['w']), number(t['h']));
      final seam = previous == null
          ? 0.0
          : _rowJoinGap(p, previous, t, upright: true);
      if (y + seam + long > height - aisle + .00001) continue;
      final short = min(number(t['w']), number(t['h']));
      final added = placeSingle(
        t,
        wallSeatGap + depth - short,
        y + seam,
        'wall',
        'Gauche',
        'parcours-wall-left',
      );
      y += seam + long;
      if (added) previous = t;
    }
  }
  if (vertical) {
    final q = _transpose(p);
    // The transpose is geometric; it does not alter physical model dimensions.
    for (final t in tables(q)) {
      if (t['parcoursBlock'] != null) t['parcoursAxis'] = 'Verticale';
    }
    return _Layout(q, [
      for (final b in blocks)
        {...b, 'x': b['y'], 'y': b['x'], 'w': b['h'], 'h': b['w']},
    ], true);
  }
  return _Layout(p, blocks, false);
}

class _PublicGrid {
  _PublicGrid(this.p, this.blocks) {
    final aisle = eventCirculation(p);
    radius = aisle / 2;
    step = min(.25, aisle / 4);
    blockers = rows(p, 'items')
        .where(
          (i) =>
              !['entry', 'exit', 'door'].contains(i['kind']) &&
              !parcoursZoneTraversable(i) &&
              i['parcoursBlock'] == null &&
              i['unplacedByArrangement'] != true,
        )
        .toList();
    blockers.addAll(blocks);
    List<double> coordinates(double length, String pos, String extent) {
      final values =
          <double>{
                radius,
                length - radius,
                for (var v = radius; v <= length - radius; v += step)
                  double.parse(v.toStringAsFixed(8)),
                for (final b in blockers) ...[
                  number(b[pos]) - radius,
                  number(b[pos]) + number(b[extent]) + radius,
                  if (b['role'] == 'spine' &&
                      pos == (number(b['w']) > number(b['h']) ? 'y' : 'x')) ...[
                    number(b['returnAxis'], radius),
                    number(b['rightAxis'], length - radius),
                  ],
                ],
              }
              .where(
                (v) =>
                    v >= radius - .0000001 && v <= length - radius + .0000001,
              )
              .toList()
            ..sort();
      final distinct = <double>[];
      for (final value in values) {
        if (value.isFinite &&
            (distinct.isEmpty || (value - distinct.last).abs() > 1e-8)) {
          distinct.add(value);
        }
      }
      return distinct;
    }

    xs = coordinates(number(p['room']['width']), 'x', 'w');
    ys = coordinates(number(p['room']['height']), 'y', 'h');
    nx = xs.length;
    ny = ys.length;
    for (var iy = 0; iy < ny; iy++) {
      for (var ix = 0; ix < nx; ix++) {
        final v = point(iy * nx + ix),
            box = {
              'x': v.x - radius,
              'y': v.y - radius,
              'w': radius * 2,
              'h': radius * 2,
            };
        if (v.x < radius - .000001 ||
            v.y < radius - .000001 ||
            v.x + radius > number(p['room']['width']) + .000001 ||
            v.y + radius > number(p['room']['height']) + .000001) {
          continue;
        }
        if (!clear(box)) continue;
        free.add(iy * nx + ix);
      }
    }
  }
  final Json p;
  final List<Json> blocks;
  late final double radius, step;
  late final int nx, ny;
  late final List<double> xs, ys;
  late final List<Json> blockers;
  final edgeCache = <String, bool>{};
  final free = <int>{};
  Point<double> point(int id) => Point(xs[id % nx], ys[id ~/ nx]);
  bool clear(Json box) =>
      polygonFits(box, p['room']) && !blockers.any((b) => overlaps(box, b));
  bool edgeClear(int a, int b) {
    final key = '${min(a, b)}-${max(a, b)}';
    return edgeCache.putIfAbsent(key, () {
      final u = point(a), v = point(b);
      return clear({
        'x': min(u.x, v.x) - radius,
        'y': min(u.y, v.y) - radius,
        'w': (u.x - v.x).abs() + 2 * radius,
        'h': (u.y - v.y).abs() + 2 * radius,
      });
    });
  }

  int? nearest(Point<double> target, {double? limit, Set<int>? candidates}) {
    int? best;
    var distance = limit ?? double.infinity;
    for (final id in candidates ?? free) {
      final d = point(id).distanceTo(target);
      if (d < distance) {
        best = id;
        distance = d;
      }
    }
    return best;
  }

  List<int>? path(int from, int to, {Set<int> forbidden = const {}}) {
    final previous = <int, int>{from: from}, queue = Queue<int>()..add(from);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (current == to) break;
      for (final next in [
        if (current % nx > 0) current - 1,
        if (current % nx < nx - 1) current + 1,
        if (current >= nx) current - nx,
        if (current < nx * (ny - 1)) current + nx,
      ]) {
        if (free.contains(next) &&
            !forbidden.contains(next) &&
            !previous.containsKey(next) &&
            edgeClear(current, next)) {
          previous[next] = current;
          queue.add(next);
        }
      }
    }
    if (!previous.containsKey(to)) return null;
    final result = <int>[to];
    while (result.last != from) {
      result.add(previous[result.last]!);
    }
    return result.reversed.toList();
  }

  Set<int> reachable(int start) {
    final result = <int>{start}, queue = Queue<int>()..add(start);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final next in [
        if (current % nx > 0) current - 1,
        if (current % nx < nx - 1) current + 1,
        if (current >= nx) current - nx,
        if (current < nx * (ny - 1)) current + nx,
      ]) {
        if (free.contains(next) &&
            !result.contains(next) &&
            edgeClear(current, next)) {
          result.add(next);
          queue.add(next);
        }
      }
    }
    return result;
  }

  List<int>? connect(
    Set<int> from,
    Set<int> targets, {
    Set<int> forbidden = const {},
  }) {
    final previous = {for (final id in from) id: id},
        queue = Queue<int>()..addAll(from);
    int? found;
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (targets.contains(current)) {
        found = current;
        break;
      }
      for (final next in [
        if (current % nx > 0) current - 1,
        if (current % nx < nx - 1) current + 1,
        if (current >= nx) current - nx,
        if (current < nx * (ny - 1)) current + nx,
      ]) {
        if (free.contains(next) &&
            !forbidden.contains(next) &&
            !previous.containsKey(next) &&
            edgeClear(current, next)) {
          previous[next] = current;
          queue.add(next);
        }
      }
    }
    if (found == null) return null;
    final result = <int>[found];
    while (previous[result.last] != result.last) {
      result.add(previous[result.last]!);
    }
    return result.reversed.toList();
  }

  Set<int> zoneFront(Json zone) {
    final x = number(zone['x']),
        y = number(zone['y']),
        w = number(zone['w']),
        h = number(zone['h']);
    return free.where((id) {
      final v = point(id);
      return (v.x >= x - .00001 &&
              v.x <= x + w + .00001 &&
              ((v.y - y + radius).abs() < .00001 ||
                  (v.y - y - h - radius).abs() < .00001)) ||
          (v.y >= y - .00001 &&
              v.y <= y + h + .00001 &&
              ((v.x - x + radius).abs() < .00001 ||
                  (v.x - x - w - radius).abs() < .00001));
    }).toSet();
  }

  List<List<double>> simplify(List<int> path) {
    final result = <List<double>>[];
    for (var i = 0; i < path.length; i++) {
      if (i > 0 &&
          i < path.length - 1 &&
          path[i] - path[i - 1] == path[i + 1] - path[i]) {
        continue;
      }
      final v = point(path[i]);
      result.add([v.x, v.y]);
    }
    return result;
  }
}

List<Point<double>> _customerFront(Json table, double offset) {
  final x = number(table['x']),
      y = number(table['y']),
      w = number(table['w']),
      h = number(table['h']);
  final side = table['seatSide'] ?? (w >= h ? 'Bas' : 'Droite');
  return [
    for (final fraction in [.25, .5, .75])
      switch (side) {
        'Haut' => Point(x + w * fraction, y + h + offset),
        'Bas' => Point(x + w * fraction, y - offset),
        'Gauche' => Point(x + w + offset, y + h * fraction),
        _ => Point(x - offset, y + h * fraction),
      },
  ];
}

int? _frontCell(_PublicGrid grid, Point<double> target) =>
    grid.nearest(target, limit: grid.step + .05 + .00001);
int? _servedCell(_PublicGrid grid, int cell, Iterable<int> walk) {
  final point = grid.point(cell), limit = number(grid.p['aisle']) + grid.step;
  for (final id in walk) {
    if (grid.point(id).distanceTo(point) <= limit + .00001 &&
        grid.edgeClear(cell, id)) {
      return id;
    }
  }
  return null;
}

List<Json> _unservedFronts(_PublicGrid grid, List<int> walk) =>
    tables(grid.p)
        .where(
          (t) =>
              t['capacity'] != 0 &&
              t['unplacedByArrangement'] != true &&
              t['parcoursBlock'] != null &&
              _customerFront(t, grid.radius).any((point) {
                final cell = _frontCell(grid, point);
                return cell == null || _servedCell(grid, cell, walk) == null;
              }),
        )
        .toList();

int? _spliceVisit(
  _PublicGrid grid,
  List<int> walk,
  Set<int> stops,
  Set<int> mandatory, {
  Set<String> keepTables = const {},
  bool protectStop = true,
}) {
  final existing = walk.where(stops.contains).firstOrNull;
  if (existing != null) {
    if (protectStop) mandatory.add(existing);
    return existing;
  }
  final route = walk.toSet(), out = grid.connect(walk.toSet(), stops);
  if (out == null) return null;
  final departure = grid.point(out.first);
  final targets = route
      .where(
        (id) =>
            grid.point(id).distanceTo(departure) >=
            number(grid.p['aisle']) - .00001,
      )
      .toSet();
  for (var attempt = 0; attempt < 12 && targets.isNotEmpty; attempt++) {
    final back = grid.connect(
      {out.last},
      targets,
      forbidden: {...out.take(out.length - 1), ...route.difference(targets)},
    );
    if (back == null) break;
    final ai = walk.indexOf(out.first),
        bi = walk.indexOf(back.last),
        lo = min(ai, bi),
        hi = max(ai, bi);
    if (walk.sublist(lo + 1, hi).any(mandatory.contains)) {
      targets.remove(back.last);
      continue;
    }
    final bridge = [...out, ...back.skip(1)], before = [...walk];
    walk.replaceRange(lo, hi + 1, ai == lo ? bridge : bridge.reversed);
    if (_unservedFronts(grid, walk).any((t) => keepTables.contains(t['id']))) {
      walk
        ..clear()
        ..addAll(before);
      targets.remove(back.last);
      continue;
    }
    if (protectStop) mandatory.add(out.last);
    return out.last;
  }
  return null;
}

void _serveTableFronts(_PublicGrid grid, List<int> walk, Set<int> mandatory) {
  final missing = _unservedFronts(grid, walk).map((t) => t['id']).toSet();
  final kept = tables(grid.p)
      .where((t) => !missing.contains(t['id']))
      .map((t) => t['id'] as String)
      .toSet();
  final targets = <int>[];
  for (final table in tables(grid.p).where(
    (t) =>
        t['capacity'] != 0 &&
        t['unplacedByArrangement'] != true &&
        t['parcoursBlock'] != null,
  )) {
    for (final point in _customerFront(table, grid.radius)) {
      final cell = _frontCell(grid, point);
      if (cell != null && _servedCell(grid, cell, walk) == null) {
        targets.add(cell);
      }
    }
  }
  for (final cell in targets) {
    if (_servedCell(grid, cell, walk) == null) {
      _spliceVisit(
        grid,
        walk,
        {cell},
        mandatory,
        keepTables: kept,
        protectStop: false,
      );
      final stillMissing = _unservedFronts(
        grid,
        walk,
      ).map((t) => t['id']).toSet();
      kept.addAll(
        tables(grid.p)
            .where((t) => !stillMissing.contains(t['id']))
            .map((t) => t['id'] as String),
      );
    }
  }
}

void _addCoverageWarning(
  _PublicGrid grid,
  List<int> walk,
  List<String> warnings,
) {
  final missing = _unservedFronts(grid, walk);
  if (missing.isNotEmpty) warnings.add(_coverageMessage(missing));
}

String _coverageMessage(List<Json> missing) =>
    'Parcours : ${missing.length} table(s) hors du passage visiteurs (${missing.take(6).map((t) => t['label']).join(', ')}). Revoir le passage de retour ou la disposition.';

final _frontCoverageCache = <String, List<String>>{};

/// Checks the actual customer-facing frontage, including tables before the entry.
List<Json> parcoursUnservedTables(Json p) {
  if (!parcoursCurrent(p) || parcoursPaths(p).isEmpty) return [];
  final key =
      '${p['parcoursPlan']['signature']}|${jsonEncode(p['parcoursPlan']['paths'])}|${jsonEncode(p['parcoursPlan']['blocks'])}';
  final cached = _frontCoverageCache[key];
  if (cached != null) {
    return tables(p).where((t) => cached.contains(t['id'])).toList();
  }
  final grid = _PublicGrid(
    p,
    (p['parcoursPlan']['blocks'] as List).cast<Json>(),
  );
  final walk = <int>[];
  for (final route in parcoursPaths(p)) {
    for (var i = 1; i < route.length; i++) {
      final a = route[i - 1], b = route[i];
      for (final id in grid.free) {
        final v = grid.point(id);
        if (v.x >= min(a.x, b.x) - 1e-7 &&
            v.x <= max(a.x, b.x) + 1e-7 &&
            v.y >= min(a.y, b.y) - 1e-7 &&
            v.y <= max(a.y, b.y) + 1e-7) {
          walk.add(id);
        }
      }
    }
  }
  final missing = _unservedFronts(grid, walk);
  if (_frontCoverageCache.length >= 16) _frontCoverageCache.clear();
  _frontCoverageCache[key] = missing.map((t) => t['id'] as String).toList();
  return missing;
}

// A closed visitor route is a simple cycle: no repeated cells except its end.
// Stops replace an arc with two distinct connections, never an out-and-back spur.
Json _closedRoutes(
  _Layout layout,
  _PublicGrid grid,
  Map<String, int> gates,
  List<String> initialWarnings,
) {
  final p = layout.project,
      warnings = [...initialWarnings],
      services = <Json>[];
  Json failure() => {
    'paths': <List<List<double>>>[],
    'services': <Json>[],
    'warnings': [
      ...warnings,
      'Parcours : impossible de former une boucle continue sans cul-de-sac. Libérer un passage de retour, déplacer les obstacles ou réduire le mobilier.',
    ],
    'length': double.infinity,
  };
  if (layout.blocks.isEmpty || gates.isEmpty) return failure();
  final horizontal = !layout.vertical, half = eventCirculation(p) / 2;
  final spine = layout.blocks.where((b) => b['role'] == 'spine').firstOrNull;
  final blocks =
      layout.blocks
          .where((b) => !['spine', 'wall'].contains(b['role']))
          .toList()
        ..sort(
          (a, b) =>
              number(a[horizontal ? 'y' : 'x'])
                  .compareTo(number(b[horizontal ? 'y' : 'x'])),
        );
  double along(Json b) => number(b[horizontal ? 'x' : 'y']);
  double across(Json b) => number(b[horizontal ? 'y' : 'x']);
  double length(Json b) => number(b[horizontal ? 'w' : 'h']);
  double depth(Json b) => number(b[horizontal ? 'h' : 'w']);
  if (blocks.isEmpty) return failure();
  Point<double> point(double a, double b) =>
      horizontal ? Point(a, b) : Point(b, a);
  final lo = spine == null
      ? blocks.map(along).reduce(min) - half
      : along(spine) + length(spine) + half;
  final hi = spine == null
      ? blocks.map((b) => along(b) + length(b)).reduce(max) + half
      : number(
          spine['rightAxis'],
          number(p['room'][horizontal ? 'width' : 'height']) - half,
        );
  final bands = <(double, double)>[];
  for (final b in blocks) {
    if (bands.isEmpty || (bands.last.$1 - across(b)).abs() > .00001) {
      bands.add((across(b), across(b) + depth(b)));
    }
  }
  final lanes = [
    bands.first.$1 - half,
    for (var i = 1; i < bands.length; i++) (bands[i - 1].$2 + bands[i].$1) / 2,
    max(bands.last.$2, spine == null ? 0.0 : across(spine) + depth(spine)) +
        half,
  ];
  final targets = <Point<double>>[];
  for (var i = 0; i < lanes.length; i++) {
    targets.add(point(i.isEven ? lo : hi, lanes[i]));
    targets.add(point(i.isEven ? hi : lo, lanes[i]));
  }
  // Keep the return outside the serpentine, in a separate reserved passage.
  final returnAxis = spine == null ? half : number(spine['returnAxis'], half);
  targets.add(point(returnAxis, lanes.last));
  targets.add(point(returnAxis, lanes.first));
  final first = grid.nearest(targets.first, limit: grid.step);
  if (first == null) return failure();
  final walk = <int>[first];
  for (final target in targets.skip(1)) {
    final cell = grid.nearest(target);
    if (cell == null) return failure();
    if (cell == walk.last) continue;
    final segment = grid.path(
      walk.last,
      cell,
      forbidden: walk.take(walk.length - 1).toSet(),
    );
    if (segment == null) return failure();
    walk.addAll(segment.skip(1));
  }
  final finish = grid.path(
    walk.last,
    first,
    forbidden: walk.skip(1).take(walk.length - 2).toSet(),
  );
  if (finish == null) return failure();
  walk.addAll(finish.skip(1));
  // Integrate an access or service into the cycle, preserving its other stops.
  final mandatory = <int>{};
  int? include(Set<int> stops) {
    final existing = walk.where(stops.contains).firstOrNull;
    if (existing != null) {
      mandatory.add(existing);
      return existing;
    }
    final cycle = walk.take(walk.length - 1).toSet();
    final outbound = grid.connect(cycle, stops);
    if (outbound == null) return null;
    final departure = grid.point(outbound.first);
    final returnTargets = cycle
        .where(
          (cell) =>
              grid.point(cell).distanceTo(departure) >=
              eventCirculation(p) - .00001,
        )
        .toSet();
    final back = grid.connect(
      {outbound.last},
      returnTargets,
      forbidden: {
        ...outbound.take(outbound.length - 1),
        ...cycle.difference(returnTargets),
      },
    );
    if (back == null) return null;
    final a = walk.indexOf(outbound.first), b = walk.indexOf(back.last);
    final low = min(a, b), high = max(a, b);
    final direct = [...outbound, ...back.skip(1)];
    final bridge = a == low ? direct : direct.reversed.toList();
    final inside = walk.sublist(low + 1, high).toSet();
    if (inside.any(mandatory.contains)) return null;
    // Only replace a short arc, so an access cannot erase the room traversal.
    if (high - low > walk.length / 2) return null;
    walk.replaceRange(low, high + 1, bridge);
    mandatory.add(outbound.last);
    return outbound.last;
  }

  final entrance =
      rows(p, 'items').where((i) => i['kind'] == 'entry').firstOrNull ??
      rows(p, 'items').firstWhere((i) => i['kind'] == 'exit');
  final accessStops = grid.free.where((id) {
    final v = grid.point(id);
    return v.x >= number(entrance['x']) - half &&
        v.x <= number(entrance['x']) + number(entrance['w']) + half &&
        v.y >= number(entrance['y']) - half &&
        v.y <= number(entrance['y']) + number(entrance['h']) + half;
  }).toSet();
  // An entrance is an opening, not a mandatory point at its geometric centre.
  final gate = include(
    accessStops.isEmpty
        ? {gates[entrance['id']] ?? gates.values.first}
        : accessStops,
  );
  if (gate == null) return failure();
  for (final zone in rows(
    p,
    'items',
  ).where((i) => i['kind'] == 'zone' && i['parcoursAccess'] == 'À desservir')) {
    final stop = include(grid.zoneFront(zone));
    if (stop == null) {
      warnings.add(
        'Parcours : zone ${zone['label']} non desservie sans demi-tour. Revoir les passages autour de cette zone.',
      );
      continue;
    }
    final v = grid.point(stop);
    services.add({
      'id': zone['id'],
      'point': [v.x, v.y],
    });
  }
  _serveTableFronts(grid, walk, mandatory);
  _addCoverageWarning(grid, walk, warnings);
  final unique = walk.take(walk.length - 1).toSet();
  if (unique.length != walk.length - 1 || walk.first != walk.last) {
    return failure();
  }
  final open = walk.take(walk.length - 1).toList(), index = walk.indexOf(gate);
  final rotated = [...open.skip(index), ...open.take(index), gate];
  final paths = <List<List<double>>>[grid.simplify(rotated)];
  // Additional exits are terminal access links. They must never replace an
  // arc of the exhibitor loop or turn its connected maze into separate islands.
  for (final access in rows(p, 'items').where(
    (i) =>
        (i['kind'] == 'entry' || i['kind'] == 'exit') &&
        i['id'] != entrance['id'],
  )) {
    final target = gates[access['id']];
    final branch = target == null ? null : grid.connect(unique, {target});
    if (branch == null) {
      warnings.add('Parcours : accès ${access['label']} non raccordé.');
    } else if (branch.length > 1) {
      paths.add(grid.simplify(branch));
    }
  }
  return {
    'paths': paths,
    'services': services,
    'warnings': warnings,
    'length': walk.length * grid.step,
  };
}

bool _singleInteriorBarrier(_PublicGrid grid) {
  final pending = grid.blockers.toSet(),
      width = number(grid.p['room']['width']),
      height = number(grid.p['room']['height']);
  var islands = 0;
  final privateBlocks = grid.blocks.where((b) => b['role'] != 'wall').toSet();
  bool touches(Json a, Json b) =>
      number(a['x']) <= number(b['x']) + number(b['w']) + .00001 &&
      number(b['x']) <= number(a['x']) + number(a['w']) + .00001 &&
      number(a['y']) <= number(b['y']) + number(b['h']) + .00001 &&
      number(b['y']) <= number(a['y']) + number(a['h']) + .00001;
  while (pending.isNotEmpty) {
    final queue = Queue<Json>()..add(pending.first);
    pending.remove(queue.first);
    var wall = false, exhibitors = false;
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      exhibitors = exhibitors || privateBlocks.contains(current);
      wall =
          wall ||
          number(current['x']) < .00001 ||
          number(current['y']) < .00001 ||
          number(current['x']) + number(current['w']) >= width - .00001 ||
          number(current['y']) + number(current['h']) >= height - .00001;
      final linked = pending.where((b) => touches(current, b)).toList();
      pending.removeAll(linked);
      queue.addAll(linked);
    }
    if (!wall && exhibitors) islands++;
  }
  return islands == 1;
}

// In open circulation, opposite single rows are served by a connected set
// of public aisles. Their junctions are choices, not a forced visitor loop.
Json _openNetworkRoutes(
  _Layout layout,
  _PublicGrid grid,
  Map<String, int> gates,
  List<String> initialWarnings,
) {
  final p = layout.project, warnings = [...initialWarnings];
  final horizontal = !layout.vertical;
  final blocks = layout.blocks.where((b) => b['role'] != 'perimeter').toList()
    ..sort(
      (a, b) =>
          number(a[horizontal ? 'y' : 'x'])
              .compareTo(number(b[horizontal ? 'y' : 'x'])),
    );
  if (blocks.isEmpty || gates.isEmpty) {
    return {
      'paths': [],
      'warnings': [...warnings, 'Parcours ouvert : aucun passage accessible.'],
      'services': [],
      'length': double.infinity,
    };
  }
  double across(Json b) => number(b[horizontal ? 'y' : 'x']);
  double depth(Json b) => number(b[horizontal ? 'h' : 'w']);
  final half = grid.radius;
  final lo =
      blocks.map((b) => number(b[horizontal ? 'x' : 'y'])).reduce(min) - half;
  final hi =
      blocks
          .map(
            (b) =>
                number(b[horizontal ? 'x' : 'y']) +
                number(b[horizontal ? 'w' : 'h']),
          )
          .reduce(max) +
      half;
  final lanes = [
    across(blocks.first) - half,
    for (var i = 1; i < blocks.length; i++)
      (across(blocks[i - 1]) + depth(blocks[i - 1]) + across(blocks[i])) / 2,
    across(blocks.last) + depth(blocks.last) + half,
  ];
  Point<double> point(double along, double across) =>
      horizontal ? Point(along, across) : Point(across, along);
  final paths = <List<List<double>>>[], visited = <int>{};
  final reachable = grid.reachable(gates.values.first);
  void connect(Point<double> from, Point<double> to) {
    final a = grid.nearest(from, candidates: reachable);
    final b = grid.nearest(to, candidates: reachable);
    final walk = a == null || b == null ? null : grid.path(a, b);
    if (walk == null) {
      warnings.add('Parcours ouvert : une allée est isolée.');
    } else {
      visited.addAll(walk);
      if (walk.length > 1) paths.add(grid.simplify(walk));
    }
  }

  for (var i = 0; i < lanes.length; i++) {
    connect(
      point(i.isEven ? lo : hi, lanes[i]),
      point(i.isEven ? hi : lo, lanes[i]),
    );
  }
  connect(point(lo, lanes.first), point(lo, lanes.last));
  connect(point(hi, lanes.first), point(hi, lanes.last));
  for (final gate in gates.values) {
    final branch = grid.connect(visited, {gate});
    if (branch == null) {
      warnings.add('Parcours ouvert : un accès n’est pas raccordé.');
    } else {
      visited.addAll(branch);
      if (branch.length > 1) paths.add(grid.simplify(branch));
    }
  }
  final services = <Json>[];
  for (final zone in rows(
    p,
    'items',
  ).where((i) => i['kind'] == 'zone' && i['parcoursAccess'] == 'À desservir')) {
    final stops = grid.zoneFront(zone);
    final branch = grid.connect(visited, stops);
    if (branch == null) {
      warnings.add('Parcours ouvert : zone ${zone['label']} non desservie.');
    } else {
      visited.addAll(branch);
      if (branch.length > 1) paths.add(grid.simplify(branch));
      final v = grid.point(branch.last);
      services.add({
        'id': zone['id'],
        'point': [v.x, v.y],
      });
    }
  }
  _addCoverageWarning(grid, visited.toList(), warnings);
  return {
    'paths': paths,
    'warnings': warnings.toSet().toList(),
    'services': services,
    'length': visited.length * grid.step,
  };
}

Json _routes(_Layout layout) {
  final spine = layout.blocks.where((b) => b['role'] == 'spine').firstOrNull;
  final axis = layout.vertical ? 'y' : 'x',
      extent = number(
        layout.project['room'][layout.vertical ? 'height' : 'width'],
      );
  if (spine != null && number(spine[axis]) > extent / 2) {
    final result = _routes(_reflectLayout(layout)),
        index = layout.vertical ? 1 : 0;
    for (final path in result['paths'] as List) {
      for (final point in path as List) {
        point[index] = extent - number(point[index]);
      }
    }
    for (final service in result['services'] as List? ?? []) {
      service['point'][index] = extent - number(service['point'][index]);
    }
    return result;
  }
  final p = layout.project,
      grid = _PublicGrid(p, layout.blocks),
      warnings = <String>[];
  final accesses = rows(
    p,
    'items',
  ).where((i) => i['kind'] == 'entry' || i['kind'] == 'exit').toList();
  final gates = <String, int>{};
  for (final gate in accesses) {
    final center = Point(
      number(gate['x']) + number(gate['w']) / 2,
      number(gate['y']) + number(gate['h']) / 2,
    );
    final cell = grid.nearest(
      center,
      limit:
          max(number(gate['w']), number(gate['h'])) / 2 +
          eventCirculation(p) * 1.5,
    );
    if (cell == null) {
      warnings.add(
        'Parcours : accès ${gate['label']} non raccordé, espace insuffisant.',
      );
    } else {
      gates[gate['id']] = cell;
    }
  }
  if (accesses.isEmpty) {
    warnings.add(
      'Parcours : aucune entrée ou sortie définie. Ajouter les accès puis relancer la disposition.',
    );
  }
  final paths = <List<List<double>>>[];
  final services = <Json>[];
  final perimeterEdges = layout.blocks
      .where((b) => b['role'] == 'perimeter')
      .map((b) => b['edge'])
      .toSet();
  if (!parcoursClosed(p) &&
      (perimeterEdges.containsAll(['top', 'bottom']) ||
          perimeterEdges.containsAll(['left', 'right']))) {
    return _openNetworkRoutes(layout, grid, gates, warnings);
  }
  if (spine != null && parcoursClosed(p) ||
      accesses.length == 1 && accesses.single['kind'] == 'entry') {
    final route = _closedRoutes(layout, grid, gates, warnings);
    if (parcoursClosed(p) &&
        (!layout.blocks.any((b) => b['role'] == 'spine') ||
            !_singleInteriorBarrier(grid))) {
      (route['warnings'] as List).add(
        'Parcours : cette disposition ne peut pas imposer un chemin unique. Autoriser un appui au mur pour fermer les raccourcis, libérer la rangée de liaison ou réduire le mobilier.',
      );
    }
    return route;
  }
  if (layout.blocks.isEmpty) {
    warnings.add(
      'Parcours : impossible de former un îlot fermé avec le mobilier et les dimensions disponibles.',
    );
    return {'paths': paths, 'warnings': warnings, 'length': double.infinity};
  }
  final points = <Point<double>>[];
  final horizontal = !layout.vertical;
  final blocks = layout.blocks.where((b) => b['role'] != 'perimeter').toList()
    ..sort(
      (a, b) =>
          number(a[horizontal ? 'y' : 'x'])
              .compareTo(number(b[horizontal ? 'y' : 'x'])),
    );
  // Several islands split by an obstacle can occupy the same band. Traverse
  // their shared upper/lower aisle once rather than treating each as a new turn.
  if (blocks.every(
    (b) => (b['routeVertical'] as bool? ?? layout.vertical) == layout.vertical,
  )) {
    final grouped = <Json>[];
    for (final block in blocks) {
      final across = horizontal ? 'y' : 'x';
      final depth = horizontal ? 'h' : 'w';
      final along = horizontal ? 'x' : 'y';
      final length = horizontal ? 'w' : 'h';
      if (grouped.isNotEmpty &&
          (number(grouped.last[across]) - number(block[across])).abs() <
              .00001 &&
          (number(grouped.last[depth]) - number(block[depth])).abs() < .00001) {
        final start = min(number(grouped.last[along]), number(block[along]));
        final end = max(
          number(grouped.last[along]) + number(grouped.last[length]),
          number(block[along]) + number(block[length]),
        );
        grouped.last[along] = start;
        grouped.last[length] = end - start;
      } else {
        grouped.add({...block});
      }
    }
    blocks
      ..clear()
      ..addAll(grouped);
  }
  final half = eventCirculation(p) / 2;
  bool? previousForcedEnd;
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i],
        x = number(b['x']),
        y = number(b['y']),
        w = number(b['w']),
        h = number(b['h']);
    final blockHorizontal = !(b['routeVertical'] as bool? ?? layout.vertical);
    final along = blockHorizontal ? x : y;
    final end = along + (blockHorizontal ? w : h);
    final roomEnd = number(p['room'][blockHorizontal ? 'width' : 'height']);
    final atStart = along.abs() < .00001,
        atEnd = (end - roomEnd).abs() < .00001;
    final far = atStart
        ? true
        : atEnd
        ? false
        : i.isEven;
    if ((atStart || atEnd) && previousForcedEnd == far) {
      warnings.add(
        'Parcours : des rangées ferment une allée en cul-de-sac. Essayer un autre sens de disposition.',
      );
    }
    previousForcedEnd = atStart || atEnd ? far : null;
    final turn = far ? end + half : along - half;
    if (blockHorizontal) {
      final fromBottom =
          b['routeVertical'] != null &&
          blockHorizontal != horizontal &&
          points.isNotEmpty &&
          points.last.y > y + h / 2;
      points.add(Point(turn, fromBottom ? y + h + half : y - half));
      points.add(Point(turn, fromBottom ? y - half : y + h + half));
    } else {
      final fromRight =
          b['routeVertical'] != null &&
          blockHorizontal != horizontal &&
          points.isNotEmpty &&
          points.last.x > x + w / 2;
      points.add(Point(fromRight ? x + w + half : x - half, turn));
      points.add(Point(fromRight ? x - half : x + w + half, turn));
    }
  }
  // Centre a shared aisle between a main block and a supplementary wall row.
  // This serves both frontages without adding a succession of artificial U-turns.
  for (var i = 0; i < points.length; i++) {
    var point = points[i];
    for (final row in layout.blocks.where((b) => b['role'] == 'perimeter')) {
      final x = number(row['x']),
          y = number(row['y']),
          w = number(row['w']),
          h = number(row['h']);
      Point<double>? candidate;
      if (row['edge'] == 'bottom' &&
          point.x >= x - half &&
          point.x <= x + w + half &&
          y > point.y + half) {
        candidate = Point(point.x, (point.y - half + y) / 2);
      }
      if (row['edge'] == 'top' &&
          point.x >= x - half &&
          point.x <= x + w + half &&
          y + h < point.y - half) {
        candidate = Point(point.x, (point.y + half + y + h) / 2);
      }
      if (row['edge'] == 'right' &&
          point.y >= y - half &&
          point.y <= y + h + half &&
          x > point.x + half) {
        candidate = Point((point.x - half + x) / 2, point.y);
      }
      if (row['edge'] == 'left' &&
          point.y >= y - half &&
          point.y <= y + h + half &&
          x + w < point.x - half) {
        candidate = Point((point.x + half + x + w) / 2, point.y);
      }
      if (candidate == null) continue;
      final a = _frontCell(grid, point), b = _frontCell(grid, candidate);
      if (a != null && b != null && grid.edgeClear(a, b)) point = grid.point(b);
    }
    points[i] = point;
  }
  final entry = accesses
      .where((g) => g['kind'] == 'entry' && gates.containsKey(g['id']))
      .firstOrNull;
  final start = entry == null
      ? (gates.values.firstOrNull ?? grid.nearest(points.first))
      : gates[entry['id']];
  if (start == null) {
    return {
      'paths': paths,
      'warnings': [...warnings, 'Parcours : aucun passage praticable.'],
      'length': double.infinity,
    };
  }
  if (grid.point(start).distanceTo(points.last) <
      grid.point(start).distanceTo(points.first)) {
    final rev = points.reversed.toList();
    points
      ..clear()
      ..addAll(rev);
  }
  if (points.length >= 2) {
    final a = points[0], b = points[1], v = grid.point(start);
    final dx = b.x - a.x, dy = b.y - a.y;
    final norm = dx * dx + dy * dy;
    if (norm > .00001) {
      final t = ((v.x - a.x) * dx + (v.y - a.y) * dy) / norm;
      final projection = Point(a.x + t * dx, a.y + t * dy);
      if (t > 0 && t < 1 && projection.distanceTo(v) <= half + .00001) {
        points.removeAt(0);
      }
    }
  }
  if (horizontal && blocks.length > 1) {
    final b = blocks.first;
    final x = number(b['x']),
        y = number(b['y']),
        w = number(b['w']),
        h = number(b['h']);
    final origin = grid.point(start);
    if (x > half &&
        origin.x < x &&
        points.first.x > x + w / 2 &&
        points.first.y < y) {
      points.insertAll(0, [
        Point(origin.x, y + h / 2),
        Point(x - half, y + h / 2),
        Point(x - half, y - half),
      ]);
    }
  }
  // For a single island, visit the first cap and both complete public
  // faces before taking a separate perimeter return towards the exit.
  if (blocks.length == 1) {
    final b = blocks.single;
    final x = number(b['x']),
        y = number(b['y']),
        w = number(b['w']),
        h = number(b['h']);
    final horizontalBlock = !(b['routeVertical'] as bool? ?? layout.vertical);
    final origin = grid.point(start);
    if (horizontalBlock && x > half && origin.x < x) {
      points
        ..clear()
        ..addAll([
          Point(origin.x, y + h / 2),
          Point(x - half, y + h / 2),
          Point(x - half, y - half),
          Point(x + w + half, y - half),
          Point(x + w + half, y + h + half),
          Point(x - half, y + h + half),
          Point(x - half, number(p['room']['height']) - half),
        ]);
    } else if (!horizontalBlock && y > half && origin.y < y) {
      points
        ..clear()
        ..addAll([
          Point(x + w / 2, origin.y),
          Point(x + w / 2, y - half),
          Point(x - half, y - half),
          Point(x - half, y + h + half),
          Point(x + w + half, y + h + half),
          Point(x + w + half, y - half),
          Point(number(p['room']['width']) - half, y - half),
        ]);
    }
  }
  final walk = <int>[start];
  final reachable = grid.reachable(start);
  for (final target in points) {
    final cell = grid.nearest(target, candidates: reachable);
    if (cell == null) continue;
    if (walk.contains(cell)) continue;
    final segment = grid.path(
      walk.last,
      cell,
      forbidden: walk.take(walk.length - 1).toSet(),
    );
    if (segment == null) {
      warnings.add(
        'Parcours : une allée est isolée. Déplacer les obstacles ou réduire le mobilier.',
      );
      continue;
    }
    walk.addAll(segment.skip(1));
  }
  final exits = accesses
      .where((g) => g['kind'] == 'exit' && gates.containsKey(g['id']))
      .where(
        (g) => entry != null || gates[g['id']] != start || gates.length == 1,
      )
      .toList();
  final destination = exits.isEmpty
      ? start
      : gates[exits.reduce(
          (a, b) =>
              grid.point(walk.last).distanceTo(grid.point(gates[a['id']]!)) <
                  grid.point(walk.last).distanceTo(grid.point(gates[b['id']]!))
              ? a
              : b,
        )['id']]!;
  if (exits.isEmpty && accesses.length == 1) {
    // Prefer a perimeter return rather than retracing the entire S.
    for (final target in [
      Point(
        number(p['room']['width']) - half,
        number(p['room']['height']) - half,
      ),
      Point(number(p['room']['width']) - half, half),
    ]) {
      final cell = grid.nearest(target, candidates: reachable);
      if (cell == null) continue;
      final segment = grid.path(walk.last, cell);
      if (segment != null) walk.addAll(segment.skip(1));
    }
  }
  final finish = grid.path(
    walk.last,
    destination,
    forbidden: walk.take(walk.length - 1).toSet(),
  );
  if (finish == null) {
    warnings.add('Parcours : la sortie ne rejoint pas le parcours.');
  } else {
    walk.addAll(finish.skip(1));
  }
  final mandatory = <int>{walk.first, walk.last};
  _serveTableFronts(grid, walk, mandatory);
  final initiallyMissing = _unservedFronts(
    grid,
    walk,
  ).map((t) => t['id']).toSet();
  final servedTables = tables(p)
      .where((t) => !initiallyMissing.contains(t['id']))
      .map((t) => t['id'] as String)
      .toSet();
  for (final zone in rows(
    p,
    'items',
  ).where((i) => i['kind'] == 'zone' && i['parcoursAccess'] == 'À desservir')) {
    final stop = _spliceVisit(
      grid,
      walk,
      grid.zoneFront(zone),
      mandatory,
      keepTables: servedTables,
    );
    if (stop == null) {
      warnings.add(
        'Parcours : zone ${zone['label']} non desservie sans demi-tour. Revoir les passages autour de cette zone.',
      );
    } else {
      mandatory.add(stop);
      final v = grid.point(stop);
      services.add({
        'id': zone['id'],
        'point': [v.x, v.y],
      });
    }
  }
  _serveTableFronts(grid, walk, mandatory);
  final coverageWalk = [...walk];
  paths.add(grid.simplify(walk));
  for (final gate in accesses) {
    final cell = gates[gate['id']];
    if (cell == null) continue;
    final branch = grid.path(start, cell);
    if (branch == null) {
      warnings.add('Parcours : accès ${gate['label']} isolé.');
      continue;
    }
    // Trim shared portions; draw only the branch to the common visitor route.
    final common = walk.toSet();
    final first = branch.lastIndexWhere(common.contains);
    if (first < branch.length - 1) {
      coverageWalk.addAll(branch);
      paths.add(grid.simplify(branch.sublist(max(0, first))));
    }
  }
  _addCoverageWarning(grid, coverageWalk, warnings);
  if (parcoursClosed(p)) {
    // An attractive blue line does not close shortcuts. All public accesses
    // must force a visit to every frontage even on their shortest connection.
    var shortcut =
        accesses.where((i) => i['kind'] == 'entry').isEmpty ||
        accesses.where((i) => i['kind'] == 'exit').isEmpty;
    final entries = accesses.where((i) => i['kind'] == 'entry');
    final exits = accesses.where((i) => i['kind'] == 'exit');
    for (final entry in entries) {
      for (final exit in exits) {
        final a = gates[entry['id']], b = gates[exit['id']];
        final direct = a == null || b == null ? null : grid.path(a, b);
        if (direct == null || _unservedFronts(grid, direct).isNotEmpty) {
          shortcut = true;
          continue;
        }
        // Try to bypass each frontage, including by a longer alternative.
        for (final table in tables(p).where(
          (t) =>
              t['parcoursBlock'] != null &&
              t['capacity'] != 0 &&
              t['unplacedByArrangement'] != true,
        )) {
          for (final point in _customerFront(table, grid.radius)) {
            final cell = _frontCell(grid, point);
            if (cell == null) {
              shortcut = true;
              break;
            }
            final frontage = grid.free
                .where((id) => _servedCell(grid, cell, [id]) != null)
                .toSet();
            if (frontage.contains(a) || frontage.contains(b)) continue;
            if (grid.path(a!, b!, forbidden: frontage) != null) {
              shortcut = true;
              break;
            }
          }
          if (shortcut) break;
        }
      }
    }
    if (shortcut) {
      warnings.add(
        'Parcours fermé : des raccourcis permettent de manquer des exposants. Modifier les accès, autoriser les appuis nécessaires ou réduire le mobilier. Aucun parcours ouvert n’est substitué.',
      );
      paths.clear();
    }
  }
  return {
    'paths': paths,
    'warnings': warnings.toSet().toList(),
    'services': services,
    'length': walk.length * grid.step,
  };
}

List<_Layout> _complementaryLayouts(_Layout layout) {
  final originals = {for (final t in tables(layout.project)) t['id']: clone(t)};
  final remaining = originals.values
      .where(
        (t) =>
            t['unplacedByArrangement'] == true &&
            t['capacity'] != 0 &&
            t['fixed'] != true,
      )
      .length;
  if (remaining < 3) return [];
  final source = clone(layout.project);
  final protected = <String>{};
  for (final t in tables(source)) {
    if (t['unplacedByArrangement'] != true) {
      t['fixed'] = true;
      protected.add(t['id']);
    }
  }
  final helperIds = <String>{};
  for (var i = 0; i < layout.blocks.length; i++) {
    final b = layout.blocks[i], id = '_reserved-block-$i';
    helperIds.add(id);
    rows(source, 'items').add({
      ...b,
      'id': id,
      'kind': 'zone',
      'shape': 'rectangle',
      'label': '',
      'fixed': true,
    });
  }
  final candidates = <_Layout>[];
  for (final vertical in [!layout.vertical, layout.vertical]) {
    for (final pattern in [0, 3]) {
      for (var limit = 1; limit <= min(8, remaining ~/ 2); limit++) {
        final extra = _build(source, vertical, limit, pattern);
        for (final t in tables(extra.project)) {
          final old = originals[t['id']]!;
          t['fixed'] = old['fixed'];
          if (!protected.contains(t['id']) && t['parcoursBlock'] != null) {
            t['parcoursBlock'] = 'extra-${t['parcoursBlock']}';
          }
        }
        rows(
          extra.project,
          'items',
        ).removeWhere((i) => helperIds.contains(i['id']));
        final combined = _Layout(extra.project, [
          for (final b in layout.blocks)
            {...b, 'routeVertical': layout.vertical},
          for (final b in extra.blocks)
            {...b, 'id': 'extra-${b['id']}', 'routeVertical': vertical},
        ], layout.vertical);
        if (combined.count > layout.count) candidates.add(combined);
      }
    }
  }
  candidates.sort((a, b) => b.count.compareTo(a.count));
  return candidates.take(2).toList();
}

List<_Layout> _perimeterLayouts(
  _Layout layout, {
  List<String> edges = const ['right', 'bottom', 'left', 'top'],
}) {
  if (layout.blocks.isEmpty || parcoursClosed(layout.project)) return [];
  final results = <_Layout>[];
  for (final edge in edges) {
    final p = clone(layout.project);
    final pool =
        tables(p)
            .where(
              (t) =>
                  t['unplacedByArrangement'] == true &&
                  t['fixed'] != true &&
                  t['capacity'] != 0 &&
                  t['shape'] != 'cercle',
            )
            .toList()
          ..sort(
            (a, b) => max(
              number(b['w']),
              number(b['h']),
            ).compareTo(max(number(a['w']), number(a['h']))),
          );
    if (pool.isEmpty) continue;
    final vertical = edge == 'left' || edge == 'right';
    final depth = pool
        .map((t) => min(number(t['w']), number(t['h'])))
        .reduce(max);
    final margin = pool.fold<double>(
      max(
        eventWallGap(p),
        max(eventCirculation(p) / 2, eventExhibitorGap(p) / 2),
      ),
      (v, t) => max(
        v,
        adaptedPlaces(comfortTable(p, t)).fold<double>(
          seatEnvelope(comfortTable(p, t)),
          (v, place) => max(v, number(place['depth'])),
        ),
      ),
    );
    final width = number(p['room']['width']),
        height = number(p['room']['height']);
    final lastBandBottom = layout.blocks
        .where((b) => !['perimeter', 'wall'].contains(b['role']))
        .map((b) => number(b['y']) + number(b['h']))
        .fold<double>(0, max);
    final bottomFront = min(
      height - margin - depth,
      lastBandBottom + eventCirculation(p),
    );
    final limit = (vertical ? height : width) - eventCirculation(p) / 2;
    final placed = rows(
      p,
      'items',
    ).where((t) => t['unplacedByArrangement'] != true).toList();
    final blocks = <Json>[];
    var cursor = eventCirculation(p) / 2;
    Json? previous;
    for (final t in pool) {
      final q = _rowOrientation(t, upright: vertical),
          long = max(number(t['w']), number(t['h'])),
          short = min(number(t['w']), number(t['h']));
      final seam = previous == null
          ? 0.0
          : tableJoinDistance(
              p,
              previous,
              vertical ? 'bottom' : 'right',
              q,
              vertical ? 'top' : 'left',
            );
      final beforeSearch = cursor;
      var fitted = false;
      while (cursor + seam + long <= limit + .00001) {
        q.addAll({
          'x': vertical
              ? (edge == 'left'
                    ? margin + depth - short
                    : width - margin - depth)
              : cursor + seam,
          'y': vertical
              ? cursor + seam
              : (edge == 'top' ? margin + depth - short : bottomFront),
          'sides': 'Un côté',
          'seatSide': {
            'left': 'Gauche',
            'right': 'Droite',
            'top': 'Haut',
            'bottom': 'Bas',
          }[edge],
          'parcoursRole': 'wall',
          'parcoursMaze': true,
          'parcoursAxis': vertical ? 'Verticale' : 'Horizontale',
          'parcoursBlock': 'perimeter-$edge-${t['id']}',
        });
        q.remove('unplacedByArrangement');
        final blockedAccess = rows(p, 'items').any(
          (i) =>
              (['entry', 'exit', 'door'].contains(i['kind']) &&
                  overlaps(q, i, eventCirculation(p) / 2)) ||
              (i['kind'] == 'zone' &&
                  i['parcoursAccess'] == 'À desservir' &&
                  overlaps(q, i, eventCirculation(p))),
        );
        if (!blockedAccess && fits(p, q, [...placed, q])) {
          fitted = true;
          break;
        }
        cursor += .2;
      }
      if (!fitted) {
        cursor = beforeSearch;
        continue;
      }
      t
        ..clear()
        ..addAll(q);
      placed.add(t);
      previous = t;
      cursor += seam + long;
      blocks.add({
        'id': q['parcoursBlock'],
        'role': 'perimeter',
        'edge': edge,
        'singleExhibitorDepth': margin,
        'x': number(q['x']) - (edge == 'left' ? margin : 0),
        'y': number(q['y']) - (edge == 'top' ? margin : 0),
        'w': number(q['w']) + (vertical ? margin : 0),
        'h': number(q['h']) + (vertical ? 0 : margin),
      });
    }
    if (blocks.isNotEmpty) {
      results.add(_Layout(p, [...layout.blocks, ...blocks], layout.vertical));
    }
  }
  return results;
}

// Translate only a proposed open layout; protected furniture and accesses stay
// at their saved positions. Freed vendor space can fund the opposite wall row.
_Layout? _shiftOpenLayout(_Layout layout, double dx, double dy) {
  final p = clone(layout.project);
  final shifted = <Json>[];
  for (final t in tables(p).where(
    (t) => t['parcoursBlock'] != null && t['unplacedByArrangement'] != true,
  )) {
    if (t['fixed'] == true || t['capacity'] == 0) return null;
    t['x'] = number(t['x']) + dx;
    t['y'] = number(t['y']) + dy;
    shifted.add(t);
  }
  final blocks = [
    for (final b in layout.blocks)
      {...b, 'x': number(b['x']) + dx, 'y': number(b['y']) + dy},
  ];
  final obstacles = rows(p, 'items')
      .where(
        (i) => i['kind'] != 'table' || i['fixed'] == true || i['capacity'] == 0,
      )
      .toList();
  if (blocks.any((b) => obstacles.any((i) => overlaps(b, i)))) return null;
  final items = rows(
    p,
    'items',
  ).where((i) => i['unplacedByArrangement'] != true).toList();
  final geometry = PlanGeometry(p, items);
  if (shifted.any((t) => !fits(p, t, items, geometry: geometry))) return null;
  return _Layout(p, blocks, layout.vertical);
}

List<_Layout> _oppositePerimeterLayouts(_Layout layout) {
  if (parcoursClosed(layout.project)) return [];
  final p = layout.project;
  final pool = tables(p)
      .where(
        (t) =>
            t['unplacedByArrangement'] == true &&
            t['fixed'] != true &&
            t['capacity'] != 0 &&
            t['shape'] != 'cercle',
      )
      .toList();
  if (pool.length < 2) return [];
  final margin = pool.fold<double>(
    max(
      eventWallGap(p),
      max(eventCirculation(p) / 2, eventExhibitorGap(p) / 2),
    ),
    (v, t) => max(
      v,
      adaptedPlaces(comfortTable(p, t)).fold<double>(
        seatEnvelope(comfortTable(p, t)),
        (v, place) => max(v, number(place['depth'])),
      ),
    ),
  );
  final shift =
      margin + pool.map((t) => min(number(t['w']), number(t['h']))).reduce(max);
  final results = <_Layout>[];
  for (final vertical in [false, true]) {
    for (final direction in [1.0, -1.0]) {
      final moved = _shiftOpenLayout(
        layout,
        vertical ? direction * shift : 0,
        vertical ? 0 : direction * shift,
      );
      if (moved == null) continue;
      final firstEdge = vertical
          ? (direction > 0 ? 'right' : 'left')
          : (direction > 0 ? 'bottom' : 'top');
      final secondEdge = vertical
          ? (direction > 0 ? 'left' : 'right')
          : (direction > 0 ? 'top' : 'bottom');
      for (final first in _perimeterLayouts(moved, edges: [firstEdge])) {
        for (final second in _perimeterLayouts(first, edges: [secondEdge])) {
          if (second.count > layout.count) results.add(second);
        }
      }
    }
  }
  return results;
}

int arrangeParcours(Json p) {
  if (!parcoursAvailable(p)) {
    throw const FormatException(
      'Parcours réservé aux événements personnalisés, marchés de Noël et brocantes.',
    );
  }
  final base = clone(p);
  clearParcoursLayout(base);
  base['arrangementMode'] = 'Parcours';
  final orientation =
      (p['parcoursSettings'] as Map?)?['orientation'] ?? 'Automatique';
  final choices = <_Layout>[];
  final accesses = rows(
    base,
    'items',
  ).where((i) => i['kind'] == 'entry' || i['kind'] == 'exit').toList();
  final imposed = parcoursClosed(p);
  final wallLayout =
      (p['parcoursSettings'] as Map?)?['wallLayout'] ?? 'Automatique';
  for (final vertical in [false, true]) {
    if (orientation == 'Horizontale' && vertical ||
        orientation == 'Verticale' && !vertical) {
      continue;
    }
    for (
      var pairs = 1;
      pairs <= max(8, min(24, tables(base).length ~/ 2));
      pairs++
    ) {
      if (imposed) {
        choices.add(_build(base, vertical, pairs, 3, maze: true));
        if (accesses.length > 1) {
          choices.add(_build(base, vertical, pairs, 3));
        }
        continue;
      }
      for (final pattern
          in parcoursClosed(p)
              ? [3]
              : wallSides(base).isEmpty
              ? [0]
              : wallLayout == 'Même mur (en peigne)'
              ? [1, 2]
              : wallLayout == 'Alterné'
              ? [3]
              : [3, 1, 2, 0]) {
        choices.add(_build(base, vertical, pairs, pattern));
        if (accesses.length > 1) {
          choices.add(_build(base, vertical, pairs, pattern, accessHead: true));
        }
      }
    }
  }
  final seen = <String>{};
  choices.removeWhere(
    (layout) => !seen.add(
      jsonEncode([
        for (final t in tables(layout.project))
          [t['id'], t['x'], t['y'], t['w'], t['h'], t['unplacedByArrangement']],
      ]),
    ),
  );
  choices.sort((a, b) {
    if (imposed) {
      final maze = (b.blocks.any((q) => q['role'] == 'spine') ? 1 : 0)
          .compareTo(a.blocks.any((q) => q['role'] == 'spine') ? 1 : 0);
      if (maze != 0) return maze;
    }
    final count = b.count.compareTo(a.count);
    return count != 0 ? count : a.blocks.length.compareTo(b.blocks.length);
  });
  final evaluated = imposed
      ? choices.take(64).toList()
      : [
          for (final vertical in [false, true])
            for (final lead in [false, true])
              ...choices
                  .where(
                    (c) =>
                        c.vertical == vertical &&
                        c.blocks.any((b) => b['accessHead'] == true) == lead,
                  )
                  .take(6),
        ];
  final routeCache = <_Layout, Json>{};
  if (!imposed && !parcoursClosed(p)) {
    final viable = <_Layout>[];
    for (final layout in evaluated) {
      final result = _routes(layout);
      routeCache[layout] = result;
      if ((result['warnings'] as List).isEmpty) viable.add(layout);
    }
    // Obstacles may invalidate the densest candidates. Explore less crowded
    // bands rather than accepting tables outside the visitor route.
    if (viable.isEmpty) {
      final fallback = choices
          .where((layout) => !evaluated.contains(layout))
          .take(32)
          .toList();
      for (final layout in fallback) {
        final result = _routes(layout);
        routeCache[layout] = result;
        evaluated.add(layout);
        if ((result['warnings'] as List).isEmpty) {
          viable.add(layout);
          if (viable.length >= 2) break;
        }
      }
    }
    if (viable.isEmpty) {
      final movableCount = tables(base)
          .where((t) => t['fixed'] != true && t['capacity'] != 0)
          .length;
      final budgets =
          <int>{
              movableCount - 2,
              movableCount * 3 ~/ 4,
              movableCount ~/ 2,
              movableCount ~/ 4,
              6,
              4,
            }.where((n) => n >= 4 && n < movableCount).toList()
            ..sort((a, b) => b.compareTo(a));
      for (final count in budgets) {
        if (viable.isNotEmpty) break;
        for (final vertical in [false, true]) {
          if (orientation == 'Horizontale' && vertical ||
              orientation == 'Verticale' && !vertical) {
            continue;
          }
          for (var pairs = 1; pairs <= min(4, count ~/ 2); pairs++) {
            final layout = _build(base, vertical, pairs, 0, tableLimit: count);
            final result = _routes(layout);
            routeCache[layout] = result;
            evaluated.add(layout);
            if ((result['warnings'] as List).isEmpty) viable.add(layout);
          }
        }
      }
    }
    viable.sort((a, b) => b.count.compareTo(a.count));
    for (final vertical in [false, true]) {
      for (final layout
          in viable.where((c) => c.vertical == vertical).take(2)) {
        evaluated.addAll(_complementaryLayouts(layout));
        evaluated.addAll(_perimeterLayouts(layout));
        evaluated.addAll(_oppositePerimeterLayouts(layout));
      }
    }
  }
  _Layout? best;
  Json? routes;
  var score = double.negativeInfinity;
  for (final layout in evaluated) {
    final result = routeCache[layout] ?? _routes(layout);
    final value =
        layout.count * 10000 -
        (result['warnings'] as List).length * 100000 -
        tables(layout.project).where((t) => t['parcoursRole'] == 'cap').length *
            100 -
        layout.blocks.length * 20 -
        number(result['length'], 100000);
    final fewerWarnings =
        routes == null ||
        (result['warnings'] as List).length <
            (routes['warnings'] as List).length;
    final equalWarnings =
        routes != null &&
        (result['warnings'] as List).length ==
            (routes['warnings'] as List).length;
    if (best == null || fewerWarnings || (equalWarnings && value > score)) {
      best = layout;
      routes = result;
      score = value;
    }
  }
  final proposal = best!.project;
  final originals = {for (final t in tables(p)) t['id']: t};
  final clean = {for (final t in tables(base)) t['id']: t};
  for (final t in tables(proposal)) {
    if (t['fixed'] == true || t['capacity'] == 0) continue;
    final original = originals[t['id']]!, before = clean[t['id']]!;
    if (t['parcoursBlock'] != null) {
      t['parcoursOriginal'] = {
        for (final key in ['w', 'h', 'rotation', 'sides', 'seatSide'])
          if (before.containsKey(key)) key: before[key],
      };
      final swapped =
          (number(t['w']) - number(before['h'])).abs() < .00001 &&
          (number(t['h']) - number(before['w'])).abs() < .00001 &&
          number(before['w']) != number(before['h']);
      final model = rows(
        p,
        'types',
      ).where((type) => type['id'] == before['type']).firstOrNull;
      final initialRotation =
          before['rotation'] as int? ??
          (model != null &&
                  ((number(before['w']) < number(before['h'])) !=
                      (number(model['w']) < number(model['h'])))
              ? 90
              : 0);
      t['rotation'] = (initialRotation + (swapped ? 90 : 0)) % 360;
    }
    original
      ..clear()
      ..addAll(t);
  }
  parkUnplacedTables(p);
  for (final t in tables(p)) {
    if (t['fixed'] == true || t['capacity'] == 0) {
      for (final key in [
        'parcoursMaze',
        'parcoursOriginal',
        'parcoursBlock',
        'parcoursRole',
        'parcoursGap',
        'parcoursAxis',
      ]) {
        t.remove(key);
      }
    }
  }
  final geometry = PlanGeometry(p, rows(p, 'items'));
  final invalidBlocks = tables(p)
      .where(
        (t) =>
            t['parcoursBlock'] != null &&
            !unplacedTable(p, t) &&
            !fits(p, t, rows(p, 'items'), geometry: geometry),
      )
      .map((t) => t['parcoursBlock'])
      .toSet();
  if (invalidBlocks.isNotEmpty) {
    for (final t in tables(p)) {
      if (invalidBlocks.contains(t['parcoursBlock'])) {
        t['unplacedByArrangement'] = true;
      }
    }
    best.blocks.removeWhere((b) => invalidBlocks.contains(b['id']));
    parkUnplacedTables(p);
    routes = _routes(_Layout(p, best.blocks, best.vertical));
    (routes['warnings'] as List).add(
      'Parcours : îlot écarté après vérification des dimensions et des places adaptées.',
    );
  }
  final unsupported = tables(p)
      .where(
        (t) =>
            t['shape'] == 'cercle' && t['fixed'] != true && t['capacity'] != 0,
      )
      .length;
  if (unsupported > 0) {
    (routes!['warnings'] as List).add(
      'Parcours : $unsupported tables rondes écartées, elles ne permettent pas de fermer les îlots.',
    );
  }
  for (final t in tables(p)) {
    if (unplacedTable(p, t)) {
      t['parcoursUnplacedReason'] = t['shape'] == 'cercle'
          ? 'table ronde incompatible avec un îlot fermé'
          : 'mobilier, fermeture ou espace insuffisant pour former un îlot fermé';
    }
  }
  p['parcoursPlan'] = {
    'blocks': best.blocks,
    'paths': routes!['paths'],
    'warnings': routes['warnings'],
    'services': routes['services'] ?? <Json>[],
    'signature': parcoursSignature(p),
  };
  return tables(p).where((t) => unplacedTable(p, t)).length;
}
