import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'joining_test.dart' show table, plan, type;
import 'ui_test.dart' show MemoryStore;

void main() {
  testWidgets(
    'Outside cleanup preserves stock and fixed tables; full models are disabled with tooltip',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = plan([
        table('inside', 3, 3)..['type'] = 'alpha',
        table('outside', 13, 2)
          ..addAll({'type': 'alpha', 'unplacedByArrangement': true}),
        table('collision', 3, 3)..['type'] = 'beta',
        table('fixed-outside', 16, 2)..addAll({'type': 'beta', 'fixed': true}),
      ], 'Aucun');
      p['types'] = [
        type('alpha', quantity: 2, limit: 2),
        type('beta', quantity: 5, limit: 5),
      ];
      final before = clone(p);
      expect(
        tableOutsideRoom(p, tables(p).firstWhere((t) => t['id'] == 'outside')),
        true,
      );
      await tester.pumpWidget(Tableo(store: MemoryStore([p])));
      await tester.pumpAndSettle();
      final add = find.byKey(const ValueKey('plan-tool-add'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobilier').last);
      await tester.pumpAndSettle();
      final full = find.byKey(const ValueKey('add-table-type-alpha'));
      expect(tester.widget<MenuItemButton>(full).onPressed, isNull);
      expect(
        tester
            .widget<MenuItemButton>(
              find.byKey(const ValueKey('add-table-type-beta')),
            )
            .onPressed,
        isNotNull,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(full));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(
        find.text('Maximum autorisé atteint : 2 élément(s) de mobilier.'),
        findsOneWidget,
      );
      await mouse.removePointer();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      if (find.byType(PopupMenuItem<String>).evaluate().isNotEmpty) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      final remove = find.byKey(const ValueKey('plan-tool-remove-outside'));
      expect(tester.widget<IconButton>(remove).onPressed, isNotNull);
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tables(p).map((t) => t['id']),
        unorderedEquals(['inside', 'collision', 'fixed-outside']),
      );
      expect(p['types'], before['types']);
      expect(tester.widget<IconButton>(remove).onPressed, isNull);
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobilier').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MenuItemButton>(
              find.byKey(const ValueKey('add-table-type-alpha')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Annuler'));
      await tester.pumpAndSettle();
      expect(p['items'], before['items']);
    },
  );
}
