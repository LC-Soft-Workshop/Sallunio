part of 'domain.dart';

void requireEditable(Json p, {bool plan = false}) {
  if (p['eventLocked'] == true || plan && p['planLocked'] == true) {
    throw const FormatException('Déverrouiller avant de modifier.');
  }
}

List<Json> searchPlanItems(Json p, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return rows(p, 'items');
  final linked = <String>{};
  for (final g in rows(p, 'groups')) {
    final persons = (g['seats'] as List? ?? []).cast<Json>();
    if ('${g['name']} ${g['contact'] ?? ''} ${g['email'] ?? ''} ${g['phone'] ?? ''} ${persons.map((s) => s['name'] ?? '').join(' ')}'
        .toLowerCase()
        .contains(q)) {
      linked.addAll([
        for (final a in (g['alloc'] as List? ?? [])) a['table'] as String,
        for (final a in (g['standAlloc'] as List? ?? [])) a['table'] as String,
        for (final seat in persons)
          if (seat['table'] != null) seat['table'] as String,
      ]);
    }
  }
  return rows(p, 'items')
      .where(
        (i) =>
            linked.contains(i['id']) ||
            '${furnitureShortLabel(i)} ${i['label']} ${rows(p, 'types').where((t) => t['id'] == i['type']).map((t) => t['name']).join(' ')}'
                .toLowerCase()
                .contains(q),
      )
      .toList();
}

Set<String> rectangleSelection(
  Json p,
  double left,
  double top,
  double right,
  double bottom,
) => rows(p, 'items')
    .where(
      (i) =>
          number(i['x']) >= min(left, right) &&
          number(i['y']) >= min(top, bottom) &&
          number(i['x']) + number(i['w']) <= max(left, right) &&
          number(i['y']) + number(i['h']) <= max(top, bottom),
    )
    .map((i) => i['id'] as String)
    .toSet();
void applyPositions(Json p, Map<String, (double, double)> positions) {
  requireEditable(p, plan: true);
  final draft = clone(p);
  for (final i in rows(draft, 'items')) {
    final xy = positions[i['id']];
    if (xy != null) {
      i['x'] = xy.$1;
      i['y'] = xy.$2;
      i.remove('unplacedByArrangement');
    }
  }
  for (final i in rows(
    draft,
    'items',
  ).where((i) => positions.containsKey(i['id']))) {
    if (i['fixed'] == true) {
      throw const FormatException('La sélection contient une position fixée.');
    }
    if (number(i['x']) < 0 ||
        number(i['y']) < 0 ||
        number(i['x']) + number(i['w']) >
            number(p['room']['width']) + .000001 ||
        number(i['y']) + number(i['h']) >
            number(p['room']['height']) + .000001 ||
        !polygonFits(p, i)) {
      throw const FormatException(
        'Le déplacement sortirait du contour de la salle.',
      );
    }
    if (isSeatingFurniture(i) &&
        rows(draft, 'items').any(
          (b) => b['id'] != i['id'] && isSeatingFurniture(b) && overlaps(i, b),
        )) {
      throw const FormatException(
        'Le déplacement créerait une superposition de mobilier.',
      );
    }
  }
  for (final i in rows(p, 'items')) {
    final xy = positions[i['id']];
    if (xy != null) {
      i['x'] = xy.$1;
      i['y'] = xy.$2;
      i.remove('unplacedByArrangement');
    }
  }
}

void nudgeSelection(Json p, Set<String> ids, double dx, double dy) =>
    applyPositions(p, {
      for (final i in rows(p, 'items').where((i) => ids.contains(i['id'])))
        i['id']: (number(i['x']) + dx, number(i['y']) + dy),
    });
