import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/parcours.dart';

import 'parcours_test.dart' show market, noOverlap, simpleLoop;
import 'open_parcours_test.dart' show lateralEntranceMarket, simpleOpen;

void main() {
  test('Closed entrance to exit forces all frontages with no bypass', () {
    final p = market(count: 22, wall: 'Tous les murs');
    p['room']['width'] = 10.7;
    rows(p, 'items').firstWhere((i) => i['kind'] == 'exit')['x'] = 10.1;
    p['parcoursSettings']['circulation'] = 'Fermé';
    expect(arrange(p), 0);
    expect(parcoursClosed(p), true);
    expect(parcoursWarnings(p), isEmpty);
    expect(parcoursUnservedTables(p), isEmpty);
    simpleOpen(p);
    noOverlap(p);
    validateProject(clone(p));
  });
  test('Lateral exit retains the connected closed maze and every frontage', () {
    final p = lateralEntranceMarket();
    p['parcoursSettings']['circulation'] = 'Fermé';
    final accesses = clone({
      'items': rows(
        p,
        'items',
      ).where((i) => i['kind'] == 'entry' || i['kind'] == 'exit').toList(),
    });
    arrange(p);
    expect(parcoursClosed(p), true);
    expect(parcoursWarnings(p), isEmpty);
    expect(tables(p).any((t) => t['parcoursRole'] == 'spine'), true);
    final loop = parcoursPaths(p).first;
    expect(loop.first, loop.last);
    final cycleOnly = clone(p);
    cycleOnly['parcoursPlan']['paths'] = [p['parcoursPlan']['paths'].first];
    simpleLoop(cycleOnly);
    expect(parcoursUnservedTables(p), isEmpty);
    expect(p['parcoursPlan']['services'].single['id'], 'bar');
    expect({
      'items': rows(
        p,
        'items',
      ).where((i) => i['kind'] == 'entry' || i['kind'] == 'exit').toList(),
    }, accesses);
    noOverlap(p);
    validateProject(p);
  });
  test('Open mode remains explicit and rejects unknown saved modes', () {
    final p = lateralEntranceMarket();
    expect(parcoursClosed(p), false);
    validateProject(p);
    p['parcoursSettings']['circulation'] = 'Autre';
    expect(() => validateProject(p), throwsFormatException);
  });
}
