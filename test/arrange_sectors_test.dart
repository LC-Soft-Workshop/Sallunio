import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

import 'joining_test.dart' show table, plan;

void main() {
  test('Free left sector precedes extending a row on the right', () {
    final right = table('right', 6, 1);
    final zone = <String, dynamic>{
      'id': 'centre',
      'kind': 'zone',
      'label': '',
      'zoneFill': 'Invisible',
      'x': 4.2,
      'y': 0.0,
      'w': 1.0,
      'h': 9.0,
    };
    final p = plan([zone, right], 'Petits côtés');
    final candidate = findPosition(p, table('new', 0, 0), [zone, right])!;
    expect(
      number(candidate['x']) + number(candidate['w']),
      lessThanOrEqualTo(4.2),
    );
    expect(fits(p, candidate, [zone, right]), true);
  });
  test('Mixed stock fills large tables first and joins small tables in remaining spaces', () {
    final items = <Json>[
      for (var i = 0; i < 3; i++) table('large-$i', 0, 0),
      table('small-1', 0, 0, w: 1.2, h: .75, capacity: 4),
      table('small-2', 0, 0, w: 1.2, h: .75, capacity: 4),
      for (var i = 3; i < 10; i++) table('large-$i', 0, 0),
      {
        'id': 'centre',
        'kind': 'zone',
        'label': '',
        'zoneFill': 'Invisible',
        'x': 7.4,
        'y': 0.0,
        'w': 1.2,
        'h': 9.0,
      },
    ];
    final p = plan(items, 'Petits côtés');
    p['room']['width'] = 16.0;
    expect(arrange(p), 0);
    for (final small in tables(
      p,
    ).where((t) => t['id'].toString().startsWith('small'))) {
      expect(
        tables(p).any(
          (other) =>
              other['id'] != small['id'] &&
              joinedEdges(p, small, other) != null,
        ),
        true,
      );
      expect(number(small['x']), lessThan(7.4));
    }
    for (final t in tables(p)) {
      expect(fits(p, t, rows(p, 'items')), true);
    }
  });
}
