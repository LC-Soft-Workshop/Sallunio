import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/csv_example.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';

class ExampleStore extends Store {
  Json saved = demoProject();
  ExampleStore(String path) {
    directory = path;
  }
  @override
  Future<List<Json>> load() async => [clone(saved)];
  @override
  Future<void> save(Json p) async {
    saved = clone(p);
  }
}

void main() {
  test('Exact packaged CSV has UTF-8 BOM, supported headers, fictitious rows and valid quoting', () async {
    final bytes = await File('examples/modele-reservations.csv').readAsBytes();
    expect(bytes, utf8.encode(exampleCsv));
    expect(bytes.take(3), [239, 187, 191]);
    final rows = parseCsv(utf8.decode(bytes));
    expect(rows.first, [
      'référent',
      'effectif',
      'repas',
      'mobilité',
      'allergies',
    ]);
    expect(rows.length, 6);
    expect(rows.skip(1).every((r) => r.length == 5), true);
    expect(rows[2][4], 'Exemple : noix; lait');
    expect(rows.last[0], 'René fictif');
    expect(
      rows.skip(1).map((r) => int.parse(r[1])).reduce((a, b) => a + b),
      22,
    );
    expect(rows.last[2], '');
    expect(rows[3][2], 'Ne mange pas');
  });
  testWidgets(
    'Example action saves exact CSV without changing reservations, then exact copy imports via supported mapping',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('tableo-csv-example-'),
      ))!;
      expect(dir.parent.absolute.path, Directory.systemTemp.absolute.path);
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = ExampleStore(dir.path);
      final initial = clone(store.saved);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('CSV d’exemple'));
      await tester.pumpAndSettle();
      expect(find.text('Obligatoires'), findsOneWidget);
      expect(find.text('Facultatifs'), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(store.saved, initial);
      await tester.tap(find.text('CSV d’exemple'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer une copie'));
      await tester.pumpAndSettle();
      final path =
          '${dir.path}${Platform.pathSeparator}modele-reservations.csv';
      await tester.tap(find.text('Valider'));
      for (
        var i = 0;
        i < 100 &&
            find
                .textContaining('CSV d’exemple enregistré :')
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.textContaining('CSV d’exemple enregistré :'), findsOneWidget);
      expect(
        await tester.runAsync(() => File(path).readAsBytes()),
        await tester.runAsync(
          () => File('examples/modele-reservations.csv').readAsBytes(),
        ),
      );
      expect(store.saved, initial);
      await tester.tap(find.text('1. Importer les réservations (CSV)'));
      await tester.pumpAndSettle();
      final input = tester.widget<TextField>(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            )
            .first,
      );
      expect(input.controller!.text, path);
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
      expect(find.text('5 lignes. Extrait :'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remplacer réservations').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider les lignes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      final groups = rows(store.saved, 'groups');
      expect(groups.length, 5);
      expect(workspaceStats(store.saved)['reserved'], 22);
      expect(groups.last['name'], 'René fictif');
      expect(groups.last['meal'], 'Normal');
      expect(groups[1]['needs'], 'Fauteuil');
      expect(groups[1]['allergy'], 'Exemple : noix; lait');
      expect(groups[2]['needs'], 'Autre mobilité');
      expect(store.saved['room'], initial['room']);
      expect(store.saved['items'], initial['items']);
      expect(store.saved['types'], initial['types']);
      expect(mealTotals(store.saved)['Ne mange pas'], 3);
      expect(mealTotals(store.saved)['Normal'], 14);
      expect(tester.takeException(), isNull);
    },
  );
}
