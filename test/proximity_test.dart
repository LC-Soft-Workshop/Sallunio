import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';

import 'joining_test.dart' show table, plan;

Json project() {
  final p = plan([
    table('a', 1, 1),
    table('b', 4, 1),
    table('c', 9, 7),
  ], 'Aucun');
  p['groups'] = List<Json>.generate(
    3,
    (i) => {
      'id': 'g${i + 1}',
      'name': 'Groupe ${i + 1}',
      'count': 6,
      'meal': 'Normal',
      'needs': '',
      'allergy': '',
      'alloc': <Json>[],
      'locked': false,
    },
  );
  return p;
}

void main() {
  test('A near B and B far C places C on the far side of the room', () {
    final p = project(), groups = rows(project(), 'groups');
    setReservationPreference(p, rows(p, 'groups')[0], 'g2', 'near');
    setReservationPreference(p, rows(p, 'groups')[1], 'g3', 'far');
    allocate(p);
    final gs = rows(p, 'groups');
    expect(
      tableDistance(
        assignedTables(p, gs[0]).single,
        assignedTables(p, gs[1]).single,
      ),
      lessThanOrEqualTo(3.000001),
    );
    expect(
      tableDistance(
        assignedTables(p, gs[1]).single,
        assignedTables(p, gs[2]).single,
      ),
      greaterThanOrEqualTo(farPreferenceDistance(p)),
    );
    expect(gs.every((g) => (g['alloc'] as List).single['count'] == 6), true);
    expect(groups.length, 3);
  });
  test(
    'Editing preference from opposite group updates the single relationship',
    () {
      final p = project(), gs = rows(project(), 'groups');
      setReservationPreference(p, rows(p, 'groups')[0], 'g2', 'near');
      expect(reservationPreferences(p, rows(p, 'groups')[1])['g1'], 'near');
      setReservationPreference(p, rows(p, 'groups')[1], 'g1', 'far');
      expect(reservationPreferences(p, rows(p, 'groups')[0])['g2'], 'far');
      expect(gs.length, 3);
      removeReservation(p, 'g1');
      expect(reservationPreferences(p, rows(p, 'groups').first), isEmpty);
    },
  );
  test(
    'Locked assignments are preserved and impossible preference is reported',
    () {
      final p = project();
      final gs = rows(p, 'groups');
      gs[0]['locked'] = true;
      gs[0]['alloc'] = [
        {'table': 'a', 'count': 6},
      ];
      gs[1]['locked'] = true;
      gs[1]['alloc'] = [
        {'table': 'b', 'count': 6},
      ];
      setReservationPreference(p, gs[0], 'g2', 'far');
      allocate(p);
      expect(gs[0]['alloc'], [
        {'table': 'a', 'count': 6},
      ]);
      expect(gs[1]['alloc'], [
        {'table': 'b', 'count': 6},
      ]);
      expect(
        reservationPreferenceChecks(p)
            .any((s) => s.contains('préférence loin à revoir')),
        true,
      );
    },
  );
  test('Preferences survive JSON and self links are rejected', () {
    final p = demoProject();
    final gs = rows(p, 'groups');
    setReservationPreference(p, gs.first, gs.last['id'], 'near');
    final copy = clone(p);
    validateProject(copy);
    expect(
      reservationPreferences(copy, rows(copy, 'groups').first)[gs.last['id']],
      'near',
    );
    expect(
      () => setReservationPreference(p, gs.first, gs.first['id'], 'far'),
      throwsFormatException,
    );
  });
}
