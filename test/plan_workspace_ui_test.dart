import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'parcours_ui_test.dart' show fonts;
import 'ui_test.dart' show MemoryStore;
import 'joining_test.dart' show table;
import 'plan_toolbar_test.dart' show clickTool, tool;

void main() {
  testWidgets(
    'Each event restores its own view and right click opens object actions',
    (t) async {
      desktop(t);
      final a = demoProject()..['name'] = 'Plan A',
          b = demoProject()..['name'] = 'Plan B';
      b['id'] = uid();
      await t.pumpWidget(Tableo(store: MemoryStore([a, b])));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('plan-zoom-in')));
      await t.pumpAndSettle();
      await t.tap(find.text('Plan B').first);
      await t.pumpAndSettle();
      expect(find.text('100 %'), findsOneWidget);
      await t.tap(find.text('Plan A').first);
      await t.pumpAndSettle();
      expect(find.text('125 %'), findsOneWidget);
      final item = find.byKey(ValueKey('plan-item-${tables(a).first['id']}'));
      final mouse = await t.createGesture(
        kind: ui.PointerDeviceKind.mouse,
        buttons: 2,
      );
      await mouse.down(t.getCenter(item));
      await mouse.up();
      await t.pumpAndSettle();
      expect(find.text('Verrouiller'), findsOneWidget);
      await t.tap(find.text('Verrouiller'));
      await t.pumpAndSettle();
      expect(tables(a).first['fixed'], true);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Quantity uses authorized remainder, direct last item and disabled empty model',
    (t) async {
      desktop(t);
      final store = SnapshotStore();
      final p = store.saved;
      p['groups'] = <Json>[];
      p['items'] = <Json>[];
      p['types'] = [
        {
          'id': 'model',
          'name': 'Modèle test',
          'shape': 'rectangle',
          'w': 1.8,
          'h': .8,
          'capacity': 6,
          'quantity': 20,
          'limit': 3,
          'source': 'Propre',
          'enabled': true,
          'seating': 'Chaises',
          'sides': 'Tous côtés',
          'usage': furnitureUses.first,
        },
      ];
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      Future<void> model() async {
        await t.ensureVisible(tool('add'));
        await t.tap(tool('add'));
        await t.pumpAndSettle();
        await t.tap(find.text('Mobilier').last);
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('add-table-type-model')));
        await t.pumpAndSettle();
      }

      await model();
      expect(find.text('Encore disponibles sur le plan : 3'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('add-furniture-quantity')),
        '4',
      );
      await t.pump();
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Ajouter'))
            .onPressed,
        isNull,
      );
      await t.enterText(
        find.byKey(const ValueKey('add-furniture-quantity')),
        '2',
      );
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Ajouter'));
      await t.pumpAndSettle();
      expect(tables(store.saved).length, 2);
      await model();
      expect(tables(store.saved).length, 3);
      expect(
        find.byKey(const ValueKey('add-furniture-quantity')),
        findsNothing,
      );
      await t.tap(tool('add'));
      await t.pumpAndSettle();
      await t.tap(find.text('Mobilier').last);
      await t.pumpAndSettle();
      expect(
        t
            .widget<MenuItemButton>(
              find.byKey(const ValueKey('add-table-type-model')),
            )
            .onPressed,
        isNull,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Ctrl toggles complete groups, Escape deselects and view options are saved',
    (t) async {
      desktop(t);
      final store = SnapshotStore();
      final p = store.saved;
      p['items'] = [
        table('a', 1.4, 3),
        table('b', 3.2, 3),
        table('c', 7, 3),
        table('d', 8.8, 3),
      ];
      p['groups'] = <Json>[];
      p['joining'] = 'Petits côtés';
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      await clickTool(t, 'assembly');
      Future<void> select(String id) async {
        await t.tap(find.byKey(ValueKey('plan-item-$id')));
        await t.pump(const Duration(milliseconds: 350));
        await t.pumpAndSettle();
      }

      await select('a');
      expect(find.textContaining('2 table(s)'), findsOneWidget);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await select('c');
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(find.textContaining('4 table(s)'), findsOneWidget);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await select('a');
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(find.textContaining('2 table(s)'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Aucune sélection'), findsOneWidget);
      await clickTool(t, 'display');
      expect(find.text('Afficher la légende'), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Légende'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('plan-zoom-in')));
      await t.pumpAndSettle();
      expect(find.text('125 %'), findsOneWidget);
      expect(store.saved['planView']['legend'], true);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      expect(find.text('125 %'), findsOneWidget);
      expect(find.text('Légende'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Compact toolbar screenshot and object creation presets', (
    t,
  ) async {
    desktop(t);
    await fonts(t);
    final store = SnapshotStore();
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-shot'),
        child: Tableo(store: store),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(tool('add'));
    await t.tap(tool('add'));
    await t.pumpAndSettle();
    await t.tap(find.text('Zone').last);
    await t.pumpAndSettle();
    final field = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == 'Fonction',
    );
    expect(
      t.widget<DropdownButtonFormField<String>>(field).initialValue,
      'zone',
    );
    await t.tap(find.text('Annuler').last);
    await t.pumpAndSettle();
    expect(
      t.getTopLeft(find.byKey(const ValueKey('plan-arrange-button'))).dy,
      closeTo(t.getTopLeft(find.byKey(const ValueKey('plan-toolbar'))).dy, 1),
    );
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('workspace-shot')),
    );
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('tmp').create(recursive: true);
      await File('tmp/plan-workspace-preview.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    expect(t.takeException(), isNull);
    t.view.physicalSize = const Size(1024, 768);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Passer au mode sombre'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('tmp/plan-workspace-small-dark.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  });
}
