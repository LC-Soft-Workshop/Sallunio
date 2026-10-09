import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';

class EmptyStore extends Store {
  Json saved = demoProject()..['attendanceTarget'] = 25;
  EmptyStore() {
    directory = 'Fictif';
  }
  @override
  Future<List<Json>> load() async => [clone(saved)];
  @override
  Future<void> save(Json p) async {
    saved = clone(p);
  }
}

void main() {
  testWidgets(
    'Empty event with duplicate CSV requires choices, never silently adds both',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('tableo-delta-ui-'),
      ))!;
      expect(dir.parent.absolute.path, Directory.systemTemp.absolute.path);
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/doublons.csv');
      await tester.runAsync(
        () => file.writeAsString(
          'référent;effectif\nAlex;2\n Alex ;2\nNouveau;3\n',
        ),
      );
      final store = EmptyStore();
      store.saved['groups'] = <Json>[];
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1. Importer les réservations (CSV)'));
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
        i < 100 && find.text('Prévisualisation et mapping').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.tap(find.text('Valider les lignes'));
      await tester.pumpAndSettle();
      expect(find.text('Import • doublons à vérifier'), findsOneWidget);
      await tester.tap(find.text('Confirmer l’import'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Ligne 2 : choisir une action'),
        findsOneWidget,
      );
      expect(rows(store.saved, 'groups'), isEmpty);
      await tester.tap(find.byType(DropdownButton<String>).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter distinct').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ignorer').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer l’import'));
      await tester.pumpAndSettle();
      expect(rows(store.saved, 'groups').length, 2);
      expect(workspaceStats(store.saved)['reserved'], 5);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Reset then import example: empty list uses global addition, cancellation is safe',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = EmptyStore();
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tout supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      final emptied = clone(store.saved);
      await tester.tap(find.text('CSV d’exemple'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      Future<void> preview() async {
        await tester.tap(find.text('1. Importer les réservations (CSV)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Valider'));
        for (
          var i = 0;
          i < 100 &&
              find.text('Prévisualisation et mapping').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(
          find.text('Liste vide : import en ajout, sans remplacement.'),
          findsOneWidget,
        );
        expect(find.text('Remplacer réservations'), findsNothing);
        await tester.tap(find.text('Valider les lignes'));
        await tester.pumpAndSettle();
        expect(find.text('Ajouter 5 réservations ?'), findsOneWidget);
        expect(find.text('Ignorer'), findsNothing);
      }

      await preview();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(store.saved, emptied);
      await preview();
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(rows(store.saved, 'groups').length, 5);
      expect(workspaceStats(store.saved)['reserved'], 22);
      expect(store.saved['attendanceTarget'], 25);
      expect(store.saved['room'], emptied['room']);
      expect(store.saved['items'], emptied['items']);
      expect(tester.takeException(), isNull);
    },
  );
}
