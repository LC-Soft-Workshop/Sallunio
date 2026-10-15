import 'dart:convert';
import 'dart:io';

import 'package:tableo/exports.dart';
import 'package:tableo/plan_export.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/event_backup.dart';
import 'package:tableo/plan_tools.dart';

import 'ui_test.dart' show MemoryStore;

void main() {
  test(
    'PDF without meals builds without food legend and preserves source data',
    () async {
      final p = demoProject()..['mealService'] = 'Non';
      final before = clone(p);
      expect(planSvg(p), isNot(contains('Allergie')));
      expect(planSvg(p), isNot(contains('Repas :')));
      Directory('tmp').createSync(recursive: true);
      await exportPdf(
        p,
        'tmp/preferences-no-meals.pdf',
        includeService: true,
        overwriteConfirmed: true,
      );
      expect(
        File('tmp/preferences-no-meals.pdf').lengthSync(),
        greaterThan(1000),
      );
      expect(p, before);
    },
  );

  test(
    'Hidden food markers preserve meal and allergy data through backup and CSV',
    () {
      final p = demoProject();
      final g = rows(p, 'groups').first;
      g['meal'] = 'Végétarien';
      g['allergy'] = 'Allergie fictive';
      g['needs'] = 'Fauteuil';
      g['alloc'] = [
        {'table': tables(p).first['id'], 'count': g['count']},
      ];
      p['mealService'] = 'Non';
      final before = clone(p);
      expect(
        planMarkerColors(p).keys
            .any((k) => k == 'Allergie' || k.startsWith('Repas :')),
        false,
      );
      expect(
        tableMarkers(p, tables(p).first['id']),
        contains('Mobilité / PMR'),
      );
      expect(
        tableMarkers(p, tables(p).first['id']),
        isNot(contains('Allergie')),
      );
      expect(eventCsv(p, 'Réservations'), contains('Allergie fictive'));
      final restored = readEventBackup(jsonEncode(eventBackup([p]))).single;
      expect(restored['groups'], before['groups']);
      restored['mealService'] = 'Oui';
      expect(
        tableMarkers(restored, tables(restored).first['id']),
        containsAll(['Allergie', 'Repas : Végétarien']),
      );
    },
  );
  testWidgets(
    'Preferences without meals hides food fields and preserves stored preferences',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = demoProject();
      p['mealService'] = 'Non';
      final g = rows(p, 'groups').first;
      g['count'] = 1;
      g['meal'] = 'Végétarien';
      g['allergy'] = 'Allergie fictive';
      g['needs'] = 'Fauteuil';
      p['groups'] = [g];
      await tester.pumpWidget(Tableo(store: MemoryStore([p])));
      await tester.pumpAndSettle();
      expect(find.text('Allergie'), findsNothing);
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      expect(find.text('+ Repas'), findsNothing);
      expect(find.textContaining('Allergie fictive'), findsNothing);
      await tester.ensureVisible(find.text('Préférences'));
      await tester.tap(find.text('Préférences'));
      await tester.pumpAndSettle();
      expect(find.text('Allergies'), findsNothing);
      expect(find.text('Repas'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();
      expect(g['meal'], 'Végétarien');
      expect(g['allergy'], 'Allergie fictive');
      expect(
        individualSeat(rows(p, 'groups').first, 0)['allergy'],
        'Allergie fictive',
      );
      expect(individualSeat(rows(p, 'groups').first, 0)['need'], 'Fauteuil');
      p['mealService'] = 'Oui';
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(Tableo(store: MemoryStore([p])));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      expect(find.text('+ Repas'), findsOneWidget);
      await tester.ensureVisible(find.text('Préférences'));
      await tester.tap(find.text('Préférences'));
      await tester.pumpAndSettle();
      expect(find.text('Allergies'), findsOneWidget);
      expect(find.text('Repas'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == 'Allergie fictive',
        ),
        findsOneWidget,
      );
    },
  );
}
