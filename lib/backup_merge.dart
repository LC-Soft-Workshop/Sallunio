import 'dart:convert';

import 'domain.dart';

const keepAllVersions = 'all';

class BackupEntry {
  final String token, category, origin;
  final int source;
  final Json value;
  final int placedTables;
  BackupEntry(
    this.token,
    this.category,
    this.origin,
    this.source,
    this.value, {
    this.placedTables = 0,
  });

  String get name => '${value['name']}';
  String get description => switch (category) {
    'rooms' =>
      '${value['width']} × ${value['height']} m • contour ${'${value['polygon'] ?? ''}'.isEmpty ? 'rectangulaire' : 'personnalisé'}',
    'types' =>
      '${value['w']} × ${value['h']} m • ${value['capacity']} places • stock ${value['quantity']} • $placedTables table(s) dans le plan',
    _ => '${value['count']} personnes • ${value['meal'] ?? ''}',
  };
}

class BackupConflict {
  final String key, category, name;
  final List<BackupEntry> versions;
  BackupConflict(this.key, this.category, this.name, this.versions);
  String get label =>
      '${switch (category) {
        'rooms' => 'Salle',
        'types' => 'Mobilier',
        _ => 'Réservation',
      }} : $name';
}

/// A detached review. Nothing in either the open event or the backup is changed
/// until every same-name conflict has an explicit decision.
class BackupMergePlan {
  final Json target;
  final List<Json> sources;
  final bool rooms, furniture, reservations;
  final List<BackupEntry> entries = [];
  late final List<BackupConflict> conflicts;

  BackupMergePlan(
    Json target,
    List<Json> sources, {
    required this.rooms,
    required this.furniture,
    required this.reservations,
  }) : target = clone(target),
       sources = sources.map(clone).toList() {
    if (!rooms && !furniture && !reservations) {
      throw const FormatException(
        'Choisir les salles, le mobilier et/ou les réservations.',
      );
    }
    if (sources.isEmpty) {
      throw const FormatException('Choisir un événement source.');
    }
    for (var source = -1; source < this.sources.length; source++) {
      final event = source < 0 ? this.target : this.sources[source];
      final origin = source < 0
          ? 'Événement ouvert : ${event['name']}'
          : 'Événement ${source + 1} : ${event['name']}';
      if (rooms) {
        final saved = <Json>[];
        for (final room in [event['room'] as Json, ...rows(event, 'rooms')]) {
          if (!saved.any((r) => _roomEqual(r, room))) saved.add(room);
        }
        for (var i = 0; i < saved.length; i++) {
          entries.add(
            BackupEntry('rooms/$source/$i', 'rooms', origin, source, saved[i]),
          );
        }
      }
      for (final category in [
        if (furniture) 'types',
        if (reservations) 'groups',
      ]) {
        final values = rows(event, category);
        for (var i = 0; i < values.length; i++) {
          final value = values[i];
          entries.add(
            BackupEntry(
              '$category/$source/$i',
              category,
              origin,
              source,
              value,
              placedTables: category == 'types'
                  ? rows(
                      event,
                      'items',
                    ).where((item) => item['type'] == value['id']).length
                  : 0,
            ),
          );
        }
      }
    }
    final byName = <String, List<BackupEntry>>{};
    for (final entry in entries) {
      final key = '${entry.category}/${entry.name.trim().toLowerCase()}';
      byName.putIfAbsent(key, () => []).add(entry);
    }
    conflicts = [
      for (final e in byName.entries)
        if (e.value.length > 1)
          BackupConflict(
            e.key,
            e.value.first.category,
            e.value.first.name,
            e.value,
          ),
    ];
  }

  static bool _roomEqual(Json a, Json b) {
    String canonical(Json room) {
      final keys = room.keys.toList()..sort();
      return jsonEncode({for (final key in keys) key: room[key]});
    }

    return canonical(a) == canonical(b);
  }

