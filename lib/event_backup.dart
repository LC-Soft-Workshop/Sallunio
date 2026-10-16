import 'dart:convert';

import 'domain.dart';

Json eventBackup(List<Json> events) => {
  'format': 'tableo-backup',
  'version': 1,
  'events': events.map(clone).toList(),
};

List<Json> readEventBackup(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Fichier Sallunio invalide.');
  }
  final List<dynamic> source;
  if (decoded['format'] == 'tableo-backup') {
    if (decoded['version'] != 1 || decoded['events'] is! List) {
      throw const FormatException('Format de sauvegarde non pris en charge.');
    }
    source = decoded['events'];
  } else {
    source = [decoded]; // Legacy single-event exports.
  }
  if (source.isEmpty) {
    throw const FormatException(
      'Cette sauvegarde ne contient aucun événement.',
    );
  }
  return source.map((value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Événement invalide dans la sauvegarde.');
    }
    final event = clone(value);
    validateProject(event);
    migrateEventSettings(event);
    return event;
  }).toList();
}

Json injectEventBackup(
  Json target,
  List<Json> sources, {
  required bool furniture,
  required bool reservations,
}) {
  if (!furniture && !reservations) {
    throw const FormatException('Choisir le mobilier et/ou les réservations.');
  }
  final result = clone(target);
  final labels = rows(result, 'items').map((item) => item['label']).toSet();
  for (final source in sources) {
    final typeIds = <String, String>{};
    final itemIds = <String, String>{};
    if (furniture) {
      for (final type in rows(source, 'types')) {
        final copy = clone(type);
        typeIds[type['id']] = copy['id'] = uid();
        rows(result, 'types').add(copy);
      }
      for (final item in rows(source, 'items').where(
        (item) =>
            ['table', 'bench', 'banc', 'chair', 'pmr'].contains(item['kind']),
      )) {
        final copy = clone(item);
        itemIds[item['id']] = copy['id'] = uid();
        if (copy['type'] != null) copy['type'] = typeIds[copy['type']];
        final originalLabel = copy['label'] as String;
        var label = originalLabel, index = 1;
        while (labels.contains(label)) {
          label = '$originalLabel (importé ${index++})';
        }
        copy['label'] = label;
        labels.add(label);
        rows(result, 'items').add(copy);
      }
    }
    if (reservations) {
      final groupIds = {
        for (final group in rows(source, 'groups')) group['id']: uid(),
      };
      for (final meal in source['meals']) {
        if (!(result['meals'] as List).contains(meal)) {
          result['meals'].add(meal);
        }
      }
      for (final group in rows(source, 'groups')) {
        final copy = clone(group);
        copy['id'] = groupIds[group['id']];
        copy['alloc'] = <Json>[
          for (final allocation in (group['alloc'] as List).cast<Json>())
            if (itemIds.containsKey(allocation['table']))
              {...allocation, 'table': itemIds[allocation['table']]},
        ];
        copy['standAlloc'] = <Json>[
          for (final a in (group['standAlloc'] as List? ?? []).cast<Json>())
            if (itemIds.containsKey(a['table']))
              {...a, 'id': uid(), 'table': itemIds[a['table']]},
        ];
        copy['reserved'] = itemIds[group['reserved']] ?? '';
        for (final seat in (copy['seats'] as List? ?? []).cast<Json>()) {
          final mapped = itemIds[seat['table']];
          if (mapped == null) {
            seat.remove('table');
            seat.remove('slot');
          } else {
            seat['table'] = mapped;
          }
        }
        copy['separate'] = groupIds[group['separate']] ?? '';
        copy['placeProximity'] = {
          for (final entry in (group['placeProximity'] as Map? ?? {}).entries)
            if (itemIds.containsKey(entry.key)) itemIds[entry.key]: entry.value,
        };
        copy['proximity'] = {
          for (final entry in (group['proximity'] as Map? ?? {}).entries)
            if (groupIds.containsKey(entry.key))
              groupIds[entry.key]: entry.value,
        };
        if ((copy['alloc'] as List).isEmpty) copy['locked'] = false;
        copy['placementReview'] = false;
        rows(result, 'groups').add(copy);
      }
    }
  }
  validateProject(result);
  return result;
}
