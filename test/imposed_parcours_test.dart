import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/parcours.dart';

import 'parcours_test.dart' show market, noOverlap, simpleLoop;
import 'joining_test.dart' show table;

Json perimeterMarket({int extras = 0}) {
  final p = market(
    count: 0,
    wall: 'Haut + bas',
    exit: false,
    orientation: 'Automatique',
  );
  p['room'].addAll({'width': 25.0, 'height': 12.0});
  p['aisle'] = 1.2;
  p['parcoursSettings']['imposedLoop'] = true;
  rows(p, 'items').first['y'] = 4.8;
  rows(p, 'items').first['h'] = 2.0;
  rows(p, 'items').addAll([
    for (var i = 0; i < 35 + extras; i++) table('L$i', 0, 0, sides: 'Un côté'),
    for (var i = 0; i < 18; i++)
      table('S$i', 0, 0, w: 1.2, h: .6, capacity: 4, sides: 'Un côté'),
    table('service', 23, 6, w: 1.2, h: .6, capacity: 0),
    {
      'id': 'bar',
      'kind': 'zone',
      'shape': 'rectangle',
      'fixed': false,
      'label': 'Zone fictive',
      'x': 21.5,
      'y': 8.0,
      'w': 3.5,
      'h': 4.0,
      'zoneFill': 'Hachures',
      'parcoursAccess': 'À desservir',
    },
  ]);
  return p;
}

void main() {
  test('Resizing the entrance preserves the imposed visitor layout', () {
    final p = perimeterMarket(extras: 7);
    arrange(p);
    final entrance = rows(p, 'items').firstWhere((i) => i['kind'] == 'entry');
    entrance.addAll({'w': 1.8, 'h': 4.0, 'y': 3.5});
    arrange(p);
    expect(p['arrangementMode'], 'Parcours');
    expect(tables(p).any((t) => t['parcoursRole'] == 'spine'), true);
    expect(parcoursWarnings(p), isEmpty);
    noOverlap(p);
    simpleLoop(p);
    validateProject(p);
  });
  test('Added mixed tables extend single wall rows around a double-row visitor loop', () {
    final initial = perimeterMarket();
    arrange(initial);
    final initialCount = tables(initial)
        .where((t) => !unplacedTable(initial, t))
        .length;
    final larger = perimeterMarket(extras: 7);
    arrange(larger);
    expect(parcoursWarnings(larger), isEmpty);
    noOverlap(larger);
    simpleLoop(larger);
    final placed = tables(larger)
        .where((t) => !unplacedTable(larger, t))
        .length;
    expect(placed, greaterThan(initialCount));
    final walls = tables(larger)
        .where((t) => t['parcoursRole'] == 'wall')
        .toList();
    expect(walls, isNotEmpty);
    for (final t in walls) {
      expect(number(t['y']), greaterThanOrEqualTo(.6 - 1e-8));
      expect(number(t['y']) + number(t['h']), closeTo(1.4, 1e-8));
      expect(t['seatSide'], 'Haut');
    }
    expect(
      tables(larger)
          .where((t) => (number(t['y']) + number(t['h']) - 12).abs() < 1e-8)
          .every((t) => number(t['w']) <= number(t['h'])),
      true,
    );
    expect(larger['parcoursPlan']['services'].single['id'], 'bar');
    final groups = <String, List<Json>>{};
    for (final t in tables(
      larger,
    ).where((t) => ['upper', 'lower'].contains(t['parcoursRole']))) {
      groups
          .putIfAbsent('${t['parcoursBlock']}/${t['parcoursRole']}', () => [])
          .add(t);
    }
    expect(
      groups.values.any(
        (row) => row.map((t) => number(t['w'])).toSet().length > 1,
      ),
      true,
    );
    for (final row in groups.values) {
      final outer = row.first['parcoursRole'] == 'upper'
          ? number(row.first['x'])
          : number(row.first['x']) + number(row.first['w']);
      for (final t in row) {
        expect(
          t['parcoursRole'] == 'upper'
              ? number(t['x'])
              : number(t['x']) + number(t['w']),
          closeTo(outer, 1e-8),
        );
      }
    }
    validateProject(larger);
  });
  for (final wall in ['Mur gauche', 'Mur droit', 'Mur haut', 'Mur bas']) {
    test(
      'Imposed loop honours $wall and preserves every physical table size',
      () {
        final vertical = wall == 'Mur haut' || wall == 'Mur bas';
        final p = market(
          count: 42,
          wall: wall,
          exit: false,
          orientation: vertical ? 'Verticale' : 'Horizontale',
        );
        p['room'].addAll({'width': 18.0, 'height': 18.0});
        p['parcoursSettings']['imposedLoop'] = true;
        final areas = {
          for (final t in tables(p)) t['id']: number(t['w']) * number(t['h']),
        };
        arrange(p);
        expect(parcoursWarnings(p), isEmpty);
        noOverlap(p);
        simpleLoop(p);
        expect(
          tables(p).where((t) => t['parcoursRole'] == 'spine'),
          isNotEmpty,
        );
        for (final t in tables(p)) {
          expect(
            number(t['w']) * number(t['h']),
            closeTo(areas[t['id']]!, 1e-8),
          );
        }
        validateProject(p);
      },
    );
  }
  test('Missing wall support explicitly reports that a unique route cannot be imposed', () {
    final p = market(count: 42, exit: false)
      ..['parcoursSettings']['imposedLoop'] = true;
    arrange(p);
    expect(parcoursWarnings(p).any((w) => w.contains('chemin unique')), true);
  });
  test(
    'An imposed loop has a continuous spine and alternating sealed ends',
    () {
      final p = market(count: 42, wall: 'Tous les murs', exit: false);
      p['room'].addAll({'width': 18.0, 'height': 12.0});
      p['parcoursSettings']['imposedLoop'] = true;
      arrange(p);
      expect(parcoursWarnings(p), isEmpty);
      final spine = tables(p)
          .where((t) => t['parcoursRole'] == 'spine')
          .toList();
      expect(spine, isNotEmpty);
      noOverlap(p);
      simpleLoop(p);
      final blocks = (p['parcoursPlan']['blocks'] as List)
          .where((b) => !['spine', 'wall'].contains(b['role']))
          .toList();
      expect(blocks.length, greaterThanOrEqualTo(2));
      for (var i = 0; i < blocks.length; i++) {
        final b = blocks[i];
        if (i.isEven) {
          expect(
            number(b['x']),
            closeTo(number(spine.first['x']) + number(spine.first['w']), 1e-6),
          );
        } else {
          expect(number(b['x']) + number(b['w']), closeTo(18, 1e-6));
        }
      }
    },
  );
  test('Only a connection end can touch a wall in parcours mode', () {
    final p = market(wall: 'Tous les murs', exit: false);
    final broad = table('broad', .6, 8.2, sides: 'Un côté')
      ..['seatSide'] = 'Haut';
    expect(wallClearanceFits(p, broad), false);
    expect(wallEdges(p, broad), isEmpty);
    final end = table('end', 0, 2, sides: 'Un côté')..['seatSide'] = 'Bas';
    expect(wallClearanceFits(p, end), true);
    expect(wallEdges(p, end), {'left'});
  });
}
