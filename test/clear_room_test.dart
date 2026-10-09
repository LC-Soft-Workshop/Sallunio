import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;

void main() {
  test(
    'Clearing zones preserves tables, stock, assignments and access objects',
    () {
      final p = demoProject();
      allocate(p);
      final groups = rows(p, 'groups').map(clone).toList();
      clearRoom(p, {'zones'}, includeLocked: true);
      expect(rows(p, 'items').any((i) => i['kind'] == 'zone'), false);
      expect(tables(p).length, 6);
      expect(rows(p, 'types').length, 3);
      expect(rows(p, 'groups'), groups);
      expect(rows(p, 'items').any((i) => i['kind'] == 'entry'), true);
    },
  );
  test('Clearing tables removes related assignments and references but not groups or stock', () {
    final p = demoProject();
    allocate(p);
    rows(p, 'groups').first['reserved'] = tables(p).first['id'];
    rows(p, 'groups').first['locked'] = true;
    clearRoom(p, {'tables'});
    expect(tables(p), isEmpty);
    expect(rows(p, 'groups').length, 3);
    expect(workspaceStats(p)['reserved'], 19);
    expect(workspaceStats(p)['assigned'], 0);
    expect(rows(p, 'groups').first['reserved'], '');
    expect(rows(p, 'groups').first['locked'], false);
    expect(rows(p, 'types').length, 3);
    validateProject(p);
  });
  test('Types can be cleared without removing or moving placed furniture', () {
    final p = demoProject();
    final before = tables(p).map(clone).toList();
    clearRoom(p, {'types'});
    expect(rows(p, 'types'), isEmpty);
    for (var i = 0; i < before.length; i++) {
      before[i].remove('type');
      expect(tables(p)[i], before[i]);
    }
    validateProject(p);
  });
  test('Clear all selected elements keeps reservations and proximity', () {
    final p = demoProject();
    allocate(p);
    final gs = rows(p, 'groups');
    setReservationPreference(p, gs.first, gs.last['id'], 'near');
    clearRoom(p, roomClearChoices.keys.toSet(), includeLocked: true);
    expect(rows(p, 'items'), isEmpty);
    expect(rows(p, 'types'), isEmpty);
    expect(workspaceStats(p)['reserved'], 19);
    expect(reservationPreferences(p, gs.first)[gs.last['id']], 'near');
    validateProject(p);
  });
  testWidgets(
    'Clear dialog cancels safely, clears only checked zones and can be undone',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore(), initial = clone(SnapshotStore().saved);
      rows(
        store.saved,
        'items',
      ).firstWhere((i) => i['kind'] == 'zone')['fixed'] = false;
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vider la salle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(rows(store.saved, 'items').length, rows(initial, 'items').length);
      await tester.tap(find.text('Vider la salle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vider les éléments cochés'));
      await tester.pumpAndSettle();
      expect(
        rows(store.saved, 'items').where((i) => i['kind'] == 'zone'),
        isEmpty,
      );
      expect(tables(store.saved).length, 6);
      await tester.tap(find.byTooltip('Annuler'));
      await tester.pumpAndSettle();
      expect(
        rows(store.saved, 'items').where((i) => i['kind'] == 'zone').length,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
