import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/main.dart';
import 'package:tableo/domain.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
String value(String label) =>
    (field(label).evaluate().single.widget as TextField).controller!.text;
void main() {
  testWidgets(
    'Furniture category changes visible defaults and preserves custom names',
    (t) async {
      desktop(t);
      final store = SnapshotStore();
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      await t.tap(find.text('Mobilier').first);
      await t.pumpAndSettle();
      await t.tap(find.text('+ Type'));
      await t.pumpAndSettle();
      await t.tap(find.text('Chaise').last);
      await t.pumpAndSettle();
      expect(value('Nom du type'), 'Nouvelle chaise');
      expect(value('Largeur (m)'), '0.5');
      expect(value('Profondeur (m)'), '0.5');
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Usage des nouvelles pièces',
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Forme de la table',
        ),
        findsNothing,
      );
      await t.tap(find.text('Chaise enfant').last);
      await t.pumpAndSettle();
      expect(value('Nom du type'), 'Nouvelle chaise enfant');
      expect(value('Largeur (m)'), '0.4');
      expect(value('Profondeur (m)'), '0.4');
      await t.tap(find.text('Banc').last);
      await t.pumpAndSettle();
      expect(value('Nom du type'), 'Nouveau banc');
      expect(value('Longueur du banc (m)'), '2.0');
      expect(value('Profondeur (m)'), '0.4');
      await t.enterText(field('Nom du type'), 'Siège bleu');
      await t.tap(find.text('Chaise').last);
      await t.pumpAndSettle();
      expect(value('Nom du type'), 'Siège bleu');
      await t.tap(find.text('Enregistrer').last);
      await t.pumpAndSettle();
      final model = rows(store.saved, 'types').last;
      expect(model['shape'], 'chaise');
      expect(model['name'], 'Siège bleu');
      expect(model['w'], .5);
      expect(model['h'], .5);
      expect(model['capacity'], 1);
      expect(model['usage'], furnitureUses.first);
      expect(model.containsKey('_furnitureKind'), false);
      expect(t.takeException(), isNull);
    },
  );
}
