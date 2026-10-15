import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/main.dart';
import 'package:tableo/domain.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'plan_toolbar_test.dart' show clickTool;
import 'mixed_furniture_test.dart' show exhibitor;

void main() {
  testWidgets(
    'Names toggle controls stand painter without losing assignments',
    (t) async {
      desktop(t);
      final store = SnapshotStore(), p = store.saved;
      final table = tables(p).first;
      table['usage'] = furnitureUses[1];
      final g = exhibitor('Exposant fictif', 1);
      p['groups'] = [g];
      setStandPortion(p, g, table, length: 1);
      final before = clone(g);
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      List<StandPortionsPainter> painters() => t
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<StandPortionsPainter>()
          .toList();
      expect(painters(), isNotEmpty);
      expect(painters().every((p) => !p.showNames), true);
      await clickTool(t, 'labels');
      expect(painters().every((p) => p.showNames), true);
      await clickTool(t, 'labels');
      expect(painters().every((p) => !p.showNames), true);
      expect(g, before);
      expect(t.takeException(), isNull);
    },
  );
}
