import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/backup_merge.dart';

Json emptyTarget() {
  final p = demoProject();
  p['items'] = <Json>[];
  p['types'] = <Json>[];
  p['groups'] = <Json>[];
  p['rooms'] = <Json>[];
  p['room']['name'] = 'Salle actuelle';
  return p;
}

Json source(String name, {double width = 1.8}) {
  final p = demoProject();
  p['name'] = name;
  p['room']['name'] = 'Salle $name';
  final type = clone(rows(p, 'types').first);
  type['name'] = 'Table 180';
  type['w'] = width;
  type['quantity'] = type['limit'] = 2;
  final table = clone(tables(p).first);
  table['w'] = width;
  table['type'] = type['id'];
  p['types'] = [type];
  p['items'] = [table];
  final groups = rows(p, 'groups').take(2).map(clone).toList();
  for (var i = 0; i < groups.length; i++) {
    groups[i]['name'] = '$name groupe $i';
    groups[i]['count'] = 2;
    groups[i]['seats'] = <Json>[];
    groups[i]['alloc'] = [
      {'table': table['id'], 'count': 2},
    ];
    groups[i]['reserved'] = table['id'];
    groups[i]['locked'] = true;
  }
  groups[0]['proximity'] = {groups[1]['id']: 'near'};
  groups[0]['separate'] = groups[1]['id'];
  p['groups'] = groups;
  validateProject(p);
  return p;
}

void main() {
  test(
    'Rooms only import catalogues and preserve all current event content',
    () {
      final target = demoProject(), original = clone(target);
      final saved = source('A');
      saved['rooms'] = [
        clone(saved['room']),
        {...clone(saved['room']), 'name': 'Autre salle'},
      ];
      final plan = BackupMergePlan(
        target,
        [saved],
        rooms: true,
        furniture: false,
        reservations: false,
      );
      expect(plan.conflicts, isEmpty);
      final result = plan.apply({});
      expect(
        rows(result, 'rooms').where((r) => r['name'] == 'Salle A').length,
        1,
      );
      expect(
        rows(result, 'rooms').any((r) => r['name'] == 'Autre salle'),
        true,
      );
      for (final key in [
        'room',
        'items',
        'types',
        'groups',
        'id',
        'name',
        'meals',
      ]) {
        expect(result[key], target[key], reason: key);
      }
      expect(target, original);
    },
  );

  test('Common furniture requires a choice; choosing second event retains its model and tables', () {
    final target = emptyTarget(), a = source('A'), b = source('B', width: 2.4);
    final originalA = clone(a), originalB = clone(b);
    final plan = BackupMergePlan(
      target,
      [a, b],
      rooms: false,
      furniture: true,
      reservations: false,
    );
    expect(plan.conflicts.single.name, 'Table 180');
    expect(() => plan.apply({}), throwsFormatException);
    final conflict = plan.conflicts.single;
    final result = plan.apply({conflict.key: conflict.versions.last.token});
    expect(rows(result, 'types').single['w'], 2.4);
    expect(tables(result).single['w'], 2.4);
    expect(tables(result).single['type'], rows(result, 'types').single['id']);
    expect(a, originalA);
    expect(b, originalB);
  });

  test('Selected model keeps its assignments; discarded models leave reservations unassigned without dangling links', () {
    final a = source('A'), b = source('B', width: 2.4);
    final plan = BackupMergePlan(
      emptyTarget(),
      [a, b],
      rooms: true,
      furniture: true,
      reservations: true,
    );
    final conflict = plan.conflicts.single;
    final result = plan.apply({conflict.key: conflict.versions.last.token});
    final groups = rows(result, 'groups');
    for (final group in groups.take(2)) {
      expect(group['count'], 2);
      expect(group['alloc'], isEmpty);
      expect(group['reserved'], '');
      expect(group['locked'], false);
    }
    for (final group in groups.skip(2)) {
      expect(group['alloc'].single['table'], tables(result).single['id']);
      expect(group['reserved'], tables(result).single['id']);
    }
    expect(groups[0]['proximity'], {groups[1]['id']: 'near'});
    expect(groups[2]['proximity'], {groups[3]['id']: 'near'});
    expect(groups[0]['separate'], groups[1]['id']);
    validateProject(result);
  });

  test('Keeping every version renames models and rooms and preserves IDs in open event', () {
    final target = source('Courant'), a = source('A'), b = source('B');
    for (final p in [target, a, b]) {
      p['room']['name'] = 'Grande salle';
    }
    final plan = BackupMergePlan(
      target,
      [a, b],
      rooms: true,
      furniture: true,
      reservations: true,
    );
    final result = plan.apply({
      for (final c in plan.conflicts) c.key: keepAllVersions,
    });
    expect(rows(result, 'types').length, 3);
    expect(rows(result, 'types').map((t) => t['name']).toSet().length, 3);
    expect(rows(result, 'rooms').map((r) => r['name']).toSet().length, 3);
    expect(tables(result).first['id'], tables(target).first['id']);
    expect(tables(result).first['x'], tables(target).first['x']);
    expect(
      rows(result, 'groups').first['id'],
      rows(target, 'groups').first['id'],
    );
    expect(tables(result).map((t) => t['id']).toSet().length, 3);
    validateProject(result);
  });

  test('Replacing current furniture explicitly frees its groups and preserves unrelated event settings', () {
    final target = source('Courant'), b = source('B');
    final plan = BackupMergePlan(
      target,
      [b],
      rooms: false,
      furniture: true,
      reservations: false,
    );
    final conflict = plan.conflicts.single;
    final result = plan.apply({conflict.key: conflict.versions.last.token});
    expect(
      rows(result, 'groups').map((g) => g['id']).toList(),
      rows(target, 'groups').map((g) => g['id']).toList(),
    );
    expect(
      rows(
        result,
        'groups',
      ).every((g) => g['alloc'].isEmpty && g['reserved'] == ''),
      true,
    );
    expect(result['room'], target['room']);
    expect(result['id'], target['id']);
  });

  test(
    'Homonymous reservations are never merged without an explicit decision',
    () {
      final a = source('A'), b = source('B');
      rows(b, 'groups').first['name'] = rows(a, 'groups').first['name'];
      final plan = BackupMergePlan(
        emptyTarget(),
        [a, b],
        rooms: false,
        furniture: false,
        reservations: true,
      );
      expect(() => plan.apply({}), throwsFormatException);
      final c = plan.conflicts.single;
      final chosen = plan.apply({c.key: c.versions.last.token});
      expect(rows(chosen, 'groups').length, 3);
      final all = plan.apply({c.key: keepAllVersions});
      expect(rows(all, 'groups').length, 4);
      expect(rows(all, 'groups').map((g) => g['id']).toSet().length, 4);
      expect(rows(all, 'groups').every((g) => g['alloc'].isEmpty), true);
    },
  );
}
