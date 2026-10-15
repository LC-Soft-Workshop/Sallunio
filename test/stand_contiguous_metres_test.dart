import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

import 'joining_test.dart' show table;
import 'mixed_furniture_test.dart' show exhibitor;

Json plan(List<Json> items) => newProject('Marché fictif')
  ..['items'] = items
  ..['allowMixedStandTypes'] = true;
Json stand(String id, double x, double y, {double w = 1.8, double h = .8}) => {
  ...table(id, x, y, w: w, h: h),
  'usage': 'Stand / exposition',
};
void main() {
  test('A stand skips an isolated remainder and spans mixed-depth contiguous tables', () {
    final p = plan([
      stand('a', 1, 1),
      stand('b', 2.8, 1),
      stand('c', 4.6, 1, w: 1.2, h: .6),
      stand('d', 1, 4),
    ]);
    p['groups'] = [exhibitor('Camille', 3), exhibitor('Morgan', 3)];
    allocate(p);
    final m = rows(p, 'groups')[1];
    expect(m['standAlloc'].map((a) => a['table']), ['b', 'c']); // Remaining continuous capacity is insufficient: keep one chain, never use isolated d.
    final ids = (m['standAlloc'] as List).map((a) => a['table']).toSet();
    expect(ids.contains('d'), false);
    expect(standAllocationWarnings(p).join(' '), contains('Longueur continue'));
  });
  test('Full requested metres use narrow and wide tables without crossing an aisle', () {
    final p = plan([
      stand('isolated', 1, 1, w: 1.0),
      stand('wide', 1, 4),
      stand('narrow', 2.8, 4, w: 1.2, h: .5),
      stand('extra', 4, 4, w: 1.8),
    ]);
    p['groups'] = [exhibitor('Morgan', 3)];
    allocate(p);
    final a = rows(p, 'groups').single['standAlloc'] as List;
    expect(a.map((v) => v['table']), ['wide', 'narrow']);
    expect(
      a.fold<double>(0, (n, v) => n + number(v['length'])),
      closeTo(3, 1e-6),
    );
  });
  test('Vertical frontage also joins different table widths', () {
    final p = plan([
      stand('a', 1, 1, w: .8, h: 1.8),
      stand('b', 1, 2.8, w: .5, h: 1.2),
    ]);
    p['groups'] = [exhibitor('Morgan', 3)];
    allocate(p);
    expect(rows(p, 'groups').single['standAlloc'].length, 2);
    expect(standSummary(p)['assignedMetres'], closeTo(3, 1e-6));
  });
}
