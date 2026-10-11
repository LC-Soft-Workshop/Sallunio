import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/parcours.dart';
import 'package:tableo/plan_export.dart';

import 'joining_test.dart' show table;

Json market({
  int count = 12,
  String orientation = 'Horizontale',
  String closure = 'À l’extérieur',
  double gap = 1.2,
  String wall = 'Aucun',
  bool exit = true,
}) {
  final p = newProject('Marché fictif');
  p['activity'] = 'Marché de Noël';
  p['mealService'] = 'Non';
  p['arrangementMode'] = 'Parcours';
  p['wallSupport'] = wall;
  p['parcoursSettings'] = {
    'exhibitorGap': gap,
    'orientation': orientation,
    'closure': closure,
  };
  p['items'] = <Json>[
    {
      'id': 'entry',
      'kind': 'entry',
      'shape': 'rectangle',
      'fixed': false,
      'label': 'Entrée',
      'x': 0.0,
      'y': 0.0,
      'w': .6,
      'h': .6,
    },
    if (exit)
      {
        'id': 'exit',
        'kind': 'exit',
        'shape': 'rectangle',
        'fixed': false,
        'label': 'Sortie',
        'x': 11.4,
        'y': 8.4,
        'w': .6,
        'h': .6,
      },
    for (var i = 0; i < count; i++) table('T$i', 3, 3, sides: 'Un côté'),
  ];
  return p;
}

void noOverlap(Json p) {
  final items = rows(p, 'items');
  for (final a in tables(p)) {
    for (final b in items) {
      if (a['id'] != b['id']) {
        expect(overlaps(a, b), false, reason: '${a['id']} / ${b['id']}');
      }
    }
    if (!unplacedTable(p, a)) {
      expect(fits(p, a, items), true, reason: '${a['id']}: ${issues(p)}');
    }
  }
}

void simpleLoop(Json p) {
  final path = parcoursPaths(p).single;
  expect(path.first, path.last);
  const epsilon = 1e-8;
  final segments = <(Point<double>, Point<double>)>[];
  for (var i = 1; i < path.length; i++) {
    final a = path[i - 1], b = path[i];
    if (a.distanceTo(b) < epsilon) continue;
    expect((a.x - b.x).abs() < epsilon || (a.y - b.y).abs() < epsilon, true);
    segments.add((a, b));
  }
  bool between(double value, double a, double b) =>
      value >= min(a, b) - epsilon && value <= max(a, b) + epsilon;
  bool intersects(
    (Point<double>, Point<double>) u,
    (Point<double>, Point<double>) v,
  ) {
    final a = u.$1, b = u.$2, c = v.$1, d = v.$2;
    final uh = (a.y - b.y).abs() < epsilon, vh = (c.y - d.y).abs() < epsilon;
    if (uh && vh) {
      return (a.y - c.y).abs() < epsilon &&
          max(min(a.x, b.x), min(c.x, d.x)) <=
              min(max(a.x, b.x), max(c.x, d.x)) + epsilon;
    }
    if (!uh && !vh) {
      return (a.x - c.x).abs() < epsilon &&
          max(min(a.y, b.y), min(c.y, d.y)) <=
              min(max(a.y, b.y), max(c.y, d.y)) + epsilon;
    }
    return uh
        ? between(c.x, a.x, b.x) && between(a.y, c.y, d.y)
        : between(a.x, c.x, d.x) && between(c.y, a.y, b.y);
  }

  for (var i = 0; i < segments.length; i++) {
    for (var j = 0; j < i; j++) {
      final u = segments[i], v = segments[j];
      if (i == j + 1 || (i == segments.length - 1 && j == 0)) {
        final dot =
            (u.$2.x - u.$1.x) * (v.$2.x - v.$1.x) +
            (u.$2.y - u.$1.y) * (v.$2.y - v.$1.y);
        expect(
          dot,
          greaterThanOrEqualTo(-epsilon),
          reason: 'Demi-tour sur un segment',
        );
      } else {
        expect(
          intersects(u, v),
          false,
          reason: 'Croisement ou segment parcouru deux fois : $u / $v',
        );
      }
    }
  }
}

