import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/parcours.dart';

import 'imposed_parcours_test.dart' show perimeterMarket;
import 'joining_test.dart' show table;

void main() {
  for (final same in [false, true]) {
    test('border zones same dimensions $same', () {
      final p = perimeterMarket(extras: 20);
      p['parcoursSettings']['circulation'] = 'Fermé';
      rows(p, 'items').removeWhere((i) => i['id'] == 'service');
      if (same) {
        rows(p, 'items').removeWhere(isSeatingFurniture);
        for (var n = 0; n < 75; n++) {
          rows(p, 'items').add(table('T$n', 0, 0, sides: 'Un côté'));
        }
      }
      rows(p, 'items').addAll([
        {
          'id': 'wc',
          'kind': 'zone',
          'shape': 'rectangle',
          'label': 'Zone fictive',
          'fixed': false,
          'x': 12.7,
          'y': 0.0,
          'w': 1.5,
          'h': 1.5,
        },
        {
          'id': 'entry2',
          'kind': 'entry',
          'shape': 'rectangle',
          'label': 'Accès fictif',
          'fixed': false,
          'x': 21.8,
          'y': 0.0,
          'w': 1.2,
          'h': 1.0,
        },
        {
          'id': 'exit',
          'kind': 'exit',
          'shape': 'rectangle',
          'label': 'Sortie fictive',
          'fixed': false,
          'x': 24.0,
          'y': 6.5,
          'w': 1.0,
          'h': 1.0,
        },
      ]);
      for (final t in tables(p)) {
        t['usage'] = 'Places assises';
      }
      final before = clone(p);
      expect(parcoursFurnitureError(p), contains('Places assises'));
      expect(
        () => arrange(p),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Stand / exposition'),
          ),
        ),
      );
      expect(p, before);
    });
  }
}
