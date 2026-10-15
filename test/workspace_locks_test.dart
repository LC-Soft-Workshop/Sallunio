import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'plan_toolbar_test.dart' show clickTool, tool;

void main() {
  testWidgets(
    'Locked plan blocks movement and editing but accepts reservation assignment',
    (t) async {
      desktop(t);
      final store = SnapshotStore();
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      await clickTool(t, 'plan-lock');
      expect(store.saved['planLocked'], true);
      final before = rows(store.saved, 'items').map(clone).toList();
      final item = find.byKey(
        ValueKey('plan-item-${tables(store.saved).first['id']}'),
      );
      await t.drag(item, const Offset(70, 40));
      await t.pumpAndSettle();
      expect(rows(store.saved, 'items'), before);
      await t.tap(item);
      await t.pump(const Duration(milliseconds: 350));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
      await t.pumpAndSettle();
      expect(find.textContaining('Retirer 1'), findsNothing);
      expect(t.widget<IconButton>(tool('edit')).onPressed, isNull);
      expect(t.widget<IconButton>(tool('add')).onPressed, isNull);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Disposer mobilier'),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.text('Réservations').first);
      await t.pumpAndSettle();
      await t.tap(find.text('2. Attribuer les groupes aux tables'));
      await t.pumpAndSettle();
      expect(workspaceStats(store.saved)['assigned'], 19);
      expect(rows(store.saved, 'items'), before);
      await t.tap(find.text('Voir les attributions'));
      await t.pumpAndSettle();
      await t.tap(find.text('Plan de salle').first);
      await t.pumpAndSettle();
      await clickTool(t, 'plan-lock');
      expect(store.saved['planLocked'], false);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Event read-only persists, blocks mutations and permits explicit unlock',
    (t) async {
      desktop(t);
      final store = SnapshotStore();
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('event-lock')));
      await t.pumpAndSettle();
      expect(store.saved['eventLocked'], true);
      final before = clone(store.saved);
      await t.drag(
        find.byKey(ValueKey('plan-item-${tables(store.saved).first['id']}')),
        const Offset(70, 40),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('plan-zoom-in')));
      await t.pumpAndSettle();
      expect(store.saved, before);
      await t.tap(find.text('Réservations').first);
      await t.pumpAndSettle();
      final absorber = t
          .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
          .where((w) => w.absorbing);
      expect(absorber, isNotEmpty);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      expect(find.text('Événement verrouillé — lecture seule'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('event-lock')));
      await t.pumpAndSettle();
      expect(store.saved['eventLocked'], false);
      await t.tap(find.text('Réservations').first);
      await t.pumpAndSettle();
      await t.tap(find.text('2. Attribuer les groupes aux tables'));
      await t.pumpAndSettle();
      expect(workspaceStats(store.saved)['assigned'], 19);
      expect(t.takeException(), isNull);
    },
  );
}
