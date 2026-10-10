import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/magnetism.dart';

import 'joining_test.dart' show table;

Json scene(
  List<Json> items, {
  String joining = 'Les deux',
  String wall = 'Aucun',
}) {
  final p = newProject('Plan fictif');
  p['items'] = items;
  p['joining'] = joining;
  p['wallSupport'] = wall;
  p['aisle'] = 1.2;
  p['room']['width'] = p['room']['height'] = 20.0;
  return p;
}

void applySnap(Json p, Set<String> ids, MagneticSnap snap) {
  for (final item in rows(p, 'items').where((i) => ids.contains(i['id']))) {
    item['x'] = number(item['x']) + snap.dx;
    item['y'] = number(item['y']) + snap.dy;
  }
}

Json object(String kind, double x, double y, {double w = 2, double h = 2}) => {
  'id': 'object-$kind',
  'kind': kind,
  'label': 'Objet fictif',
  'shape': 'rectangle',
  'x': x,
  'y': y,
  'w': w,
  'h': h,
  'fixed': false,
};

void main() {
  test('Invisible unnamed zones have a useful magnetic cue', () {
    final a = table('a', 2.08, 3.05), zone = object('zone', 3.8, 3);
    zone['label'] = '';
    zone['zoneFill'] = 'Invisible';
    expect(magneticSnap(scene([a, zone]), {'a'}).label, 'Accroche : Zone');
  });
  test('Diagonal polygon wall snapping follows its inward normal', () {
    final item = object('zone', 3.04, 3.04, w: 1, h: 1), p = scene([item]);
    p['room']['polygon'] = '0,6;6,0;20,0;20,20;0,20';
    final snap = magneticSnap(p, {'object-zone'});
    expect(snap.active, true);
    applySnap(p, {'object-zone'}, snap);
    expect(number(item['x']), closeTo(3, 1e-8));
    expect(number(item['y']), closeTo(3, 1e-8));
    expect(polygonFits(item, p['room']), true);
  });
  test('Single table joins on permitted edges with a centred axis, without mutating inputs', () {
    final a = table('a', 2.08, 4.04),
        b = table('b', 3.8, 4),
        p = scene([a, b]),
        before = clone(p);
    final snap = magneticSnap(p, {'a'});
    expect(snap.active, true);
    expect(snap.dx, closeTo(-.08, 1e-8));
    expect(snap.dy, closeTo(-.04, 1e-8));
    expect(p, before);
    applySnap(p, {'a'}, snap);
    expect(joinedEdges(p, a, b), isNotNull);
    expect(fits(p, a, rows(p, 'items')), true);
  });
  test(
    'A joined assembly connects to another assembly by one rigid translation',
    () {
      final a = table('a', 2.08, 4),
          b = table('b', 3.88, 4),
          c = table('c', 5.6, 4),
          d = table('d', 7.4, 4);
      c['fixed'] = d['fixed'] = true;
      final p = scene([a, b, c, d]),
          fixed = [clone(c), clone(d)],
          distance = tableDistance(a, b);
      final snap = magneticSnap(p, {'a', 'b'});
      expect(snap.active, true);
      expect(snap.dx, closeTo(-.08, 1e-8));
      applySnap(p, {'a', 'b'}, snap);
      expect(tableDistance(a, b), closeTo(distance, 1e-8));
      expect([c, d], fixed);
      expect(joinedEdges(p, b, c), isNotNull);
      expect(fits(p, a, rows(p, 'items')), true);
      expect(fits(p, b, rows(p, 'items')), true);
    },
  );
  test('Mixed table sizes keep their shared axis when two assemblies snap', () {
    final a = table('a', 2.06, 4.05),
        b = table('b', 3.86, 4.075, w: 1.2, h: .75),
        c = table('c', 5, 4);
    final p = scene([a, b, c]),
        distance = tableDistance(a, b),
        snap = magneticSnap(scene([a, b, c]), {'a', 'b'});
    expect(snap.active, true);
    applySnap(p, {'a', 'b'}, snap);
    expect(joinedEdges(p, a, b), isNotNull);
    expect(joinedEdges(p, b, c), isNotNull);
    expect(tableDistance(a, b), closeTo(distance, 1e-8));
    expect(b['w'], 1.2);
    expect(b['h'], .75);
  });
  for (final kind in ['zone', 'obstacle', 'entry', 'exit', 'door']) {
    test('Table snaps to $kind without a doubled gap or overlap', () {
      final a = table('a', 2.08, 3.05),
          b = object(kind, 3.8, 3),
          p = scene([a, b], joining: 'Aucun');
      final snap = magneticSnap(p, {'a'});
      expect(snap.active, true);
      applySnap(p, {'a'}, snap);
      expect(number(a['x']) + number(a['w']), closeTo(number(b['x']), 1e-8));
      expect(overlaps(a, b), false);
      expect(fits(p, a, rows(p, 'items')), true);
    });
  }
  test('Moving background objects also snap to tables', () {
    final a = table('a', 2, 3), b = object('zone', 3.88, 3), p = scene([a, b]);
    final snap = magneticSnap(p, {'object-zone'});
    expect(snap.active, true);
    applySnap(p, {'object-zone'}, snap);
    expect(number(b['x']), closeTo(3.8, 1e-8));
    expect(overlaps(a, b), false);
  });
  test('Forbidden joins and circles never snap into table contact', () {
    final a = table('a', 3, 3.03),
        b = table('b', 3, 3.8),
        p = scene([a, b], joining: 'Petits côtés');
    expect(magneticSnap(p, {'a'}).active, false);
    a['shape'] = 'cercle';
    a['w'] = a['h'] = .8;
    b['x'] = 3.8;
    b['y'] = 3;
    p['joining'] = 'Les deux';
    expect(magneticSnap(p, {'a'}).active, false);
  });
  test('Non-joined tables can snap to the configured passage spacing', () {
    final a = table('a', 2.06, 3),
        b = table('b', 5, 3),
        p = scene([a, b], joining: 'Aucun');
    final snap = magneticSnap(p, {'a'});
    expect(snap.active, true);
    applySnap(p, {'a'}, snap);
    expect(
      number(b['x']) - number(a['x']) - number(a['w']),
      closeTo(1.2, 1e-8),
    );
    expect(joinedEdges(p, a, b), isNull);
    expect(fits(p, a, rows(p, 'items')), true);
  });
  test(
    'Wall support snaps directly; without support it keeps half the aisle',
    () {
      final a = table('a', .08, 3), p = scene([a], wall: 'Mur gauche');
      final supported = magneticSnap(p, {'a'});
      expect(supported.active, true);
      applySnap(p, {'a'}, supported);
      expect(number(a['x']), closeTo(0, 1e-8));
      p['wallSupport'] = 'Aucun';
      a['x'] = .67;
      final passage = magneticSnap(p, {'a'});
      expect(passage.active, true);
      applySnap(p, {'a'}, passage);
      expect(number(a['x']), closeTo(.6, 1e-8));
      expect(wallClearanceFits(p, a), true);
    },
  );
  test('Assembly can snap to the room corner while retaining all relative positions', () {
    final a = table('a', .08, .67),
        b = table('b', 1.88, .67),
        p = scene([a, b], wall: 'Mur gauche');
    final snap = magneticSnap(p, {'a', 'b'});
    expect(snap.guides.length, 2);
    applySnap(p, {'a', 'b'}, snap);
    expect(number(a['x']), closeTo(0, 1e-8));
    expect(number(a['y']), closeTo(.6, 1e-8));
    expect(number(b['x']) - number(a['x']), closeTo(1.8, 1e-8));
  });
  test('Wall snapping accounts for adapted place depth', () {
    final a = table('a', 3, 1.28), p = scene([a]);
    a['adaptedPlaces'] = [
      {'slot': 0, 'width': .9, 'depth': 1.2},
    ];
    final snap = magneticSnap(p, {'a'});
    expect(snap.active, true);
    applySnap(p, {'a'}, snap);
    expect(number(a['y']), closeTo(1.2, 1e-8));
    expect(fits(p, a, rows(p, 'items')), true);
  });
  test('Polygon wall snapping follows the wall and validates the complete envelope', () {
    final a = object('zone', 2, .06, w: 1, h: 1), p = scene([a]);
    p['room']['polygon'] = '0,0;20,0;20,20;0,20';
    final snap = magneticSnap(p, {'object-zone'});
    expect(snap.active, true);
    applySnap(p, {'object-zone'}, snap);
    expect(number(a['y']), closeTo(0, 1e-8));
    expect(polygonFits(a, p['room']), true);
  });
  test('A snap never moves a locked member or introduces a collision for another member', () {
    final a = table('a', 2.08, 4),
        b = table('b', 3.88, 4),
        c = table('c', 5.6, 4),
        obstacle = object('obstacle', 2.0, 4, w: .07, h: .8),
        p = scene([a, b, c, obstacle]);
    final before = clone(p);
    expect(magneticSnap(p, {'a', 'b'}).active, false);
    expect(p, before);
    b['fixed'] = true;
    obstacle['x'] = 15;
    expect(magneticSnap(p, {'a', 'b'}).active, false);
  });
  test('Distant targets cannot pull a table toward them', () {
    final a = table('a', 3, 3), b = table('b', 10, 10), p = scene([a, b]);
    final snap = magneticSnap(p, {'a'});
    expect(snap.active, false);
    expect(sqrt(snap.dx * snap.dx + snap.dy * snap.dy), 0);
  });
}
