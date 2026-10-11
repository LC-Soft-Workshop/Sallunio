import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/event_backup.dart';
import 'package:tableo/backup_merge.dart';
import 'package:tableo/plan_export.dart';

import 'joining_test.dart' show table, plan;

Json fixture(String kind) {
  final p = plan([
    table('a', 1, 1),
    table('b', 8, 5),
    {
      'id': 'place',
      'kind': kind,
      'label': 'Bar fictif',
      'shape': 'rectangle',
      'x': 10.0,
      'y': 5.0,
      'w': 1.0,
      'h': 1.0,
      'fixed': false,
      'proximityEnabled': 'Oui',
    },
  ], 'Aucun');
  p['groups'] = <Json>[
    {
      'id': 'g',
      'name': 'Fictif',
      'count': 4,
      'meal': 'Normal',
      'needs': '',
      'allergy': '',
      'alloc': <Json>[],
      'locked': false,
      'placeProximity': {'place': 'near'},
    },
  ];
  return p;
}

void main() {
  test(
    'Far from an individual zone and selective import keep current targets',
    () {
      final p = fixture('zone');
      rows(p, 'groups').single['placeProximity'] = {'place': 'far'};
      allocate(p);
      expect(assignedTables(p, rows(p, 'groups').single).single['id'], 'a');
      final source = newProject('Source');
      final merged = BackupMergePlan(
        p,
        [source],
        rooms: false,
        furniture: true,
        reservations: false,
      ).apply({});
      expect(rows(merged, 'groups').single['placeProximity'], {'place': 'far'});
      validateProject(merged);
    },
  );

  for (final kind in ['zone', 'entry', 'exit']) {
    test(
      'Allocation favours nearest $kind and preserves preference in backup',
      () {
        final p = fixture(kind);
        validateProject(p);
        allocate(p);
        expect(assignedTables(p, rows(p, 'groups').single).single['id'], 'b');
        expect(reservationPreferenceChecks(p), isEmpty);
        final restored = readEventBackup(jsonEncode(eventBackup([p]))).single;
        expect(rows(restored, 'groups').single['placeProximity'], {
          'place': 'near',
        });
        final imported = injectEventBackup(
          newProject('Target'),
          [p],
          furniture: false,
          reservations: true,
        );
        expect(rows(imported, 'groups').single['placeProximity'], isEmpty);
        expect(planSvg(p), isNot(contains('placeProximity')));
        expect(planSvg(p), isNot(contains('préférence')));
      },
    );
  }
  test(
    'A place preference is allocated before an otherwise flexible group',
    () {
      final p = fixture('zone');
      final wanted = rows(p, 'groups').single;
      p['groups'] = <Json>[
        {
          ...wanted,
          'id': 'flexible',
          'name': 'Flexible',
          'count': 6,
          'placeProximity': <String, String>{},
          'alloc': <Json>[],
        },
        wanted,
      ];
      allocate(p);
      expect(assignedTables(p, wanted).single['id'], 'b');
      expect(assignedTables(p, rows(p, 'groups').first).single['id'], 'a');
    },
  );
  test('Individual target, rename, disabling and legacy conversion', () {
    final p = fixture('zone');
    rows(
      p,
      'items',
    ).add({...rows(p, 'items').last, 'id': 'other', 'x': 0.0, 'y': 1.0});
    allocate(p);
    final g = rows(p, 'groups').single;
    expect(assignedTables(p, g).single['id'], 'b');
    rows(p, 'items')[2]['label'] = 'Cuisine renommée';
    expect(
      proximityTargetName(proximityPlaces(p, 'place').single),
      'Cuisine renommée',
    );
    rows(p, 'items')[2]['proximityEnabled'] = 'Non';
    prunePlacePreferences(p);
    expect(reservationPlacePreferences(g), isEmpty);
    rows(p, 'items')[2]['kind'] = 'toilet';
    g['placeProximity'] = {'toilet': 'near'};
    migrateEventSettings(p);
    expect(rows(p, 'items')[2]['kind'], 'zone');
    expect(reservationPlacePreferences(g), isEmpty);
    validateProject(p);
  });
  test(
    'Missing place is private information; malformed preferences rejected',
    () {
      final p = fixture('zone');
      rows(p, 'items').removeLast();
      allocate(p);
      prunePlacePreferences(p);
      expect(reservationPreferenceChecks(p), isEmpty);
      expect(issues(p).join(), isNot(contains('Bar fictif')));
      rows(p, 'groups').single['placeProximity'] = {'zone': 'near'};
      expect(() => validateProject(p), throwsFormatException);
    },
  );
  test(
    'Included zones are resizable, below tables, exported and cleared safely',
    () {
      final p = fixture('zone');
      final t = rows(p, 'items').last;
      expect(canResizePlanObject(t), true);
      expect(planPaintOrder(p).first['kind'], 'zone');
      expect(planSvg(p), contains('translate(1000.0 500.0)'));
      expect(planSvg(p), contains('#bed8e9'));
      t['fixed'] = true;
      clearRoom(p, {'zones'});
      expect(proximityTargets(p), hasLength(1));
      clearRoom(p, {'zones'}, includeLocked: true);
      expect(proximityTargets(p), isEmpty);
      validateProject(p);
    },
  );
}
