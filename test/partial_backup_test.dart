import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/event_backup.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';

class InjectionStore extends Store {
  final Json current = demoProject()..['name'] = 'Événement ouvert';
  Json? saved;
  InjectionStore() {
    directory = 'tmp';
  }
  @override
  Future<List<Json>> load() async => [current];
  @override
  Future<void> save(Json p) async {
    saved = clone(p);
  }

  @override
  Future<void> saveEvents(List<Json> events) async {
    expect(events.length, 1);
    expect(events.single['id'], current['id']);
    saved = clone(events.single);
  }
}

void main() {
  Json source() {
    final p = demoProject();
    allocate(p);
    final groups = rows(p, 'groups');
    groups.first['proximity'] = {groups[1]['id']: 'near'};
    groups.first['separate'] = groups[1]['id'];
    groups.first['reserved'] = tables(p).first['id'];
    return p;
  }

  test(
    'Reservations only preserve destination and clear foreign table links',
    () {
      final target = demoProject(), backup = source();
      final original = clone(target);
      final result = injectEventBackup(
        target,
        [backup],
        furniture: false,
        reservations: true,
      );
      expect(result['id'], target['id']);
      expect(result['room'], target['room']);
      expect(result['items'], target['items']);
      expect(result['types'], target['types']);
      expect(
        rows(result, 'groups').take(rows(target, 'groups').length).toList(),
        target['groups'],
      );
      final imported = rows(
        result,
        'groups',
      ).skip(rows(target, 'groups').length).toList();
      expect(
        imported.every(
          (g) =>
              (g['alloc'] as List).isEmpty &&
              g['reserved'] == '' &&
              g['locked'] == false,
        ),
        true,
      );
      expect(imported.first['separate'], imported[1]['id']);
      expect(imported.first['proximity'], {imported[1]['id']: 'near'});
      expect(target, original);
      validateProject(result);
    },
  );
  test('Furniture only adds stock and placed tables; preserves reservations and room objects', () {
    final target = demoProject(), backup = source();
    final result = injectEventBackup(
      target,
      [backup],
      furniture: true,
      reservations: false,
    );
    expect(result['groups'], target['groups']);
    expect(result['room'], target['room']);
    expect(
      rows(result, 'types').length,
      rows(target, 'types').length + rows(backup, 'types').length,
    );
    expect(
      tables(result).length,
      tables(target).length + tables(backup).length,
    );
    expect(
      rows(result, 'items').where((i) => i['kind'] != 'table').length,
      rows(target, 'items').where((i) => i['kind'] != 'table').length,
    );
    expect(
      tables(result).map((t) => t['id']).toSet().length,
      tables(result).length,
    );
    expect(
      tables(result).map((t) => t['label']).toSet().length,
      tables(result).length,
    );
    validateProject(result);
  });
  test('Both retain assignments and remap every reference, even across multiple sources with same IDs', () {
    final target = demoProject(), backup = source();
    final result = injectEventBackup(
      target,
      [backup, clone(backup)],
      furniture: true,
      reservations: true,
    );
    final groupCount = rows(target, 'groups').length;
    final imported = rows(result, 'groups').skip(groupCount).toList();
    final oldTables = tables(target).map((t) => t['id']).toSet();
    final allTables = tables(result).map((t) => t['id']).toSet();
    for (final group in imported) {
      for (final allocation in group['alloc']) {
        expect(allTables.contains(allocation['table']), true);
        expect(oldTables.contains(allocation['table']), false);
      }
    }
    expect(imported.first['reserved'], isNot(backup['groups'][0]['reserved']));
    expect(imported.first['proximity'], {imported[1]['id']: 'near'});
    expect(imported[groupCount]['proximity'], {
      imported[groupCount + 1]['id']: 'near',
    });
    expect(imported.map((g) => g['id']).toSet().length, imported.length);
    validateProject(result);
  });
  testWidgets(
    'Reservations injection updates open event, is undoable and does not create an event',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = InjectionStore();
      final original = clone(store.current);
      final path = File('tmp/injection-${uid()}.tableo.json').absolute.path;
      await tester.runAsync(
        () => File(path).writeAsString(jsonEncode(eventBackup([source()]))),
      );
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
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
      await tester.tap(find.text('Importer la sélection'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Réservations'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(
                CheckboxListTile,
                'Restauration complète des événements',
              ),
            )
            .value,
        false,
      );
      await tester.tap(find.text('Importer'));
      await tester.pumpAndSettle();
      expect(store.saved!['name'], 'Événement ouvert');
      expect(
        rows(store.saved!, 'groups').length,
        rows(original, 'groups').length * 2,
      );
      expect(store.saved!['items'], original['items']);
      expect(find.text('Repas associatif • démonstration'), findsNothing);
      await tester.tap(find.byTooltip('Annuler'));
      await tester.pumpAndSettle();
      expect(
        rows(store.saved!, 'groups').length,
        rows(original, 'groups').length,
      );
      await tester.runAsync(() => File(path).delete());
      expect(tester.takeException(), isNull);
    },
  );
}
