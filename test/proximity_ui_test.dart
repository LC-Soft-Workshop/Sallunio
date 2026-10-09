import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;

void main() {
  testWidgets(
    'Save near and far preferences without moving existing assignments',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore();
      allocate(store.saved);
      final groups = rows(store.saved, 'groups');
      final allocations = groups
          .map((g) => clone({'alloc': g['alloc']}))
          .toList();
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      final card = find.ancestor(
        of: find.text('Morgan (fictif)'),
        matching: find.byType(Card),
      );
      final button = find.descendant(
        of: card,
        matching: find.text('Proximité'),
      );
      await tester.scrollUntilVisible(
        button,
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('reservations-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await tester.tap(fields.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proche de ce groupe').last);
      await tester.pumpAndSettle();
      await tester.tap(fields.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Loin de ce groupe').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      final saved = rows(store.saved, 'groups');
      expect(
        reservationPreferences(store.saved, saved[1])[saved[0]['id']],
        'near',
      );
      expect(
        reservationPreferences(store.saved, saved[1])[saved[2]['id']],
        'far',
      );
      expect(
        saved.map((g) => clone({'alloc': g['alloc']})).toList(),
        allocations,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
