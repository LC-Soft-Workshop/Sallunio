import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

import 'stand_contiguous_metres_test.dart' show stand;
import 'mixed_furniture_test.dart' show exhibitor;
import 'arrangement_start_test.dart' as deployment;

void main() {
  Json fixture() => newProject('Test')
    ..['items'] = [
      stand('a', 1, 1)..['type'] = 'A',
      stand('b', 2.8, 1)..['type'] = 'B',
    ]
    ..['groups'] = [exhibitor('Test', 3)];
  test('Deployment groups interleaved stand models', () {
    final p = deployment.room(start: 'Haut gauche');
    p['items'] = [
      for (final n in [1, 2, 3, 4])
        {
          ...deployment.table('T$n'),
          'usage': furnitureUses[1],
          'type': n.isOdd ? 'A' : 'B',
        },
    ];
    expect(arrange(p), 0);
    final placed = tables(p).toList()
      ..sort((a, b) {
        final y = number(a['y']).compareTo(number(b['y']));
        return y != 0 ? y : number(a['x']).compareTo(number(b['x']));
      });
    expect(placed.map((t) => t['type']), ['A', 'A', 'B', 'B']);
  });
  test('Default forbids mixing even equal sized distinct models', () {
    final p = fixture();
    allocateStands(p);
    expect(standSummary(p)['assignedMetres'], closeTo(1.8, 1e-6));
  });
  test('Explicit mixing allows a continuous mixed stand', () {
    final p = fixture()..['allowMixedStandTypes'] = true;
    allocateStands(p);
    expect(standSummary(p)['assignedMetres'], closeTo(3, 1e-6));
  });
  test('Manual mixing is rejected in both units without mutation', () {
    final p = fixture(), g = rows(p, 'groups').single, ts = tables(p);
    setStandPortion(p, g, ts[0], length: 1);
    expect(
      () => setStandPortion(p, g, ts[1], length: 1),
      throwsFormatException,
    );
    expect(g['standAlloc'].length, 1);
    g['standUnit'] = 'Tables';
    expect(
      () => setStandPortion(p, g, ts[1], whole: true),
      throwsFormatException,
    );
    p['allowMixedStandTypes'] = true;
    setStandPortion(p, g, ts[1], whole: true);
    expect(g['standAlloc'].length, 2);
  });
  test('Whole tables choose a model with enough free tables', () {
    final p = newProject('Stand')
      ..['items'] = [
        stand('a', 1, 1)..['type'] = 'A',
        stand('b', 3, 1)..['type'] = 'B',
        stand('c', 5, 1)..['type'] = 'B',
      ];
    final g = exhibitor('Stand', 0)
      ..['standUnit'] = 'Tables'
      ..['requestedTables'] = 2;
    p['groups'] = [g];
    allocateStands(p);
    expect((g['standAlloc'] as List).map((a) => a['table']), ['b', 'c']);
  });
  test('Whole table mixing is explicitly opt in', () {
    final p = fixture(), g = rows(p, 'groups').single;
    g['standUnit'] = 'Tables';
    g['requestedTables'] = 2;
    allocateStands(p);
    expect(g['standAlloc'].length, 1);
    p['allowMixedStandTypes'] = true;
    allocateStands(p);
    expect(g['standAlloc'].length, 2);
  });
  test('Rotation preserves model identity, depth changes do not', () {
    final a = stand('a', 1, 1), b = stand('b', 1, 1, w: .8, h: 1.8);
    expect(standTypeKey(a), standTypeKey(b));
    b['w'] = .6;
    expect(standTypeKey(a), isNot(standTypeKey(b)));
  });
}
