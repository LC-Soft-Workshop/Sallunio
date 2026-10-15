import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/event_backup.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';

import 'plan_images_test.dart' show image;

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
  test('Complete image backup restores embedded bytes and properties after source deletion and database restart', () async {
    final folder = Directory('tmp/image-backup-${uid()}').absolute;
    await folder.create(recursive: true);
    final original = await File('test/fixtures/logo-fiches.png').readAsBytes();
    final source = File('${folder.path}/original.png');
    await source.writeAsBytes(original);
    final events = [demoProject(), demoProject()];
    for (var n = 0; n < events.length; n++) {
      rows(events[n], 'items').addAll([
        image('image-$n-a')
          ..['imageData'] = base64Encode(await source.readAsBytes())
          ..['angle'] = 90.0
          ..['fixed'] = true,
        image('image-$n-b')
          ..['x'] = 4.5
          ..['y'] = 3.25
          ..['w'] = 2.75
          ..['h'] = 1.25,
      ]);
    }
    final backup = File('${folder.path}/complete.tableo.json');
    await backup.writeAsString(jsonEncode(eventBackup(events)));
    await source.delete();
    final loaded = readEventBackup(await backup.readAsString());
    expect(loaded, events);
    final store = Store();
    await store.open(path: '${folder.path}/restored');
    try {
      await store.saveEvents(loaded);
    } finally {
      await store.close();
    }
    final reopened = Store();
    await reopened.open(path: '${folder.path}/restored');
    try {
      final restored = await reopened.load();
      expect(restored.length, 2);
      for (final expected in events) {
        final actual = restored.singleWhere((p) => p['id'] == expected['id']);
        expect(actual, expected);
        for (final item in rows(
          actual,
          'items',
        ).where((i) => i['kind'] == 'image')) {
          expect(base64Decode(item['imageData']), original);
        }
      }
    } finally {
      await reopened.close();
    }
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
      for (final kind in ['zone', 'obstacle', 'entry', 'exit']) {
        rows(store.events[1], 'items').add({
          'id': uid(),
          'kind': kind,
          'label': 'Objet fictif $kind',
          'shape': 'rectangle',
          'x': 4.0,
          'y': 4.0,
          'w': 1.0,
          'h': 1.0,
          'fixed': true,
          if (kind == 'zone') 'zoneFill': 'Invisible',
        });
      }
      rows(store.events[1], 'items').addAll([
        image('backup-image-a')
          ..['angle'] = 90.0
          ..['fixed'] = true,
        image('backup-image-b')..['x'] = 6.0,
      ]);
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
      final backedUp = readEventBackup(saved!);
      expect(backedUp.length, 2);
      expect(
        rows(backedUp[1], 'items').where((i) => i['kind'] == 'image').toList(),
        rows(
          store.events[1],
          'items',
        ).where((i) => i['kind'] == 'image').toList(),
      );
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
      final restored = clone(store.events.last)..['id'] = store.events[1]['id'];
      expect(
        restored,
        store.events[1],
        reason: 'Full restoration retains every field, object and position',
      );
      for (final kind in ['zone', 'obstacle', 'entry', 'exit']) {
        expect(rows(restored, 'items').any((i) => i['kind'] == kind), true);
      }
      await tester.runAsync(() => File(path).delete());
      expect(tester.takeException(), isNull);
    },
  );
}
