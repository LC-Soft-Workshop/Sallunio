import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/event_backup.dart';
import 'package:tableo/main.dart';

import 'joining_test.dart' show table, plan;
import 'attributions_test.dart' show SnapshotStore, desktop;
import 'join_gap_ui_test.dart' show save;
import 'parcours_test.dart' show market;

import 'package:tableo/parcours.dart';

Json comfortPlan() {
  final p = plan([
    table('a', 3, 3, w: 3, capacity: 10),
    table('b', 10, 3, w: 3, capacity: 10),
  ], 'Aucun');
  p['room']['width'] = 18.0;
  p['room']['height'] = 12.0;
  p['comfort'] = {...comfortableDefaults(p), 'seatWidth': .6};
  p['groups'] = <Json>[];
  return p;
}

void main() {
  test('Comfort applies to a generated parcours and invalidates it only on a real setting change', () {
    final p = market(count: 8);
    p['comfort'] = comfortableDefaults(p);
    arrangeParcours(p);
    expect(parcoursCurrent(p), true);
    expect(tables(p).any((t) => !unplacedTable(p, t)), true);
    expect(
      issues(p).where((s) => s.contains('chevauchement physique')),
      isEmpty,
    );
    validateProject(p);
    p['comfort']['parcoursWallGap'] = 1.1;
    expect(parcoursCurrent(p), false);
  });

  test(
    'Automatic standard arrangement respects event comfort without overlap',
    () {
      final p = comfortPlan();
      for (final t in tables(p)) {
        t['x'] = 0.0;
        t['y'] = 0.0;
      }
      arrange(p);
      expect(tables(p).every((t) => !unplacedTable(p, t)), true);
      expect(
        issues(p).where(
          (s) =>
              s.contains('chevauchement') ||
              s.contains('passage inférieur') ||
              s.contains('au mur'),
        ),
        isEmpty,
      );
      validateProject(p);
    },
  );

  test('Legacy comfort remains unchanged, presets depend on meals and remain event-specific', () {
    final p = plan([table('a', 2, 2)], 'Aucun');
    expect(eventTableGap(p), .9);
    expect(eventWallGap(p), .45);
    expect(effectiveCapacity(p, tables(p).single), 6);
    expect(comfortableDefaults(p)['tableGap'], 2.4);
    final other = clone(p)..['mealService'] = 'Non';
    expect(comfortableDefaults(other)['tableGap'], 2.2);
    p['comfort'] = comfortableDefaults(p);
    expect(effectiveCapacity(p, tables(p).single), 4);
    expect(effectiveCapacity(other, tables(other).single), 6);
    validateProject(p);
    final restored = readEventBackup(jsonEncode(eventBackup([p]))).single;
    expect(restored['comfort'], p['comfort']);
  });
  test('Free aisles add seating once, PMR circulation and wall clearance are applied', () {
    final p = comfortPlan();
    expect(eventTableGap(p), closeTo(2.4, 1e-8));
    p['groups'] = <Json>[
      {
        'id': 'g',
        'name': 'PMR',
        'count': 1,
        'meal': 'Normal',
        'needs': 'Fauteuil',
        'allergy': '',
        'alloc': <Json>[],
        'locked': false,
      },
    ];
    expect(eventCirculation(p), 1.5);
    expect(eventTableGap(p), closeTo(2.7, 1e-8));
    final a = tables(p).first;
    a['adaptedPlaces'] = <Json>[
      {'slot': 0, 'width': .8, 'depth': 1.0},
    ];
    final geo = PlanGeometry(p, rows(p, 'items'));
    expect(adaptedPlaces(geo.view(a)).first['width'], .9);
    expect(adaptedPlaces(geo.view(a)).first['depth'], 1.3);
    expect(adaptedPlaces(a).first['depth'], 1.0);
    a['y'] = .9;
    expect(wallClearanceFits(p, a), false);
    a['y'] = 3.0;
    expect(wallClearanceFits(p, a), true);
    final b = tables(p).last;
    b['x'] = 8.0;
    expect(fits(p, b, rows(p, 'items')), false);
  });
  test(
    'Parcours uses public aisle, private vendor gap and its own wall reserve',
    () {
      final p = comfortPlan();
      p['arrangementMode'] = 'Parcours';
      expect(eventTableGap(p), 1.2);
      expect(eventExhibitorGap(p), 1.4);
      expect(eventWallGap(p), .8);
      p['comfort']['parcoursWallGap'] = 1.0;
      expect(eventWallGap(p), 1.0);
      expect(eventComfort(p)['wallGap'], 1.8);
    },
  );
  test('PMR allocation and individual seat favour a marked main aisle, fixed assignment preserved', () {
    final p = comfortPlan();
    final ts = tables(p);
    for (final t in ts) {
      t['adaptedPlaces'] = <Json>[
        {'slot': 3, 'width': .9, 'depth': 1.3},
        {'slot': 4, 'width': .9, 'depth': 1.3},
      ];
    }
    rows(p, 'items').add({
      'id': 'aisle',
      'kind': 'zone',
      'label': 'Allée',
      'shape': 'rectangle',
      'x': 0.0,
      'y': 0.0,
      'w': 1.5,
      'h': 12.0,
      'fixed': false,
      'mainAisle': 'Oui',
    });
    final group = <String, dynamic>{
      'id': 'g',
      'name': 'Fictif',
      'count': 1,
      'meal': 'Normal',
      'needs': 'Fauteuil',
      'allergy': '',
      'alloc': <Json>[],
      'locked': false,
    };
    p['groups'] = <Json>[group];
    allocate(p);
    expect(assignedTables(p, group).single['id'], 'a');
    expect(tablePeople(p, ts.first)[4]?['group']['id'], 'g');
    group['locked'] = true;
    group['alloc'] = <Json>[
      {'table': 'b', 'count': 1},
    ];
    allocate(p);
    expect(assignedTables(p, group).single['id'], 'b');
  });
  test('Invalid and inconsistent comfort is rejected', () {
    final p = comfortPlan();
    p['comfort']['seatWidth'] = double.nan;
    expect(() => validateProject(p), throwsFormatException);
    p['comfort'] = comfortableDefaults(p);
    p['comfort']['pmrAisleWidth'] = .8;
    expect(() => validateProject(p), throwsFormatException);
  });
  testWidgets(
    'Event comfort saves decimal comma and can be cancelled without moving tables',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore();
      final positions = clone({
        'items': store.saved['items'],
        'groups': store.saved['groups'],
      });
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('plan-tool-settings')));
      await tester.tap(find.byKey(const ValueKey('plan-tool-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confort').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('comfort-recommended')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('comfort-seatWidth'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '0,60');
      await save(tester);
      expect(store.saved['comfort']['seatWidth'], .6);
      expect(store.saved['items'], positions['items']);
      expect(store.saved['groups'], positions['groups']);
      await tester.ensureVisible(find.byKey(const ValueKey('plan-tool-settings')));
      await tester.tap(find.byKey(const ValueKey('plan-tool-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confort').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(field);
      await tester.enterText(field, '0,80');
      await tester.tap(find.text('Annuler').last);
      await tester.pumpAndSettle();
      expect(store.saved['comfort']['seatWidth'], .6);
      expect(tester.takeException(), isNull);
    },
  );
}
