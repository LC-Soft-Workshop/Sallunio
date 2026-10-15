import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/keyboard_dialog.dart';
import 'package:tableo/main.dart';
import 'package:tableo/domain.dart';

import 'ui_test.dart' show MemoryStore;
import 'joining_test.dart' show table, plan;

void main() {
  testWidgets('Dialog Enter validates, Escape cancels, Tab visits inputs', (
    tester,
  ) async {
    final first = TextEditingController(), second = TextEditingController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    String? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              accepted = await showDialog<String>(
                context: context,
                builder: (c) => KeyboardDialog(
                  title: const Text('Propriétés'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(controller: first),
                      TextField(controller: second),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(c, first.text + second.text),
                      child: const Text('Enregistrer'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'A');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).last)
          .focusNode
          .hasFocus,
      true,
    );
    await tester.enterText(find.byType(TextField).last, 'B');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(accepted, 'AB');
    expect(find.text('Propriétés'), findsNothing);
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Propriétés'), findsNothing);
    expect(find.text('Ouvrir'), findsOneWidget);
  });

  testWidgets(
    'Delete removes a plan table, preserves stock and supports undo',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = plan([table('T1', 3, 3), table('T2', 6, 3)], 'Aucun')
        ..['types'] = demoProject()['types'];
      final stock = clone(p)['types'];
      await tester.pumpWidget(Tableo(store: MemoryStore([p])));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('plan-item-${tables(p).first['id']}')),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tables(p).any((t) => t['label'] == 'T1'), false);
      expect(p['types'], stock);
      await tester.tap(find.byTooltip('Annuler'));
      await tester.pumpAndSettle();
      expect(tables(p).any((t) => t['label'] == 'T1'), true);
    },
  );
  testWidgets(
    'Delete removes mixed selection but preserves fixed objects and stock',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = plan([
        table('a', 3, 3),
        table('b', 6, 3),
        table('locked', 3, 6)..['fixed'] = true,
      ], 'Aucun');
      p['types'] = demoProject()['types'];
      rows(p, 'items').addAll([
        {
          'id': 'z',
          'kind': 'zone',
          'label': 'Zone fictive',
          'x': 8.0,
          'y': 6.0,
          'w': 1.0,
          'h': 1.0,
          'fixed': false,
        },
        {
          'id': 'keep',
          'kind': 'zone',
          'label': 'Zone conservée',
          'x': 8.0,
          'y': 2.0,
          'w': 1.0,
          'h': 1.0,
          'fixed': false,
        },
      ]);
      final before = clone(p);
      await tester.pumpWidget(Tableo(store: MemoryStore([p])));
      await tester.pumpAndSettle();
      for (final id in ['a', 'b', 'locked', 'z']) {
        if (id != 'a') {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        }
        await tester.tap(find.byKey(ValueKey('plan-item-$id')));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        if (id != 'a') {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        rows(p, 'items').map((i) => i['id']),
        unorderedEquals(['locked', 'keep']),
      );
      expect(p['types'], before['types']);
      await tester.tap(find.byTooltip('Annuler'));
      await tester.pumpAndSettle();
      expect(p['items'], before['items']);
    },
  );
  testWidgets(
    'Property shortcuts preserve text deletion and reject invalid input',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = plan([table('a', 3, 3)], 'Aucun'),
          before = clone(plan([table('a', 3, 3)], 'Aucun'));
      await tester.pumpWidget(Tableo(store: MemoryStore([p])));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-item-a')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-tool-edit')));
      await tester.pumpAndSettle();
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'ABC');
      final controller = tester.widget<TextField>(field).controller!;
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(controller.text, 'BC');
      expect(tables(p), hasLength(1));
      final width = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Longueur / diamètre (m)',
      );
      await tester.ensureVisible(width);
      await tester.enterText(width, '0');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tables(p).first['w'], before['items'][0]['w']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(p['items'], before['items']);
    },
  );
}
