import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/exports.dart';

import 'joining_test.dart' show table;
import 'mixed_furniture_test.dart' show seatedGroup, exhibitor, standPlan;

void main() {
  test(
    'Search links persons, groups and table numbers without modifying data',
    () {
      final p = demoProject();
      allocate(p);
      final g = rows(p, 'groups').first;
      g['seats'] = [
        {
          'number': 1,
          'name': 'Alice Essai',
          'table': tables(p).first['id'],
          'slot': 0,
        },
      ];
      final before = clone(p);
      expect(
        searchPlanItems(
          p,
          'Alice',
        ).any((i) => i['id'] == tables(p).first['id']),
        true,
      );
      expect(searchPlanItems(p, 'T1'), isNotEmpty);
      expect(p, before);
    },
  );
  test('Rectangle selection, numeric nudges and alignments are constrained and atomic', () {
    final p = demoProject();
    p['groups'] = <Json>[];
    p['items'] = [table('a', 1, 2), table('b', 5, 3), table('c', 9, 4)];
    expect(rectangleSelection(p, 0, 0, 7, 5), {'a', 'b'});
    alignFurnitureSelection(p, {'a', 'b', 'c'}, 'Aligner en haut');
    expect(tables(p).map((i) => i['y']), [2.0, 2.0, 2.0]);
    nudgeSelection(p, {'a'}, .01, 0);
    expect(tables(p).first['x'], closeTo(1.01, 1e-6));
    final before = clone(p);
    expect(() => nudgeSelection(p, {'a'}, 4, 0), throwsFormatException);
    expect(p, before);
    p['planLocked'] = true;
    expect(() => nudgeSelection(p, {'a'}, .01, 0), throwsFormatException);
  });
  test('Duplication preserves grouping, enforces inventory limits and excludes assignments', () {
    final p = demoProject();
    p['groups'] = <Json>[];
    p['items'] = [
      {...table('a', 1, 2), 'type': 'model'},
    ];
    p['types'] = [
      {
        'id': 'model',
        'shape': 'rectangle',
        'name': 'Test',
        'w': 1.8,
        'h': .8,
        'capacity': 6,
        'quantity': 2,
        'limit': 2,
        'source': 'Propre',
        'enabled': true,
        'seating': 'Chaises',
      },
    ];
    final copies = duplicatePlanSelection(p, {'a'});
    expect(copies.length, 1);
    expect(copies.single['id'], isNot('a'));
    expect(overlaps(tables(p)[0], tables(p)[1]), false);
    expect(() => duplicatePlanSelection(p, {'a'}), throwsFormatException);
    expect(tables(p).length, 2);
  });
  test('Renumbering honors protected numbers and retains stable assignment references', () {
    final p = demoProject();
    allocate(p);
    final before = rows(p, 'groups').map(clone).toList();
    tables(p).first['label'] = 'T99';
    tables(p).first['numberLocked'] = true;
    final labels = renumberingPreview(p, 'Rangées');
    expect(labels, isNot(contains(tables(p).first['id'])));
    applyRenumbering(p, labels);
    expect(tables(p).first['label'], 'T99');
    expect(rows(p, 'groups'), before);
  });
  test('Waiting list retains preferences, excludes allocation and supports reactivation', () {
    final p = demoProject();
    final g = rows(p, 'groups').first;
    allocate(p);
    setWaitingStatus(p, g, true);
    allocate(p);
    expect(g['alloc'], isEmpty);
    expect(workspaceStats(p)['reserved'], 7);
    expect(
      reservationAllocationReasons(p, g).single,
      contains('Liste d’attente'),
    );
    setWaitingStatus(p, g, false);
    allocate(p);
    expect(reservationAssigned(g), 12);
  });
  test('Stand waiting list excludes requested metres until confirmed', () {
    final p = standPlan();
    p['groups'] = [exhibitor('a', 3)];
    final g = rows(p, 'groups').single;
    setWaitingStatus(p, g, true);
    allocate(p);
    expect(standSummary(p)['requestedMetres'], 0);
    setWaitingStatus(p, g, false);
    allocate(p);
    expect(standSummary(p)['assignedMetres'], 3);
  });
  test('Normalized names and contacts flag duplicates without merging', () {
    final p = demoProject();
    rows(
      p,
      'groups',
    ).first.addAll({'name': 'Élodie Dupont', 'contact': '0102030405'});
    expect(
      similarReservations(p, {
        'id': 'new',
        'name': 'elodie dupont',
        'contact': '',
      }).length,
      1,
    );
    expect(
      similarReservations(p, {
        'id': 'new',
        'name': 'Différent',
        'contact': '01 02 03 04 05',
      }).length,
      1,
    );
  });
  test(
    'Reservation filters distinguish pending, partial, complete and PMR',
    () {
      final p = demoProject();
      allocate(p);
      final g = rows(p, 'groups').first;
      expect(
        reservationMatchesFilter(p, g, 'Attribution complète', 'Camille'),
        true,
      );
      setWaitingStatus(p, g, true);
      expect(
        reservationMatchesFilter(p, g, 'Liste d’attente', 'Camille'),
        true,
      );
      expect(
        reservationMatchesFilter(p, g, 'Attribution complète', 'Camille'),
        false,
      );
    },
  );
  test(
    'Swapping equal allocations preserves identities and refuses locked groups',
    () {
      final p = demoProject();
      p['groups'] = [seatedGroup('a', 2), seatedGroup('b', 2)];
      allocate(p);
      final a = rows(p, 'groups')[0], b = rows(p, 'groups')[1];
      a['alloc'] = [
        {'table': tables(p)[0]['id'], 'count': 2},
      ];
      b['alloc'] = [
        {'table': tables(p)[1]['id'], 'count': 2},
      ];
      final id = tables(p)[1]['id'];
      swapReservationAssignments(p, 'a', 'b');
      expect(rows(p, 'groups')[0]['alloc'][0]['table'], id);
      rows(p, 'groups')[0]['locked'] = true;
      expect(
        () => swapReservationAssignments(p, 'a', 'b'),
        throwsFormatException,
      );
    },
  );
  test(
    'Swap numbered chairs keeps people and exchanges their seat positions',
    () {
      final p = demoProject();
      p['groups'] = [seatedGroup('a', 1), seatedGroup('b', 1)];
      final gs = rows(p, 'groups');
      for (var n = 0; n < 2; n++) {
        gs[n]['alloc'] = [
          {'table': tables(p)[n]['id'], 'count': 1},
        ];
        gs[n]['seats'] = [
          {
            'number': 1,
            'name': 'Personne $n',
            'companion': '',
            'meal': 'Normal',
            'need': '',
            'allergy': '',
            'table': tables(p)[n]['id'],
            'slot': 1,
          },
        ];
      }
      final target = gs[1]['seats'][0]['table'];
      swapReservationAssignments(p, 'a', 'b');
      expect(rows(p, 'groups')[0]['seats'][0]['name'], 'Personne 0');
      expect(rows(p, 'groups')[0]['seats'][0]['table'], target);
    },
  );
  test('Bulk changes preserve geometry and update only requested fields', () {
    final p = demoProject();
    p['groups'] = <Json>[];
    final id = tables(p).first['id'];
    final before = clone(tables(p).first);
    bulkFurnitureProperties(
      p,
      {id},
      {'note': 'Préparer', 'numberLocked': true},
    );
    final after = tables(p).first;
    expect(after['x'], before['x']);
    expect(after['w'], before['w']);
    expect(after['note'], 'Préparer');
    expect(after['numberLocked'], true);
  });
  test('Public and tiled PDF variants are generated independently', () async {
    final p = demoProject();
    allocate(p);
    await Directory('tmp/pdfs').create(recursive: true);
    for (final audience in ['Organisation', 'Visiteurs', 'Exposants']) {
      await exportPdf(
        p,
        'tmp/pdfs/profile-$audience.pdf',
        overwriteConfirmed: true,
        includeSummary: false,
        includeCards: false,
        planAudience: audience,
      );
    }
    await exportPdf(
      p,
      'tmp/pdfs/tiled-plan.pdf',
      overwriteConfirmed: true,
      includeSummary: false,
      includeCards: false,
      planColumns: 2,
      planRows: 2,
    );
  });
}
