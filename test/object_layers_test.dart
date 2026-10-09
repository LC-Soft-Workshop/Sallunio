import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/plan_export.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;

Json object(String kind) => {
  'id': 'background-$kind',
  'kind': kind,
  'label': 'Objet fictif',
  'shape': 'rectangle',
  'x': 3.0,
  'y': 3.0,
  'w': 4.0,
  'h': 2.0,
  'fixed': false,
  if (kind == 'zone') 'zoneFill': 'Plein',
};

void main() {
  for (final kind in ['entry', 'exit', 'door']) {
    testWidgets(
      '$kind resizes from the outside of its handle, undo and lock work',
      (tester) async {
        desktop(tester);
        final store = SnapshotStore(), item = object(kind);
        store.saved['items'] = [item];
        store.saved['groups'] = [];
        await tester.pumpWidget(Tableo(store: store));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('plan-item-${item['id']}')));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        final handle = find.byKey(
          ValueKey('resize-${item['id']}-bottom-right'),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(handle) + const Offset(7, 7),
        );
        for (var i = 0; i < 3; i++) {
          await gesture.moveBy(const Offset(20, 15));
          await tester.pump();
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(number(rows(store.saved, 'items').single['w']), greaterThan(4));
        expect(number(rows(store.saved, 'items').single['h']), greaterThan(2));
        await tester.tap(find.byTooltip('Annuler'));
        await tester.pumpAndSettle();
        expect(rows(store.saved, 'items').single, item);
        final fixed = find.text('Position fixée', skipOffstage: false);
        await tester.ensureVisible(fixed);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Position fixée'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('resize-${item['id']}-bottom-right')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final kind in ['zone', 'obstacle', 'entry', 'exit', 'door']) {
    testWidgets(
      'Tables remain selectable over overlapping $kind; collision remains',
      (tester) async {
        desktop(tester);
        final store = SnapshotStore(),
            background = object(kind),
            table = tables(store.saved)[0];
        table['x'] = 4.0;
        table['y'] = 3.4;
        store.saved['items'] = [table, background];
        store.saved['groups'] = [];
        final before = clone(store.saved);
        expect(issues(before).any((e) => e.contains('chevauchement')), true);
        await tester.pumpWidget(Tableo(store: store));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('plan-item-${table['id']}')));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        final painters = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<ItemPainter>()
            .toList();
        expect(painters.last.item['id'], table['id']);
        expect(painters.last.selected, true);
        expect(painters.last.conflict, true);
        expect(painters.first.selected, false);
        expect(store.saved, before);
        expect(
          find.byKey(ValueKey('resize-${table['id']}-bottom-right')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'Paint and PDF layer order is stable without changing geometry or data',
    () {
      final p = demoProject(),
          table = tables(p)[0],
          a = object('zone'),
          b = object('obstacle');
      p['groups'] = [];
      table['x'] = 4.0;
      table['y'] = 3.4;
      b['x'] = 2.0;
      p['items'] = [table, a, b];
      final before = clone(p);
      expect(planPaintOrder(p).map((item) => item['id']), [
        a['id'],
        b['id'],
        table['id'],
      ]);
      final svg = planSvg(p);
      expect(
        svg.indexOf('translate(300.0 300.0)'),
        lessThan(svg.indexOf('translate(400.0 340.0)')),
      );
      final foreground = planSvg(p, tablesOnly: true, withGrid: false);
      expect(foreground.contains('fill="white"'), false);
      expect(foreground.contains('translate(300.0 300.0)'), false);
      expect(foreground.contains('translate(400.0 340.0)'), true);
      expect(foreground.contains('#ff0000'), true);
      expect(p, before);
    },
  );
  test(
    'Resize eligibility excludes tables, obstacles and all locked objects',
    () {
      final p = demoProject();
      for (final kind in [
        'zone',
        'entry',
        'exit',
        'door',
        'table',
        'obstacle',
      ]) {
        final item = object(kind), before = clone(object(kind));
        resizeZone(p, item, before, .5, .4, 'top-left');
        if (['table', 'obstacle'].contains(kind)) {
          expect(item, before);
        } else {
          expect(number(item['x']) + number(item['w']), 7);
          expect(number(item['y']) + number(item['h']), 5);
        }
        item['fixed'] = true;
        final locked = clone(item);
        resizeZone(p, item, locked, 2, 2, 'bottom-right');
        expect(item, locked);
      }
    },
  );
}
