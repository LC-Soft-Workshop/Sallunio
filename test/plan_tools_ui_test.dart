import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'file_dialogs_test.dart' show TestDialogs;

import 'dart:io';

void main() {
  testWidgets(
    'Optional individual name is saved without changing group counts',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore(),
          group = rows(store.saved, 'groups')[0],
          table = tables(store.saved)[0];
      group['count'] = 1;
      group['name'] = 'Groupe fictif';
      group['needs'] = '';
      group['alloc'] = [
        {'table': table['id'], 'count': 1},
      ];
      store.saved['groups'] = [group];
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Préférences', skipOffstage: false).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Préférences').first);
      await tester.pumpAndSettle();
      final name = find.byKey(const ValueKey('person-name-0'));
      await tester.ensureVisible(name);
      await tester.pumpAndSettle();
      await tester.enterText(name, 'Personne fictive');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      final saved = rows(store.saved, 'groups')[0];
      expect(saved['seats'][0]['name'], 'Personne fictive');
      expect(saved['count'], 1);
      expect(saved['alloc'], group['alloc']);
      expect(
        tablePlaceLabels(store.saved, tables(store.saved)[0]).first,
        'Personne fictive',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Adapted place form saves capacity and remains undoable', (
    tester,
  ) async {
    desktop(tester);
    final store = SnapshotStore(), table = tables(store.saved)[0];
    store.saved['groups'] = [];
    await tester.pumpWidget(Tableo(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('plan-item-${table['id']}')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('plan-tool-adapted')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-tool-adapted')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un emplacement adapté'));
    await tester.pumpAndSettle();
    expect(find.textContaining('5 places utilisables'), findsOneWidget);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(effectiveCapacity(store.saved, tables(store.saved)[0]), 5);
    await tester.tap(find.byTooltip('Annuler'));
    await tester.pumpAndSettle();
    expect(effectiveCapacity(store.saved, tables(store.saved)[0]), 6);
    expect(tester.takeException(), isNull);
  });
  testWidgets('CSV menu writes a chosen file without editing reservations', (
    tester,
  ) async {
    desktop(tester);
    final store = SnapshotStore(),
        dialogs = TestDialogs(),
        before = clone(store.saved);
    final folder = Directory('tmp')..createSync(recursive: true);
    final path = '${folder.absolute.path}/fictive-feature-export-${uid()}.csv';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    dialogs.result = path;
    await tester.pumpWidget(Tableo(store: store, fileDialogs: dialogs));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fichiers ▾'));
    await tester.pumpAndSettle();
    expect(find.text('CSV'), findsNothing);
    await tester.tap(find.text('Exporter CSV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exporter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parcourir • Enregistrer sous'));
    await tester.pumpAndSettle();
    for (
      var i = 0;
      i < 50 && find.textContaining('CSV enregistré :').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.textContaining('CSV enregistré :'), findsOneWidget);
    expect(file.existsSync(), true);
    expect(
      parseCsv(file.readAsStringSync()).length,
      rows(before, 'groups').length + 1,
    );
    expect(store.saved, before);
    expect(dialogs.seen.single.save, true);
    expect(tester.takeException(), isNull);
  });
  for (final corner in [
    'top-left',
    'top-right',
    'bottom-left',
    'bottom-right',
  ]) {
    testWidgets(
      'Entire resize handle receives drag at its outer edge: $corner',
      (tester) async {
        desktop(tester);
        final store = SnapshotStore(), p = demoProject();
        final zone = rows(p, 'items').firstWhere((i) => i['kind'] == 'zone');
        zone['x'] = zone['y'] = 4.0;
        zone['fixed'] = false;
        zone['w'] = zone['h'] = 2.0;
        zone['zoneFill'] = 'Invisible';
        p['items'] = [zone];
        p['groups'] = [];
        store.saved = p;
        await tester.pumpWidget(Tableo(store: store));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('plan-item-${zone['id']}')));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        final handle = find.byKey(ValueKey('resize-${zone['id']}-$corner'));
        final center = tester.getCenter(handle);
        final left = corner.contains('left'), top = corner.contains('top');
        // Inside the visible 18px square, on the half outside the object's bounds.
        final gesture = await tester.startGesture(
          center + Offset(left ? -7 : 7, top ? -7 : 7),
        );
        for (var i = 0; i < 3; i++) {
          await gesture.moveBy(Offset(left ? -20 : 20, top ? -20 : 20));
          await tester.pump();
        }
        await gesture.up();
        await tester.pumpAndSettle();
        final saved = rows(store.saved, 'items').single;
        expect(number(saved['w']), greaterThan(2));
        expect(number(saved['h']), greaterThan(2));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Ctrl selection drags both tables rigidly and undo restores the layout',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore();
      final ts = tables(store.saved).take(2).toList();
      ts[0]['x'] = ts[0]['y'] = 3.0;
      ts[1]['x'] = 5.0;
      ts[1]['y'] = 3.0;
      ts[0]['fixed'] = ts[1]['fixed'] = false;
      store.saved['items'] = ts;
      store.saved['groups'] = [];
      final before = clone(store.saved);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('plan-item-${ts[0]['id']}')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.byKey(ValueKey('plan-item-${ts[1]['id']}')));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('plan-item-${ts[0]['id']}'))),
      );
      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(20, 10));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      final moved = tables(store.saved);
      expect(number(moved[0]['x']), greaterThan(3));
      expect(number(moved[1]['x']) - number(moved[0]['x']), closeTo(2, 1e-8));
      await tester.tap(find.byTooltip('Annuler'));
      await tester.pumpAndSettle();
      expect(store.saved['items'], before['items']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Distance measurement uses metres and stays outside saved event',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore(), before = clone(SnapshotStore().saved);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('plan-tool-measure'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final overlay = find.byKey(const ValueKey('distance-overlay'));
      final point = tester.getTopLeft(overlay) + const Offset(60, 60);
      await tester.tapAt(point);
      await tester.pump();
      await tester.tapAt(point + const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('Distance :'), findsOneWidget);
      expect(find.textContaining('Distance : 0.00'), findsNothing);
      // No checkpoint or storage write for this temporary tool.
      expect(store.saved['name'], before['name']);
      expect(find.byTooltip('Annuler'), findsOneWidget);
      final undo = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Annuler',
        ),
      );
      expect(undo.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
