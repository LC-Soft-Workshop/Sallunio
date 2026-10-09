import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';

import 'attributions_test.dart' show desktop;
import 'event_delete_test.dart' show EventStore;
import 'flutter_paths.dart' show materialIconsPath;
import 'ui_test.dart' show MemoryStore;

void main() {
  testWidgets(
    'Sun/moon switch changes theme, keeps current page and event data',
    (tester) async {
      desktop(tester);
      final store = MemoryStore();
      final before = clone(store.projects.first);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Passer au mode sombre'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
      expect(find.text('1. Importer les réservations (CSV)'), findsOneWidget);
      expect(store.darkMode, true);
      expect(store.projects.first, before);
      await tester.tap(find.text('Plan de salle').first);
      await tester.pumpAndSettle();
      final grid = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<GridPainter>()
          .single;
      expect(grid.dark, true);
      await tester.tap(find.byTooltip('Passer au mode clair'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(store.darkMode, false);
      expect(store.projects.first, before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Theme switch exists without any event and starts from saved preference',
    (tester) async {
      desktop(tester);
      final store = EventStore()
        ..events.clear()
        ..demoOnEmpty = false
        ..darkMode = true;
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Aucun événement'), findsOneWidget);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await tester.tap(find.byTooltip('Passer au mode clair'));
      await tester.pumpAndSettle();
      expect(store.darkMode, false);
      expect(store.events, isEmpty);
    },
  );

  test(
    'Theme preference persists separately and does not rewrite events',
    () async {
      final directory = await Directory.systemTemp.createTemp('tableo-theme-');
      final store = Store();
      await store.open(path: directory.path);
      final event = demoProject();
      await store.save(event);
      final before = await store.db.query('projects');
      expect(store.darkMode, false);
      await store.saveDarkMode(true);
      expect(await store.db.query('projects'), before);
      await store.close();
      final reopened = Store();
      await reopened.open(path: directory.path);
      expect(reopened.darkMode, true);
      expect(await reopened.load(), [event]);
      await reopened.saveDarkMode(false);
      expect(await reopened.db.query('projects'), before);
      await reopened.close();
      await directory.delete(recursive: true);
    },
  );

  testWidgets('Render dark and light plans for contrast verification', (
    tester,
  ) async {
    desktop(tester);
    await tester.runAsync(() async {
      for (final entry in {
        'Roboto': 'C:/Windows/Fonts/arial.ttf',
        'MaterialIcons': materialIconsPath(),
      }.entries) {
        await (FontLoader(entry.key)..addFont(
              File(entry.value)
                  .readAsBytes()
                  .then((b) => b.buffer.asByteData()),
            ))
            .load();
      }
    });
    final capture = GlobalKey();
    final store = MemoryStore();
    allocate(store.projects.first);
    rows(store.projects.first, 'items').add({
      'id': 'theme-outline',
      'kind': 'zone',
      'label': 'Zone transparente',
      'shape': 'rectangle',
      'x': 5.0,
      'y': 6.0,
      'w': 2.0,
      'h': 1.0,
      'fixed': false,
      'zoneFill': 'Contour seul',
      'zoneColor': 'Bleu',
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: Tableo(store: store),
      ),
    );
    await tester.pumpAndSettle();
    for (final name in ['light', 'dark']) {
      if (name == 'dark') {
        await tester.tap(find.byTooltip('Passer au mode sombre'));
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final screenshot = await boundary.toImage();
        final bytes = await screenshot.toByteData(
          format: ui.ImageByteFormat.png,
        );
        await Directory('output/qa').create(recursive: true);
        await File('output/qa/theme-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        screenshot.dispose();
      });
      expect(tester.takeException(), isNull);
    }
  });
}
