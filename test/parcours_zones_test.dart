import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/parcours.dart';

import 'parcours_test.dart' show market, noOverlap, simpleLoop;
import 'joining_test.dart' show table;

Json servicePlan({bool selected = true}) {
  final p = market(count: 20);
  p['room']['width'] = 18.0;
  p['room']['height'] = 12.0;
  rows(
    p,
    'items',
  ).firstWhere((i) => i['kind'] == 'exit').addAll({'x': 17.4, 'y': 11.4});
  rows(p, 'items').add({
    'id': 'bar',
    'kind': 'zone',
    'shape': 'rectangle',
    'fixed': false,
    'label': 'Bar fictif',
    'x': 8.0,
    'y': 4.0,
    'w': 2.0,
    'h': 2.0,
    'zoneFill': 'Plein',
    'zoneColor': 'Bleu',
    'parcoursAccess': selected ? 'À desservir' : 'À exclure',
  });
  return p;
}

void main() {
  test('A selected bar belongs to the single-entry loop without an out-and-back branch', () {
    final p = servicePlan();
    rows(p, 'items').removeWhere((i) => i['kind'] == 'exit');
    arrange(p);
    simpleLoop(p);
    final services = p['parcoursPlan']['services'] as List;
    expect(services.single['id'], 'bar');
    expect(parcoursWarnings(p), isEmpty);
    noOverlap(p);
  });
  test('Selected bar is visited on its accessible edge, with one full passage free of tables', () {
    final p = servicePlan();
    arrange(p);
    expect(parcoursWarnings(p), isEmpty);
    noOverlap(p);
    final service = (p['parcoursPlan']['services'] as List).single;
    expect(service['id'], 'bar');
    final point = Point(
      number(service['point'][0]),
      number(service['point'][1]),
    );
    final zone = rows(p, 'items').firstWhere((i) => i['id'] == 'bar');
    final dx = max(
      0.0,
      max(
        number(zone['x']) - point.x,
        point.x - number(zone['x']) - number(zone['w']),
      ),
    );
    final dy = max(
      0.0,
      max(
        number(zone['y']) - point.y,
        point.y - number(zone['y']) - number(zone['h']),
      ),
    );
    expect(sqrt(dx * dx + dy * dy), closeTo(number(p['aisle']) / 2, 1e-6));
    expect(parcoursPaths(p).first.contains(point), true);
    final buffer = {...zone, 'x': 7.1, 'y': 3.1, 'w': 3.8, 'h': 3.8};
    for (final t in tables(p)) {
      expect(overlaps(t, buffer), false);
    }
    validateProject(p);
  });
  test(
    'Unselected zones are not added as stops and stay physically excluded',
    () {
      final p = servicePlan(selected: false);
      arrange(p);
      expect(p['parcoursPlan']['services'], isEmpty);
      noOverlap(p);
    },
  );
  test(
    'An unreachable service zone is reported rather than silently omitted',
    () {
      final p = servicePlan();
      rows(p, 'items').add({
        'id': 'blocked',
        'kind': 'obstacle',
        'shape': 'rectangle',
        'fixed': true,
        'label': 'Obstacle fictif',
        'x': 7.0,
        'y': 3.0,
        'w': 4.0,
        'h': 4.0,
      });
      arrange(p);
      expect(
        parcoursWarnings(p)
            .any((w) => w.contains('zone') && w.contains('non desservie')),
        true,
      );
      expect(p['parcoursPlan']['services'], isEmpty);
    },
  );
  test('Invisible public aisles forbid furniture but connect the bar and distant areas', () {
    final p = market(count: 0, wall: 'Tous les murs', exit: false);
    p['room'].addAll({'width': 25.0, 'height': 12.0});
    p['aisle'] = 1.2;
    p['items'] = <Json>[
      {
        'id': 'entry',
        'kind': 'entry',
        'shape': 'rectangle',
        'fixed': false,
        'label': 'Entrée fictive',
        'x': 0.0,
        'y': 4.8,
        'w': 1.0,
        'h': 2.0,
      },
      {
        'id': 'bar',
        'kind': 'zone',
        'shape': 'rectangle',
        'fixed': false,
        'label': 'Bar fictif',
        'x': 10.0,
        'y': 4.0,
        'w': 3.7,
        'h': 4.0,
        'zoneFill': 'Plein',
        'parcoursAccess': 'À desservir',
      },
      {
        'id': 'h-aisle',
        'kind': 'zone',
        'shape': 'rectangle',
        'fixed': false,
        'label': 'Allée horizontale',
        'x': 1.4,
        'y': 4.5,
        'w': 22.2,
        'h': 3.0,
        'zoneFill': 'Invisible',
        'parcoursPassage': 'Oui',
      },
      {
        'id': 'v-aisle',
        'kind': 'zone',
        'shape': 'rectangle',
        'fixed': false,
        'label': 'Allée verticale',
        'x': 10.2,
        'y': .3,
        'w': 3.5,
        'h': 11.5,
        'zoneFill': 'Invisible',
        'parcoursPassage': 'Oui',
      },
      for (var i = 0; i < 26; i++) table('L$i', 0, 0, sides: 'Un côté'),
      for (var i = 0; i < 26; i++)
        table('S$i', 0, 0, w: 1.2, h: .6, capacity: 4, sides: 'Un côté'),
    ];
    final failed = arrange(p);
    expect(failed, lessThanOrEqualTo(12));
    noOverlap(p);
    expect(parcoursWarnings(p), isEmpty);
    expect(p['parcoursPlan']['services'].single['id'], 'bar');
    expect(parcoursPaths(p).first.first, parcoursPaths(p).first.last);
    simpleLoop(p);
    final copy = clone(p);
    validateProject(copy);
    copy['parcoursPlan']['services'] = 'invalid';
    expect(() => validateProject(copy), throwsFormatException);
  });
  test('Changing zone selection invalidates stale routes and preserves other geometry', () {
    final p = servicePlan(selected: false);
    arrange(p);
    final zone = rows(p, 'items').firstWhere((i) => i['id'] == 'bar');
    zone['parcoursAccess'] = 'À desservir';
    expect(parcoursCurrent(p), false);
    arrange(p);
    expect(p['parcoursPlan']['services'].single['id'], 'bar');
    zone['parcoursPassage'] = 'bad';
    expect(() => validateProject(p), throwsFormatException);
  });
}
