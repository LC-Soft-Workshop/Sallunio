import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/exports.dart';
import 'package:tableo/main.dart';
import 'package:tableo/plan_export.dart';

import 'file_dialogs_test.dart' show TestStore;

Json documentFixture() {
  final p = demoProject();
  allocate(p);
  final groups = rows(p, 'groups');
  final oldId = groups[1]['id'];
  groups[1]['id'] = 'PREFERENCE_CONFIDENTIELLE_ID';
  for (final group in groups) {
    if (group['separate'] == oldId) group['separate'] = groups[1]['id'];
  }
  setReservationPreference(p, groups.first, groups[1]['id'], 'far');
  groups.first['note'] = 'NOTE_INTERNE_RESERVATION';
  tables(p).first['note'] = 'NOTE_INTERNE_TABLE';
  groups.first['seats'] = [
    {
      'number': 1,
      'meal': 'Sans gluten',
      'need': 'Fauteuil',
      'allergy': 'Arachides',
      'companion': '2',
    },
  ];
  rows(p, 'items').addAll([
    {
      'id': 'invisible',
      'kind': 'zone',
      'label': 'ZONE_INVISIBLE_CONFIDENTIELLE',
      'shape': 'rectangle',
      'x': 6.2,
      'y': 0.0,
      'w': .6,
      'h': 9.0,
      'fixed': true,
      'zoneFill': 'Invisible',
    },
    {
      'id': 'hatch',
      'kind': 'zone',
      'label': 'Piste de danse',
      'shape': 'rectangle',
      'x': 3.0,
      'y': 6.2,
      'w': 2.0,
      'h': 1.8,
      'fixed': false,
      'zoneColor': 'Orange',
      'zoneFill': 'Hachures croisées',
    },
    {
      'id': 'outline',
      'kind': 'zone',
      'label': 'Espace libre',
      'shape': 'cercle',
      'x': 6.0,
      'y': 6.2,
      'w': 1.5,
      'h': 1.5,
      'fixed': false,
      'zoneColor': 'Vert',
      'zoneFill': 'Contour seul',
    },
  ]);
  return p;
}

void main() {
  for (final corner in arrangementCorners) {
    test(
      'Arrangement starts from $corner and preserves fixed/service items',
      () {
        final p = demoProject();
        p['arrangementCorner'] = corner;
        p['joining'] = 'Petits côtés';
        final originals = tables(p).take(2).map(clone).toList();
        final fixed = {
          'id': 'fixed',
          'kind': 'table',
          'label': 'Fixe',
          'shape': 'rectangle',
          'x': 4.0,
          'y': 4.0,
          'w': 1.8,
          'h': .8,
          'capacity': 6,
          'fixed': true,
          'sides': 'Longs côtés',
        };
        final service = {
          ...fixed,
          'id': 'service',
          'label': 'Service',
          'x': 7.0,
          'capacity': 0,
          'fixed': false,
        };
        p['items'] = <Json>[...originals, fixed, service];
        expect(arrange(p), 0);
        final first = tables(p).first;
        expect(number(first['x']) > 6, corner.endsWith('droite'));
        expect(number(first['y']) > 4.5, corner.startsWith('Bas'));
        expect(fixed['x'], 4.0);
        expect(fixed['y'], 4.0);
        expect(service['x'], 7.0);
        for (final table in tables(p).take(2)) {
          expect(fits(p, table, rows(p, 'items')), true);
          expect(table['w'], 1.8);
          expect(table['h'], .8);
        }
      },
    );
  }
  test(
    'Corner arrangement respects concave room and failure remains atomic',
    () {
      final p = demoProject();
      p['items'] = tables(p).take(2).map(clone).toList();
      p['room']['polygon'] = '0,0;12,0;12,5;8,5;8,9;0,9';
      p['arrangementCorner'] = 'Bas droite';
      expect(arrange(p), 0);
      expect(tables(p).every((t) => fits(p, t, rows(p, 'items'))), true);
      p['room']['polygon'] = '';
      p['room']['width'] = 2.0;
      p['room']['height'] = 1.0;
      final before = clone(p);
      expect(arrange(p), greaterThan(0));
      expect(p['items'], before['items']);
    },
  );
  test('Private preferences stay outside general controls and plan SVG', () {
    final p = documentFixture();
    expect(reservationPreferenceChecks(p), isNotEmpty);
    expect(
      [
        ...issues(p),
        ...preparationNotes(p),
      ].where((s) => s.contains('préférence') || s.contains('proximité')),
      isEmpty,
    );
    final svg = planSvg(p);
    expect(svg, isNot(contains('PREFERENCE_CONFIDENTIELLE_ID')));
    expect(svg, contains('clip-path'));
    expect(svg, contains('#a9d8bf'));
    expect(
      rows(
        p,
        'items',
      ).where(visibleInPlanPdf).any((item) => item['id'] == 'invisible'),
      false,
    );
  });
  test(
    'Generate privacy and rendering fixtures for every PDF audience',
    () async {
      await Directory('tmp/pdfs').create(recursive: true);
      final p = documentFixture();
      for (final section in [
        'plan',
        'summary',
        'cards',
        'reception',
        'service',
        'all',
      ]) {
        await exportPdf(
          p,
          'tmp/pdfs/organization-$section.pdf',
          overwriteConfirmed: true,
          includePlan: section == 'plan' || section == 'all',
          includeSummary: section == 'summary' || section == 'all',
          includeCards: section == 'cards' || section == 'all',
          includeReception: section == 'reception' || section == 'all',
          includeService: section == 'service' || section == 'all',
        );
      }
      await exportPdf(
        p,
        'tmp/pdfs/organization-labels.pdf',
        overwriteConfirmed: true,
        includePlan: true,
        includeSummary: false,
        includeCards: false,
        includePlaceLabels: true,
      );
    },
  );
  testWidgets(
    'Cursor coordinates are in metres and table drag remains continuous',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TestStore();
      final id = tables(store.project).first['id'];
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      final table = find.byKey(ValueKey('plan-item-$id'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(table));
      await mouse.moveTo(tester.getCenter(table));
      await tester.pump();
      expect(
        find.textContaining('Curseur : X 1.90 m • Y 1.50 m'),
        findsOneWidget,
      );
      await tester.drag(table, const Offset(60, 30));
      await tester.pumpAndSettle();
      final moved = tables(store.project).first;
      expect(number(moved['x']), greaterThan(1.0));
      expect(
        find.textContaining(
          'T1 : X ${number(moved['x']).toStringAsFixed(2)} m',
        ),
        findsOneWidget,
      );
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Notes save in reservations and tables and survive reopen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = TestStore();
    final id = tables(store.project).first['id'];
    await tester.pumpWidget(Tableo(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réservations').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier').first);
    await tester.pumpAndSettle();
    final note = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == 'Note d’organisation (interne)',
    );
    await tester.ensureVisible(note);
    await tester.enterText(note, 'Arrivée tardive');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(rows(store.project, 'groups').first['note'], 'Arrivée tardive');
    await tester.tap(find.text('Plan de salle').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('plan-item-$id')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(ValueKey('plan-item-$id')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(note);
    await tester.enterText(note, 'Table des bénévoles');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(tables(store.project).first['note'], 'Table des bénévoles');
    validateProject(clone(store.project));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(Tableo(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réservations').first);
    await tester.pumpAndSettle();
    expect(find.text('Note : Arrivée tardive'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