  Json apply(Map<String, String> decisions) {
    final accepted = entries.map((e) => e.token).toSet();
    for (final conflict in conflicts) {
      final choice = decisions[conflict.key];
      if (choice == keepAllVersions) continue;
      if (!conflict.versions.any((entry) => entry.token == choice)) {
        throw FormatException(
          'Choisir la version à garder pour ${conflict.label}.',
        );
      }
      accepted.removeAll(
        conflict.versions.where((e) => e.token != choice).map((e) => e.token),
      );
    }
    final selected = entries.where((e) => accepted.contains(e.token)).toList();
    final result = clone(target);
    String reference(int source, dynamic id) => '$source/$id';
    String unique(String name, String origin, Set<String> names) {
      if (names.add(name.trim().toLowerCase())) return name;
      var candidate = '$name ($origin)', n = 2;
      while (!names.add(candidate.trim().toLowerCase())) {
        candidate = '$name ($origin $n)';
        n++;
      }
      return candidate;
    }

    if (rooms) {
      final names = <String>{};
      result['rooms'] = [
        for (final entry in selected.where((e) => e.category == 'rooms'))
          clone(entry.value)
            ..['name'] = unique(entry.name, entry.origin, names),
      ];
    }
    if (!furniture && !reservations) {
      validateProject(result);
      return result;
    }
    final typeIds = <String, String>{}, itemIds = <String, String>{};
    if (furniture) {
      final names = <String>{};
      result['types'] = <Json>[];
      for (final entry in selected.where((e) => e.category == 'types')) {
        final copy = clone(entry.value);
        final id = entry.source < 0 ? copy['id'] as String : uid();
        typeIds[reference(entry.source, copy['id'])] = id;
        copy['id'] = id;
        copy['name'] = unique(entry.name, entry.origin, names);
        rows(result, 'types').add(copy);
      }
      result['items'] = rows(target, 'items')
          .where(
            (item) => ![
              'table',
              'bench',
              'banc',
              'chair',
              'pmr',
            ].contains(item['kind']),
          )
          .map(clone)
          .toList();
      for (final item in rows(result, 'items')) {
        itemIds[reference(-1, item['id'])] = item['id'];
      }
      final labels = rows(
        result,
        'items',
      ).map((i) => '${i['label']}'.trim().toLowerCase()).toSet();
      for (var source = -1; source < sources.length; source++) {
        final event = source < 0 ? target : sources[source];
        for (final item in rows(event, 'items').where(
          (i) => ['table', 'bench', 'banc', 'chair', 'pmr'].contains(i['kind']),
        )) {
          final type = item['type'];
          if (type != null && !typeIds.containsKey(reference(source, type))) {
            continue;
          }
          final copy = clone(item);
          final id = source < 0 ? copy['id'] as String : uid();
          itemIds[reference(source, copy['id'])] = id;
          copy['id'] = id;
          if (type != null) copy['type'] = typeIds[reference(source, type)];
          if (source < 0) {
            labels.add('${copy['label']}'.trim().toLowerCase());
          } else {
            copy['label'] = unique(
              '${copy['label']}',
              'importé ${source + 1}',
              labels,
            );
          }
          rows(result, 'items').add(copy);
        }
      }
    } else {
      for (final item in rows(target, 'items')) {
        itemIds[reference(-1, item['id'])] = item['id'];
      }
    }
    final selectedGroups = reservations
        ? selected.where((e) => e.category == 'groups').toList()
        : [
            for (var i = 0; i < rows(target, 'groups').length; i++)
              BackupEntry(
                'existing/$i',
                'groups',
                '',
                -1,
                rows(target, 'groups')[i],
              ),
          ];
    final groupIds = {
      for (final e in selectedGroups)
        reference(e.source, e.value['id']): e.source < 0
            ? e.value['id'] as String
            : uid(),
    };
    result['groups'] = <Json>[];
    for (final entry in selectedGroups) {
      final copy = clone(entry.value);
      copy['id'] = groupIds[reference(entry.source, copy['id'])];
      copy['alloc'] = <Json>[
        for (final allocation in (entry.value['alloc'] as List).cast<Json>())
          if (itemIds.containsKey(reference(entry.source, allocation['table'])))
            {
              ...allocation,
              'table': itemIds[reference(entry.source, allocation['table'])],
            },
      ];
      copy['standAlloc'] = <Json>[
        for (final a in (entry.value['standAlloc'] as List? ?? []).cast<Json>())
          if (itemIds.containsKey(reference(entry.source, a['table'])))
            {
              ...a,
              'id': uid(),
              'table': itemIds[reference(entry.source, a['table'])],
            },
      ];
      copy['reserved'] =
          itemIds[reference(entry.source, copy['reserved'])] ?? '';
      for (final seat in (copy['seats'] as List? ?? []).cast<Json>()) {
        final mapped = itemIds[reference(entry.source, seat['table'])];
        if (mapped == null) {
          seat.remove('table');
          seat.remove('slot');
        } else {
          seat['table'] = mapped;
        }
      }
      copy['separate'] =
          groupIds[reference(entry.source, copy['separate'])] ?? '';
      copy['placeProximity'] = {
        for (final pref in (copy['placeProximity'] as Map? ?? {}).entries)
          if (itemIds.containsKey(reference(entry.source, pref.key)))
            itemIds[reference(entry.source, pref.key)]: pref.value,
      };
      copy['proximity'] = {
        for (final e in (copy['proximity'] as Map? ?? {}).entries)
          if (groupIds.containsKey(reference(entry.source, e.key)))
            groupIds[reference(entry.source, e.key)]: e.value,
      };
      if ((copy['alloc'] as List).isEmpty &&
          (entry.source >= 0 ||
              (entry.value['alloc'] as List).isNotEmpty ||
              ('${entry.value['reserved'] ?? ''}'.isNotEmpty &&
                  copy['reserved'] == ''))) {
        copy['locked'] = false;
      }
      if (entry.source >= 0) copy['placementReview'] = false;
      rows(result, 'groups').add(copy);
    }
    if (reservations) {
      for (final source in sources) {
        for (final meal in source['meals']) {
          if (!(result['meals'] as List).contains(meal)) {
            result['meals'].add(meal);
          }
        }
      }
    }
    validateProject(result);
    return result;
  }
}
