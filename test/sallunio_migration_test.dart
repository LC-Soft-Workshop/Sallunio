import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/event_backup.dart';
import 'package:tableo/storage.dart';
import 'package:tableo/main.dart';

import 'ui_test.dart' show MemoryStore;

void main() {
  test(
    'Legacy Tableo data, assignments and SQLite path survive Sallunio',
    () async {
      final raw = jsonDecode(
        File('test/fixtures/tableo-1.2.1-backup.json').readAsStringSync(),
      );
      final events = readEventBackup(jsonEncode(raw));
      expect(events.length, 4);
      expect(eventBackup(events)['format'], 'tableo-backup');
      expect(
        defaultDataDirectory(environment: {'APPDATA': 'C:/Fictif'}),
        endsWith('Tableo'),
      );
      final folder = (Directory('tmp').absolute..createSync(recursive: true))
          .createTempSync('sallunio-compat-');
      final store = Store();
      try {
        await store.open(path: folder.path);
        for (final event in events) {
          await store.save(event);
        }
        await store.saveDarkMode(true);
        await store.close();
        await store.open(path: folder.path);
        expect(store.darkMode, true);
        final restored = await store.load();
        expect(restored.length, events.length);
        expect(File('${folder.path}/tableo.sqlite').existsSync(), true);
        for (final event in events) {
          final saved = restored.singleWhere((e) => e['id'] == event['id']);
          validateProject(saved);
          expect(saved['name'], event['name']);
          expect(saved['items'], event['items']);
          expect(saved['groups'], event['groups']);
        }
      } finally {
        await store.close();
        folder.deleteSync(recursive: true);
      }
    },
  );
  testWidgets('Workspace displays Sallunio and the supplied image', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(Tableo(store: MemoryStore()));
    await tester.pumpAndSettle();
    expect(find.text('Sallunio'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/branding/sallunio.png',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
