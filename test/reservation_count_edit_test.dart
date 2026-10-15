import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;

void main() {
  testWidgets(
    'Editing a reservation from 3 to 30 updates saved count and counters',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore();
      store.saved['groups'] = [rows(store.saved, 'groups').last];
      allocate(store.saved);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Modifier'),
        100,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('reservations-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.drag(
        find.byKey(const ValueKey('reservations-list')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifier'));
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (w) =>
            w is TextField && w.decoration?.labelText == 'Nombre de personnes',
      );
      final childField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.labelText ?? '').startsWith('Chaises enfant ('),
      );
      await tester.enterText(childField, '1');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('encore disponible(s) dans le stock autorisé'),
        findsOneWidget,
      );
      expect(rows(store.saved, 'groups').single['count'], 3);
      await tester.enterText(childField, '0');
      await tester.enterText(field, '30');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(rows(store.saved, 'groups').single['count'], 30);
      expect(workspaceStats(store.saved)['reserved'], 30);
      expect(find.text('30'), findsWidgets);
      expect(
        find.text('30 personnes réservées • 3 attribuées • 27 à placer'),
        findsOneWidget,
      );
      expect(find.textContaining('Effectif modifié : 3 → 30'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      expect(workspaceStats(store.saved)['reserved'], 30);
      expect(tester.takeException(), isNull);
    },
  );
}
