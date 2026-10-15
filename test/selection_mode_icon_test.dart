import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'plan_toolbar_test.dart' show tool, clickTool;

void main() {
  testWidgets('Selection icon and tooltip follow all three modes', (t) async {
    desktop(t);
    await t.pumpWidget(Tableo(store: SnapshotStore()));
    await t.pumpAndSettle();
    void check(IconData icon, String name) {
      expect(
        find.descendant(of: tool('select'), matching: find.byIcon(icon)),
        findsOneWidget,
      );
      expect(find.byTooltip('Sélection — $name'), findsOneWidget);
    }

    check(Icons.ads_click, 'multiple');
    for (final mode in ['rectangle', 'group', 'multiple']) {
      await clickTool(t, 'select');
      await t.tap(
        find.byWidgetPredicate(
          (w) => w is CheckedPopupMenuItem<String> && w.value == mode,
        ),
      );
      await t.pumpAndSettle();
      check(
        mode == 'rectangle'
            ? Icons.select_all
            : mode == 'group'
            ? Icons.widgets_outlined
            : Icons.ads_click,
        mode == 'group' ? 'groupée' : mode,
      );
    }
    expect(t.takeException(), isNull);
  });
}