void alignFurnitureSelection(Json p, Set<String> ids, String action) {
  final items = rows(p, 'items').where((i) => ids.contains(i['id'])).toList();
  if (items.length < 2) {
    throw const FormatException('Sélectionner au moins deux objets.');
  }
  final positions = <String, (double, double)>{};
  final left = items.map((i) => number(i['x'])).reduce(min),
      top = items.map((i) => number(i['y'])).reduce(min);
  final right = items.map((i) => number(i['x']) + number(i['w'])).reduce(max),
      bottom = items.map((i) => number(i['y']) + number(i['h'])).reduce(max);
  if (action == 'Répartir horizontalement' ||
      action == 'Répartir verticalement') {
    if (items.length < 3) {
      throw const FormatException(
        'Sélectionner au moins trois objets pour répartir.',
      );
    }
    final horizontal = action == 'Répartir horizontalement',
        axis = horizontal ? 'x' : 'y',
        size = horizontal ? 'w' : 'h';
    items.sort((a, b) => number(a[axis]).compareTo(number(b[axis])));
    final gap =
        ((horizontal ? right - left : bottom - top) -
            items.fold<double>(0, (v, i) => v + number(i[size]))) /
        (items.length - 1);
    if (gap < 0) {
      throw const FormatException(
        'Espace insuffisant pour répartir sans chevauchement.',
      );
    }
    var cursor = horizontal ? left : top;
    for (final i in items) {
      positions[i['id']] = horizontal
          ? (cursor, number(i['y']))
          : (number(i['x']), cursor);
      cursor += number(i[size]) + gap;
    }
  } else {
    for (final i in items) {
      var x = number(i['x']), y = number(i['y']);
      switch (action) {
        case 'Aligner à gauche':
          x = left;
        case 'Aligner à droite':
          x = right - number(i['w']);
        case 'Aligner en haut':
          y = top;
        case 'Aligner en bas':
          y = bottom - number(i['h']);
        case 'Centrer horizontalement':
          x = (left + right - number(i['w'])) / 2;
        case 'Centrer verticalement':
          y = (top + bottom - number(i['h'])) / 2;
      }
      positions[i['id']] = (x, y);
    }
  }
  applyPositions(p, positions);
}

List<Json> duplicatePlanSelection(Json p, Set<String> ids) {
  requireEditable(p, plan: true);
  final originals = rows(
    p,
    'items',
  ).where((i) => ids.contains(i['id'])).toList();
  if (originals.isEmpty) throw const FormatException('Sélection vide.');
  for (final type in rows(p, 'types')) {
    final required = originals.where((i) => i['type'] == type['id']).length;
    if (required > 0 && type['enabled'] != true) {
      throw FormatException('${type['name']} est exclu de cet événement.');
    }
    final free =
        min(type['quantity'] as int, type['limit'] as int) -
        rows(p, 'items').where((i) => i['type'] == type['id']).length;
    if (required > free) {
      throw FormatException(
        '${type['name']} : $required nécessaires, $free encore autorisés.',
      );
    }
  }
  final copies = <Json>[];
  final labels = rows(p, 'items').map(furnitureShortLabel).toSet();
  for (final original in originals) {
    final item = clone(original)
      ..['id'] = uid()
      ..['fixed'] = false;
    item.remove('unplacedByArrangement');
    item.remove('blockedSlots');
    item.remove('numberLocked');
    final prefix = switch (item['kind']) {
      'chair' => item['shape'] == 'chaise enfant' ? 'CE' : 'C',
      'bench' => 'B',
      'pmr' => 'PMR ',
      'table' => 'T',
      _ => '${original['label']} • copie ',
    };
    var n = 1;
    while (labels.contains('$prefix$n')) {
      n++;
    }
    item['label'] = '$prefix$n';
    labels.add(item['label']);
    copies.add(item);
  }
  for (var attempt = 1; attempt <= 80; attempt++) {
    final dx = ((attempt - 1) % 10 + 1) * .5, dy = ((attempt - 1) ~/ 10) * .5;
    for (var n = 0; n < copies.length; n++) {
      copies[n]['x'] = number(originals[n]['x']) + dx;
      copies[n]['y'] = number(originals[n]['y']) + dy;
    }
    if (copies.every(
      (i) =>
          number(i['x']) + number(i['w']) <= number(p['room']['width']) &&
          number(i['y']) + number(i['h']) <= number(p['room']['height']) &&
          polygonFits(p, i) &&
          !rows(p, 'items').any((b) => overlaps(i, b)),
    )) {
      rows(p, 'items').addAll(copies);
      return copies;
    }
  }
  throw const FormatException(
    'Aucun emplacement libre pour dupliquer cet ensemble.',
  );
}

