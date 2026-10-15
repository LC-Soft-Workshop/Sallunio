import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'arrangement_start_test.dart' show room, table;
import 'attributions_test.dart' show desktop;
import 'ui_test.dart' show MemoryStore, immediateArrangement;

void main() {
  testWidgets(
    'Excess tables stay visible, selectable and arrangement can be undone',
    (tester) async {
      desktop(tester);
      final p = room(start: 'Bas droite');
      p['room']['width'] = 4.0;
      p['room']['height'] = 3.0;
      p['items'] = [for (var i = 0; i < 6; i++) table('T$i')];
      final before = clone(p)['items'];
      await tester.pumpWidget(
        Tableo(
          store: MemoryStore([p]),
          arrangementRunner: immediateArrangement,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disposer mobilier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disposer'));
      await tester.pumpAndSettle();
      final pending = tables(p).where((t) => unplacedTable(p, t)).toList();
      expect(pending, isNotEmpty);
      expect(find.text('Hors salle : manque de place'), findsOneWidget);
      expect(find.textContaining('Pas assez de place :'), findsOneWidget);
      final target = find.byKey(ValueKey('plan-item-${pending.last['id']}'));
      final bounds = tester.getRect(target);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(tester.view.physicalSize.width));
      final painter =
          tester
                  .widget<CustomPaint>(
                    find
                        .descendant(
                          of: target,
                          matching: find.byType(CustomPaint),
                        )
                        .first,
                  )
                  .painter
              as ItemPainter;
      expect(painter.conflict, true);
      expect(painter.item['unplacedByArrangement'], true);
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final selectedPainter =
          tester
                  .widget<CustomPaint>(
                    find
                        .descendant(
                          of: target,
                          matching: find.byType(CustomPaint),
                        )
                        .first,
                  )
                  .painter
              as ItemPainter;
      expect(
        selectedPainter.selected,
        true,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .where((t) => t != null && t.contains('X '))
            .join('\n'),
      );
      await tester.tap(find.byTooltip('Annuler'));
      await tester.pumpAndSettle();
      expect(p['items'], before);
      expect(tester.takeException(), isNull);
    },
  );
}
