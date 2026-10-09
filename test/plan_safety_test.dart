import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

import 'joining_test.dart' show table, plan;

void main() {
  test('Automatic placement uses one exact aisle, without grid rounding', () {
    final a = table('a', 1, 1, w: .8, h: .8, sides: 'Tous côtés');
    final b = table('b', 4, 4, w: .8, h: .8, sides: 'Tous côtés');
    final p = plan([a], 'Aucun');
    final result = findPosition(p, b, [a])!;
    expect(
      number(result['x']) - number(a['x']) - number(a['w']),
      closeTo(.9, 1e-8),
    );
    expect(result['y'], a['y']);
  });
  test('Aisle is measured once between table edges on either axis', () {
    for (final aisle in [.9, 1.5]) {
      for (final vertical in [true, false]) {
        final a = table('a', 1, 1, w: .8, h: .8, sides: 'Tous côtés');
        final b = table(
          'b',
          vertical ? 1 : 1.8 + aisle,
          vertical ? 1.8 + aisle : 1,
          w: .8,
          h: .8,
          sides: 'Tous côtés',
        );
        final p = plan([a, b], 'Aucun')..['aisle'] = aisle;
        expect(fits(p, a, rows(p, 'items')), true);
        expect(
          issues(
            p,
          ).where((s) => s.contains('passage') || s.contains('encombrement')),
          isEmpty,
        );
        b[vertical ? 'y' : 'x'] = 1.8 + aisle - .01;
        expect(fits(p, a, rows(p, 'items')), false);
        expect(issues(p).any((s) => s.contains('passage')), true);
      }
    }
  });
  test('Failed arrangement leaves every original position intact', () {
    final p = plan([table('a', 2, 2), table('b', 2, 4)], 'Aucun');
    p['room']['width'] = 4.0;
    p['room']['height'] = 4.0;
    p['aisle'] = 1.5;
    final before = clone(p);
    expect(arrange(p), greaterThan(0));
    expect(p, before);
  });

  test('Successful arrangement with 1.50 m aisles has no conflicts', () {
    final p = plan([table('a', 2, 2), table('b', 2, 2)], 'Petits côtés');
    p['aisle'] = 1.5;
    expect(arrange(p), 0);
    for (final t in tables(p)) {
      expect(fits(p, t, rows(p, 'items')), isTrue);
    }
  });

  test('Rotation preserves centres, allocations and capacity', () {
    final p = demoProject();
    final t = tables(p).first;
    final cx = number(t['x']) + number(t['w']) / 2;
    final cy = number(t['y']) + number(t['h']) / 2;
    final groups = rows(p, 'groups').map(clone).toList();
    rotateTables(p);
    expect(number(t['x']) + number(t['w']) / 2, closeTo(cx, 1e-8));
    expect(number(t['y']) + number(t['h']) / 2, closeTo(cy, 1e-8));
    expect(t['w'], .8);
    expect(t['capacity'], 6);
    expect(rows(p, 'groups'), groups);
  });

  test('Markers include anonymous mobility, allergy and meal overrides', () {
    final p = demoProject();
    final g = rows(p, 'groups').first;
    g['alloc'] = [
      {'table': 'a', 'count': 2},
    ];
    g['seats'] = [
      {'need': 'Fauteuil', 'allergy': 'Noix', 'meal': 'Sans gluten'},
    ];
    expect(
      tableMarkers(p, 'a'),
      containsAll([
        'Mobilité / PMR',
        'Allergie',
        'Repas : Sans gluten',
        'Repas : Normal',
      ]),
    );
    expect(tableMarkers(p, 'b'), isEmpty);
  });
}
