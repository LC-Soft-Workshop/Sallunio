import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

import 'mixed_furniture_test.dart' show exhibitor;
import 'stand_contiguous_metres_test.dart' show plan, stand;

void main() {
  test('A reservation cannot jump over an occupied portion', () {
    final p = plan([stand('a', 1, 1), stand('b', 2.8, 1), stand('c', 4.6, 1)]);
    final held = exhibitor('held', .6)..['locked'] = true,
        wanted = exhibitor('wanted', 3);
    p['groups'] = [held, wanted];
    setStandPortion(p, held, tables(p)[1], offset: 0, length: .6);
    allocate(p);
    expect((wanted['standAlloc'] as List).map((a) => a['table']), ['b', 'c']);
    expect(wanted['standAlloc'][0]['offset'], closeTo(.6, 1e-6));
    expect(standAllocationIsContiguous(p, wanted), true);
  });
  test(
    'Existing locked disconnected assignments are preserved and reported',
    () {
      final p = plan([stand('a', 1, 1), stand('b', 1, 4)]);
      final g = exhibitor('held', 3)..['locked'] = true;
      p['groups'] = [g];
      for (final t in tables(p)) {
        setStandPortion(p, g, t, length: 1.5);
      }
      final before = clone(g);
      allocate(p);
      expect(g, before);
      expect(standAllocationWarnings(p).join(' '), contains('non contiguës'));
    },
  );
}
