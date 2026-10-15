import 'dart:math';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/event_backup.dart';
import 'package:tableo/exports.dart';
import 'package:tableo/plan_export.dart';
import 'package:tableo/plan_tools.dart';

import 'joining_test.dart' show table;

Json exhibitor(String id, double metres, {bool share = true}) => {
  'id': id,
  'name': 'Exposant $id',
  'count': 1,
  'meal': 'Normal',
  'allergy': '',
  'needs': '',
  'companion': 'Non',
  'alloc': <Json>[],
  'locked': false,
  'reserved': '',
  'bookingKind': assignmentModes[1],
  'standUnit': standUnits[1],
  'requestedTables': 1,
  'requestedMetres': metres,
  'shareTable': share ? 'Oui' : 'Non',
  'standAlloc': <Json>[],
};
Json standPlan() {
  final p = newProject('Marché fictif');
  p['activity'] = 'Marché de Noël';
  p['mealService'] = 'Non';
  p['items'] = [
    for (var i = 0; i < 4; i++)
      {...table('t$i', 1 + i * 1.8, 2), 'usage': furnitureUses[1]},
  ];
  return p;
}

Json audiencePlan({int count = 24}) {
  final p = newProject('Spectacle fictif');
  p['room']['width'] = 16.0;
  p['room']['height'] = 14.0;
  p['comfort'] = {...comfortableDefaults(p), 'wallGap': .45, 'rowGap': .85};
  p['items'] = <Json>[
    {
      'id': 'scene',
      'kind': 'zone',
      'shape': 'rectangle',
      'label': 'Scène',
      'x': 5.0,
      'y': 0.0,
      'w': 6.0,
      'h': 1.0,
      'fixed': true,
    },
    for (var i = 0; i < count; i++)
      {
        ...table('c$i', 1, 3, w: .5, h: .5, capacity: 1),
        'kind': 'chair',
        'shape': 'chaise',
        'usage': furnitureUses.first,
      },
  ];
  return p;
}

