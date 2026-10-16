import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/external_links.dart';
import 'package:tableo/github_updates.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show desktop;
import 'event_delete_test.dart' show EventStore;

class FakeUpdates implements UpdateService {
  int calls = 0;
  @override
  Uri get changelogUrl =>
      Uri.https('github.com', '/example/tableo/blob/main/CHANGELOG.md');
  @override
  Future<UpdateInfo?> check() async {
    calls++;
    final url = Uri.https('github.com', '/example/tableo/releases/tag/v1.0.32');
    return UpdateInfo(version: '1.0.32', releaseUrl: url, changelogUrl: url);
  }
}

class FakeLinks implements LinkOpener {
  final opened = <Uri>[];
  @override
  Future<void> open(Uri uri) async => opened.add(uri);
}

void main() {
  testWidgets(
    'Available update and French notes accessible even without an event',
    (tester) async {
      desktop(tester);
      final store = EventStore()
        ..events.clear()
        ..demoOnEmpty = false;
      final updates = FakeUpdates();
      final links = FakeLinks();
      await tester.pumpWidget(
        Tableo(store: store, updateService: updates, linkOpener: links),
      );
      await tester.pumpAndSettle();
      expect(updates.calls, 1);
      expect(find.text('Aucun événement'), findsOneWidget);
      await tester.tap(find.text('Mise à jour 1.0.32'));
      await tester.pumpAndSettle();
      expect(find.text('Sallunio 1.0.32 est disponible'), findsOneWidget);
      await tester.tap(find.text('Voir les changements'));
      await tester.pumpAndSettle();
      expect(links.opened.single.path, '/example/tableo/releases/tag/v1.0.32');
      expect(store.events, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