Map<String, String> renumberingPreview(Json p, String order) {
  final result = <String, String>{};
  for (final kind in ['table', 'chair', 'childChair', 'bench', 'pmr']) {
    final items = tables(p)
        .where(
          (i) => kind == 'childChair'
              ? i['kind'] == 'chair' && i['shape'] == 'chaise enfant'
              : i['kind'] == kind &&
                    (kind != 'chair' || i['shape'] != 'chaise enfant'),
        )
        .toList();
    final vertical = order == 'Colonnes';
    items.sort((a, b) {
      final first = number(a[vertical ? 'x' : 'y'])
          .compareTo(number(b[vertical ? 'x' : 'y']));
      return first != 0
          ? first
          : number(a[vertical ? 'y' : 'x'])
                .compareTo(number(b[vertical ? 'y' : 'x']));
    });
    final prefix = switch (kind) {
      'chair' => 'C',
      'childChair' => 'CE',
      'bench' => 'B',
      'pmr' => 'PMR ',
      _ => 'T',
    };
    final reserved = items
        .where((i) => i['numberLocked'] == true)
        .map(furnitureShortLabel)
        .toSet();
    var n = 1;
    for (final i in items) {
      if (i['numberLocked'] == true) continue;
      while (reserved.contains('$prefix$n')) {
        n++;
      }
      result[i['id']] = '$prefix${n++}';
    }
  }
  return result;
}

void applyRenumbering(Json p, Map<String, String> labels) {
  requireEditable(p, plan: true);
  for (final item in tables(p)) {
    if (item['numberLocked'] != true && labels.containsKey(item['id'])) {
      item['label'] = labels[item['id']];
    }
  }
}

void bulkFurnitureProperties(Json p, Set<String> ids, Json changes) {
  requireEditable(p, plan: true);
  final targets = rows(p, 'items').where((i) => ids.contains(i['id'])).toList();
  if (targets.any((i) => i['fixed'] == true)) {
    throw const FormatException(
      'Déverrouiller les positions avant modification collective.',
    );
  }
  final draft = clone(p);
  if (changes['usage'] != null) {
    changeFurnitureUsage(
      draft,
      ids.where((id) => tables(draft).any((i) => i['id'] == id)).toSet(),
      changes['usage'],
    );
  }
  if (changes['capacity'] == 0) {
    changeFurnitureUsage(
      draft,
      ids
          .where(
            (id) =>
                tables(draft).any((i) => i['id'] == id && i['kind'] == 'table'),
          )
          .toSet(),
      'Service',
    );
  }
  for (final i in rows(draft, 'items').where((i) => ids.contains(i['id']))) {
    for (final key in ['note', 'numberLocked']) {
      if (changes.containsKey(key)) {
        if (changes[key] == null) {
          i.remove(key);
        } else {
          i[key] = changes[key];
        }
      }
    }
    if (i['kind'] == 'table') {
      for (final key in [
        'capacity',
        'sides',
        'seatSide',
        'seating',
        'joinGap',
        'joinGapSides',
      ]) {
        if (changes.containsKey(key)) {
          if (changes[key] == null) {
            i.remove(key);
          } else {
            i[key] = changes[key];
          }
        }
      }
    }
  }
  validateProject(draft);
  p.clear();
  p.addAll(draft);
}

String _reservationToken(Object? value) => '${value ?? ''}'
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');
bool nearReservationName(String a, String b) {
  if (a == b) return a.isNotEmpty;
  if (min(a.length, b.length) < 5 || (a.length - b.length).abs() > 1) {
    return false;
  }
  var i = 0, j = 0, changes = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++changes > 1) return false;
    if (a.length >= b.length) i++;
    if (b.length >= a.length) j++;
  }
  return changes + (a.length - i) + (b.length - j) <= 1;
}

