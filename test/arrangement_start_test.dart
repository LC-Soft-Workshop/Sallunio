import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

Json room({String start = 'Centre'}) {
  final p = demoProject();
  p['groups'] = <Json>[];
  p['items'] = <Json>[];
  p['room']['width'] = 12.0;
  p['room']['height'] = 9.0;
  p['room']['polygon'] = '';
  p['arrangementCorner'] = start;
  p['joining'] = 'Petits côtés';
  return p;
}

Json table(String id, {double w = 1.8, double h = .8}) => {
  'id': id,
  'label': id,
  'kind': 'table',
  'shape': 'rectangle',
  'x': 2.0,
  'y': 2.0,
  'w': w,
  'h': h,
  'capacity': 6,
  'fixed': false,
  'sides': 'Tous côtés',
  'seating': 'Chaises',
};

void main() {
  test(
    'Boundary roundoff is accepted but a real seating overflow is rejected',
    () {
      final p = room();
      final t = table('edge');
      t['x'] = .6;
      t['y'] = 8 - (8 - .55 - .8) - .8;
      expect(number(t['y']) - .55, lessThan(0));
      expect(fits(p, t, []), true);
      t['y'] = .549;
      expect(fits(p, t, []), false);
    },
  );

  for (final start in ['Bas gauche', 'Bas droite']) {
    test(
      '$start keeps mixed tables and seating envelopes inside with no spatial alert',
      () {
        final p = room(start: start);
        p['items'] = [
          for (var i = 0; i < 15; i++)
            table('T$i', w: i < 10 ? 1.8 : 1.2, h: i < 10 ? .8 : .75),
        ];
        expect(arrange(p), 0);
        final geometry = PlanGeometry(p, rows(p, 'items'));
        for (final t in tables(p)) {
          expect(
            fits(p, t, rows(p, 'items'), geometry: geometry),
            true,
            reason: t['label'],
          );
        }
        expect(issues(p), isEmpty);
      },
    );
  }

  test(
    'Centre begins at exact room centre and preserves fixed/service positions',
    () {
      final p = room();
      final fixed = table('fixed')
        ..['fixed'] = true
        ..['x'] = .6
        ..['y'] = .6;
      final service = table('service')
        ..['capacity'] = 0
        ..['x'] = 9.5
        ..['y'] = 7.5;
      p['items'] = [table('first'), table('second'), fixed, service];
      final beforeFixed = clone(fixed), beforeService = clone(service);
      expect(arrange(p), 0);
      final first = tables(p).first;
      expect(number(first['x']) + number(first['w']) / 2, 6);
      expect(number(first['y']) + number(first['h']) / 2, 4.5);
      expect(joinedEdges(p, first, tables(p)[1]), isNotNull);
      expect(fixed, beforeFixed);
      expect(service, beforeService);
      validateProject(p);
    },
  );

  test('Centre avoids invisible central zone and places excess outside', () {
    final p = room();
    final zone = {
      'id': 'zone',
      'kind': 'zone',
      'label': '',
      'shape': 'rectangle',
      'x': 5.0,
      'y': 0.0,
      'w': 2.0,
      'h': 9.0,
      'fixed': true,
      'fill': 'Invisible',
    };
    p['items'] = [table('first'), table('second'), zone];
    expect(arrange(p), 0);
    expect(tables(p).every((t) => fits(p, t, rows(p, 'items'))), true);
    expect(tables(p).every((t) => !overlaps(t, zone)), true);
    p['room']['width'] = 1.0;
    p['room']['height'] = 1.0;
    expect(arrange(p), greaterThan(0));
    expect(tables(p).every((t) => unplacedTable(p, t)), true);
    expect(rows(p, 'items').last, zone);
  });
}
