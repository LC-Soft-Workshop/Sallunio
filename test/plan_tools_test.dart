import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/plan_tools.dart';
import 'package:tableo/backup_merge.dart';

void main() {
  test('Removed or reassigned table never blocks editing a named person', () {
    final p = demoProject(), g = rows(p, 'groups')[0], t = tables(p)[0];
    g['seats'] = [
      {
        'number': 1,
        'name': 'Personne fictive',
        'meal': 'Normal',
        'need': 'Fauteuil',
        'allergy': 'fictive',
        'companion': '',
        'table': t['id'],
        'slot': 5,
      },
    ];
    g['alloc'] = [
      {'table': t['id'], 'count': 1},
    ];
    t['capacity'] = 4;
    final draft = clone(g);
    pruneIndividualPlaces(p, draft);
    expect(draft['seats'][0]['table'], t['id']);
    expect(draft['seats'][0].containsKey('slot'), false);
    g['alloc'] = [];
    final unassigned = clone(g), before = clone(g);
    pruneIndividualPlaces(p, unassigned);
    expect(unassigned['seats'][0].containsKey('table'), false);
    expect(unassigned['seats'][0]['name'], 'Personne fictive');
    expect(unassigned['seats'][0]['need'], 'Fauteuil');
    expect(g, before);
  });
  test(
    'Partial import remaps individual places and retains adapted furniture',
    () {
      final target = newProject('Événement fictif'),
          source = demoProject(),
          table = tables(source)[0],
          group = rows(source, 'groups')[0];
      table['adaptedPlaces'] = [
        {'slot': 0, 'width': .9, 'depth': 1.2},
      ];
      group['seats'] = [
        {
          'number': 1,
          'name': 'Personne fictive',
          'meal': 'Normal',
          'need': 'Fauteuil',
          'allergy': '',
          'companion': '',
          'table': table['id'],
          'slot': 0,
        },
      ];
      group['alloc'] = [
        {'table': table['id'], 'count': 1},
      ];
      final plan = BackupMergePlan(
        target,
        [source],
        rooms: false,
        furniture: true,
        reservations: true,
      );
      expect(plan.conflicts, isEmpty);
      final merged = plan.apply({});
      final imported = rows(
        merged,
        'groups',
      ).firstWhere((g) => g['name'] == group['name']);
      final seat = imported['seats'][0];
      expect(seat['name'], 'Personne fictive');
      expect(seat['table'], isNot(table['id']));
      final copiedTable = tables(merged)
          .firstWhere((t) => t['id'] == seat['table']);
      expect(adaptedPlaces(copiedTable), adaptedPlaces(table));
      expect(seat['slot'], 0);
      final reservationsOnly = BackupMergePlan(
        target,
        [source],
        rooms: false,
        furniture: false,
        reservations: true,
      ).apply({});
      expect(
        rows(reservationsOnly, 'groups')[0]['seats'][0].containsKey('table'),
        false,
      );
    },
  );
  test(
    'Rigid selection rotation preserves dimensions, distances and allocations',
    () {
      final p = demoProject();
      final ts = tables(p).take(3).toList();
      for (var i = 0; i < ts.length; i++) {
        ts[i]['x'] = 3.0 + i * 1.8;
        ts[i]['y'] = 3.0;
        ts[i]['fixed'] = false;
      }
      final before = ts.map(clone).toList(),
          groups = rows(p, 'groups').map(clone).toList();
      final distance = tableDistance(ts[0], ts[2]);
      final ids = ts.map((t) => t['id'] as String).toSet();
      transformTableSelection(p, ids, rotate: true);
      expect(tableDistance(ts[0], ts[2]), closeTo(distance, 1e-8));
      for (var i = 0; i < ts.length; i++) {
        expect(ts[i]['w'], before[i]['h']);
        expect(ts[i]['h'], before[i]['w']);
      }
      for (var i = 0; i < 3; i++) {
        transformTableSelection(p, ids, rotate: true);
      }
      for (var i = 0; i < ts.length; i++) {
        expect(number(ts[i]['x']), closeTo(number(before[i]['x']), 1e-8));
        expect(number(ts[i]['y']), closeTo(number(before[i]['y']), 1e-8));
      }
      transformTableSelection(p, ids, dx: 1, dy: .5);
      expect(number(ts[0]['x']), closeTo(number(before[0]['x']) + 1, 1e-8));
      expect(rows(p, 'groups'), groups);
    },
  );
  test(
    'Locked selection is atomic; translation at boundary keeps assembly intact',
    () {
      final p = demoProject(), ts = tables(demoProject());
      p['items'] = ts.take(2).map(clone).toList();
      final a = tables(p)[0], b = tables(p)[1];
      final ids = {a['id'] as String, b['id'] as String};
      b['fixed'] = true;
      final before = clone(p);
      expect(
        () => transformTableSelection(p, ids, dx: 2),
        throwsFormatException,
      );
      expect(p, before);
      b['fixed'] = false;
      a['fixed'] = false;
      final distance = tableDistance(a, b);
      transformTableSelection(p, ids, dx: -100, dy: -100);
      expect(min(number(a['x']), number(b['x'])), closeTo(0, 1e-8));
      expect(tableDistance(a, b), closeTo(distance, 1e-8));
      validateProject(p);
    },
  );
  test(
    'Adapted width reduces capacity; depth changes only its seating edge',
    () {
      final p = demoProject(), table = tables(p)[0];
      table['x'] = table['y'] = 4.0;
      table['adaptedPlaces'] = [
        {'slot': 0, 'width': .9, 'depth': 1.2},
      ];
      expect(effectiveCapacity(p, table), 5);
      final bounds = envelope(table);
      expect(number(bounds['y']), closeTo(2.8, 1e-8));
      expect(
        number(bounds['h']),
        closeTo(number(table['h']) + 1.2 + .55, 1e-8),
      );
      final points = placeLabelPositions(table, 5, {});
      expect(points.length, 5);
      expect(points[0].x, greaterThan(0));
      expect(table['capacity'], 6);
    },
  );
  test('Names, individual placement, companions and split groups follow quantities', () {
    final p = demoProject(), group = rows(p, 'groups')[0], ts = tables(p);
    p['groups'] = [group];
    group['needs'] = '';
    group['count'] = 4;
    ts[0]['adaptedPlaces'] = [
      {'slot': 0, 'width': .9, 'depth': 1.2},
    ];
    group['alloc'] = [
      {'table': ts[0]['id'], 'count': 2},
      {'table': ts[1]['id'], 'count': 2},
    ];
    group['seats'] = List.generate(
      4,
      (i) => {
        'number': i + 1,
        'name': 'Fictif $i',
        'meal': 'Normal',
        'allergy': '',
        'need': i == 0 ? 'Fauteuil' : '',
        'companion': i == 0 ? '2' : '',
        if (i == 1) 'table': ts[0]['id'],
        if (i == 1) 'slot': 1,
      },
    );
    expect(tablePlaceLabels(p, ts[0]).take(2), ['Fictif 0', 'Fictif 1']);
    expect(tablePlaceLabels(p, ts[1]).take(2), ['Fictif 2', 'Fictif 3']);
    expect(assignedPeople(p, group)[2]['table']['id'], ts[1]['id']);
    expect(
      issues(p).any((e) => e.contains('prévoir un emplacement adapté')),
      false,
    );
    resizeReservation(group, 3);
    expect(group['seats'].length, 3);
    expect(tablePlaceLabels(p, ts[1]).whereType<String>(), ['Fictif 2']);
  });
  test('Filters retain capacity and only mark matching physical occupants', () {
    final p = demoProject(), ts = tables(p), group = rows(p, 'groups')[0];
    p['groups'] = [group];
    group['count'] = 2;
    group['needs'] = '';
    group['alloc'] = [
      {'table': ts[0]['id'], 'count': 1},
      {'table': ts[1]['id'], 'count': 1},
    ];
    group['seats'] = [
      {
        'number': 1,
        'meal': 'Normal',
        'need': '',
        'allergy': 'fictive',
        'companion': '',
      },
      {
        'number': 2,
        'meal': 'Végétarien',
        'need': '',
        'allergy': '',
        'companion': '',
      },
    ];
    final geo = PlanGeometry(p, rows(p, 'items')), before = clone(p);
    expect(tableMatchesFilter(p, ts[0], 'Allergie', geo), true);
    expect(tableMatchesFilter(p, ts[1], 'Allergie', geo), false);
    expect(tableMatchesFilter(p, ts[1], 'Repas : Végétarien', geo), true);
    expect(tableMatchesFilter(p, ts[0], 'Repas : Végétarien', geo), false);
    expect(tableMatchesFilter(p, ts[2], 'Tables vides', geo), true);
    expect(p, before);
  });
  test('CSV escapes user text, keeps group counts and excludes private preferences', () {
    final p = demoProject(), g = rows(p, 'groups')[0];
    g['name'] = '=Fictif; "nom"';
    g['note'] = 'secret-note';
    g['proximity'] = {rows(p, 'groups')[1]['id']: 'secret-distance'};
    final before = clone(p), text = eventCsv(p, 'Réservations');
    final csv = parseCsv(text);
    expect(csv.length, rows(p, 'groups').length + 1);
    expect(csv[1][0], "'=Fictif; \"nom\"");
    expect(csv[1][1], '${g['count']}');
    expect(text.contains('secret'), false);
    expect(eventCsv(p, 'Attributions').contains('secret'), false);
    expect(eventCsv(p, 'Totaux des repas').contains('secret'), false);
    expect(p, before);
  });
  test('Malformed adapted and individual metadata rejected on import', () {
    final p = demoProject();
    tables(p)[0]['adaptedPlaces'] = [
      {'slot': 0, 'width': .1, 'depth': 1.2},
    ];
    expect(() => validateProject(p), throwsFormatException);
    tables(p)[0].remove('adaptedPlaces');
    rows(p, 'groups')[0]['seats'] = [
      {
        'number': 1,
        'name': 7,
        'meal': 'Normal',
        'need': '',
        'allergy': '',
        'companion': '',
      },
    ];
    expect(() => validateProject(p), throwsFormatException);
  });
  test('Individual table choice exchanges people without changing group quantities', () {
    final p = demoProject(), g = rows(p, 'groups')[0], ts = tables(p);
    p['groups'] = [g];
    g['count'] = 4;
    g['needs'] = '';
    g['alloc'] = [
      {'table': ts[0]['id'], 'count': 2},
      {'table': ts[1]['id'], 'count': 2},
    ];
    g['seats'] = List.generate(
      4,
      (i) => {
        'number': i + 1,
        'name': 'Fictif $i',
        'meal': 'Normal',
        'need': '',
        'allergy': '',
        'companion': '',
        if (i == 3) 'table': ts[0]['id'],
        if (i == 3) 'slot': 0,
      },
    );
    expect(tablePlaceLabels(p, ts[0]).take(2), ['Fictif 3', 'Fictif 0']);
    expect(tablePlaceLabels(p, ts[1]).take(2), ['Fictif 1', 'Fictif 2']);
    expect(occupancy(p, ts[0]['id']), 2);
    expect(occupancy(p, ts[1]['id']), 2);
    expect(assignedPeople(p, g)[3]['table']['id'], ts[0]['id']);
  });
  test(
    'Quarter turn carries numbered adapted places with the physical table',
    () {
      final p = demoProject(), table = tables(p)[0];
      table['adaptedPlaces'] = [
        {'slot': 0, 'width': .9, 'depth': 1.2},
      ];
      final points = placeLabelPositions(table, 5, {}),
          height = number(table['h']);
      rotateTable(table, p);
      final rotated = placeLabelPositions(table, 5, {});
      for (var i = 0; i < points.length; i++) {
        expect(rotated[i].x, closeTo(height - points[i].y, 1e-8));
        expect(rotated[i].y, closeTo(points[i].x, 1e-8));
      }
    },
  );
}
