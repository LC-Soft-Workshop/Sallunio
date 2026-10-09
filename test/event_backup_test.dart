import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/event_backup.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';

class BackupStore extends Store {
  final events = [
    demoProject()..['name'] = 'Festival été',
    demoProject()..['name'] = 'Brocante hiver',
  ];
  BackupStore() {
    directory = 'tmp';
  }
  @override
  Future<List<Json>> load() async => [...events];
  @override
  Future<void> save(Json event) async {}
  @override
  Future<void> saveEvents(List<Json> imported) async {
    events.addAll(imported.map(clone));
  }
}

void main() {
  test('Backup retains dynamic names, allocations and settings; legacy export accepted', () {
    final a = demoProject()..['name'] = 'Festival été';
    allocate(a);
    a['defaultSides'] = 'Tous côtés';
    a['tableCards'] = {'message': 'Bienvenue'};
    final b = demoProject()..['name'] = 'Brocante hiver';
    final loaded = readEventBackup(jsonEncode(eventBackup([a, b])));
    expect(loaded.map((p) => p['name']), ['Festival été', 'Brocante hiver']);
    expect(loaded.first['groups'], a['groups']);
    expect(loaded.first['defaultSides'], 'Tous côtés');
    expect(loaded.first['tableCards'], a['tableCards']);
    expect(readEventBackup(jsonEncode(a)).single['name'], 'Festival été');
    expect(
      () => readEventBackup(
        jsonEncode({'format': 'tableo-backup', 'version': 1, 'events': []}),
      ),
      throwsFormatException,
    );
    expect(
      () => readEventBackup(
        jsonEncode({
          'format': 'tableo-backup',
          'version': 2,
          'events': [a],
        }),
      ),
      throwsFormatException,
    );
  });
  test('Event imports save together and roll back on failure', () async {
    final folder = await Directory.systemTemp.createTemp('tableo-backup-');
    final store = Store();
    await store.open(path: folder.path);
    try {
      final old = demoProject();
      await store.save(old);
      final one = demoProject(), two = demoProject();
      await store.saveEvents([one, two]);
      expect((await store.load()).length, 3);
      final bad = demoProject()..['unserializable'] = Object();
      await expectLater(
        store.saveEvents([demoProject(), bad]),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect((await store.load()).length, 3);
    } finally {
      await store.close();
      await folder.delete(recursive: true);
    }
  });
  testWidgets(
    'Save all events, read their names then import only selected event',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = BackupStore();
      final path = File('tmp/backup-ui-${uid()}.tableo.json').absolute.path;
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fichiers ▾'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exporter projet'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckboxListTile, 'Tout sauvegarder'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            )
            .first,
        path,
      );
      await tester.tap(find.text('Valider'));
      for (
        var i = 0;
        i < 100 &&
            find.textContaining('Exporter projet terminé :').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final saved = await tester.runAsync(() => File(path).readAsString());
      expect(readEventBackup(saved!).length, 2);
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
        path,
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
      expect(
        find.widgetWithText(CheckboxListTile, 'Festival été'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(CheckboxListTile, 'Brocante hiver'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Tout importer'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Importer la sélection'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Brocante hiver'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Importer la sélection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Importer'));
      await tester.pumpAndSettle();
      expect(store.events.length, 3);
      expect(store.events.last['name'], 'Brocante hiver');
      expect(store.events.last['id'], isNot(store.events[1]['id']));
      expect(store.events.last['groups'], store.events[1]['groups']);
      await tester.runAsync(() => File(path).delete());
      expect(tester.takeException(), isNull);
    },
  );
}
