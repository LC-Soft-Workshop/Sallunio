import 'flutter_paths.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';

class MemoryStore extends Store {
  final List<Json> projects;
  MemoryStore([List<Json>? initial]) : projects = initial ?? [demoProject()] {
    directory = 'Données fictives';
  }
  @override
  Future<List<Json>> load() async => projects;
  @override
  Future<void> save(Json p) async {}
}

Future<Json> immediateArrangement(Json p) async => arrangeProject(p);

void main() {
  testWidgets(
    'Selected furniture types bulk action includes benches and preserves plan until chosen',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final project = demoProject();
      project['items'] = <Json>[];
      project['groups'] = <Json>[];
      rows(project, 'types')[0]['quantity'] = 3;
      rows(project, 'types')[0]['limit'] = 3;
      rows(project, 'types')[1]['enabled'] = false;
      await tester.pumpWidget(Tableo(store: MemoryStore([project])));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobilier').first);
      await tester.pumpAndSettle();
      expect(find.text('Ajouter au plan'), findsWidgets);
      expect(find.text('Ajouter tout'), findsNWidgets(2));
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Petits côtés').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter tout le mobilier sélectionné'));
      await tester.pumpAndSettle();
      expect(tables(project).length, 11);
      expect(
        rows(project, 'items').where((i) => i['kind'] == 'bench'),
        hasLength(8),
      );
      expect(
        find.text('Dernier ajout : 11 placé(s), 0 non placé(s).'),
        findsOneWidget,
      );
      expect(
        joinedEdges(project, tables(project)[0], tables(project)[1]),
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Visible CSV replacement then automatic group attribution preserves room and layout',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final project = demoProject();
      project['groups'] = <Json>[];
      final before = clone(project), store = MemoryStore([project]);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Initial plan');
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      expect(find.text('1. Importer les réservations (CSV)'), findsOneWidget);
      await tester.tap(find.text('1. Importer les réservations (CSV)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            )
            .first,
        File('test/fixtures/reservations.csv').absolute.path,
      );
      await tester.tap(find.text('Valider'));
      for (
        var i = 0;
        i < 100 && find.text('Prévisualisation et mapping').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.text('Prévisualisation et mapping'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'CSV preview');
      expect(
        find.text('Liste vide : import en ajout, sans remplacement.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Valider les lignes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Camille fictif'),
        150,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('reservations-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Camille fictif'), findsOneWidget);
      expect(rows(project, 'groups').length, 3);
      expect(tester.takeException(), isNull, reason: 'Imported groups');
      expect(project['room'], before['room']);
      expect(project['items'], before['items']);
      expect(project['types'], before['types']);
      await tester.ensureVisible(
        find.widgetWithText(
          FilledButton,
          '2. Attribuer les groupes aux tables',
        ),
      );
      await tester.tap(find.text('2. Attribuer les groupes aux tables'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('19 / 19 personnes attribuées.'),
        findsWidgets,
      );
      await tester.tap(find.text('Voir les attributions'));
      await tester.pumpAndSettle();
      expect(find.text('Attributions par table'), findsOneWidget);
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('T1 (6), T2 (6)'),
        150,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('reservations-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('T1 (6), T2 (6)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Navigation desktop, group lookup, edit and undo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = GlobalKey();
    await tester.runAsync(() async {
      final textFont = FontLoader('Roboto')
        ..addFont(
          File('C:/Windows/Fonts/arial.ttf')
              .readAsBytes()
              .then((v) => v.buffer.asByteData()),
        );
      await textFont.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(materialIconsPath())
              .readAsBytes()
              .then((v) => v.buffer.asByteData()),
        );
      await icons.load();
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: Tableo(store: MemoryStore()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary =
        capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final screenshot = await boundary.toImage();
      final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
      await Directory('output/qa').create(recursive: true);
      await File('output/qa/plan.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.tap(find.text('Réservations').first);
    await tester.pumpAndSettle();
    expect(find.text('Camille (fictif)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField).first, 'Camille');
    await tester.pump();
    expect(find.text('Morgan (fictif)'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text('+ Groupe'));
    await tester.pumpAndSettle();
    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogFields.at(0), 'Jordan fictif');
    await tester.enterText(dialogFields.at(1), '2');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Jordan fictif'),
      150,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('reservations-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Jordan fictif'), findsOneWidget);
    await tester.tap(find.byTooltip('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('Jordan fictif'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('2. Attribuer les groupes aux tables'),
      -150,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('reservations-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      tester.element(
        find.widgetWithText(
          FilledButton,
          '2. Attribuer les groupes aux tables',
        ),
      ),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('2. Attribuer les groupes aux tables'));
    await tester.pumpAndSettle();
    expect(find.textContaining('19 / 19 personnes attribuées.'), findsWidgets);
    await tester.tap(find.text('Voir les attributions'));
    await tester.pumpAndSettle();
    expect(find.text('Attributions par table'), findsOneWidget);
    await tester.tap(find.text('Réservations').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('T1 (6), T2 (6)'),
      150,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('reservations-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('T1 (6), T2 (6)'), findsOneWidget);
    await tester.tap(find.text('Mobilier').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Table 180'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Contrôles').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Événements').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
