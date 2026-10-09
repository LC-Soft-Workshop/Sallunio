import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'file_dialogs_test.dart' show TestStore;
import 'preparation_checks_test.dart' show fixture;

Json oneSidePlan() {
  final p = fixture();
  final t = clone(tables(p).first);
  t.addAll({
    'x': 2.0,
    'y': 2.0,
    'w': .8,
    'h': 1.8,
    'sides': 'Un côté',
    'seatSide': 'Droite',
    'capacity': 6,
  });
  p['items'] = [t];
  final g = rows(p, 'groups').single;
  g.addAll({
    'count': 6,
    'alloc': <Json>[],
    'locked': false,
    'reserved': '',
    'separate': '',
    'proximity': <String, String>{},
    'seats': <Json>[],
  });
  return p;
}

void main() {
  test('Automatic allocation changes no geometry and creates no comfort error within defined capacity', () {
    final p = oneSidePlan();
    expect(comfortableCapacity(tables(p).single), 3);
    final itemsBefore = clone(p)['items'];
    final notesBefore = preparationNotes(p);
    expect(issues(p).any((s) => s.contains('places attribuées')), true);
    allocate(p);
    expect(allocationSummary(p)['assigned'], 6);
    expect(issues(p), isEmpty);
    expect(p['items'], itemsBefore);
    expect(preparationNotes(p), notesBefore);
    expect(preparationNotes(p).single, contains('repère de confort 3'));
  });

  test('Real capacity and physical conflicts remain alerts even with comfort information', () {
    final p = oneSidePlan();
    final g = rows(p, 'groups').single, t = tables(p).single;
    g['count'] = 7;
    g['alloc'] = [
      {'table': t['id'], 'count': 7},
    ];
    expect(
      issues(p).any((s) => s.contains('capacité utilisable dépassée (6)')),
      true,
    );
    g['count'] = 6;
    g['alloc'][0]['count'] = 6;
    rows(
      p,
      'items',
    ).add({...clone(t), 'id': 'collision', 'label': 'Collision'});
    expect(issues(p).any((s) => s.contains('chevauchement physique')), true);
    expect(issues(p).where((s) => s.contains('confort')), isEmpty);
    rows(p, 'items').last['x'] = number(t['x']) + number(t['w']) + .5;
    expect(issues(p).any((s) => s.contains('passage inférieur')), true);
  });

  testWidgets(
    'Reservation allocation leaves controls clear and the comfort reference informational',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TestStore()..project = oneSidePlan();
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2. Attribuer les groupes aux tables'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('6 / 6 personnes attribuées.'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Voir les attributions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contrôles').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('confort insuffisant'), findsNothing);
      expect(find.text('Informations de préparation'), findsOneWidget);
      expect(find.textContaining('repère de confort 3 places'), findsOneWidget);
      expect(issues(store.project), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
