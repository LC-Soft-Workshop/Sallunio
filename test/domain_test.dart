import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/storage.dart';
import 'package:tableo/exports.dart';

void main() {
  test('Irregular room contour excludes missing corner', () {
    final p = demoProject();
    p['room']['polygon'] = '0,0;12,0;12,6;8,6;8,9;0,9';
    final t = tables(p).first;
    t['x'] = 9.0;
    t['y'] = 7.0;
    expect(fits(p, t, [], passages: false), false);
    t['x'] = 1.0;
    t['y'] = 1.0;
    expect(fits(p, t, [], passages: false), true);
  });
  test('Anonymous meals override defaults, non-eaters retain seat', () {
    final p = demoProject();
    final g = rows(p, 'groups').first;
    g['seats'] = [
      {
        'number': 1,
        'meal': 'Végétarien',
        'need': 'Fauteuil',
        'allergy': '',
        'companion': '2',
      },
    ];
    expect(mealTotals(p)['Normal'], 11);
    expect(mealTotals(p)['Végétarien'], 5);
    expect(mealTotals(p)['Ne mange pas'], 3);
    expect(preparationNotes(p).any((s) => s.contains('place 1')), true);
  });
  test('Rotation keeps long-side capacity and protects reserved access', () {
    final p = demoProject();
    final t = tables(p).first;
    final capacity = comfortableCapacity(t);
    t['w'] = .8;
    t['h'] = 1.8;
    expect(comfortableCapacity(t), capacity);
    expect(envelope(t)['w'], closeTo(1.9, .001));
    t['x'] = 11.0;
    t['y'] = .1;
    expect(fits(p, t, rows(p, 'items')), false);
    expect(issues(p).any((v) => v.contains('Sortie secours')), true);
  });
  test('Separated groups never share a table in automatic proposal', () {
    final p = demoProject();
    arrange(p);
    final gs = rows(p, 'groups');
    gs[0]['count'] = 2;
    gs[1]['count'] = 2;
    gs[0]['separate'] = gs[1]['id'];
    allocate(p);
    final a = (gs[0]['alloc'] as List).map((v) => v['table']).toSet();
    final b = (gs[1]['alloc'] as List).map((v) => v['table']).toSet();
    expect(a.intersection(b), isEmpty);
  });
  test('CSV quoted multiline, escaped quotes and BOM', () {
    final result = parseCsv(
      '\uFEFFréférent;effectif;allergies\n"Camille; A";12;"noix\net lait"\n"Alex ""B""";2;',
    );
    expect(result[1], ['Camille; A', '12', 'noix\net lait']);
    expect(result[2][0], 'Alex "B"');
    expect(() => parseCsv('a;b\n"bad;2'), throwsFormatException);
  });
  test('Arrangement respects fixed objects and seating/aisle envelopes', () {
    final p = demoProject();
    final t = tables(p).first;
    t['fixed'] = true;
    final x = t['x'], y = t['y'];
    expect(arrange(p), 0);
    expect(t['x'], x);
    expect(t['y'], y);
    for (final t in tables(p)) {
      expect(fits(p, t, rows(p, 'items')), isTrue);
    }
  });
  test(
    'Allocation honors capacity, fixed assignments and no sacrificed aisle',
    () {
      final p = demoProject();
      arrange(p);
      allocate(p);
      for (final t in tables(p)) {
        expect(occupancy(p, t['id']) <= t['capacity'], isTrue);
      }
      final g = rows(p, 'groups').first;
      g['locked'] = true;
      final before = clone(g);
      allocate(p);
      expect(g['alloc'], before['alloc']);
      final t = tables(p).last;
      t['x'] = 0.0;
      for (final g in rows(p, 'groups')) {
        g['locked'] = false;
      }
      allocate(p);
      expect(occupancy(p, t['id']), 0);
    },
  );
  test('Validation rejects invalid dimensions and dangling allocations', () {
    final p = demoProject();
    validateProject(p);
    p['room']['width'] = -1;
    expect(() => validateProject(p), throwsFormatException);
    p['room']['width'] = 12.0;
    rows(p, 'groups').first['alloc'] = [
      {'table': 'missing', 'count': 2},
    ];
    expect(() => validateProject(p), throwsFormatException);
  });
  test('SQLite reopen, independent project copy and deletion', () async {
    final dir = await Directory.systemTemp.createTemp('tableo-test-');
    final s = Store();
    await s.open(path: dir.path);
    final p = demoProject();
    await s.save(p);
    await s.close();
    final reopened = Store();
    await reopened.open(path: dir.path);
    expect((await reopened.load()).single['name'], p['name']);
    final copy = clone(p);
    copy['id'] = uid();
    copy['groups'] = <Json>[];
    await reopened.save(copy);
    expect((await reopened.load()).length, 2);
    await reopened.delete(p['id']);
    expect((await reopened.load()).single['groups'], isEmpty);
    await reopened.close();
    await dir.delete(recursive: true);
  });
  test('PDF export creates preparation plan and four-card pages', () async {
    final p = demoProject();
    arrange(p);
    allocate(p);
    final dir = await Directory.systemTemp.createTemp('tableo-pdf-');
    expect(dir.parent.absolute.path, Directory.systemTemp.absolute.path);
    final path = '${dir.path}/demo.pdf';
    await exportPdf(p, path);
    final bytes = await File(path).readAsBytes();
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(10000));
    await dir.delete(recursive: true);
  });
  test('Realistic allocation benchmark 600 participants / 100 tables', () {
    final p = newProject('Benchmark fictif');
    p['room']['width'] = 50.0;
    p['room']['height'] = 50.0;
    p['items'] = List.generate(
      100,
      (i) => {
        'id': 't$i',
        'kind': 'table',
        'label': 'T$i',
        'shape': 'rectangle',
        'x': 1.0 + i % 10 * 4.0,
        'y': 1.0 + i ~/ 10 * 4.0,
        'w': 1.8,
        'h': .8,
        'capacity': 6,
        'fixed': false,
        'seating': 'Chaises',
        'sides': 'Longs côtés',
      },
    );
    p['groups'] = List.generate(
      150,
      (i) => {
        'id': 'g$i',
        'name': 'Fictif $i',
        'count': 4,
        'meal': 'Normal',
        'needs': '',
        'alloc': <Json>[],
      },
    );
    final watch = Stopwatch()..start();
    allocate(p);
    watch.stop();
    expect(tables(p).fold<int>(0, (s, t) => s + occupancy(p, t['id'])), 600);
    // Report measured hardware-dependent duration, no commercial limit.
    // ignore: avoid_print
    print(
      'BENCHMARK 600 participants / 100 tables : ${watch.elapsedMilliseconds} ms',
    );
  });
}
