import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

import 'joining_test.dart' show table, plan;

void main() {
  test('Different widths join with centred short faces, manually and automatically', () {
    final a = table('a', 2, 1, w: .8, h: 1.8);
    final b = table('b', 2.125, 2.88, w: .75, h: 1.2);
    final p = plan([a, b], 'Petits côtés');
    final snapped = snapToJoin(p, b, [a, b]);
    expect(snapped['x'], closeTo(2.025, 1e-8));
    expect(snapped['y'], closeTo(2.8, 1e-8));
    expect(joinedEdges(p, a, snapped), ('bottom', 'top'));
    expect(fits(p, snapped, [a]), true);
    final automatic = findPosition(p, b, [a])!;
    expect(joinedEdges(p, a, automatic), isNotNull);
    p['joining'] = 'Grands côtés';
    expect(joinedEdges(p, a, snapped), isNull);
  });
  test(
    'Different heights join on centred long sides, circles remain separate',
    () {
      final a = table('a', 2, 2, w: .8, h: 1.8);
      final b = table('b', 2.8, 2.3, w: .75, h: 1.2);
      final p = plan([a, b], 'Grands côtés');
      expect(joinedEdges(p, a, b), ('right', 'left'));
      b['shape'] = 'cercle';
      expect(joinedEdges(p, a, b), isNull);
    },
  );
  test(
    'One selected wall supports tables and removes seats on that side only',
    () {
      final a = table('a', 0, 1, w: .8, h: 1.8);
      final p = plan([a], 'Aucun')..['wallSupport'] = 'Mur gauche';
      expect(fits(p, a, []), true);
      expect(effectiveCapacity(p, a), 3);
      a['x'] = 11.2;
      expect(fits(p, a, []), false);
      a['x'] = .1;
      expect(snapToJoin(p, a, [a])['x'], 0);
    },
  );
  test('Central aisle is a user-created zone', () {
    final a = table('a', 5.7, 1, w: .8, h: 1.8);
    final p = plan([a], 'Aucun')
      ..['wallSupport'] = 'Gauche + droit / allée centrale';
    p['items'].add({
      'id': 'zone',
      'kind': 'zone',
      'label': 'Libre',
      'x': 5.5,
      'y': 0.0,
      'w': 1.0,
      'h': 9.0,
    });
    expect(fits(p, a, rows(p, 'items')), false);
    a['x'] = 11.2;
    expect(fits(p, a, []), true);
  });
}
