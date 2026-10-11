import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'join_gap_ui_test.dart' show save;

void main() {
  testWidgets('Creation retains entrances and exits and removes toilets only', (
    tester,
  ) async {
    desktop(tester);
    await tester.pumpWidget(Tableo(store: SnapshotStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ajouter un objet ou une zone'));
    await tester.pumpAndSettle();
    final function = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == 'Fonction',
    );
    await tester.tap(function);
    await tester.pumpAndSettle();
    expect(find.text('Entrée'), findsWidgets);
    expect(find.text('Sortie'), findsWidgets);
    expect(find.text('Zone'), findsWidgets);
    expect(find.text('Toilettes'), findsNothing);
    await tester.tap(find.text('Zone').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final kind in ['zone', 'entry', 'exit']) {
    testWidgets('Include and exclude $kind in reservation preferences', (
      tester,
    ) async {
      desktop(tester);
      final store = SnapshotStore();
      final item = rows(
        store.saved,
        'items',
      ).firstWhere((i) => i['kind'] == kind);
      item['fixed'] = false;
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('plan-item-${item['id']}')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-tool-edit')));
      await tester.pumpAndSettle();
      if (kind != 'zone') {
        final audience = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              (w.decoration.labelText ?? '').startsWith('Public autorisé'),
        );
        await tester.ensureVisible(audience);
        await tester.tap(audience);
        await tester.pumpAndSettle();
        await tester.tap(find.text('PMR avec accompagnants').last);
        await tester.pumpAndSettle();
      }
      final enabled = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText ==
                'Inclure dans les préférences de proximité',
      );
      await tester.ensureVisible(enabled);
      await tester.tap(enabled);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oui').last);
      await tester.pumpAndSettle();
      await save(tester);
      expect(
        proximityTargets(store.saved).map((i) => i['id']),
        contains(item['id']),
      );
      if (kind != 'zone') {
        expect(
          rows(
            store.saved,
            'items',
          ).firstWhere((i) => i['id'] == item['id'])['accessAudience'],
          'PMR avec accompagnants',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Save near and far preferences without moving existing assignments',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore();
      final zone = rows(
        store.saved,
        'items',
      ).firstWhere((i) => i['kind'] == 'zone');
      zone['proximityEnabled'] = 'Oui';
      zone['label'] = 'Bar';
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
      await tester.ensureVisible(fields.at(1));
      await tester.tap(fields.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proche de ce groupe').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(fields.last);
      await tester.tap(fields.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Loin de ce groupe').last);
      await tester.pumpAndSettle();
      final zonePreference = find.byKey(
        ValueKey('proximity-place-${zone['id']}'),
      );
      await tester.ensureVisible(zonePreference);
      await tester.tap(zonePreference);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proche').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      final saved = rows(store.saved, 'groups');
      expect(saved[1]['placeProximity'], {zone['id']: 'near'});
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
