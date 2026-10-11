import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/magnetism.dart';
import 'package:tableo/parcours.dart';

import 'joining_test.dart' show table, type, plan;
import 'imposed_parcours_test.dart' show perimeterMarket;
import 'parcours_test.dart' show noOverlap, simpleLoop;

void main() {
  test('Configured seams remain internal to an assembly of short tables', () {
    final a = table('a', 2, 2, w: .5, h: .3),
        b = table('b', 2.6, 2, w: .5, h: .3),
        c = table('c', 3.2, 2, w: .5, h: .3);
    final p = plan([a, b, c], 'Petits côtés')..['joinGap'] = .1;
    final geo = PlanGeometry(p, rows(p, 'items'));
    expect(geo.sameAssembly(a, c), true);
    expect(geo.internalContact(a, c), true);
  });
  for (final corner in arrangementCorners) {
    test('One-sided instance override remains correct from $corner', () {
      final a = table('a', 4, 4);
      final b = table('b', 7, 7)
        ..addAll({'joinGap': .02, 'joinGapSides': 'Premier bord'});
      final p = plan([a, b], 'Petits côtés')..['arrangementCorner'] = corner;
      expect(arrange(p), 0);
      expect(joinedEdges(p, a, b), isNotNull);
      expect(b.containsKey('_joinEdgeGaps'), false);
    });
  }
  test(
    'Explicit zero and inheritance resolve table, type, then general settings',
    () {
      final t = table('a', 2, 2)..['type'] = 'model';
      final model = type('model');
      final p = plan([t], 'Petits côtés')..['types'] = [model];
      expect(tableJoinEdgeGap(p, t, 'left'), 0);
      p['joinGap'] = .1;
      expect(tableJoinEdgeGap(p, t, 'left'), .1);
      model['joinGap'] = .02;
      expect(tableJoinEdgeGap(p, t, 'left'), .02);
      t['joinGap'] = .03;
      expect(tableJoinEdgeGap(p, t, 'left'), .03);
      t['joinGap'] = 0.0;
      expect(tableJoinEdgeGap(p, t, 'left'), 0);
      propagateFurniture(p, clone(model), {...model, 'joinGap': .15});
      expect(t['joinGap'], 0);
      t.remove('joinGap');
      expect(tableJoinEdgeGap(p, t, 'left'), .02);
      model.remove('joinGap');
      expect(tableJoinEdgeGap(p, t, 'left'), .1);
      validateProject(p);
      expect(tableJoinEdgeGap(clone(p), clone(t), 'left'), .1);
    },
  );
  test('One-sided gaps follow rotation and a shared gap is never doubled', () {
    final a = table('a', 2, 2)
      ..addAll({'joinGap': .1, 'joinGapSides': 'Second bord'});
    final b = table('b', 3.9, 2)..['joinGap'] = .02;
    final p = plan([a, b], 'Petits côtés');
    expect(tableJoinEdgeGap(p, a, 'left'), 0);
    expect(tableJoinEdgeGap(p, a, 'right'), .1);
    expect(tableJoinDistance(p, a, 'right', b, 'left'), .1);
    expect(joinedEdges(p, a, b), ('right', 'left'));
    expect(fits(p, b, rows(p, 'items')), true);
    rotateTable(a);
    expect(tableJoinEdgeGap(p, a, 'bottom'), .1);
    expect(tableJoinEdgeGap(p, a, 'top'), 0);
  });
  test(
    'Single and group magnets use configured junctions, not passage width',
    () {
      final a = table('a', 2, 2), b = table('b', 3.95, 2.03);
      final p = plan([a, b], 'Petits côtés')..['joinGap'] = .1;
      final snap = magneticSnap(p, {'b'});
      expect(snap.active, true);
      expect(snap.dx, closeTo(-.05, 1e-8));
      expect(snap.dy, closeTo(-.03, 1e-8));
      final moved = snapToJoin(p, b, rows(p, 'items'));
      expect(number(moved['x']), closeTo(3.9, 1e-8));
      expect(joinedEdges(p, a, moved), isNotNull);
      expect(joinedEdges(p, a, {...b, 'x': 3.8, 'y': 2.0}), isNull);
      final c = table('c', 5.85, 2.03);
      rows(p, 'items').add(c);
      final groupSnap = magneticSnap(p, {'b', 'c'});
      expect(groupSnap.dx, closeTo(-.05, 1e-8));
      expect(groupSnap.dy, closeTo(-.03, 1e-8));
      final movedC = {
        ...c,
        'x': number(c['x']) + groupSnap.dx,
        'y': number(c['y']) + groupSnap.dy,
      };
      expect(joinedEdges(p, moved, movedC), isNotNull);
    },
  );
  test(
    'Automatic normal layout applies type override and keeps the fixed anchor',
    () {
      final a = table('a', 2, 2)..addAll({'fixed': true, 'type': 'model'});
      final b = table('b', 8, 7)..['type'] = 'model';
      final p = plan([a, b], 'Petits côtés')
        ..addAll({
          'joinGap': .1,
          'types': [type('model')..['joinGap'] = .02],
        });
      expect(arrange(p), 0);
      expect(
        number(b['x']) - number(a['x']) - number(a['w']),
        closeTo(.02, 1e-8),
      );
      expect(joinedEdges(p, a, b), isNotNull);
      expect(a['x'], 2);
      expect(a['y'], 2);
    },
  );
  test(
    'Parcours packing leaves configured seams while preserving a simple loop',
    () {
      final p = perimeterMarket(extras: 7)..['joinGap'] = .1;
      arrange(p);
      expect(parcoursWarnings(p), isEmpty);
      noOverlap(p);
      simpleLoop(p);
      final spine =
          tables(p).where((t) => t['parcoursRole'] == 'spine').toList()
            ..sort((a, b) => number(a['x']).compareTo(number(b['x'])));
      expect(spine.length, greaterThan(1));
      for (var i = 1; i < spine.length; i++) {
        expect(
          number(spine[i]['x']) -
              number(spine[i - 1]['x']) -
              number(spine[i - 1]['w']),
          closeTo(.1, 1e-8),
        );
      }
      validateProject(p);
      expect(parcoursCurrent(p), true);
      p['joinGap'] = .02;
      expect(parcoursCurrent(p), false);
    },
  );
  test(
    'Round tables stay separate and configured gaps do not allow overlaps',
    () {
      final a = table('a', 2, 2), b = table('b', 3.9, 2, shape: 'cercle');
      final p = plan([a, b], 'Les deux')..['joinGap'] = .1;
      expect(joinedEdges(p, a, b), null);
      expect(fits(p, {...a, 'x': 3.5}, rows(p, 'items')), false);
    },
  );
  test('Backups reject invalid gap values at every hierarchy level', () {
    for (final gap in [-.01, double.nan, 2.01, '10']) {
      final p = newProject('Fictif')..['joinGap'] = gap;
      expect(() => validateProject(p), throwsFormatException);
    }
  });
}