List<Json> similarReservations(Json p, Json group) {
  final name = _reservationToken(group['name']),
      contact = _reservationToken(group['contact']);
  return rows(p, 'groups')
      .where(
        (g) =>
            g['id'] != group['id'] &&
            (nearReservationName(name, _reservationToken(g['name'])) ||
                contact.isNotEmpty &&
                    _reservationToken(g['contact']) == contact),
      )
      .toList();
}

void setWaitingStatus(Json p, Json group, bool waiting) {
  requireEditable(p);
  if (!waiting) {
    final error = childChairReservationError(p, {...group, 'waiting': false});
    if (error != null) throw FormatException(error);
  }
  group['waiting'] = waiting;
  if (waiting) {
    group['alloc'] = <Json>[];
    group['standAlloc'] = <Json>[];
    group['reserved'] = '';
    group['locked'] = false;
    for (final s in (group['seats'] as List? ?? [])) {
      s.remove('table');
      s.remove('slot');
      s.remove('fixed');
    }
  }
}

double reservationAssigned(Json group) => isStandBooking(group)
    ? (group['standUnit'] == 'Mètres linéaires'
          ? (group['standAlloc'] as List? ?? []).fold<double>(
              0,
              (sum, a) => sum + number(a['length']),
            )
          : (group['standAlloc'] as List? ?? []).length.toDouble())
    : (group['alloc'] as List).fold<double>(
        0,
        (sum, a) => sum + number(a['count']),
      );
double reservationRequested(Json group) => isStandBooking(group)
    ? (group['standUnit'] == 'Mètres linéaires'
          ? number(group['requestedMetres'])
          : number(group['requestedTables'], 1))
    : number(group['count']);
List<String> reservationAllocationReasons(Json p, Json group) {
  if (group['waiting'] == true) {
    return ['Liste d’attente : aucune attribution automatique.'];
  }
  if (reservationAssigned(group) + .000001 >= reservationRequested(group)) {
    return [];
  }
  if (isStandBooking(group)) {
    return standAllocationWarnings(p)
        .where((s) => s.startsWith('${group['name']} :'))
        .toList();
  }
  final remaining = reservationRequested(group) - reservationAssigned(group);
  final messages = <String>[
    '${remaining.round()} personne(s) encore sans place.',
  ];
  if (freeSeating(p)) {
    return [
      ...messages,
      'Placement libre : attribuer manuellement ou activer le placement attribué.',
    ];
  }
  if (group['locked'] == true) {
    return [
      ...messages,
      'Attribution verrouillée : déverrouiller pour compléter automatiquement.',
    ];
  }
  final ts = tables(p)
      .where((t) => furnitureUse(t) == furnitureUses.first)
      .toList();
  final geo = PlanGeometry(p, rows(p, 'items'));
  final eligible = ts
      .where((t) => fits(p, t, rows(p, 'items'), geometry: geo))
      .toList();
  if (eligible.isEmpty) {
    return [
      ...messages,
      'Aucun mobilier assis utilisable sans conflit sur le plan.',
    ];
  }
  final free = eligible.fold<int>(
    0,
    (sum, t) => sum + max(0, geo.capacity(t) - occupancy(p, t['id'])),
  );
  messages.add('Places libres utilisables : $free.');
  if (free < remaining) {
    messages.add(
      'Capacité restante insuffisante ; ajouter du mobilier ou revoir la disposition.',
    );
  } else {
    messages.add(
      'Vérifier les places réservées, les besoins de mobilité et les contraintes de regroupement.',
    );
  }
  return messages;
}

