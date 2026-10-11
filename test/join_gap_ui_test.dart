import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'joining_test.dart' show table, plan;
import 'attributions_test.dart' show SnapshotStore, desktop;

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> choose(WidgetTester tester, String current, String value) async {
  final f = find.text(current).last;
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Editing a table opens its junction locally and undo restores all positions',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore()
        ..saved = plan([
          table('a', 2, 2),
          table('b', 3.8, 2),
          table('c', 5.6, 2),
        ], 'Petits côtés');
      final before = clone(store.saved);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-item-b')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-tool-edit')));
      await tester.pumpAndSettle();
      await choose(tester, 'Hériter', 'Personnaliser');
      await tester.ensureVisible(
        field('Espacement de jonction (m, 0 = contact)'),
      );
      await tester.enterText(
        field('Espacement de jonction (m, 0 = contact)'),
        '0,60',
      );
      await save(tester);
      expect(number(tables(store.saved)[0]['x']), closeTo(1.4, 1e-8));
      expect(number(tables(store.saved)[1]['x']), 3.8);
      expect(number(tables(store.saved)[2]['x']), closeTo(6.2, 1e-8));
      expect(tables(store.saved)[1]['joinGap'], .6);
      for (var i = 0; i < 3; i++) {
        for (final key in ['y', 'w', 'h', 'rotation', 'capacity']) {
          expect(tables(store.saved)[i][key], tables(before)[i][key]);
        }
      }
      expect(tables(store.saved)[1].containsKey('_applyJoinGapNow'), false);
      await tester.tap(find.byTooltip('Annuler'));
      await tester.pumpAndSettle();
      expect(store.saved['items'], before['items']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'General, model and plan-table editors preserve inheritance, zero and positions',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore();
      final before = clone(tables(store.saved).first);
      final modelId = before['type'];
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobilier').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('join-gap-defaults')));
      await tester.pumpAndSettle();
      await tester.enterText(
        field('Espacement entre tables jointes (m, 0 = contact)'),
        '0,10',
      );
      await save(tester);
      expect(store.saved['joinGap'], .1);
      await tester.tap(find.widgetWithText(TextButton, 'Modifier').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(field('Espacement de jonction (m, 0 = contact)'))
            .enabled,
        false,
      );
      await choose(tester, 'Hériter', 'Personnaliser');
      await tester.enterText(
        field('Espacement de jonction (m, 0 = contact)'),
        '0,02',
      );
      await choose(tester, 'Les deux bords', 'Premier bord');
      await save(tester);
      // Decline propagation of unrelated dimensions/capacities.
      await tester.tap(find.text('Annuler').last);
      await tester.pumpAndSettle();
      expect(
        rows(
          store.saved,
          'types',
        ).firstWhere((t) => t['id'] == modelId)['joinGap'],
        .02,
      );
      expect(
        tableJoinSettings(store.saved, tables(store.saved).first)['joinGap'],
        .02,
      );
      await tester.tap(find.text('Plan de salle').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('plan-item-${before['id']}')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-tool-edit')));
      await tester.pumpAndSettle();
      await choose(tester, 'Hériter', 'Personnaliser');
      await tester.ensureVisible(
        field('Espacement de jonction (m, 0 = contact)'),
      );
      await tester.enterText(
        field('Espacement de jonction (m, 0 = contact)'),
        '0',
      );
      await save(tester);
      final t = tables(store.saved).first;
      expect(t['joinGap'], 0);
      expect(t['x'], before['x']);
      expect(t['y'], before['y']);
      expect(t['rotation'], before['rotation']);
      expect(t['w'], before['w']);
      expect(t['h'], before['h']);
      expect(tableJoinSettings(store.saved, t)['joinGap'], 0);
      validateProject(store.saved);
      expect(tester.takeException(), null);
    },
  );
}
