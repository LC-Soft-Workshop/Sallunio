import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';

class SnapshotStore extends Store {
  Json saved = demoProject();
  @override
  Future<List<Json>> load() async => [clone(saved)];
  @override
  Future<void> save(Json p) async {
    saved = clone(p);
  }

  SnapshotStore() {
    directory = 'Stockage fictif';
  }
}

void desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('Table snapshot is detached from mutable allocations and agrees with group total', () {
    final project = demoProject();
    allocate(project);
    final snapshot = tableAssignments(project);
    expect(snapshot.map((t) => t['occupied']), [6, 6, 4, 3, 0, 0]);
    expect(
      snapshot.fold<int>(0, (s, t) => s + (t['occupied'] as int)),
      allocationSummary(project)['assigned'],
    );
    rows(project, 'groups').first['alloc'] = <Json>[];
    expect(snapshot.first['occupied'], 6);
    expect(tableAssignments(project).first['occupied'], 0);
  });
  testWidgets(
    'Demo without CSV: saved allocation totals and all visible plan counters agree',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore();
      final capture = GlobalKey();
      await tester.runAsync(() async {
        final font = FontLoader('Roboto')
          ..addFont(
            File('C:/Windows/Fonts/arial.ttf')
                .readAsBytes()
                .then((v) => v.buffer.asByteData()),
          );
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            File(
              'E:/DEV/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then((v) => v.buffer.asByteData()),
          );
        await icons.load();
      });
      Future<void> screenshot(String name) async {
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('output/qa').create(recursive: true);
          await File('output/qa/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: Tableo(store: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('T1\n0/6'), findsOneWidget);
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2. Attribuer les groupes aux tables'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('19 / 19 personnes attribuées.'),
        findsWidgets,
      );
      expect(allocationSummary(store.saved)['assigned'], 19);
      expect(
        tables(store.saved)
            .fold<int>(0, (s, t) => s + occupancy(store.saved, t['id'])),
        19,
      );
      await tester.tap(find.text('Voir les attributions'));
      await tester.pumpAndSettle();
      await screenshot('attributions-apres-placement');
      await tester.tap(find.text('Plan de salle').first);
      await tester.pumpAndSettle();
      for (final t in tables(store.saved)) {
        expect(
          find.text('${t['label']}\n${occupancy(store.saved, t['id'])}/6'),
          findsOneWidget,
          reason: 'Live counter for ${t['label']}',
        );
      }
      expect(find.text('T1\n6/6'), findsOneWidget);
      expect(find.text('T2\n6/6'), findsOneWidget);
      expect(find.text('T3\n4/6'), findsOneWidget);
      expect(find.text('T4\n3/6'), findsOneWidget);
      await screenshot('plan-compteurs-apres-placement');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      expect(find.text('T1\n6/6'), findsOneWidget);
      expect(find.text('T3\n4/6'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('See allocations opens readable view organized by table', (
    tester,
  ) async {
    desktop(tester);
    await tester.pumpWidget(Tableo(store: SnapshotStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réservations').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2. Attribuer les groupes aux tables'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voir les attributions'));
    await tester.pumpAndSettle();
    expect(find.text('Attributions par table'), findsOneWidget);
    expect(find.text('T1 • 6 / 6 places'), findsOneWidget);
    expect(find.text('Camille (fictif) • 6 personnes'), findsWidgets);
  });
  test(
    'SQLite close/reopen preserves per-table counts, group links and total',
    () async {
      final dir = await Directory.systemTemp.createTemp('tableo-attributions-');
      final store = Store();
      await store.open(path: dir.path);
      final project = demoProject();
      allocate(project);
      await store.save(project);
      await store.close();
      final reopened = Store();
      await reopened.open(path: dir.path);
      final restored = (await reopened.load()).single;
      expect(rows(restored, 'groups'), rows(project, 'groups'));
      expect(tables(restored).map((t) => occupancy(restored, t['id'])), [
        6,
        6,
        4,
        3,
        0,
        0,
      ]);
      expect(allocationSummary(restored)['assigned'], 19);
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );
}