Json seatedGroup(String id, int count) => {
  ...exhibitor(id, 1),
  'bookingKind': assignmentModes.first,
  'count': count,
};
void main() {
  for (final side in seatingSideNames) {
    test(
      'Fan corner wedge excludes near diagonal seats and leaves center clear: $side',
      () {
        final p = audiencePlan(count: 0);
        p['comfort']['sceneGap'] = .2;
        p['comfort']['fanSideGap'] = 0.0;
        final scene = {
          'id': 'scene',
          'kind': 'zone',
          'x': 10.0,
          'y': 10.0,
          'w': side == 'Haut' || side == 'Bas' ? 6.0 : 1.0,
          'h': side == 'Haut' || side == 'Bas' ? 1.0 : 6.0,
        };
        final direction = switch (side) {
          'Haut' => -pi / 2,
          'Gauche' => pi,
          'Droite' => 0.0,
          _ => pi / 2,
        };
        final cx = number(scene['x']) + number(scene['w']) / 2,
            cy = number(scene['y']) + number(scene['h']) / 2;
        final forward = .5 + .2 + sqrt(.125) + .1;
        final seat = {
          ...table(
            'a',
            cx + forward * cos(direction) - 5 * sin(direction) - .25,
            cy + forward * sin(direction) + 5 * cos(direction) - .25,
            w: .5,
            h: .5,
            capacity: 1,
          ),
          'angle': direction * 180 / pi + 45 - 90,
        };
        final settings = {'side': side, 'fanClearanceAngle': 0.0};
        expect(fanStageClearanceFits(p, seat, scene, settings), true);
        p['comfort']['fanSideGap'] = 1.0;
        settings['fanClearanceAngle'] = 30.0;
        expect(fanStageClearanceFits(p, seat, scene, settings), false);
        seat['x'] = number(seat['x']) + 4 * cos(direction);
        seat['y'] = number(seat['y']) + 4 * sin(direction);
        expect(fanStageClearanceFits(p, seat, scene, settings), true);
        final center = {
          ...seat,
          'angle': direction * 180 / pi - 90,
          'x': cx + .95 * cos(direction) - .25,
          'y': cy + .95 * sin(direction) - .25,
        };
        expect(fanStageClearanceFits(p, center, scene, settings), true);
      },
    );
  }

  test(
    'Fan central front row follows event scene gap without angle padding',
    () {
      final p = audiencePlan(count: 60);
      for (final gap in [1.5, .2, 0.0]) {
        p['comfort']['sceneGap'] = gap;
        arrangeAudience(p, {
          'scene': 'scene',
          'layout': audienceLayouts[1],
          'side': 'Bas',
          'leftAngle': 45.0,
          'rightAngle': 45.0,
        });
        final central = tables(p)
            .where(
              (t) => !unplacedTable(p, t) && number(t['angle']).abs() < .001,
            )
            .toList();
        expect(central, isNotEmpty);
        expect(
          central.map((t) => number(t['y']) - 1).reduce(min),
          closeTo(gap, 1e-8),
        );
        validateProject(p);
        for (final t in tables(p).where((t) => !unplacedTable(p, t))) {
          expect(audienceFits(p, t, rows(p, 'items')), true);
        }
      }
    },
  );

  for (final side in seatingSideNames) {
    test(
      'Fan rows and fronts converge toward scene with audience on $side',
      () {
        final p = audiencePlan(count: 60);
        p['comfort']['fanSideGap'] = 0.0;
        p['room'].addAll({'width': 24.0, 'height': 24.0});
        final scene = rows(p, 'items').first;
        scene.addAll(switch (side) {
          'Bas' => {'x': 9.0, 'y': 0.0, 'w': 6.0, 'h': 1.0},
          'Haut' => {'x': 9.0, 'y': 23.0, 'w': 6.0, 'h': 1.0},
          'Gauche' => {'x': 23.0, 'y': 9.0, 'w': 1.0, 'h': 6.0},
          _ => {'x': 0.0, 'y': 9.0, 'w': 1.0, 'h': 6.0},
        });
        arrangeAudience(p, {
          'scene': 'scene',
          'layout': audienceLayouts[1],
          'side': side,
          'leftAngle': 45.0,
          'rightAngle': 45.0,
          'fanClearanceAngle': 0.0,
        });
        final direction = switch (side) {
          'Haut' => -pi / 2,
          'Gauche' => pi,
          'Droite' => 0.0,
          _ => pi / 2,
        };
        final center = Point(
          number(scene['x']) + number(scene['w']) / 2,
          number(scene['y']) + number(scene['h']) / 2,
        );
        final lateral = tables(p)
            .where(
              (t) =>
                  !unplacedTable(p, t) &&
                  (number(t['angle']) - (direction * 180 / pi - 90)).abs() > 1,
            )
            .toList();
        expect(lateral, isNotEmpty);
        for (final t in lateral) {
          final dx = number(t['x']) + number(t['w']) / 2 - center.x,
              dy = number(t['y']) + number(t['h']) / 2 - center.y;
          final along = -dx * sin(direction) + dy * cos(direction);
          final angle = number(t['angle']) * pi / 180;
          final frontX = sin(angle), frontY = -cos(angle);
          expect(
            (-frontX * sin(direction) + frontY * cos(direction)) * along,
            lessThan(0),
          );
          expect(audienceFits(p, t, rows(p, 'items')), true);
        }
        final first = lateral.first;
        final same = lateral
            .where(
              (t) => (number(t['angle']) - number(first['angle'])).abs() < .1,
            )
            .toList();
        final row = same
            .where(
              (t) =>
                  number(t['y']) != number(first['y']) ||
                  number(t['x']) != number(first['x']),
            )
            .toList();
        expect(row, isNotEmpty);
        final firstX = number(first['x']) + number(first['w']) / 2 - center.x,
            firstY = number(first['y']) + number(first['h']) / 2 - center.y;
        final firstAlong = -firstX * sin(direction) + firstY * cos(direction),
            firstForward = firstX * cos(direction) + firstY * sin(direction);
        final neighbour = row.where((t) {
          final x = number(t['x']) + number(t['w']) / 2 - center.x,
              y = number(t['y']) + number(t['h']) / 2 - center.y;
          return ((-x * sin(direction) + y * cos(direction)) - firstAlong)
                  .abs() <
              .7;
        }).first;
        final nextX =
                number(neighbour['x']) + number(neighbour['w']) / 2 - center.x,
            nextY =
                number(neighbour['y']) + number(neighbour['h']) / 2 - center.y;
        final nextAlong = -nextX * sin(direction) + nextY * cos(direction),
            nextForward = nextX * cos(direction) + nextY * sin(direction);
        expect(
          (nextForward - firstForward) / (nextAlong - firstAlong),
          closeTo(firstAlong < 0 ? 1 : -1, .00001),
        );
      },
    );
  }

  test('Autonomous stock creates chairs, benches and PMR footprints that survive backup', () {
    final p = newProject('Stock fictif');
    p['room'].addAll({'width': 20.0, 'height': 16.0});
    for (final shape in ['chaise', 'banc', 'emplacement PMR']) {
      final type = {
        'id': shape,
        'name': shape,
        'shape': shape,
        'w': shape == 'banc' ? 2.2 : .9,
        'h': .5,
        'capacity': shape == 'banc' ? 4 : 1,
        'quantity': 2,
        'limit': 2,
        'source': 'Propre',
        'enabled': true,
        'seating': 'Chaises',
      };
      rows(p, 'types').add(type);
      expect(addFurniture(p, [type], all: true).placed, 2);
      expect(addFurniture(p, [type]).placed, 0);
    }
    validateProject(p);
    final restored = readEventBackup(jsonEncode(eventBackup([p]))).single;
    expect(tables(restored).map((t) => t['kind']).toSet(), {
      'chair',
      'bench',
      'pmr',
    });
    clearRoom(restored, {'obstacles'});
    expect(tables(restored).length, 6);
    clearRoom(restored, {'tables'});
    expect(tables(restored), isEmpty);
    expect(rows(restored, 'types').length, 3);
  });
  test('Legacy locked allocations retain their seat identities when autonomous stock is present', () {
    final p = audiencePlan(count: 4);
    arrangeAudience(p, {
      'scene': 'scene',
      'layout': audienceLayouts.first,
      'side': 'Bas',
    });
    final g = seatedGroup('a', 2);
    g['locked'] = true;
    g['alloc'] = [
      {'table': 'c0', 'count': 1},
      {'table': 'c1', 'count': 1},
    ];
    p['groups'] = [g];
    allocate(p);
    expect(g['seats'][0]['table'], 'c0');
    expect(g['seats'][1]['table'], 'c1');
    final alloc = jsonEncode(g['alloc']);
    setSeatingAssignment(p, 'Libre');
    expect(jsonEncode(g['alloc']), alloc);
  });

  test('Defaults are event-specific but existing furniture and assignments are preserved', () {
    final p = demoProject();
    allocate(p);
    final before = jsonEncode(p['groups']);
    p['activity'] = 'Marché de Noël';
    expect(eventAssignmentMode(p), assignmentModes[1]);
    expect(
      tables(p).every((t) => furnitureUse(t) == furnitureUses.first),
      true,
    );
    expect(jsonEncode(p['groups']), before);
    p['assignmentMode'] = assignmentModes.first;
    expect(eventAssignmentMode(p), assignmentModes.first);
  });
  test(
    'Metres share a table in non-overlapping colored portions and ignore gaps',
    () {
      final p = standPlan();
      p['joinGap'] = .6;
      p['groups'] = [exhibitor('a', 3), exhibitor('b', 1.2)];
      allocate(p);
      final a = rows(p, 'groups').first, b = rows(p, 'groups').last;
      expect((a['standAlloc'] as List).length, 2);
      expect(number(a['standAlloc'][0]['length']), closeTo(1.8, 1e-8));
      expect(number(a['standAlloc'][1]['length']), closeTo(1.2, 1e-8));
      expect(number(b['standAlloc'][0]['offset']), closeTo(1.2, 1e-8));
      expect(standPortions(p, 't1').length, 2);
      expect(
        standPortions(p, 't1')[0]['color'],
        isNot(standPortions(p, 't1')[1]['color']),
      );
      expect(workspaceStats(p)['reserved'], 0);
      expect(standSummary(p)['assignedMetres'], closeTo(4.2, 1e-8));
      validateProject(p);
      expect(
        () => setStandPortion(p, b, tables(p)[1], offset: 0, length: .2),
        throwsFormatException,
      );
      final restored = readEventBackup(jsonEncode(eventBackup([p]))).single;
      expect(restored['groups'], p['groups']);
      expect(eventCsv(p, 'Attributions'), contains('1.20 m'));
      expect(planSvg(p), contains('fill="#80cbc4"'));
    },
  );
  test('Whole tables are exclusive, locked assignments survive, rounds cannot be shared', () {
    final p = standPlan();
    final a = exhibitor('a', 3, share: false), b = exhibitor('b', 1);
    p['groups'] = [a, b];
    allocate(p);
    expect(a['standAlloc'].length, 2);
    expect(standPortions(p, 't1').single['group'], 'a');
    a['locked'] = true;
    final before = jsonEncode(a['standAlloc']);
    allocate(p);
    expect(jsonEncode(a['standAlloc']), before);
    tables(p).last['shape'] = 'cercle';
    expect(
      () => setStandPortion(p, b, tables(p).last, length: .5),
      throwsFormatException,
    );
  });
  test('Bulk usage changes remove only affected allocations and preserve coordinates and rotation', () {
    final p = demoProject();
    allocate(p);
    final t = tables(p).first;
    t['angle'] = 30;
    final position = [t['x'], t['y'], t['w'], t['h'], t['angle']];
    final groups = rows(p, 'groups').length;
    changeFurnitureUsage(p, {t['id'] as String}, furnitureUses[1]);
    expect([t['x'], t['y'], t['w'], t['h'], t['angle']], position);
    expect(rows(p, 'groups').length, groups);
    expect(occupancy(p, t['id']), 0);
    expect(mealsEnabled(p), true);
    p['mealService'] = 'Non';
    changeFurnitureUsage(p, {t['id'] as String}, furnitureUses.first);
    expect(mealsEnabled(p), false);
  });
  test('Bench length and event comfort determine physical numbered places; blocked numbers stay stable', () {
    final p = audiencePlan(count: 0);
    final bench = {
      ...table('bench', 2, 4, w: 2.2, h: .45, capacity: 9),
      'kind': 'bench',
      'shape': 'banc',
      'blockedSlots': [1],
    };
    rows(p, 'items').add(bench);
    expect(effectiveCapacity(p, bench), 4);
    expect(usableSeatCapacity(p, bench), 3);
    final g = seatedGroup('a', 3);
    p['groups'] = [g];
    allocate(p);
    expect((g['seats'] as List).map((s) => s['slot']), [0, 2, 3]);
    expect(tablePeople(p, bench)[1], isNull);
    p['comfort']['benchSeatWidth'] = .7;
    expect(effectiveCapacity(p, bench), 3);
  });
  test('Free placement preserves manual numbered seats and proximity without moving furniture', () {
    final p = audiencePlan(count: 8);
    arrangeAudience(p, {
      'scene': 'scene',
      'layout': audienceLayouts.first,
      'side': 'Bas',
    });
    final g = seatedGroup('a', 4);
    p['groups'] = [g];
    allocate(p);
    final physical = jsonEncode(tables(p));
    g['seats'][0]['fixed'] = true;
    final first = clone(g['seats'][0]);
    g['placeProximity'] = {'scene': 'near'};
    rows(p, 'items').first['proximityEnabled'] = 'Oui';
    setSeatingAssignment(p, 'Libre');
    allocate(p);
    expect(g['alloc'].single['count'], 1);
    expect(g['seats'][0], first);
    expect(jsonEncode(tables(p)), physical);
    expect(reservationPreferenceChecks(p), isEmpty);
    expect(g['placeProximity'], {'scene': 'near'});
    setSeatingAssignment(p, 'Attribué');
    allocate(p);
    expect(g['alloc'].length, 4);
    expect(g['seats'][0], first);
  });
  for (final layout in audienceLayouts) {
    test(
      'Audience layout $layout preserves dimensions and avoids physical overlap',
      () {
        final p = audiencePlan();
        final dims = [
          for (final t in tables(p)) [t['w'], t['h']],
        ];
        final failed = arrangeAudience(p, {
          'scene': 'scene',
          'layout': layout,
          'side': 'Bas',
          'leftAngle': 45.0,
          'rightAngle': 45.0,
          'opening': 100.0,
        });
        expect(failed, 0);
        expect([
          for (final t in tables(p)) [t['w'], t['h']],
        ], dims);
        final ts = tables(p);
        for (var i = 0; i < ts.length; i++) {
          expect(audienceFits(p, ts[i], rows(p, 'items')), true);
          for (var j = i + 1; j < ts.length; j++) {
            expect(rotatedOverlap(ts[i], ts[j]), false);
          }
        }
        if (layout != audienceLayouts.first) {
          expect(ts.any((t) => number(t['angle']) != 0), true);
        }
        validateProject(p);
        expect(planSvg(p), contains('rotate('));
      },
    );
  }
  test('PMR is a reserved footprint without a chair and an accompanying seat stays nearby', () {
    final p = audiencePlan(count: 8);
    rows(p, 'items').add({
      ...table('pmr', 2, 4, w: .9, h: 1.3, capacity: 1),
      'kind': 'pmr',
      'shape': 'emplacement PMR',
    });
    arrangeAudience(p, {
      'scene': 'scene',
      'layout': audienceLayouts.first,
      'side': 'Bas',
    });
    final g = seatedGroup('a', 2);
    g['seats'] = [
      {
        'number': 1,
        'meal': 'Normal',
        'need': 'Fauteuil',
        'allergy': '',
        'companion': '2',
      },
      {
        'number': 2,
        'meal': 'Normal',
        'need': '',
        'allergy': '',
        'companion': '1',
      },
    ];
    p['groups'] = [g];
    allocate(p);
    expect(g['seats'][0]['table'], 'pmr');
    expect(g['seats'][1]['table'], isNotNull);
    expect(
      tables(p).firstWhere((t) => t['id'] == 'pmr')['shape'],
      'emplacement PMR',
    );
  });
  test('Partial import remaps stand and seating references without overwriting current event', () {
    final p = standPlan();
    p['groups'] = [exhibitor('a', 3)];
    allocate(p);
    final target = newProject('Courant');
    final injected = injectEventBackup(
      target,
      [p],
      furniture: true,
      reservations: true,
    );
    expect(injected['name'], 'Courant');
    final g = rows(injected, 'groups').single;
    expect(g['standAlloc'].length, 2);
    expect(
      g['standAlloc'][0]['table'],
      isNot(p['groups'][0]['standAlloc'][0]['table']),
    );
    validateProject(injected);
  });
  test('Stand cards and summary generate a PDF without mutating private preferences', () async {
    final p = standPlan();
    p['groups'] = [exhibitor('a', 3), exhibitor('b', 1)];
    allocate(p);
    p['groups'][0]['proximity'] = {'b': 'far'};
    final original = jsonEncode(p);
    final dir = Directory('tmp/mixed-pdf-test-${uid()}')
      ..createSync(recursive: true);
    try {
      final file = File('${dir.path}/stands.pdf');
      await exportPdf(
        p,
        file.path,
        includePlan: true,
        includeSummary: true,
        includeCards: true,
      );
      expect(file.lengthSync(), greaterThan(1500));
      expect(jsonEncode(p), original);
    } finally {
      final root = Directory('tmp').absolute.path;
      if (dir.absolute.path.startsWith('$root${Platform.pathSeparator}')) {
        dir.deleteSync(recursive: true);
      }
    }
  });
}
