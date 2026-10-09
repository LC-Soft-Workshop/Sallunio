import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'file_dialogs_test.dart' show TestStore;

Json fixture() {
  final p = demoProject();
  p['groups'] = [rows(p, 'groups').first];
  rows(p, 'groups').first.addAll({
    'name': 'Camy',
    'count': 2,
    'alloc': <Json>[],
    'needs': '',
    'placementReview': true,
  });
  return p;
}

void main() {
  test('Resolved allocation clears warnings even with legacy review flag', () {
    final p = fixture(), g = rows(p, 'groups').single;
    expect(issues(p), contains('Camy : 0/2 places attribuées.'));
    g['alloc'] = [
      {'table': tables(p).first['id'], 'count': 2},
    ];
    expect(issues(p).where((s) => s.startsWith('Camy')), isEmpty);
    g['alloc'] = <Json>[];
    expect(issues(p), contains('Camy : 0/2 places attribuées.'));
  });
  test('Comfort uses current occupancy and tolerates metric rounding', () {
    final p = fixture(), t = tables(p).first, g = rows(p, 'groups').single;
    t['w'] = 1.7999999999999998;
    expect(comfortableCapacity(t), 6);
    t['w'] = 1.2;
    expect(issues(p).where((s) => s.contains('confort insuffisant')), isEmpty);
    expect(
      preparationNotes(p).any((s) => s.contains('repère de confort 4')),
      true,
    );
    g['count'] = 6;
    g['alloc'] = [
      {'table': t['id'], 'count': 6},
    ];
    expect(issues(p).any((s) => s.contains('confort insuffisant')), true);
    t['w'] = 1.8;
    expect(issues(p).where((s) => s.contains('confort insuffisant')), isEmpty);
  });
  test(
    'Anonymous companion faults clear when corrected; PMR is information',
    () {
      final p = fixture(), g = rows(p, 'groups').single;
      g['alloc'] = [
        {'table': tables(p).first['id'], 'count': 2},
      ];
      g['seats'] = [
        {'number': 1, 'need': 'Fauteuil', 'companion': '3'},
      ];
      expect(issues(p).any((s) => s.contains('accompagnant invalide')), true);
      g['seats'][0]['companion'] = '2';
      expect(issues(p).where((s) => s.startsWith('Camy')), isEmpty);
      expect(preparationNotes(p).any((s) => s.contains('Fauteuil')), true);
    },
  );
  test(
    'Proximity moves from pending information to current conflict, then clears',
    () {
      final p = fixture(), g = rows(p, 'groups').single;
      final other = clone(g)
        ..addAll({'id': 'other', 'name': 'Autre', 'placementReview': false});
      rows(p, 'groups').add(other);
      g['proximity'] = {'other': 'near'};
      expect(issues(p).where((s) => s.contains('proximité')), isEmpty);
      expect(
        reservationPreferenceChecks(p).any((s) => s.contains('non vérifiable')),
        true,
      );
      final ts = tables(p);
      g['alloc'] = [
        {'table': ts[0]['id'], 'count': 2},
      ];
      other['alloc'] = [
        {'table': ts[2]['id'], 'count': 2},
      ];
      expect(
        reservationPreferenceChecks(p)
            .any((s) => s.contains('préférence proche')),
        true,
      );
      ts[2]['x'] = ts[0]['x'] + 2.8;
      expect(issues(p).where((s) => s.contains('préférence')), isEmpty);
      expect(
        reservationPreferenceChecks(p)
            .where((s) => s.contains('non vérifiable')),
        isEmpty,
      );
    },
  );
  testWidgets(
    'Manual allocation refreshes controls and undo restores missing places warning',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TestStore()..project = fixture();
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contrôles').first);
      await tester.pumpAndSettle();
      expect(find.text('Camy : 0/2 places attribuées.'), findsOneWidget);
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tables').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            )
            .first,
        '2',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contrôles').first);
      await tester.pumpAndSettle();
      expect(find.text('Camy : 0/2 places attribuées.'), findsNothing);
      expect(find.textContaining('effectif modifié'), findsNothing);
      await tester.tap(find.byTooltip('Annuler'));
      await tester.pumpAndSettle();
      expect(find.text('Camy : 0/2 places attribuées.'), findsOneWidget);
    },
  );
}
