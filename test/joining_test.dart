import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

Json table(
  String id,
  double x,
  double y, {
  double w = 1.8,
  double h = .8,
  int capacity = 6,
  String shape = 'rectangle',
  String sides = 'Longs côtés',
}) => {
  'id': id,
  'kind': 'table',
  'label': id,
  'x': x,
  'y': y,
  'w': w,
  'h': h,
  'capacity': capacity,
  'shape': shape,
  'seating': 'Chaises',
  'sides': sides,
  'fixed': false,
};
Json plan(List<Json> items, String joining) {
  final p = newProject('Fictif');
  p['items'] = items;
  p['joining'] = joining;
  return p;
}

Json type(
  String id, {
  int quantity = 5,
  int limit = 5,
  bool enabled = true,
  double w = 1.8,
  double h = .8,
  String shape = 'rectangle',
}) => {
  'id': id,
  'name': id,
  'quantity': quantity,
  'limit': limit,
  'enabled': enabled,
  'capacity': 6,
  'shape': shape,
  'w': w,
  'h': h,
  'source': 'Salle',
  'seating': 'Chaises',
};

void main() {
  test('Automatic layout joins short or long edges according to plan option and keeps fixed tables', () {
    for (final mode in ['Petits côtés', 'Grands côtés']) {
      final a = table('A', 1, 1)..['fixed'] = true,
          b = table('B', 7, 7),
          p = plan([], mode);
      p['items'] = [a, b];
      expect(arrange(p), 0);
      final contact = joinedEdges(p, a, b);
      expect(contact, isNotNull);
      expect(contact!.$1, mode == 'Petits côtés' ? 'right' : 'bottom');
      expect(a['x'], 1);
      expect(a['y'], 1);
      expect(fits(p, b, rows(p, 'items')), true);
    }
  });
  test('Contact petits côtés permitted only with explicit plan choice', () {
    final a = table('A', 1, 1), b = table('B', 2.8, 1);
    final p = plan([a, b], 'Aucun');
    expect(fits(p, a, rows(p, 'items')), false);
    p['joining'] = 'Petits côtés';
    expect(joinedEdges(p, a, b), ('right', 'left'));
    expect(fits(p, a, rows(p, 'items')), true);
    expect(effectiveCapacity(p, a), 6);
    expect(
      issues(p).where(
        (s) =>
            s.contains('chevauchement') ||
            s.contains('passage inférieur') ||
            s.contains('encombrement'),
      ),
      isEmpty,
    );
    p['joining'] = 'Grands côtés';
    expect(joinedEdges(p, a, b), null);
    expect(fits(p, a, rows(p, 'items')), false);
  });
  test('Long-side contact removes seats and adjusts automatic capacity', () {
    final a = table('A', 1, 1), b = table('B', 1, 1.8);
    final p = plan([a, b], 'Grands côtés');
    final geo = PlanGeometry(p, rows(p, 'items'));
    expect(geo.blocked['A'], {'bottom'});
    expect(geo.blocked['B'], {'top'});
    expect(geo.capacity(a), 3);
    expect(geo.capacity(b), 3);
    expect(fits(p, a, rows(p, 'items')), true);
    p['groups'] = [
      {
        'id': 'g',
        'name': 'Fictif',
        'count': 8,
        'meal': 'Normal',
        'allergy': '',
        'needs': '',
        'alloc': <Json>[],
      },
    ];
    allocate(p);
    expect(occupancy(p, 'A'), 3);
    expect(occupancy(p, 'B'), 3);
    expect(allocationSummary(p)['remaining'], 2);
    expect(
      preparationNotes(p).any((s) => s.contains('jonction sans assises')),
      true,
    );
  });
  test('All-sided seating loses end seats at short-side junction', () {
    final a = table('A', 1, 1, capacity: 8, sides: 'Tous côtés'),
        b = table('B', 2.8, 1, capacity: 8, sides: 'Tous côtés');
    final p = plan([a, b], 'Petits côtés');
    expect(effectiveCapacity(p, a), 6);
    expect(effectiveCapacity(p, b), 6);
    expect(fits(p, a, rows(p, 'items')), true);
  });
  test('Round tables, partial edge contact and overlap are never exempt', () {
    final a = table('A', 1, 1), b = table('B', 2.8, 1.1);
    final p = plan([a, b], 'Les deux');
    expect(joinedEdges(p, a, b), null);
    expect(fits(p, a, rows(p, 'items')), false);
    b['y'] = 1.0;
    b['x'] = 2.7;
    expect(joinedEdges(p, a, b), null);
    expect(fits(p, a, rows(p, 'items')), false);
    a['shape'] = 'cercle';
    b['shape'] = 'cercle';
    b['x'] = 2.8;
    expect(joinedEdges(p, a, b), null);
    expect(fits(p, a, rows(p, 'items')), false);
  });
  test(
    'Joining supports rotated tables and exact snap without moving neighbors',
    () {
      final a = table('A', 1, 1, w: .8, h: 1.8),
          b = table('B', 1, 2.8, w: .8, h: 1.8);
      final p = plan([a, b], 'Petits côtés');
      expect(joinedEdges(p, a, b), ('bottom', 'top'));
      b['y'] = 2.9;
      final snapped = snapToJoin(p, b, rows(p, 'items'));
      expect(snapped['y'], closeTo(2.8, .00001));
      expect(a['x'], 1);
      expect(a['y'], 1);
      p['joining'] = 'Aucun';
      expect(snapToJoin(p, b, rows(p, 'items'))['y'], 2.9);
    },
  );
  test('External aisles and obstacles remain protected around joined row', () {
    final a = table('A', 1, 1), b = table('B', 2.8, 1), c = table('C', 1, 2.6);
    final p = plan([a, b, c], 'Petits côtés');
    expect(
      fits(p, a, rows(p, 'items')),
      false,
    ); // 0.80 m between table edges is below the configured 0.90 m.
    c['y'] = 2.7;
    expect(fits(p, a, rows(p, 'items')), true);
    c['y'] = 4.0;
    expect(fits(p, a, rows(p, 'items')), true);
    rows(p, 'items').add({
      'id': 'o',
      'kind': 'obstacle',
      'label': 'Obstacle',
      'x': 4.7,
      'y': 1.0,
      'w': .3,
      'h': .8,
      'shape': 'rectangle',
      'fixed': true,
    });
    expect(fits(p, b, rows(p, 'items')), true);
    rows(p, 'items').last['x'] = 4.5;
    expect(fits(p, b, rows(p, 'items')), false);
  });
  test(
    'Internal solid row has no fictitious aisle, free U-shaped gap still does',
    () {
      final p = plan([
        table('A', 1, 1, w: .8, h: .8),
        table('B', 1, 1.8, w: .8, h: .8),
        table('C', 1, 2.6, w: .8, h: .8),
      ], 'Les deux');
      final geo = PlanGeometry(p, rows(p, 'items'));
      expect(
        geo.internalContact(rows(p, 'items')[0], rows(p, 'items')[2]),
        true,
      );
      final u = plan([
        table('A', 1, 1, w: .8, h: .8),
        table('B', 1.8, 1, w: .8, h: .8),
        table('C', 2.6, 1, w: .8, h: .8),
        table('D', 1, 1.8, w: .8, h: .8),
        table('E', 2.6, 1.8, w: .8, h: .8),
      ], 'Les deux');
      final ug = PlanGeometry(u, rows(u, 'items'));
      expect(ug.sameAssembly(rows(u, 'items')[3], rows(u, 'items')[4]), true);
      expect(
        ug.internalContact(rows(u, 'items')[3], rows(u, 'items')[4]),
        false,
      );
      expect(fits(u, rows(u, 'items')[3], rows(u, 'items')), false);
    },
  );
  test('Batch respects remaining stock and limit without moving existing furniture', () {
    final p = plan([], 'Petits côtés'), t = type('rect', quantity: 8, limit: 4);
    p['types'] = [t];
    final one = addFurniture(p, [t]);
    expect(one.placed, 1);
    final first = clone(rows(p, 'items').first);
    final batch = addFurniture(p, [t], all: true);
    expect(batch.placed, 3);
    expect(batch.remaining, 0);
    expect(rows(p, 'items').first, first);
    expect(tables(p).length, 4);
    final geo = PlanGeometry(p, rows(p, 'items'));
    for (final i in rows(p, 'items')) {
      expect(fits(p, i, rows(p, 'items'), geometry: geo), true);
    }
    expect(addFurniture(p, [t], all: true).placed, 0);
  });
  test(
    'Batch reports unplaced inventory instead of stacking or leaving room',
    () {
      final p = plan([], 'Aucun');
      p['room']['width'] = 3.0;
      p['room']['height'] = 3.0;
      final t = type('rect');
      p['types'] = [t];
      final batch = addFurniture(p, [t], all: true);
      expect(batch.placed, 1);
      expect(batch.remaining, 4);
      expect(tables(p).length, 1);
      expect(fits(p, tables(p).single, rows(p, 'items')), true);
      expect(t['quantity'], 5);
      expect(t['limit'], 5);
    },
  );
  test('Global batch ignores excluded types, places multiple selected types and preserves groups', () {
    final p = plan([], 'Petits côtés');
    final a = type('a', quantity: 2, limit: 2),
        b = type('b', quantity: 2, limit: 2, w: 1.5, h: 1.5, shape: 'cercle'),
        c = type('c', enabled: false);
    p['types'] = [a, b, c];
    p['groups'] = [
      {
        'id': 'g',
        'name': 'Fictif',
        'count': 12,
        'meal': 'Normal',
        'allergy': '',
        'needs': '',
        'alloc': <Json>[],
      },
    ];
    final before = clone(rows(p, 'groups').single);
    expect(addFurniture(p, rows(p, 'types'), all: true).placed, 4);
    expect(rows(p, 'groups').single, before);
    expect(rows(p, 'items').where((i) => i['type'] == 'c'), isEmpty);
    validateProject(p);
  });
  test('Group 12 uses three consecutive joined tables of four, locked placement preserved', () {
    final p = plan([], 'Petits côtés');
    final t = type('a', quantity: 4, limit: 4);
    t['capacity'] = 4;
    p['types'] = [t];
    addFurniture(p, [t], all: true);
    p['groups'] = [
      {
        'id': 'g',
        'name': 'Groupe de 12 fictif',
        'count': 12,
        'meal': 'Normal',
        'allergy': '',
        'needs': '',
        'alloc': <Json>[],
      },
      {
        'id': 'locked',
        'name': 'Fixe fictif',
        'count': 2,
        'meal': 'Normal',
        'allergy': '',
        'needs': '',
        'locked': true,
        'alloc': [
          {'table': tables(p).last['id'], 'count': 2},
        ],
      },
    ];
    final locked = clone(rows(p, 'groups').last);
    allocate(p);
    final alloc = rows(p, 'groups').first['alloc'] as List;
    expect(alloc.length, 3);
    expect(alloc.map((a) => a['count']), [4, 4, 4]);
    expect(alloc.map((a) => a['table']), tables(p).take(3).map((t) => t['id']));
    expect(rows(p, 'groups').last, locked);
    expect(allocationSummary(p)['assigned'], 14);
  });
}
