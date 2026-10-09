import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

import 'arrangement_start_test.dart' show room, table;

void main() {
  for (final start in arrangementCorners) {
    test('$start reserves half the aisle on every unsupported wall', () {
      final p = room(start: start);
      p['aisle'] = 1.2;
      p['wallSupport'] = 'Aucun';
      p['items'] = [
        for (var i = 0; i < 12; i++)
          table('T$i', w: i < 8 ? 1.8 : .75, h: i < 8 ? .8 : 1.2)
            ..['sides'] = 'Longs côtés',
      ];
      expect(arrange(p), 0);
      for (final t in tables(p)) {
        expect(number(t['x']), greaterThanOrEqualTo(.6 - 1e-7));
        expect(number(t['y']), greaterThanOrEqualTo(.6 - 1e-7));
        expect(number(t['x']) + number(t['w']), lessThanOrEqualTo(11.4 + 1e-7));
        expect(number(t['y']) + number(t['h']), lessThanOrEqualTo(8.4 + 1e-7));
      }
    });

    test(
      '$start shows excess tables outside, and returns them when room grows',
      () {
        final p = room(start: start);
        p['room']['width'] = 4.0;
        p['room']['height'] = 3.0;
        p['aisle'] = 1.2;
        p['items'] = [for (var i = 0; i < 8; i++) table('T$i')];
        final ids = tables(p).map((t) => t['id']).toList();
        final failed = arrange(p);
        final pending = tables(p).where((t) => unplacedTable(p, t)).toList();
        expect(failed, greaterThan(0));
        expect(failed, pending.length);
        expect(tables(p).map((t) => t['id']).toList(), ids);
        expect(
          issues(p).where((s) => s.contains('pas assez de place')).length,
          failed,
        );
        for (var i = 0; i < tables(p).length; i++) {
          final a = tables(p)[i];
          if (!unplacedTable(p, a)) expect(fits(p, a, rows(p, 'items')), true);
          for (final b in tables(p).skip(i + 1)) {
            expect(overlaps(a, b), false);
          }
        }
        validateProject(p);
        p['room']['width'] = 14.0;
        p['room']['height'] = 10.0;
        expect(arrange(p), 0);
        expect(tables(p).where((t) => unplacedTable(p, t)), isEmpty);
        expect(issues(p), isEmpty);
      },
    );
  }

  test(
    'Removing bottom wall support moves tables away in bottom-right mode',
    () {
      final p = room(start: 'Bas droite');
      p['aisle'] = 1.2;
      p['wallSupport'] = 'Mur bas';
      p['items'] = [for (var i = 0; i < 4; i++) table('T$i')];
      expect(arrange(p), 0);
      expect(
        tables(p)
            .any((t) => (number(t['y']) + number(t['h']) - 9).abs() < 1e-7),
        true,
      );
      p['wallSupport'] = 'Aucun';
      expect(arrange(p), 0);
      expect(
        tables(p).every((t) => number(t['y']) + number(t['h']) <= 8.4 + 1e-7),
        true,
      );
    },
  );

  test(
    'Authorised wall exempts only that wall; zones get no spacing margin',
    () {
      final p = room();
      p['aisle'] = 1.2;
      p['wallSupport'] = 'Mur gauche';
      final t = table('T')
        ..['x'] = 0.0
        ..['y'] = 2.0;
      expect(fits(p, t, []), true);
      t['y'] = 0.0;
      expect(fits(p, t, []), false);
      t['x'] = 2.0;
      t['y'] = 2.0;
      final zone = {
        'id': 'z',
        'kind': 'zone',
        'x': 3.8,
        'y': 2.0,
        'w': .4,
        'h': .8,
      };
      expect(fits(p, t, [zone]), true);
    },
  );
}
