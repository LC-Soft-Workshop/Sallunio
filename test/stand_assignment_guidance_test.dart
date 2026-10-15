import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'mixed_furniture_test.dart' show standPlan, exhibitor, seatedGroup;

void main() {
  test(
    'Unfulfilled stand requests explain missing usage and matching stock',
    () {
      final p = standPlan();
      p['groups'] = [exhibitor('a', 3)];
      for (final t in tables(p)) {
        t['usage'] = furnitureUses.first;
      }
      allocate(p);
      expect(standSummary(p)['assignedMetres'], 0);
      expect(
        standAllocationWarnings(p).single,
        contains('Aucune table du plan'),
      );
      changeFurnitureUsage(
        p,
        tables(p).map((t) => t['id'] as String).toSet(),
        furnitureUses[1],
      );
      allocate(p);
      expect(standSummary(p)['assignedMetres'], 3);
      expect(standAllocationWarnings(p), isEmpty);
      rows(p, 'groups').single['requestedType'] = 'missing-model';
      allocate(p);
      expect(standAllocationWarnings(p).single, contains('modèle demandé'));
    },
  );
  for (final accept in [true, false]) {
    testWidgets(
      'Stand-only conversion is explicit and preserves plan: $accept',
      (t) async {
        desktop(t);
        final store = SnapshotStore()..saved = standPlan();
        final p = store.saved;
        p['groups'] = [exhibitor('a', 3)];
        for (final item in tables(p)) {
          item['usage'] = furnitureUses.first;
        }
        final positions = tables(p)
            .map((item) => [item['x'], item['y'], item['w'], item['h']])
            .toList();
        await t.pumpWidget(Tableo(store: store));
        await t.pumpAndSettle();
        await t.tap(find.text('Réservations').first);
        await t.pumpAndSettle();
        await t.tap(find.text('2. Attribuer les groupes aux tables'));
        await t.pumpAndSettle();
        expect(
          find.text('Utiliser ces tables pour les stands ?'),
          findsOneWidget,
        );
        await t.tap(find.text(accept ? 'Confirmer' : 'Annuler').last);
        await t.pumpAndSettle();
        expect(standSummary(store.saved)['assignedMetres'], accept ? 3 : 0);
        expect(
          tables(store.saved)
              .map((item) => [item['x'], item['y'], item['w'], item['h']])
              .toList(),
          positions,
        );
        expect(
          tables(store.saved).every(
            (item) =>
                furnitureUse(item) ==
                (accept ? furnitureUses[1] : furnitureUses.first),
          ),
          true,
        );
        if (accept) {
          expect(
            find.textContaining('0 / 0 personnes attribuées'),
            findsNothing,
          );
        }
        expect(t.takeException(), isNull);
      },
    );
  }
  test('Mixed event does not silently borrow seated or service tables', () {
    final p = standPlan();
    p['groups'] = [exhibitor('a', 3), seatedGroup('b', 1)];
    for (final item in tables(p)) {
      item['usage'] = furnitureUses.first;
    }
    tables(p).last['capacity'] = 0;
    allocate(p);
    expect(standSummary(p)['assignedMetres'], 0);
    expect(standAllocationWarnings(p), isNotEmpty);
    expect(furnitureUse(tables(p).last), 'Service');
  });
}
