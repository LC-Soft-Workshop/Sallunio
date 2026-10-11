import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/parcours.dart';

import 'joining_test.dart' show table;
import 'parcours_test.dart' show market, noOverlap;
import 'open_parcours_test.dart' show simpleOpen;

Json perimeterZoneMarket() {
  final p = market(
    count: 0,
    wall: 'Haut + bas',
    exit: false,
    orientation: 'Automatique',
  );
  p['room'].addAll({'width': 25.0, 'height': 12.0});
  p['aisle'] = 1.2;
  p['parcoursSettings'].addAll({
    'circulation': 'Fermé',
    'wallLayout': 'Alterné',
    'imposedLoop': true,
  });
  rows(p, 'items').clear();
  rows(p, 'items').addAll([
    {
      'id': 'entry',
      'kind': 'entry',
      'label': 'Entrée fictive',
      'x': 0.0,
      'y': 5.0,
      'w': 1.0,
      'h': 1.8,
      'fixed': false,
    },
    {
      'id': 'bar',
      'kind': 'zone',
      'label': 'Bar fictif',
      'x': 21.0,
      'y': 8.0,
      'w': 4.0,
      'h': 4.0,
      'fixed': false,
      'parcoursAccess': 'À desservir',
    },
    {
      'id': 'exit',
      'kind': 'exit',
      'label': 'Sortie fictive',
      'x': 24.0,
      'y': 6.5,
      'w': 1.0,
      'h': 1.0,
      'fixed': false,
    },
    {
      'id': 'zone',
      'kind': 'zone',
      'label': 'Zone fictive',
      'x': 23.5,
      'y': 0.0,
      'w': 1.5,
      'h': 1.5,
      'fixed': false,
      'parcoursAccess': 'À exclure',
    },
    for (var i = 0; i < 30; i++) table('L$i', 0, 0, sides: 'Un côté'),
    for (var i = 0; i < 42; i++)
      table('S$i', 0, 0, w: 1.2, h: .6, capacity: 4, sides: 'Un côté'),
  ]);
  return p;
}

void main() {
  test('Perimeter zone preserves a full-width closed return passage', () {
    final p = perimeterZoneMarket();
    final before = clone(p);
    arrange(p);
    expect(parcoursWarnings(p), isEmpty);
    expect(parcoursPaths(p), isNotEmpty);
    expect(parcoursPaths(p).first.first, parcoursPaths(p).first.last);
    expect(parcoursUnservedTables(p), isEmpty);
    expect(tables(p).where((t) => unplacedTable(p, t)), isEmpty);
    expect(
      (p['parcoursPlan']['services'] as List).any((s) => s['id'] == 'bar'),
      true,
    );
    final spine = tables(p).where((t) => t['parcoursRole'] == 'spine');
    expect(spine, isNotEmpty);
    for (final t in spine) {
      expect(number(t['y']), greaterThanOrEqualTo(1.5 + 1.2 - 1e-8));
    }
    noOverlap(p);
    simpleOpen(p);
    for (final original in rows(
      before,
      'items',
    ).where((i) => i['kind'] != 'table')) {
      expect(
        rows(p, 'items').firstWhere((i) => i['id'] == original['id']),
        original,
      );
    }
    expect(p['parcoursSettings'], before['parcoursSettings']);
  });
}
