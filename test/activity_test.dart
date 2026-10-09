import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'ui_test.dart' show MemoryStore;
import 'attributions_test.dart' show desktop;

void main() {
  test('Market profile proposes one seated side and follows rotation', () {
    final p = demoProject();
    p['room'] = <String, dynamic>{
      ...p['room'],
      ...activityDefaults('Brocante'),
    };
    p['items'] = <Json>[];
    p['groups'] = <Json>[];
    final type = rows(p, 'types').first;
    type['capacity'] = 3;
    expect(addFurniture(p, [type]).placed, 1);
    final table = tables(p).single;
    expect(table['sides'], 'Un côté');
    expect(seatedEdges(table).keys, ['bottom']);
    expect(comfortableCapacity(table), 3);
    rotateTable(table, p);
    expect(seatedEdges(table).keys, ['left']);
    expect(mealsEnabled(p), false);
    expect(mealTotals(p), isEmpty);
    validateProject(clone(p));
  });
  testWidgets('New event sets activity and meals before its independent room', (
    tester,
  ) async {
    desktop(tester);
    final old = demoProject(), store = MemoryStore([demoProject()]);
    final previousName = store.projects.first['name'];
    await tester.pumpWidget(Tableo(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Événement'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .first,
      'Marché Noël test',
    );
    final activity = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == 'Activité',
    );
    await tester.tap(activity);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marché de Noël').last);
    await tester.pumpAndSettle();
    expect(find.text('Non'), findsWidgets);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Côtés assis par défaut'), findsNothing);
    expect(find.text('Prévoir des repas'), findsNothing);
    expect(find.text('Activité'), findsNothing);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(store.projects.length, 2);
    expect(store.projects.last['activity'], 'Marché de Noël');
    expect(store.projects.last['defaultSides'], 'Un côté');
    expect(store.projects.last['room']['defaultSides'], isNull);
    expect(store.projects.last['mealService'], 'Non');
    expect(rows(store.projects.last, 'groups'), isEmpty);
    await tester.tap(find.text(previousName));
    await tester.pumpAndSettle();
    expect(find.text('T1\n0/6'), findsOneWidget);
    expect(
      rows(store.projects.first, 'groups').length,
      rows(old, 'groups').length,
    );
    expect(tester.takeException(), isNull);
  });
  test('Meals belong to the event and survive changing rooms', () {
    final p = demoProject();
    p['room']['activity'] = 'Soirée repas';
    p['room']['mealService'] = 'Non';
    expect(eventActivity(p), 'Soirée');
    expect(mealsEnabled(p), false);
    p['mealService'] = 'Oui';
    expect(mealsEnabled(p), true);
    p['room'] = newProject('Autre salle')['room'];
    expect(mealsEnabled(p), true);
    p['mealService'] = 'Non';
    expect(mealsEnabled(p), false);
    expect(roomActivities, contains('Soirée'));
    expect(roomActivities, isNot(contains('Soirée repas')));
  });
  test(
    'Legacy room seating migrates to event and survives room replacement',
    () {
      final p = demoProject();
      p['room']['defaultSides'] = 'Un côté';
      p['room']['mealService'] = 'Non';
      migrateEventSettings(p);
      expect(p['defaultSides'], 'Un côté');
      expect(p['room']['defaultSides'], isNull);
      p['room'] = newProject('Autre')['room'];
      expect(eventSeatingSides(p), 'Un côté');
      expect(mealsEnabled(p), false);
      final type = rows(p, 'types').first..remove('sides');
      p['items'] = <Json>[];
      expect(addFurniture(p, [type]).placed, 1);
      expect(tables(p).single['sides'], 'Un côté');
    },
  );
}
