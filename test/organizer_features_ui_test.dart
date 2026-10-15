import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'joining_test.dart' show table;
import 'plan_toolbar_test.dart' show clickTool;

Future<void> action(WidgetTester t, String value) async {
  await clickTool(t, 'organize');
  await t.tap(
    find.byWidgetPredicate(
      (w) => w is PopupMenuItem<String> && w.value == value,
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Plan search, numeric arrows and reversible renumber preview', (
    t,
  ) async {
    desktop(t);
    final store = SnapshotStore();
    store.saved['groups'] = <Json>[];
    store.saved['items'] = [table('T20', 1, 2), table('T10', 5, 2)];
    await t.pumpWidget(Tableo(store: store));
    await t.pumpAndSettle();
    await action(t, 'search');
    await t.enterText(
      find.widgetWithText(TextField, 'Numéro, modèle, groupe ou personne'),
      'T20',
    );
    await t.pumpAndSettle();
    await t.tap(find.text('T20').last);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(tables(store.saved).first['x'], closeTo(1.01, 1e-6));
    final original = clone(store.saved);
    await action(t, 'numbers');
    expect(find.textContaining('déjà imprimé'), findsOneWidget);
    await t.tap(find.text('Annuler').last);
    await t.pumpAndSettle();
    expect(store.saved['items'], original['items']);
    await action(t, 'numbers');
    await t.tap(find.text('Valider les nouveaux numéros'));
    await t.pumpAndSettle();
    expect(tables(store.saved).map((i) => i['label']), ['T1', 'T2']);
    await t.tap(find.byTooltip('Annuler'));
    await t.pumpAndSettle();
    expect(store.saved['items'], original['items']);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Rectangle selection selects the full furniture inside its bounds',
    (t) async {
      desktop(t);
      final store = SnapshotStore();
      store.saved['groups'] = <Json>[];
      store.saved['items'] = [
        table('a', 1, 2),
        table('b', 4, 2),
        table('c', 8, 2),
      ];
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      await clickTool(t, 'select');
      await t.tap(
        find.byWidgetPredicate(
          (w) => w is CheckedPopupMenuItem<String> && w.value == 'rectangle',
        ),
      );
      await t.pumpAndSettle();
      final a = t.getRect(find.byKey(const ValueKey('plan-item-a'))),
          b = t.getRect(find.byKey(const ValueKey('plan-item-b')));
      final unchangedFurniture = t.widget(
        find.byKey(const ValueKey('plan-item-a')),
      );
      final gesture = await t.startGesture(a.topLeft - const Offset(10, 10));
      await t.pump();
      for (var n = 1; n <= 20; n++) {
        await gesture.moveTo(
          Offset.lerp(
            a.topLeft - const Offset(10, 10),
            b.bottomRight + const Offset(10, 10),
            n / 20,
          )!,
        );
        await t.pump();
        expect(
          t.widget(find.byKey(const ValueKey('plan-item-a'))),
          same(unchangedFurniture),
          reason: 'Rectangle redraw must not rebuild furniture or recalculate diagnostics',
        );
      }
      await gesture.up();
      await t.pumpAndSettle();
      expect(find.textContaining('2 table(s)'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Waiting-list status is visible, filterable and reversible', (
    t,
  ) async {
    desktop(t);
    final store = SnapshotStore();
    store.saved['groups'] = [rows(store.saved, 'groups').first];
    await t.pumpWidget(Tableo(store: store));
    await t.pumpAndSettle();
    await t.tap(find.text('Réservations').first);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Mettre en attente'),
      150,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('reservations-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      t.element(find.widgetWithText(TextButton, 'Mettre en attente')),
      alignment: .5,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Mettre en attente'));
    await t.pumpAndSettle();
    await t.tap(find.text('Confirmer').last);
    await t.pumpAndSettle();
    expect(rows(store.saved, 'groups').single['waiting'], true);
    expect(find.text('Confirmer la réservation'), findsOneWidget);
    await t.tap(find.byTooltip('Annuler'));
    await t.pumpAndSettle();
    expect(rows(store.saved, 'groups').single['waiting'], isNot(true));
    expect(t.takeException(), isNull);
  });
}
