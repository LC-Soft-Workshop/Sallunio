import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:tableo/domain.dart';

import 'package:tableo/parcours.dart';

import 'imposed_parcours_test.dart' show perimeterMarket;

import 'parcours_test.dart' show noOverlap;

import 'joining_test.dart' show table;

Json lateralEntranceMarket() {
  final p = perimeterMarket(extras: 20);
  p['parcoursSettings']['circulation'] = 'Ouvert';

  rows(p, 'items').removeWhere((i) => i['id'] == 'service');

  rows(p, 'items').first.addAll({'y': 5.2, 'h': 1.8, 'w': 1.0});

  rows(p, 'items').add({
    'id': 'exit',

    'kind': 'exit',

    'shape': 'rectangle',

    'label': 'Sortie',

    'x': 24.0,

    'y': 6.5,

    'w': 1.0,

    'h': 1.0,

    'fixed': false,
  });

  return p;
}

void simpleOpen(Json p) {
  for (final route in parcoursPaths(p)) {
    final path = <Point<double>>[];

    for (final point in route) {
      if (path.isEmpty || point.distanceTo(path.last) > 1e-8) path.add(point);
    }

    expect(path.length, greaterThanOrEqualTo(2));

    for (var i = 1; i + 1 < path.length; i++) {
      final a = path[i] - path[i - 1], b = path[i + 1] - path[i];

      expect(
        a.x * b.x + a.y * b.y,

        greaterThanOrEqualTo(-1e-8),

        reason: 'Demi-tour au point $i',
      );
    }

    for (var i = 1; i < path.length; i++) {
      final a = path[i - 1], b = path[i];

      for (var j = i + 2; j < path.length; j++) {
        if (i == 1 && j == path.length - 1 && path.first == path.last) continue;
        final c = path[j - 1], d = path[j];

        final left = max(min(a.x, b.x), min(c.x, d.x)),
            right = min(max(a.x, b.x), max(c.x, d.x));

        final top = max(min(a.y, b.y), min(c.y, d.y)),
            bottom = min(max(a.y, b.y), max(c.y, d.y));

        expect(
          right < left - 1e-8 || bottom < top - 1e-8,

          true,

          reason: 'Segments $i et $j se recoupent',
        );
      }
    }
  }
}

void main() {
  test('Vertical layout integrates every placed frontage and retains a simple path', () {
    final p = lateralEntranceMarket();

    p['parcoursSettings']['orientation'] = 'Verticale';

    arrange(p);

    expect(parcoursWarnings(p), isEmpty);

    expect(parcoursUnservedTables(p), isEmpty);

    simpleOpen(p);

    noOverlap(p);
  });

  test('A simple blue line must not silently ignore tables above a lateral entrance', () {
    final p = newProject('Fictif')
      ..addAll({
        'activity': 'Marché de Noël',

        'arrangementMode': 'Parcours',

        'aisle': 1.2,
      });

    p['room'].addAll({'width': 25.0, 'height': 12.0});

    p['items'] = [
      for (var i = 0; i < 3; i++)
        table('T$i', 1.2, i * 1.8, w: .8, h: 1.8, sides: 'Un côté')
          ..addAll({'seatSide': 'Droite', 'parcoursBlock': 'first'}),
    ];

    p['parcoursPlan'] = {
      'blocks': [
        {'id': 'first', 'x': 1.2, 'y': 0.0, 'w': 2.8, 'h': 10.0},
      ],

      'paths': [
        [
          [.6, 6.0],

          [.6, 10.6],

          [4.6, 10.6],

          [4.6, .6],
        ],
      ],

      'warnings': <String>[],

      'services': <Json>[],

      'signature': parcoursSignature(p),
    };

    simpleOpen(p);

    expect(
      parcoursWarnings(p).any((w) => w.contains('hors du passage visiteurs')),

      true,
    );

    expect(
      parcoursUnservedTables(p).map((t) => t['id']),

      containsAll(['T0', 'T1']),
    );
  });

  test('Lateral entrance and exit use one simple route, serve the bar and fill the terminal space', () {
    final p = lateralEntranceMarket();

    arrange(p);

    expect(parcoursWarnings(p), isEmpty);

    expect(
      tables(p).where((t) => !unplacedTable(p, t)).length,

      greaterThan(61),
    );

    expect(parcoursUnservedTables(p), isEmpty);

    simpleOpen(p);

    noOverlap(p);

    expect(p['parcoursPlan']['services'].single['id'], 'bar');

    expect(
      tables(p)
          .where((t) => !unplacedTable(p, t) && number(t['x']) >= 21)
          .length,

      greaterThan(0),
    );

    final bottomRows = (p['parcoursPlan']['blocks'] as List)
        .cast<Json>()
        .where((b) => b['role'] == 'perimeter' && b['edge'] == 'bottom')
        .toList();
    expect(bottomRows, isNotEmpty);
    final perimeter = (p['parcoursPlan']['blocks'] as List)
        .cast<Json>()
        .where((b) => b['role'] == 'perimeter')
        .toList();
    expect(
      perimeter.map((b) => b['edge']).toSet(),
      containsAll(['top', 'bottom']),
    );
    for (final row in perimeter) {
      final t = tables(p).firstWhere((t) => t['parcoursBlock'] == row['id']);
      final depth = row['edge'] == 'left' || row['edge'] == 'right'
          ? number(row['w']) - number(t['w'])
          : number(row['h']) - number(t['h']);
      expect(depth, closeTo(.6, 1e-6));
    }
    final mainBottom = (p['parcoursPlan']['blocks'] as List)
        .cast<Json>()
        .where((b) => b['role'] != 'perimeter')
        .map((b) => number(b['y']) + number(b['h']))
        .reduce(max);
    for (final row in bottomRows) {
      expect(number(row['y']) - mainBottom, closeTo(number(p['aisle']), 1e-6));
    }
    validateProject(p);
  });
}
