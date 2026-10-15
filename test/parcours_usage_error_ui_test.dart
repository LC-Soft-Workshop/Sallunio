import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;

void main() {
  testWidgets(
    'Seated tables report a clear error before parcours starts and keep the plan',
    (t) async {
      desktop(t);
      final store = SnapshotStore();
      store.saved['activity'] = 'Personnalisé';
      store.saved['arrangementMode'] = 'Parcours';
      store.saved['parcoursSettings'] = {'circulation': 'Fermé'};
      for (final item in tables(store.saved)) {
        item['usage'] = 'Places assises';
      }
      var calls = 0;
      await t.pumpWidget(
        Tableo(
          store: store,
          arrangementRunner: (p) async {
            calls++;
            return p;
          },
        ),
      );
      await t.pumpAndSettle();
      final before = clone(store.saved);
      await t.tap(find.text('Disposer mobilier'));
      await t.pumpAndSettle();
      await t.tap(find.text('Disposer'));
      await t.pumpAndSettle();
      expect(find.text('Parcours impossible'), findsOneWidget);
      expect(
        find.textContaining(
          'Les tables marquées « Places assises » sont exclues',
        ),
        findsOneWidget,
      );
      expect(calls, 0);
      expect(store.saved['items'], before['items']);
      expect(store.saved['groups'], before['groups']);
      await t.tap(find.text('Fermer'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
}
