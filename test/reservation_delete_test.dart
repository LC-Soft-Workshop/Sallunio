import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';

Json config(Json p) {
  final copy = clone(p);
  copy.remove('groups');
  return copy;
}

Json prepared() {
  final p = demoProject();
  p['attendanceTarget'] = 25;
  allocate(p);
  return p;
}

class DeleteStore extends Store {
  Json saved = prepared();
  DeleteStore([Json? project]) {
    if (project != null) saved = project;
    directory = 'Fictif';
  }
  @override
  Future<List<Json>> load() async => [clone(saved)];
  @override
  Future<void> save(Json p) async {
    saved = clone(p);
  }
}

void desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'Anonymous middle-place removal can be cancelled, then saved with renumbered links and free seats',
    (tester) async {
      desktop(tester);
      final p = prepared();
      final group = rows(p, 'groups').first;
      group['count'] = 3;
      group['alloc'] = [
        {'table': tables(p).first['id'], 'count': 3},
      ];
      group['seats'] = List<Json>.generate(
        3,
        (i) => {
          'number': i + 1,
          'meal': i == 1 ? 'Végétarien' : 'Normal',
          'need': i == 1 ? 'Fauteuil' : '',
          'allergy': i == 1 ? 'Fictif retiré' : '',
          'companion': i == 0 ? '3' : '',
        },
      );
      p['groups'] = [group];
      final store = DeleteStore(p), initial = clone(p);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      Future<void> removePlace() async {
        await tester.scrollUntilVisible(
          find.text('Préférences'),
          150,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('reservations-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await Scrollable.ensureVisible(
          tester.element(find.widgetWithText(TextButton, 'Préférences')),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Préférences'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byTooltip('Retirer la place anonyme 2'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Retirer la place anonyme 2'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirmer'));
        await tester.pumpAndSettle();
      }

      await removePlace();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(store.saved, initial);
      await removePlace();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      final saved = rows(store.saved, 'groups').single;
      expect(saved['count'], 2);
      expect(saved['seats'][0]['companion'], '2');
      expect(workspaceStats(store.saved)['assigned'], 2);
      expect(workspaceStats(store.saved)['free'], 34);
      await tester.tap(find.text('Plan de salle').first);
      await tester.pumpAndSettle();
      expect(find.text('T1\n2/6'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('Partial deletion releases table seats and clears only references to the removed group', () {
    final p = prepared(), before = config(p);
    final gs = rows(p, 'groups');
    final deleted = gs.first['id'];
    gs[1]['separate'] = deleted;
    removeReservation(p, deleted);
    expect(config(p), before);
    expect(gs.length, 2);
    expect(gs.first['separate'], '');
    expect(workspaceStats(p)['reserved'], 7);
    expect(workspaceStats(p)['assigned'], 7);
    expect(workspaceStats(p)['free'], 29);
    expect(occupancy(p, tables(p).first['id']), 0);
    validateProject(p);
  });
  test('Clear removes reservation details and allocations but keeps every configuration field and target', () {
    final p = prepared(), before = config(p);
    rows(p, 'groups').first['seats'] = [
      {
        'number': 1,
        'meal': 'Végétarien',
        'need': 'Fauteuil',
        'allergy': 'Fictif',
        'companion': '2',
      },
    ];
    clearReservations(p);
    expect(config(p), before);
    expect(rows(p, 'groups'), isEmpty);
    expect(workspaceStats(p)['target'], 25);
    expect(workspaceStats(p)['assigned'], 0);
    expect(workspaceStats(p)['free'], 36);
    expect(mealTotals(p).values.every((v) => v == 0), true);
    for (final t in tables(p)) {
      expect(occupancy(p, t['id']), 0);
    }
  });
  test('Count reduction trims assignments and seat links; increases keep existing assignments', () {
    final p = prepared(), g = rows(p, 'groups').first;
    g['seats'] = List<Json>.generate(
      12,
      (i) => {
        'number': i + 1,
        'meal': 'Normal',
        'need': '',
        'allergy': '',
        'companion': i == 0 ? '12' : '',
      },
    );
    resizeReservation(g, 5);
    expect(g['count'], 5);
    expect((g['alloc'] as List).single['count'], 5);
    expect((g['seats'] as List).length, 5);
    expect(g['seats'][0]['companion'], '');
    expect(g['placementReview'], true);
    resizeReservation(g, 8);
    expect((g['alloc'] as List).single['count'], 5);
    expect(workspaceStats(p)['reserved'], 15);
    expect(workspaceStats(p)['assigned'], 12);
    validateProject(p);
  });
  test('Removing anonymous middle place renumbers companion links, meals and allocation budget', () {
    final p = prepared(), g = rows(p, 'groups')[1];
    g['seats'] = List<Json>.generate(
      4,
      (i) => {
        'number': i + 1,
        'meal': i == 1 ? 'Ne mange pas' : 'Normal',
        'need': i == 1 ? 'Fauteuil' : '',
        'allergy': i == 1 ? 'Fictif retiré' : '',
        'companion': i == 0
            ? '2'
            : i == 2
            ? '4'
            : '',
      },
    );
    removeAnonymousPlace(g, 1);
    expect(g['count'], 3);
    expect((g['seats'] as List).map((s) => s['number']), [1, 2, 3]);
    expect(g['seats'][0]['companion'], '');
    expect(g['seats'][1]['companion'], '3');
    expect((g['alloc'] as List).single['count'], 3);
    expect(g['seats'].any((s) => s['allergy'] == 'Fictif retiré'), false);
    resizeReservation(g, 1);
    expect(() => removeAnonymousPlace(g, 0), throwsFormatException);
    removeReservation(p, g['id']);
    expect(rows(p, 'groups').length, 2);
    validateProject(p);
  });
  test('Partial and total deletion survive SQLite reopen without changing room or objective', () async {
    final dir = await Directory.systemTemp.createTemp('tableo-delete-');
    final p = prepared(), before = config(p);
    final store = Store();
    await store.open(path: dir.path);
    removeReservation(p, rows(p, 'groups').first['id']);
    await store.save(p);
    await store.close();
    final reopened = Store();
    await reopened.open(path: dir.path);
    final partial = (await reopened.load()).single;
    expect(workspaceStats(partial)['assigned'], 7);
    expect(config(partial), before);
    clearReservations(partial);
    await reopened.save(partial);
    await reopened.close();
    final finalStore = Store();
    await finalStore.open(path: dir.path);
    final emptied = (await finalStore.load()).single;
    expect(rows(emptied, 'groups'), isEmpty);
    expect(config(emptied), before);
    expect(workspaceStats(emptied)['free'], 36);
    await finalStore.close();
    await dir.delete(recursive: true);
  });
  testWidgets(
    'Visible reset confirms exact scope, cancellation keeps data, confirmation updates all counters',
    (tester) async {
      desktop(tester);
      final store = DeleteStore();
      final initial = clone(store.saved);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tout supprimer'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('3 groupe(s), 19 personne(s)'),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(store.saved, initial);
      await tester.tap(find.text('Tout supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(rows(store.saved, 'groups'), isEmpty);
      expect(config(store.saved), config(initial));
      expect(workspaceStats(store.saved)['free'], 36);
      expect(find.text('Camille (fictif)'), findsNothing);
      await tester.tap(find.text('Plan de salle').first);
      await tester.pumpAndSettle();
      expect(find.text('T1\n0/6'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      expect(workspaceStats(store.saved)['reservations'], 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'A one-person reservation can be removed individually with confirmation',
    (tester) async {
      desktop(tester);
      final p = prepared();
      p['groups'] = [
        {
          'id': 'solo',
          'name': 'Solo fictif',
          'count': 1,
          'meal': 'Normal',
          'allergy': '',
          'needs': '',
          'alloc': [
            {'table': tables(p).first['id'], 'count': 1},
          ],
        },
      ];
      final store = DeleteStore(p), initial = clone(p);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Supprimer le groupe'),
        150,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('reservations-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Supprimer le groupe')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Supprimer le groupe'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 groupe, 1 personne(s)'), findsOneWidget);
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(rows(store.saved, 'groups'), isEmpty);
      expect(config(store.saved), config(initial));
      expect(workspaceStats(store.saved)['free'], 36);
      expect(tester.takeException(), isNull);
    },
  );
}
