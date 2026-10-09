import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';

class CounterStore extends Store {
  Json saved = demoProject();
  CounterStore() {
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
    'Configuration duplication keeps target and furniture but resets reservation counters',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = CounterStore();
      store.saved['attendanceTarget'] = 25;
      allocate(store.saved);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Événements').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Dupliquer sans réservations'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dupliquer sans réservations'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(store.saved['attendanceTarget'], 25);
      expect(rows(store.saved, 'groups'), isEmpty);
      expect(tables(store.saved).length, 6);
      expect(workspaceStats(store.saved)['free'], 36);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Event counter dashboard and demo plan fit the native 1280 by 720 startup window',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = CounterStore();
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      expect(find.text('T1\n0/6'), findsOneWidget);
      expect(find.text('Compteurs de l’événement'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      expect(find.text('Tout supprimer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('Legacy optional target, zero, unconstrained large target and warning-only overflow', () {
    final p = demoProject()..remove('attendanceTarget');
    validateProject(p);
    final initial = workspaceStats(p);
    expect(initial['target'], null);
    expect(initial['reservations'], 3);
    expect(initial['reserved'], 19);
    expect(initial['capacity'], 36);
    expect(initial['assigned'], 0);
    expect(initial['free'], 36);
    p['attendanceTarget'] = 0;
    expect(workspaceStats(p)['target'], 0);
    expect((workspaceStats(p)['alerts'] as List).length, 1);
    p['attendanceTarget'] = 1000000;
    validateProject(p);
    expect(workspaceStats(p)['target'], 1000000);
    allocate(p);
    final stats = workspaceStats(p);
    expect(stats['assigned'], 19);
    expect(stats['free'], 17);
    expect(stats['capacity'], 36);
    p['attendanceTarget'] = 15;
    expect(
      (workspaceStats(p)['alerts'] as List).any(
        (s) => s.contains('objectif de 4'),
      ),
      true,
    );
    expect(rows(p, 'groups').length, 3);
    expect(allocationSummary(p)['assigned'], 19);
  });
  test('Capacity counters update after furniture, individual capacity, joints and group changes', () {
    final p = demoProject();
    rows(p, 'items').removeWhere((i) => i['kind'] != 'table');
    p['items'] = tables(p).take(2).toList();
    final a = tables(p)[0], b = tables(p)[1];
    a['x'] = 1.0;
    a['y'] = 1.0;
    b['x'] = 1.0;
    b['y'] = 1.8;
    p['joining'] = 'Grands côtés';
    expect(workspaceStats(p)['capacity'], 6);
    expect(
      (workspaceStats(p)['alerts'] as List).any(
        (s) => s.contains('capacité utilisable de 13'),
      ),
      true,
    );
    allocate(p);
    expect(workspaceStats(p)['assigned'], 6);
    expect(workspaceStats(p)['free'], 0);
    b['capacity'] = 4;
    expect(workspaceStats(p)['capacity'], 5);
    expect(workspaceStats(p)['overbooked'], 1);
    expect(workspaceStats(p)['free'], 0);
    p['groups'] = <Json>[];
    expect(workspaceStats(p)['reserved'], 0);
    expect(workspaceStats(p)['free'], 5);
    rows(p, 'items').removeLast();
    expect(workspaceStats(p)['capacity'], 6);
  });
  test('Objective survives JSON export/import, SQLite reopen and configuration duplication', () async {
    final p = demoProject();
    p['attendanceTarget'] = 25;
    allocate(p);
    final imported = jsonDecode(jsonEncode(p)) as Json;
    validateProject(imported);
    expect(imported['attendanceTarget'], 25);
    final copy = clone(imported);
    copy['id'] = uid();
    copy['groups'] = <Json>[];
    expect(workspaceStats(copy)['target'], 25);
    expect(workspaceStats(copy)['reservations'], 0);
    expect(workspaceStats(copy)['assigned'], 0);
    expect(workspaceStats(copy)['free'], 36);
    expect(copy['room'].containsKey('attendanceTarget'), false);
    final dir = await Directory.systemTemp.createTemp('tableo-counters-');
    final store = Store();
    await store.open(path: dir.path);
    await store.save(imported);
    await store.close();
    final restored = Store();
    await restored.open(path: dir.path);
    expect(
      workspaceStats((await restored.load()).single),
      workspaceStats(imported),
    );
    await restored.close();
    await dir.delete(recursive: true);
  });
  testWidgets(
    'Event counters update after goal edit and assignment, zero and cleared target distinct',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = CounterStore();
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      Finder tile(String label) => find.byKey(ValueKey('workspace-$label'));
      expect(
        find.descendant(
          of: tile('Objectif maximum attendu'),
          matching: find.text('Non renseigné'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile('Réservations (groupes)'),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile('Personnes réservées'),
          matching: find.text('19'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Modifier l’objectif'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '0',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(store.saved['attendanceTarget'], 0);
      expect(
        find.descendant(
          of: tile('Objectif maximum attendu'),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Modifier l’objectif'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Non renseigné').last);
      await tester.pumpAndSettle();
      expect(store.saved['attendanceTarget'], null);
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2. Attribuer les groupes aux tables'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voir les attributions'));
      await tester.pumpAndSettle();
      expect(find.text('Attributions par table'), findsOneWidget);
      expect(
        find.descendant(
          of: tile('Personnes attribuées'),
          matching: find.text('19'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile('Capacité utilisable totale'),
          matching: find.text('36'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile('Places encore libres'),
          matching: find.text('17'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
