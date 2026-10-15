import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/event_backup.dart';
import 'package:tableo/plan_tools.dart';

void main() {
  test('Reservation child chairs respect stock, count, edits and waiting', () {
    final p = demoProject();
    final type = clone(rows(p, 'types').first)
      ..addAll({
        'shape': 'chaise enfant',
        'quantity': 3,
        'limit': 2,
        'enabled': true,
      });
    p['types'] = [type];
    final a = rows(p, 'groups')[0]..['childChairs'] = 1;
    final b = rows(p, 'groups')[1]..['childChairs'] = 1;
    expect(childChairStock(p), 2);
    expect(childChairReservationError(p, a), isNull);
    expect(childChairReservationError(p, {...b, 'childChairs': 2}), isNotNull);
    expect(
      childChairReservationError(p, {...a, 'childChairs': a['count'] + 1}),
      isNotNull,
    );
    setWaitingStatus(p, b, true);
    expect(reservedChildChairs(p), 1);
    expect(childChairReservationError(p, {...a, 'childChairs': 2}), isNull);
    a['childChairs'] = 2;
    expect(() => setWaitingStatus(p, b, false), throwsFormatException);
    expect(b['waiting'], true);
    a['childChairs'] = 1;
    setWaitingStatus(p, b, false);
    expect(reservedChildChairs(p), 2);
  });
  test('Child chairs deploy, assign one seat, filter and round trip', () {
    final p = newProject('Chaises enfant');
    final model = clone(rows(demoProject(), 'types').first)
      ..addAll({
        'id': 'child',
        'name': 'Chaise enfant',
        'shape': 'chaise enfant',
        'w': .4,
        'h': .4,
        'capacity': 1,
        'usage': furnitureUses.first,
        'quantity': 3,
        'limit': 3,
        'enabled': true,
      });
    p['types'] = [model];
    expect(addFurniture(p, [model], all: true).placed, 3);
    expect(tables(p).every((t) => t['kind'] == 'chair'), true);
    expect(tables(p).map((t) => t['label']), ['CE1', 'CE2', 'CE3']);
    expect(tables(p).every((t) => effectiveCapacity(p, t) == 1), true);
    final group = clone(rows(demoProject(), 'groups').first)
      ..addAll({
        'count': 1,
        'childChairs': 1,
        'alloc': <Json>[],
        'reserved': '',
        'seats': <Json>[],
        'needs': '',
        'allergy': '',
        'locked': false,
      });
    p['groups'] = [group];
    allocate(p);
    expect(occupancy(p, tables(p).first['id']), 1);
    final geo = PlanGeometry(p, rows(p, 'items'));
    expect(
      tableMatchesFilter(p, tables(p).first, 'Entièrement attribué', geo),
      true,
    );
    expect(furnitureTooltip(p, tables(p).first), contains('Chaise enfant'));
    final restored = readEventBackup(jsonEncode(eventBackup([p]))).first;
    expect(tables(restored).first['shape'], 'chaise enfant');
    expect(eventComfort(restored)['childChairWidth'], .4);
    expect(
      renumberingPreview(p, 'Lignes').values.every((s) => s.startsWith('CE')),
      true,
    );
  });
}
