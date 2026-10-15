import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/event_icons.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;

void main() {
  test(
    'Defaults follow activity and explicit icons survive activity changes',
    () {
      final p = newProject('Fictif');
      for (final activity in roomActivities) {
        p['activity'] = activity;
        expect(eventIconData.containsKey(eventIconName(p)), true);
      }
      p['activity'] = 'Marché de Noël';
      expect(eventIconName(p), 'Sapin de Noël');
      p['icon'] = 'Café';
      p['activity'] = 'Brocante';
      expect(eventIconName(p), 'Café');
      validateProject(p);
      p.remove('icon');
      expect(eventIconName(p), 'Brocante');
    },
  );
  testWidgets(
    'Icon selection saves, displays in tabs and persists; cancelling preserves it',
    (t) async {
      desktop(t);
      final store = SnapshotStore();
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      final before = clone(store.saved);
      await t.tap(find.text('Événements').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Propriétés').first);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('event-icon-choice')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Café').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Café').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Enregistrer').last);
      await t.pumpAndSettle();
      expect(store.saved['icon'], 'Café');
      expect(store.saved['items'], before['items']);
      expect(store.saved['groups'], before['groups']);
      final chip = t.widget<ChoiceChip>(find.byType(ChoiceChip).first);
      expect((chip.avatar as Icon).icon, Icons.local_cafe);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      expect(
        (t.widget<ChoiceChip>(find.byType(ChoiceChip).first).avatar as Icon)
            .icon,
        Icons.local_cafe,
      );
      await t.tap(find.text('Événements').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Propriétés').first);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('event-icon-choice')));
      await t.pumpAndSettle();
      await t.tap(find.text('Loto').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Annuler').last);
      await t.pumpAndSettle();
      expect(store.saved['icon'], 'Café');
      expect(t.takeException(), isNull);
    },
  );
}