void main() {
  test('Closed S islands preserve table sizes and join both accesses without conflicts', () {
    final p = market();
    final before = {
      for (final t in tables(p)) t['id']: number(t['w']) * number(t['h']),
    };
    expect(arrange(p), 0);
    expect((p['parcoursPlan']['blocks'] as List), isNotEmpty);
    expect(parcoursWarnings(p), isEmpty);
    expect(parcoursPaths(p), isNotEmpty);
    expect(tables(p).where((t) => t['parcoursRole'] == 'cap'), isNotEmpty);
    expect(parcoursUnservedTables(p), isEmpty);
    for (final t in tables(p)) {
      expect(number(t['w']) * number(t['h']), closeTo(before[t['id']]!, 1e-9));
    }
    noOverlap(p);
    expect(issues(p), isEmpty);
    expect(planSvg(p), contains('<polyline'));
  });
  test('A sole entrance forms a simple loop rather than retracing the S', () {
    final p = market(exit: false, wall: 'Tous les murs');
    expect(arrange(p), 0);
    final path = parcoursPaths(p).first;
    expect(path.first, path.last);
    expect(parcoursWarnings(p), isEmpty);
    expect(tables(p).where((t) => t['parcoursRole'] == 'cap'), isNotEmpty);
    expect(parcoursUnservedTables(p), isEmpty);
    simpleLoop(p);
    noOverlap(p);
  });
  test(
    'A sole entrance reserves the opening needed to loop around comb rows',
    () {
      final p = market(
        count: 10,
        orientation: 'Verticale',
        wall: 'Mur bas',
        exit: false,
      );
      p['parcoursSettings']['wallLayout'] = 'Même mur (en peigne)';
      expect(arrange(p), 0);
      expect(parcoursWarnings(p), isEmpty);
      for (final block in p['parcoursPlan']['blocks'] as List) {
        expect(number(block['y']) + number(block['h']), lessThan(9));
      }
      final path = parcoursPaths(p).first;
      expect(path.first, path.last);
      simpleLoop(p);
      noOverlap(p);
    },
  );
  test('All wall support omits caps only at actually closed wall ends', () {
    final p = market(count: 10, wall: 'Tous les murs');
    expect(arrange(p), 0);
    final caps = tables(p).where((t) => t['parcoursRole'] == 'cap').toList();
    expect(caps.length, 2);
    for (final block in p['parcoursPlan']['blocks'] as List) {
      final closedEnds =
          (number(block['x']).abs() < 1e-8 ? 1 : 0) +
          ((number(block['x']) + number(block['w']) - 12).abs() < 1e-8 ? 1 : 0);
      expect(
        caps.where((t) => t['parcoursBlock'] == block['id']).length,
        2 - closedEnds,
      );
    }
    noOverlap(p);
    expect(parcoursWarnings(p), isEmpty);
  });
  test(
    'Between-row closures fit the exact private gap and preserve the bodies',
    () {
      final p = market(gap: 1.8, closure: 'Entre les rangées');
      expect(arrange(p), 0);
      for (final cap in tables(p).where((t) => t['parcoursRole'] == 'cap')) {
        expect(cap['h'], 1.8);
      }
      noOverlap(p);
      expect(parcoursWarnings(p), isEmpty);
    },
  );
  test('Incompatible between-row closure does not silently shorten the gap or overlap', () {
    final p = market(closure: 'Entre les rangées');
    expect(arrange(p), 12);
    expect(parcoursWarnings(p), isNotEmpty);
    noOverlap(p);
  });
  test('Vertical mode rotates whole rows and caps without resizing physical tables', () {
    final p = market(count: 8, orientation: 'Verticale');
    expect(arrange(p), 0);
    expect(
      tables(p)
          .where((t) => t['parcoursRole'] == 'upper')
          .every(
            (t) => t['w'] == .8 && t['h'] == 1.8 && t['seatSide'] == 'Droite',
          ),
      true,
    );
    noOverlap(p);
    expect(parcoursWarnings(p), isEmpty);
  });
  test('Multiple entrances and exits are connected to the public network', () {
    final p = market();
    rows(p, 'items').addAll([
      {
        'id': 'entry2',
        'kind': 'entry',
        'label': 'Entrée 2',
        'x': 0.0,
        'y': 8.4,
        'w': .6,
        'h': .6,
      },
      {
        'id': 'exit2',
        'kind': 'exit',
        'label': 'Sortie 2',
        'x': 11.4,
        'y': 0.0,
        'w': .6,
        'h': .6,
      },
    ]);
    expect(arrange(p), lessThanOrEqualTo(1));
    expect(parcoursUnservedTables(p), isEmpty);
    final paths = parcoursPaths(p);
    for (final access in rows(
      p,
      'items',
    ).where((i) => i['kind'] == 'entry' || i['kind'] == 'exit')) {
      final centre = Point(
        number(access['x']) + number(access['w']) / 2,
        number(access['y']) + number(access['h']) / 2,
      );
      expect(
        paths
            .expand((path) => path)
            .any((point) => point.distanceTo(centre) < number(p['aisle'])),
        true,
      );
    }
    expect(parcoursWarnings(p), isEmpty);
    noOverlap(p);
  });
  test(
    'Invisible zones and fixed service furniture are preserved and avoided',
    () {
      final p = market(count: 8);
      p['room']['width'] = 18.0;
      p['room']['height'] = 12.0;
      rows(p, 'items').firstWhere((i) => i['kind'] == 'exit')['x'] = 17.4;
      final zone = {
        'id': 'zone',
        'kind': 'zone',
        'label': '',
        'zoneFill': 'Invisible',
        'x': 9.0,
        'y': 0.0,
        'w': 1.0,
        'h': 12.0,
      };
      final fixed = table('fixed', 15, 4)..['fixed'] = true;
      final service = table('service', 15, 8, capacity: 0);
      rows(p, 'items').addAll([zone, fixed, service]);
      final savedFixed = clone(fixed), savedService = clone(service);
      arrange(p);
      expect(fixed, savedFixed);
      expect(service, savedService);
      noOverlap(p);
      // A full-height exclusion can disconnect entrances: report instead of crossing it.
      expect(
        parcoursWarnings(p).any(
          (w) =>
              w.contains('isolé') ||
              w.contains('sortie') ||
              w.contains('allée'),
        ),
        true,
      );
    },
  );
  test('Excess and round tables are parked without overlap, never resized', () {
    final p = market(count: 80);
    tables(p).last['shape'] = 'cercle';
    arrange(p);
    expect(tables(p).any((t) => unplacedTable(p, t)), true);
    noOverlap(p);
    expect(parcoursWarnings(p).any((w) => w.contains('rondes')), true);
  });
  test('Manual edits invalidate route guides and standard arrangement restores seating', () {
    final p = market();
    arrange(p);
    tables(p).first['x'] = number(tables(p).first['x']) + .1;
    expect(parcoursPaths(p), isEmpty);
    expect(parcoursWarnings(p), isNotEmpty);
    p['arrangementMode'] = 'Standard';
    arrange(p);
    expect(p.containsKey('parcoursPlan'), false);
    expect(
      tables(p).every(
        (t) => t['w'] == 1.8 && t['h'] == .8 && !t.containsKey('parcoursBlock'),
      ),
      true,
    );
  });
  test('Mode is limited to the three requested event types', () {
    for (final activity in roomActivities) {
      final p = market()..['activity'] = activity;
      expect(
        parcoursAvailable(p),
        ['Personnalisé', 'Marché de Noël', 'Brocante'].contains(activity),
      );
      if (!parcoursAvailable(p)) {
        expect(() => arrangeParcours(p), throwsFormatException);
      }
    }
    expect(wallSides(market(wall: 'Tous les murs')), {
      'left',
      'right',
      'top',
      'bottom',
    });
  });
  test('Odd furniture counts can combine wall and free-standing blocks', () {
    final p = market(count: 15, wall: 'Tous les murs');
    expect(arrange(p), 0);
    noOverlap(p);
    expect(parcoursWarnings(p), isEmpty);
  });
  test('Two exits without a labelled entrance connect to the common route', () {
    final p = market();
    rows(p, 'items').first['kind'] = 'exit';
    expect(arrange(p), 0);
    expect(parcoursWarnings(p), isEmpty);
    noOverlap(p);
  });
  test(
    'Repeated placement and JSON restore preserve reservations and geometry',
    () {
      final p = market();
      p['groups'] = rows(demoProject(), 'groups');
      final groups = clone({'groups': p['groups']});
      arrange(p);
      final positions = {
        for (final t in tables(p)) t['id']: [t['x'], t['y'], t['w'], t['h']],
      };
      arrange(p);
      expect(p['groups'], groups['groups']);
      expect({
        for (final t in tables(p)) t['id']: [t['x'], t['y'], t['w'], t['h']],
      }, positions);
      final copy = clone(p);
      validateProject(copy);
      expect(parcoursCurrent(copy), true);
      copy['parcoursPlan']['paths'] = ['incorrect'];
      expect(() => validateProject(copy), throwsFormatException);
    },
  );
  test('Polygonal room excludes its missing corner and keeps route inside', () {
    final p = market(count: 8);
    p['room']['polygon'] = '0,0;12,0;12,6;8,6;8,9;0,9';
    rows(p, 'items').firstWhere((i) => i['kind'] == 'exit')['x'] = 7.3;
    arrange(p);
    noOverlap(p);
    for (final path in parcoursPaths(p)) {
      for (final point in path) {
        expect(inside(point, roomPolygon(p['room'])), true);
      }
    }
  });
  test('A moved fixed table keeps its current dimensions on subsequent arrangements', () {
    final p = market();
    arrange(p);
    final cap = tables(p).firstWhere((t) => t['parcoursRole'] == 'cap');
    cap['fixed'] = true;
    final saved = clone(cap);
    arrange(p);
    for (final key in ['x', 'y', 'w', 'h', 'rotation', 'seatSide', 'fixed']) {
      expect(cap[key], saved[key]);
    }
  });
  test('Path segments keep their passage clear of all furniture and private strips', () {
    final p = market();
    arrange(p);
    final radius = number(p['aisle']) / 2;
    for (final route in parcoursPaths(p)) {
      for (var n = 1; n < route.length; n++) {
        final a = route[n - 1], b = route[n];
        final steps = max(1, (a.distanceTo(b) / .1).ceil());
        for (var i = 0; i <= steps; i++) {
          final v = Point(
            a.x + (b.x - a.x) * i / steps,
            a.y + (b.y - a.y) * i / steps,
          );
          final box = {
            'x': v.x - radius,
            'y': v.y - radius,
            'w': radius * 2,
            'h': radius * 2,
          };
          for (final t in [
            ...tables(p),
            ...(p['parcoursPlan']['blocks'] as List).cast<Json>(),
          ]) {
            expect(overlaps(box, t), false);
          }
        }
      }
    }
  });
}
