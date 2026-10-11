import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

import 'joining_test.dart' show table, plan;

Json row() => plan([
  table('a', 2, 2),
  table('b', 3.8, 2),
  table('c', 5.6, 2),
  table('d', 7.4, 2),
], 'Petits côtés');
void main() {
  test(
    'Local opening moves connected neighbours, preserves anchor and dimensions',
    () {
      final p = row();
      p['groups'] = [
        {
          'id': 'g',
          'name': 'Fictif',
          'count': 2,
          'alloc': [
            {'table': 'b', 'count': 2},
          ],
        },
      ];
      final before = clone(p);
      tables(p)[1].addAll({'joinGap': .1, 'joinGapSides': 'Les deux bords'});
      expect(applyTableJoinGapLocally(p, before, 'b'), contains('appliquée'));
      final expected = [1.9, 3.8, 5.7, 7.5];
      for (var i = 0; i < expected.length; i++) {
        expect(number(tables(p)[i]['x']), closeTo(expected[i], 1e-8));
      }
      for (final t in tables(p)) {
        final old = tables(before).firstWhere((v) => v['id'] == t['id']);
        for (final key in ['y', 'w', 'h', 'capacity', 'rotation']) {
          expect(t[key], old[key]);
        }
        expect(t['unplacedByArrangement'], isNot(true));
      }
      expect(p['groups'], before['groups']);
    },
  );
  test('One selected edge creates an opening on that side only', () {
    final p = row(), before = clone(row());
    tables(p)[1].addAll({'joinGap': .2, 'joinGapSides': 'Second bord'});
    expect(applyTableJoinGapLocally(p, before, 'b'), contains('appliquée'));
    expect(number(tables(p)[0]['x']), 2);
    expect(number(tables(p)[1]['x']), 3.8);
    expect(number(tables(p)[2]['x']), closeTo(5.8, 1e-8));
    expect(number(tables(p)[3]['x']), closeTo(7.6, 1e-8));
  });
  test('An inherited spacing can be applied to tables still touching', () {
    final p = row()..['joinGap'] = .1, before = clone(p);
    expect(applyTableJoinGapLocally(p, before, 'b'), contains('appliquée'));
    expect(number(tables(p)[2]['x']), closeTo(5.7, 1e-8));
  });
  test('A rotated table opens only its configured connection edge', () {
    final p = plan([
      table('a', 2, 2, w: .8, h: 1.8),
      table('b', 2, 3.8, w: .8, h: 1.8),
      table('c', 2, 5.6, w: .8, h: 1.8),
    ], 'Petits côtés');
    for (final t in tables(p)) {
      t['rotation'] = 90;
    }
    final before = clone(p);
    tables(p)[1].addAll({'joinGap': .2, 'joinGapSides': 'Second bord'});
    expect(applyTableJoinGapLocally(p, before, 'b'), contains('appliquée'));
    expect(number(tables(p)[0]['y']), 2);
    expect(number(tables(p)[1]['y']), 3.8);
    expect(number(tables(p)[2]['y']), closeTo(5.8, 1e-8));
    expect(
      tables(p)
          .every((t) => t['rotation'] == 90 && t['w'] == .8 && t['h'] == 1.8),
      true,
    );
  });
  test('A locked neighbour blocks the proposal atomically', () {
    final p = row();
    tables(p)[2]['fixed'] = true;
    final before = clone(p);
    tables(p)[1]['joinGap'] = .1;
    expect(applyTableJoinGapLocally(p, before, 'b'), contains('fixée'));
    expect(
      tables(p).map((t) => [t['x'], t['y']]),
      tables(before).map((t) => [t['x'], t['y']]),
    );
  });
  test(
    'An obstacle blocks the opening without excluding or moving any table',
    () {
      final p = row();
      rows(p, 'items').add({
        'id': 'obstacle',
        'kind': 'obstacle',
        'x': 9.25,
        'y': 2.0,
        'w': 1.0,
        'h': 1.0,
      });
      final before = clone(p);
      tables(p)[1]['joinGap'] = .1;
      expect(applyTableJoinGapLocally(p, before, 'b'), contains('bloquée'));
      expect(tables(p).map((t) => t['x']), tables(before).map((t) => t['x']));
      expect(tables(p).any((t) => t['unplacedByArrangement'] == true), false);
    },
  );
  test('Parcours junctions can be opened without redistributing the plan', () {
    final p = row()..['joining'] = 'Aucun';
    for (final t in tables(p)) {
      t['parcoursBlock'] = 'row';
    }
    final before = clone(p);
    tables(p)[1]['joinGap'] = .1;
    expect(applyTableJoinGapLocally(p, before, 'b'), contains('appliquée'));
    expect(number(tables(p)[2]['x']), closeTo(5.7, 1e-8));
  });
}