bool reservationMatchesFilter(Json p, Json g, String filter, String query) {
  final terms =
      '${g['name']} ${g['contact'] ?? ''} ${g['email'] ?? ''} ${g['phone'] ?? ''} ${(g['seats'] as List? ?? []).map((s) => s['name'] ?? '').join(' ')}'
          .toLowerCase();
  if (!terms.contains(query.toLowerCase())) return false;
  if (filter == 'Liste d’attente') return g['waiting'] == true;
  if (filter == 'Confirmées') return g['waiting'] != true;
  final assigned = reservationAssigned(g), requested = reservationRequested(g);
  if (filter == 'Attribution complète') {
    return g['waiting'] != true && assigned >= requested;
  }
  if (filter == 'Attribution partielle') {
    return assigned > 0 && assigned < requested;
  }
  if (filter == 'Sans attribution') return assigned == 0;
  if (filter == 'Mobilité / PMR') {
    return '${g['needs']} ${(g['seats'] as List? ?? []).map((s) => s['need']).join(' ')}'
        .replaceAll('null', '')
        .trim()
        .isNotEmpty;
  }
  if (filter.startsWith('Repas : ')) {
    return '${g['meal']}' == filter.substring(8) ||
        (g['seats'] as List? ?? []).any(
          (s) => s['meal'] == filter.substring(8),
        );
  }
  if (filter.startsWith('Modèle : ')) {
    return g['requestedType'] == filter.substring(9) ||
        [...(g['alloc'] as List), ...(g['standAlloc'] as List? ?? [])].any(
          (a) => tables(p).any(
            (t) => t['id'] == a['table'] && t['type'] == filter.substring(9),
          ),
        );
  }
  return true;
}

void swapReservationAssignments(Json p, String left, String right) {
  requireEditable(p);
  final a = rows(p, 'groups').firstWhere((g) => g['id'] == left),
      b = rows(p, 'groups').firstWhere((g) => g['id'] == right);
  if (left == right ||
      a['waiting'] == true ||
      b['waiting'] == true ||
      a['locked'] == true ||
      b['locked'] == true ||
      [
        ...(a['seats'] as List? ?? []),
        ...(b['seats'] as List? ?? []),
      ].any((s) => s['fixed'] == true)) {
    throw const FormatException(
      'Déverrouiller les attributions et utiliser deux réservations confirmées distinctes.',
    );
  }
  if (isStandBooking(a) != isStandBooking(b) ||
      isStandBooking(a) && a['standUnit'] != b['standUnit'] ||
      (reservationRequested(a) - reservationRequested(b)).abs() > .000001 ||
      (reservationAssigned(a) - reservationAssigned(b)).abs() > .000001) {
    throw const FormatException(
      'Échange disponible entre demandes et quantités attribuées équivalentes.',
    );
  }
  final draft = clone(p),
      x = rows(draft, 'groups').firstWhere((g) => g['id'] == left),
      y = rows(draft, 'groups').firstWhere((g) => g['id'] == right);
  for (final key in ['alloc', 'standAlloc']) {
    final old = x[key];
    x[key] = y[key] ?? <Json>[];
    y[key] = old ?? <Json>[];
  }
  final oldSeatsX = (x['seats'] as List? ?? [])
      .map((s) => Map<String, dynamic>.from(s))
      .toList();
  final oldSeatsY = (y['seats'] as List? ?? [])
      .map((s) => Map<String, dynamic>.from(s))
      .toList();
  for (final pair in [(x, oldSeatsY), (y, oldSeatsX)]) {
    final g = pair.$1;
    g['reserved'] = '';
    final seats = (g['seats'] as List? ?? []).cast<Json>();
    for (var n = 0; n < seats.length; n++) {
      final seat = seats[n];
      seat.remove('table');
      seat.remove('slot');
      if (n < pair.$2.length && pair.$2[n]['table'] != null) {
        seat['table'] = pair.$2[n]['table'];
        seat['slot'] = pair.$2[n]['slot'];
      }
    }
    if (pair.$2.any((s) => s['table'] != null) &&
        seats.length != pair.$2.length) {
      throw const FormatException(
        'Les listes de places numérotées doivent avoir la même taille pour un échange.',
      );
    }
  }
  validateProject(draft);
  for (final t in tables(draft)) {
    if (occupancy(draft, t['id']) > effectiveCapacity(draft, t)) {
      throw const FormatException('Capacité insuffisante après échange.');
    }
  }
  p.clear();
  p.addAll(draft);
}
