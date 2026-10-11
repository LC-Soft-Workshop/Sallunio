import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/event_backup.dart';

import 'place_proximity_test.dart' show fixture;

void main() {
  for (final kind in ['entry', 'exit']) {
    for (final pmr in [false, true]) {
      test(
        '$kind audience filtering for group PMR=$pmr, companions included',
        () {
          final p = fixture(kind);
          final item = rows(p, 'items').last;
          final group = rows(p, 'groups').single;
          group['seats'] = <Json>[
            {
              'number': 1,
              'need': pmr ? 'Fauteuil' : '',
              'name': '',
              'meal': 'Normal',
              'allergy': '',
              'companion': '',
            },
          ];
          rows(p, 'items').add({
            ...item,
            'id': 'other',
            'x': 0.0,
            'accessAudience': 'Tous publics',
          });
          item['accessAudience'] = 'PMR avec accompagnants';
          expect(groupHasPmr(group), pmr);
          expect(accessCompatible(p, item, group), pmr);
          expect(
            groupProximityTargets(p, group).any((i) => i['id'] == 'place'),
            pmr,
          );
          item['accessAudience'] = 'Non-PMR uniquement';
          expect(accessCompatible(p, item, group), !pmr);
          item['accessAudience'] = 'Tous publics';
          expect(accessCompatible(p, item, group), true);
          validateProject(p);
          final restored = readEventBackup(jsonEncode(eventBackup([p]))).single;
          expect(
            rows(
              restored,
              'items',
            ).firstWhere((i) => i['id'] == 'place')['accessAudience'],
            'Tous publics',
          );
        },
      );
    }
  }
  test(
    'Two entrances restrict audience, one exit remains common independently',
    () {
      final p = fixture('entry');
      final first = rows(p, 'items').last;
      first['accessAudience'] = 'PMR avec accompagnants';
      final exit = {...first, 'id': 'exit', 'kind': 'exit'};
      rows(p, 'items').add(exit);
      final group = rows(p, 'groups').single;
      expect(accessCompatible(p, first, group), true);
      rows(
        p,
        'items',
      ).add({...first, 'id': 'second', 'proximityEnabled': 'Non'});
      expect(accessCompatible(p, first, group), false);
      expect(accessCompatible(p, exit, group), true);
      rows(p, 'items').removeLast();
      expect(accessCompatible(p, first, group), true);
      group['needs'] = 'Autre mobilité';
      first['accessAudience'] = 'Non-PMR uniquement';
      expect(accessCompatible(p, first, group), true);
    },
  );
  test('An incompatible old wish is ignored and reported privately; invalid audience rejected', () {
    final p = fixture('entry');
    final item = rows(p, 'items').last;
    item['accessAudience'] = 'PMR avec accompagnants';
    rows(p, 'items').add({
      ...item,
      'id': 'second',
      'accessAudience': 'Tous publics',
      'x': 0.0,
    });
    final group = rows(p, 'groups').single;
    expect(preferenceScore(p, group, tables(p).last), 0);
    expect(
      reservationPreferenceChecks(p).single,
      contains('accès incompatible'),
    );
    item['accessAudience'] = 'Impossible';
    expect(() => validateProject(p), throwsFormatException);
  });
}
