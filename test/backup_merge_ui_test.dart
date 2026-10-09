import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/event_backup.dart';
import 'package:tableo/main.dart';

import 'backup_merge_test.dart' show emptyTarget, source;
import 'partial_backup_test.dart' show InjectionStore;

Future<void> openImport(WidgetTester tester, InjectionStore store) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final file = File('tmp/merge-${uid()}.tableo.json').absolute;
  await tester.runAsync(
    () => file.writeAsString(
      jsonEncode(eventBackup([source('Démo 1'), source('Démo 2', width: 2.4)])),
    ),
  );
  addTearDown(() async {
    if (await file.exists()) await file.delete();
  });
  await tester.pumpWidget(Tableo(store: store));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Fichiers ▾'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Importer projet'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        )
        .first,
    file.path,
  );
  await tester.tap(find.text('Valider'));
  for (
    var i = 0;
    i < 100 && find.text('Événements à importer').evaluate().isEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
  await tester.tap(find.text('Importer la sélection'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'All categories merge two sources with explicit furniture choice and undo',
    (tester) async {
      final store = InjectionStore();
      store.current
        ..clear()
        ..addAll(emptyTarget());
      final original = clone(store.current);
      await openImport(tester, store);
      await tester.tap(
        find.widgetWithText(
          CheckboxListTile,
          'Tout sélectionner pour l’événement ouvert',
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['Salles', 'Mobilier', 'Réservations']) {
        expect(
          tester
              .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, label),
              )
              .value,
          true,
        );
      }
      await tester.tap(find.text('Importer'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continuer'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Fusionner les événements sélectionnés'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(find.text('Mobilier : Table 180'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Importer les choix'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Événement 2 : Démo 2').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Importer les choix'));
      await tester.pumpAndSettle();
      expect(store.saved!['id'], original['id']);
      expect(store.saved!['room'], original['room']);
      expect(rows(store.saved!, 'types').single['w'], 2.4);
      expect(rows(store.saved!, 'groups').length, 4);
      expect(
        rows(store.saved!, 'rooms').any((r) => r['name'] == 'Salle Démo 1'),
        true,
      );
      expect(
        rows(store.saved!, 'rooms').any((r) => r['name'] == 'Salle Démo 2'),
        true,
      );
      await tester.tap(find.byTooltip('Annuler'));
      await tester.pumpAndSettle();
      expect(store.saved!['items'], original['items']);
      expect(store.saved!['groups'], original['groups']);
      expect(store.saved!['rooms'], original['rooms']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Rooms only can use second event without adding furniture or reservations',
    (tester) async {
      final store = InjectionStore();
      final original = clone(store.current);
      await openImport(tester, store);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Salles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Importer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Événement 2 : Démo 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(store.saved!['items'], original['items']);
      expect(store.saved!['groups'], original['groups']);
      expect(store.saved!['types'], original['types']);
      expect(store.saved!['room'], original['room']);
      expect(
        rows(store.saved!, 'rooms').any((r) => r['name'] == 'Salle Démo 2'),
        true,
      );
      expect(
        rows(store.saved!, 'rooms').any((r) => r['name'] == 'Salle Démo 1'),
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cancelling conflicts performs no write and leaves open event intact',
    (tester) async {
      final store = InjectionStore();
      store.current
        ..clear()
        ..addAll(emptyTarget());
      final original = clone(store.current);
      await openImport(tester, store);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Mobilier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Importer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fusionner les événements sélectionnés'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler').last);
      await tester.pumpAndSettle();
      expect(store.saved, isNull);
      expect(store.current, original);
      expect(tester.takeException(), isNull);
    },
  );
}
