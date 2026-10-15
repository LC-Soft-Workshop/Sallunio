import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

import 'arrangement_start_test.dart' show room, table;
import 'mixed_furniture_test.dart' show audiencePlan;

Map<String, List<dynamic>> positions(Json p) => {
  for (final t in tables(p)) t['label']: [t['x'], t['y'], t['w'], t['h']],
};
void main() {
  test('Table placement is independent of inventory order and uses natural numbers', () {
    final a = room(start: 'Haut gauche');
    a['items'] = [table('T10'), table('T2'), table('T1')];
    final b = clone(a);
    b['items'] = rows(b, 'items').reversed.toList();
    expect(arrange(a), 0);
    expect(arrange(b), 0);
    expect(positions(a), positions(b));
    final placed = tables(a).toList()
      ..sort((x, y) {
        final row = number(x['y']).compareTo(number(y['y']));
        return row != 0 ? row : number(x['x']).compareTo(number(y['x']));
      });
    expect(placed.map((t) => t['label']), ['T1', 'T2', 'T10']);
  });
  for (final kind in ['chair', 'bench']) {
    test(
      'Scene $kind placement keeps numeric labels despite inventory order',
      () {
        final a = audiencePlan(count: 3);
        final labels = kind == 'chair'
            ? ['Chaise 10', 'Chaise 2', 'Chaise 1']
            : ['B10', 'B2', 'B1'];
        for (var n = 0; n < 3; n++) {
          tables(a)[n].addAll({'kind': kind, 'label': labels[n]});
        }
        final b = clone(a);
        b['items'] = rows(b, 'items').reversed.toList();
        final settings = {
          'scene': 'scene',
          'layout': audienceLayouts.first,
          'side': 'Bas',
        };
        expect(arrangeAudience(a, settings), 0);
        expect(arrangeAudience(b, settings), 0);
        expect(positions(a), positions(b));
        expect(tables(a).map((t) => t['label']), labels);
        final sorted = tables(a).toList()..sort(compareFurnitureNumbers);
        expect(number(sorted[0]['x']), greaterThan(number(sorted[1]['x'])));
        expect(number(sorted[1]['x']), greaterThan(number(sorted[2]['x'])));
      },
    );
  }
}
