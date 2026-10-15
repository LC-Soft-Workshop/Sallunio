import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;

void main() {
  testWidgets(
    'Editor accepts zero capacity and clearing explicitly includes fixed zones',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore();
      final id = tables(store.saved).first['id'];
      final zoneId = rows(
        store.saved,
        'items',
      ).firstWhere((i) => i['kind'] == 'zone')['id'];
      rows(store.saved, 'items').firstWhere((i) => i['id'] == zoneId)['fixed'] =
          true;
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      final point = tester.getCenter(find.byKey(ValueKey('plan-item-$id')));
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Capacité individuelle (0 = service)',
      );
      await tester.enterText(field, '0');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(tables(store.saved).first['capacity'], 0);
      expect(find.text('T1\nService'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Vider la salle'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Vider la salle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vider les éléments cochés'));
      await tester.pumpAndSettle();
      expect(rows(store.saved, 'items').any((i) => i['id'] == zoneId), true);
      await tester.ensureVisible(find.byTooltip('Vider la salle'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Vider la salle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zones'));
      await tester.ensureVisible(find.text('Inclure les éléments verrouillés'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inclure les éléments verrouillés'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vider les éléments cochés'));
      await tester.pumpAndSettle();
      expect(rows(store.saved, 'items').any((i) => i['id'] == zoneId), false);
      expect(tester.takeException(), isNull);
    },
  );
  test('Selective clearing keeps fixed objects and locked assignments unless included', () {
    final p = demoProject();
    allocate(p);
    final table = tables(p).first;
    table['fixed'] = true;
    final group = rows(p, 'groups').first;
    group['locked'] = true;
    final assignment = clone({'alloc': group['alloc']});
    clearRoom(p, {'assignments'});
    expect(group['alloc'], assignment['alloc']);
    clearRoom(p, {'tables', 'zones', 'access'});
    expect(tables(p), [table]);
    expect(rows(p, 'items').any((i) => i['kind'] == 'entry'), true);
    clearRoom(p, {'tables', 'zones', 'access'}, includeLocked: true);
    expect(rows(p, 'items'), isEmpty);
    expect(group['alloc'], isEmpty);
  });
  test(
    'Zero-capacity service table survives arrangement and receives no people',
    () {
      final p = demoProject();
      final service = tables(p).first;
      service['capacity'] = 0;
      service['x'] = 8.0;
      service['y'] = 3.0;
      expect(arrange(p), 0);
      expect(service['x'], 8.0);
      expect(service['y'], 3.0);
      expect(seatedEdges(service), isEmpty);
      expect(seatEnvelope(service), 0);
      allocate(p);
      expect(occupancy(p, service['id']), 0);
      expect(tablePlaceLabels(p, service), isEmpty);
      validateProject(clone(p));
    },
  );
  testWidgets(
    'Object function updates default label but preserves custom text',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore();
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('plan-tool-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-tool-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Obstacle').last);
      await tester.pumpAndSettle();
      final function = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Fonction',
      );
      final label = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Libellé (zone personnalisable)',
      );
      await tester.tap(function);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zone').last);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(label).controller!.text, 'Zone');
      await tester.enterText(label, 'Piste de danse');
      await tester.tap(function);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entrée').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(label).controller!.text,
        'Piste de danse',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(rows(store.saved, 'items').last['label'], 'Piste de danse');
      expect(rows(store.saved, 'items').last['kind'], 'entry');
      expect(tester.takeException(), isNull);
    },
  );
}
