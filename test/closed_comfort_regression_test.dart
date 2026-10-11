import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/parcours.dart';

import 'imposed_parcours_test.dart' show perimeterMarket;
import 'parcours_test.dart' show noOverlap;

void main() {
  for (final comfort in [false, true]) {
    test(
      'Closed alternating layout with two entries preserves event comfort: $comfort',
      () {
        final p = perimeterMarket(extras: 20);
        rows(p, 'items').removeWhere((i) => i['id'] == 'service');
        p['wallSupport'] = 'Haut + bas';
        p['parcoursSettings']['wallLayout'] = 'Alterné';
        p['parcoursSettings']['circulation'] = 'Fermé';
        p['parcoursSettings']['orientation'] = 'Automatique';
        if (comfort) {
          p['comfort'] = {...comfortableDefaults(p), 'exhibitorGap': 1.2};
        }
        rows(p, 'items').addAll([
          {
            'id': 'entry2',
            'kind': 'entry',
            'label': 'Entrée fictive',
            'x': 11.0,
            'y': 0.0,
            'w': 1.0,
            'h': 1.0,
            'fixed': false,
          },
          {
            'id': 'exit',
            'kind': 'exit',
            'label': 'Sortie fictive',
            'x': 24.0,
            'y': 6.5,
            'w': 1.0,
            'h': 1.0,
            'fixed': false,
          },
        ]);
        final beforeComfort = clone(p)['comfort'];
        arrange(p);
        expect(parcoursPaths(p), isNotEmpty);
        expect(parcoursWarnings(p), isEmpty);
        expect(p['comfort'], beforeComfort);
        noOverlap(p);
      },
    );
  }
}
