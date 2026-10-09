import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';

import 'attributions_test.dart' show desktop;

class EventStore extends Store {
  final events = [demoProject()];
  EventStore() {
    directory = 'Événements fictifs';
  }
  @override
  Future<List<Json>> load() async => events.map(clone).toList();
  @override
  Future<void> save(Json p) async {
    events.removeWhere((e) => e['id'] == p['id']);
    events.add(clone(p));
  }

  @override
  Future<void> delete(String id) async {
    events.removeWhere((e) => e['id'] == id);
    demoOnEmpty = false;
  }
}

void main() {
  testWidgets(
    'Event deletion is visible in event view, confirms and leaves last deletion empty',
    (tester) async {
      desktop(tester);
      final store = EventStore();
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Événements').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(store.events.length, 1);
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(store.events, isEmpty);
      expect(find.text('Aucun événement'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Aucun événement'), findsOneWidget);
      expect(find.text('Créer un événement'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('SQLite remembers intentional empty list after reopening', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tableo-event-delete-',
    );
    final store = Store();
    await store.open(path: directory.path);
    final p = demoProject();
    await store.save(p);
    await store.delete(p['id']);
    await store.close();
    final reopened = Store();
    await reopened.open(path: directory.path);
    expect(await reopened.load(), isEmpty);
    expect(reopened.demoOnEmpty, false);
    await reopened.close();
    await directory.delete(recursive: true);
  });
}
