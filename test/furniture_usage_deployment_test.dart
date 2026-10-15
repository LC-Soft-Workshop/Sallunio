import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'mixed_furniture_ui_test.dart' show choose;

void main() {
  testWidgets(
    'Model edited to stand propagates to existing and all new pieces',
    (t) async {
      desktop(t);
      final store = SnapshotStore();
      final p = store.saved;
      p['groups'] = <Json>[];
      p['items'] = <Json>[];
      p['types'] = [
        {
          'id': 'stock',
          'name': 'Modèle fictif',
          'shape': 'rectangle',
          'w': 1.8,
          'h': .8,
          'capacity': 6,
          'usage': furnitureUses.first,
          'quantity': 3,
          'limit': 3,
          'source': 'Propre',
          'enabled': true,
          'seating': 'Chaises',
          'sides': 'Tous côtés',
        },
      ];
      expect(addFurniture(p, rows(p, 'types')).placed, 1);
      final existing = tables(p).single;
      final before = [
        existing['id'],
        existing['x'],
        existing['y'],
        existing['w'],
        existing['h'],
      ];
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      await t.tap(find.text('Mobilier').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Modifier').last);
      await t.pumpAndSettle();
      await choose(t, 'Usage des nouvelles pièces', furnitureUses[1]);
      await t.tap(find.text('Enregistrer').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Confirmer').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Ajouter tout le mobilier sélectionné'));
      await t.pumpAndSettle();
      expect(tables(store.saved).length, 3);
      expect(
        tables(store.saved).every((i) => furnitureUse(i) == furnitureUses[1]),
        true,
      );
      final same = tables(store.saved).first;
      expect([same['id'], same['x'], same['y'], same['w'], same['h']], before);
      expect(t.takeException(), isNull);
    },
  );
}
