import 'dart:math';

import 'domain.dart';

/// A rigid transformation: distances and table dimensions stay unchanged.
void transformTableSelection(
  Json project,
  Set<String> ids, {
  double dx = 0,
  double dy = 0,
  bool rotate = false,
}) {
  final selected = tables(project).where((t) => ids.contains(t['id'])).toList();
  if (selected.isEmpty) return;
  if (selected.any((t) => t['fixed'] == true)) {
    throw const FormatException(
      'Déverrouiller les tables sélectionnées avant de déplacer cet ensemble.',
    );
  }
  final left = selected.map((t) => number(t['x'])).reduce(min);
  final top = selected.map((t) => number(t['y'])).reduce(min);
  final right = selected
      .map((t) => number(t['x']) + number(t['w']))
      .reduce(max);
  final bottom = selected
      .map((t) => number(t['y']) + number(t['h']))
      .reduce(max);
  final cx = (left + right) / 2, cy = (top + bottom) / 2;
  for (final table in selected) {
    var x = number(table['x']) + number(table['w']) / 2;
    var y = number(table['y']) + number(table['h']) / 2;
    if (rotate) {
      final oldX = x;
      x = cx - (y - cy);
      y = cy + (oldX - cx);
      rotateTable(table);
    }
    table['x'] = x - number(table['w']) / 2 + dx;
    table['y'] = y - number(table['h']) / 2 + dy;
    table.remove('unplacedByArrangement');
  }
  final shiftX = max(0.0, -selected.map((t) => number(t['x'])).reduce(min));
  final shiftY = max(0.0, -selected.map((t) => number(t['y'])).reduce(min));
  for (final table in selected) {
    table['x'] = number(table['x']) + shiftX;
    table['y'] = number(table['y']) + shiftY;
  }
}

const planFilters = [
  'Toutes les tables',
  'Tables vides',
  'Places disponibles',
  'Mobilité / PMR',
  'Allergie',
];
bool tableMatchesFilter(Json p, Json table, String filter, PlanGeometry geo) {
  if (filter == 'Toutes les tables') return true;
  if (filter == 'Tables vides') return occupancy(p, table['id']) == 0;
  if (filter == 'Places disponibles') {
    return occupancy(p, table['id']) < geo.capacity(table);
  }
  return tableMarkers(p, table['id']).contains(filter);
}

String _csvCell(Object? value) {
  final text = (value ?? '').toString();
  // Prevent spreadsheet formula interpretation of user supplied text.
  final safe = RegExp(r'^\s*[=+@-]').hasMatch(text) ? "'$text" : text;
  return '"${safe.replaceAll('"', '""')}"';
}

String eventCsv(Json p, String section) {
  final data = <List<Object?>>[];
  if (section == 'Réservations') {
    data.add([
      'Référent',
      'Effectif',
      'Repas',
      'Mobilité',
      'Allergies',
      'Personnes et places',
    ]);
    for (final g in rows(p, 'groups')) {
      final assigned = assignedPeople(p, g);
      final details = <String>[];
      for (var i = 0; i < g['count']; i++) {
        final s = individualSeat(g, i);
        final table = assigned[i]['table'];
        details.add(
          '${(s['name'] ?? '').toString().isEmpty ? 'Personne ${i + 1}' : s['name']}'
          '${table == null ? '' : ' : ${table['label']} place ${(assigned[i]['slot'] as int) + 1}'}'
          '${mealsEnabled(p) ? ' / ${s['meal']}' : ''}'
          '${(s['need'] ?? '').toString().isEmpty ? '' : ' / ${s['need']}'}'
          '${(s['allergy'] ?? '').toString().isEmpty ? '' : ' / ${s['allergy']}'}',
        );
      }
      data.add([
        g['name'],
        g['count'],
        mealsEnabled(p) ? g['meal'] : '',
        g['needs'],
        g['allergy'],
        details.join('\n'),
      ]);
    }
  } else if (section == 'Attributions') {
    data.add([
      'Table',
      'Places utilisables',
      'Places attribuées',
      'Référent',
      'Nombre',
    ]);
    for (final t in tables(p)) {
      final groups = rows(p, 'groups').where(
        (g) => (g['alloc'] as List).any(
          (a) => a['table'] == t['id'] && a['count'] > 0,
        ),
      );
      if (groups.isEmpty) {
        data.add([
          t['label'],
          effectiveCapacity(p, t),
          occupancy(p, t['id']),
          '',
          0,
        ]);
      }
      for (final g in groups) {
        final count = (g['alloc'] as List)
            .where((a) => a['table'] == t['id'])
            .fold<int>(0, (sum, a) => sum + (a['count'] as int));
        data.add([
          t['label'],
          effectiveCapacity(p, t),
          occupancy(p, t['id']),
          g['name'],
          count,
        ]);
      }
    }
  } else if (section == 'Totaux des repas') {
    data.add(['Repas', 'Nombre']);
    for (final e in mealTotals(p).entries) {
      data.add([e.key, e.value]);
    }
  } else {
    throw const FormatException('Type d’export inconnu.');
  }
  // Closed field list deliberately excludes notes and proximity preferences.
  return '\uFEFF${data.map((row) => row.map(_csvCell).join(';')).join('\r\n')}\r\n';
}
