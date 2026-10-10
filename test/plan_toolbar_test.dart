import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'joining_test.dart' show table;

Finder tool(String id) => find.byKey(ValueKey('plan-tool-$id'));
Future<void> clickTool(WidgetTester tester, String id) async {
  await tester.ensureVisible(tool(id));
  await tester.pumpAndSettle();
  await tester.tap(tool(id));
  await tester.pumpAndSettle();
}

Json paintedTable(WidgetTester tester, String id) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<ItemPainter>()
    .firstWhere((p) => p.item['id'] == id)
    .item;

void main() {
  testWidgets(
    'Square tools occupy the left canvas edge; rotation appears once',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore();
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      for (final name in [
        'magnet',
        'labels',
        'select',
        'filter',
        'assembly',
        'rotate',
        'measure',
        'adapted',
        'fixed',
        'edit',
        'tables',
        'objects',
        'joining',
        'wall',
        'center',
      ]) {
        expect(tool(name), findsOneWidget);
        final size = tester.getSize(tool(name));
        expect(size.width, 38);
        expect(size.height, 38);
      }
      final item = find.byKey(
        ValueKey('plan-item-${tables(store.saved)[0]['id']}'),
      );
      expect(
        tester.getTopLeft(tool('magnet')).dx,
        lessThan(tester.getTopLeft(item).dx),
      );
      expect(find.text('Toutes les tables : 90°'), findsNothing);
      expect(find.byIcon(Icons.rotate_right), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Wall and joining menus save choices, filters stay temporary', (
    tester,
  ) async {
    desktop(tester);
    final store = SnapshotStore();
    await tester.pumpWidget(Tableo(store: store));
    await tester.pumpAndSettle();
    await clickTool(tester, 'wall');
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CheckedPopupMenuItem<String> && w.value == 'Mur gauche',
      ),
    );
    await tester.pumpAndSettle();
    expect(store.saved['wallSupport'], 'Mur gauche');
    await clickTool(tester, 'joining');
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CheckedPopupMenuItem<String> && w.value == 'Petits côtés',
      ),
    );
    await tester.pumpAndSettle();
    expect(store.saved['joining'], 'Petits côtés');
    final before = clone(store.saved);
    await clickTool(tester, 'filter');
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CheckedPopupMenuItem<String> && w.value == 'Tables vides',
      ),
    );
    await tester.pumpAndSettle();
    expect(store.saved, before);
    await clickTool(tester, 'labels');
    expect(tester.widget<IconButton>(tool('labels')).isSelected, true);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'An assembly magnetically joins another, then detaches with small moves; undo restores data',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore();
      store.saved['items'] = [
        table('a', 1.4, 3),
        table('b', 3.2, 3),
        table('c', 7, 3),
        table('d', 8.8, 3),
      ];
      store.saved['groups'] = [];
      store.saved['joining'] = 'Petits côtés';
      store.saved['aisle'] = 1.2;
      final before = clone(store.saved);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await clickTool(tester, 'assembly');
      final item = find.byKey(const ValueKey('plan-item-a'));
      await tester.tap(item);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(item));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      final scale = tester.getSize(item).width / 1.8;
      final current = number(paintedTable(tester, 'a')['x']);
      await gesture.moveBy(Offset((3.46 - current) * scale, 0));
      await tester.pump();
      expect(number(paintedTable(tester, 'a')['x']), closeTo(3.4, 1e-7));
      expect(number(paintedTable(tester, 'b')['x']), closeTo(5.2, 1e-7));
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<MagneticGuidePainter>(),
        isNotEmpty,
      );
      for (var i = 0; i < 11; i++) {
        await gesture.moveBy(Offset(-.03 * scale, 0));
        await tester.pump();
      }
      expect(number(paintedTable(tester, 'a')['x']), lessThan(3.3));
      await gesture.up();
      await tester.pumpAndSettle();
      final moved = tables(store.saved);
      expect(number(moved[1]['x']) - number(moved[0]['x']), closeTo(1.8, 1e-7));
      expect(moved[2], tables(before)[2]);
      expect(moved[3], tables(before)[3]);
      await tester.tap(find.byTooltip('Annuler'));
      await tester.pumpAndSettle();
      expect(store.saved['items'], before['items']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Alt and the magnet icon allow free positioning', (tester) async {
    desktop(tester);
    final store = SnapshotStore();
    store.saved['items'] = [table('a', 1.4, 3), table('b', 5, 3)];
    store.saved['groups'] = [];
    store.saved['joining'] = 'Petits côtés';
    await tester.pumpWidget(Tableo(store: store));
    await tester.pumpAndSettle();
    final item = find.byKey(const ValueKey('plan-item-a'));
    await tester.tap(item);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final gesture = await tester.startGesture(tester.getCenter(item));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final scale = tester.getSize(item).width / 1.8;
    final current = number(paintedTable(tester, 'a')['x']);
    await gesture.moveBy(Offset((3.26 - current) * scale, 0));
    await tester.pump();
    expect(number(paintedTable(tester, 'a')['x']), closeTo(3.26, 1e-7));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(number(tables(store.saved)[0]['x']), closeTo(3.26, 1e-7));
    await clickTool(tester, 'magnet');
    expect(tester.widget<IconButton>(tool('magnet')).isSelected, false);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Lock and edit tools act on the selected background object', (
    tester,
  ) async {
    desktop(tester);
    final store = SnapshotStore();
    final zone = rows(
      store.saved,
      'items',
    ).firstWhere((i) => i['kind'] == 'zone');
    zone['fixed'] = false;
    await tester.pumpWidget(Tableo(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('plan-item-${zone['id']}')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await clickTool(tester, 'fixed');
    expect(
      rows(
        store.saved,
        'items',
      ).firstWhere((i) => i['id'] == zone['id'])['fixed'],
      true,
    );
    await clickTool(tester, 'fixed');
    expect(
      rows(
        store.saved,
        'items',
      ).firstWhere((i) => i['id'] == zone['id'])['fixed'],
      false,
    );
    await clickTool(tester, 'edit');
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
