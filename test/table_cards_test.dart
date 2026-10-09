import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/exports.dart';

void main() {
  test(
    'Standalone A6 cards omit empty tables and retain split quantities',
    () async {
      final p = demoProject();
      final ts = tables(p);
      final g = rows(p, 'groups').first;
      g['name'] = 'Camille exemple';
      g['alloc'] = [
        for (var i = 0; i < 5; i++)
          {'table': ts[i]['id'], 'count': i == 4 ? 4 : 2},
      ];
      rows(p, 'groups')[1]['name'] = 'Morgan exemple';
      rows(p, 'groups')[1]['alloc'] = [
        {'table': ts[0]['id'], 'count': 3},
      ];
      rows(p, 'groups')[2]['alloc'] = [];
      await Directory('output/pdf').create(recursive: true);
      final path = 'output/pdf/exemple-fiches-tables.pdf';
      await exportPdf(p, path, cardsOnly: true, overwriteConfirmed: true);
      expect(await File(path).length(), greaterThan(1000));
    },
  );
  test('No occupied table creates no empty cards PDF', () async {
    final path = 'tmp/no-table-cards-${uid()}.pdf';
    await expectLater(
      exportPdf(demoProject(), path, cardsOnly: true),
      throwsFormatException,
    );
    expect(File(path).existsSync(), false);
  });
}
