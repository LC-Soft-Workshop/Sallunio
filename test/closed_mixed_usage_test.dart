import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

import 'imposed_parcours_test.dart' show perimeterMarket;

void main() {
  test(
    'Dedicated stand furniture keeps seated tables outside automatic parcours',
    () {
      final p = perimeterMarket(extras: 20);
      p['parcoursSettings']['circulation'] = 'Fermé';
      for (final t in tables(p)) {
        if (t['capacity'] != 0) t['usage'] = 'Stand / exposition';
      }
      final seated = tables(p).first;
      seated.addAll({'usage': 'Places assises', 'x': 22.0, 'y': 4.0});
      final before = clone(seated);
      arrange(p);
      final after = tables(p).firstWhere((t) => t['id'] == before['id']);
      for (final key in ['x', 'y', 'w', 'h', 'usage', 'capacity', 'sides']) {
        expect(after[key], before[key]);
      }
      expect(after['parcoursBlock'], isNull);
    },
  );
}
