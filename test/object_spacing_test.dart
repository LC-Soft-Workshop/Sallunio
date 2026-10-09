import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

import 'joining_test.dart' show table, plan;

void main() {
  test(
    'Other objects can touch a seated edge, but never overlap the table',
    () {
      for (final kind in ['zone', 'obstacle', 'entry', 'exit', 'door']) {
        final a = table('a', 2, 2);
        final b = <String, dynamic>{
          'id': 'b',
          'label': 'Objet',
          'kind': kind,
          'x': 2.0,
          'y': 2.8,
          'w': 1.8,
          'h': 1.0,
        };
        final p = plan([a, b], 'Aucun');
        expect(fits(p, a, [a, b]), true, reason: kind);
        expect(issues(p).where((v) => v.contains('a / Objet')), isEmpty);
        b['y'] = 2.79;
        expect(fits(p, a, [a, b]), false, reason: kind);
        expect(issues(p).any((v) => v.contains('chevauchement')), true);
      }
    },
  );
}
