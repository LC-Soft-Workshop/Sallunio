part of 'domain.dart';

const assignmentModes = ['Places assises', 'Exposants / stands'];
const standUnits = ['Tables', 'Mètres linéaires'];
const furnitureUses = ['Places assises', 'Stand / exposition', 'Service'];
const audienceLayouts = [
  'Rangées droites',
  'Éventail à trois blocs',
  'Arc de cercle partiel',
];
String eventAssignmentMode(Json p) =>
    p['assignmentMode'] ??
    (['Marché de Noël', 'Brocante'].contains(eventActivity(p))
        ? assignmentModes[1]
        : assignmentModes.first);
String furnitureUse(Json t) =>
    t['capacity'] == 0 ? 'Service' : t['usage'] ?? 'Places assises';
bool isSeatingFurniture(Json t) =>
    ['table', 'chair', 'bench', 'pmr'].contains(t['kind']);
bool isStandBooking(Json g) => g['bookingKind'] == assignmentModes[1];
bool freeSeating(Json p) => p['seatingAssignment'] == 'Libre';
int childChairStock(Json p) => rows(p, 'types')
    .where((t) => t['shape'] == 'chaise enfant' && t['enabled'] == true)
    .fold<int>(
      0,
      (sum, t) => sum + min(t['quantity'] as int, t['limit'] as int),
    );

int reservedChildChairs(Json p, {String? exceptId}) => rows(p, 'groups')
    .where((g) => g['waiting'] != true && g['id'] != exceptId)
    .fold<int>(0, (sum, g) => sum + (g['childChairs'] as int? ?? 0));

String? childChairReservationError(Json p, Json g) {
  final count = g['childChairs'] ?? 0;
  if (count is! int || count < 0 || count > (g['count'] as int)) {
    return 'Le nombre de chaises enfant doit être compris entre 0 et le nombre de personnes.';
  }
  final available = max(
    0,
    childChairStock(p) - reservedChildChairs(p, exceptId: g['id']),
  );
  if (g['waiting'] != true && count > available) {
    return 'Chaises enfant : $available encore disponible(s) dans le stock autorisé.';
  }
  return null;
}

int autonomousCapacity(Json p, Json t) {
  if (furnitureUse(t) != 'Places assises') return 0;
  final count = t['kind'] == 'bench'
      ? (max(number(t['w']), number(t['h'])) /
                number(eventComfort(p)['benchSeatWidth'], .55))
            .floor()
      : 1;
  return max(0, count);
}

double standLength(Json t) => max(number(t['w']), number(t['h']));
// Rotation never changes a model; individual dimension changes do.
String standTypeKey(Json t) {
  final a = number(t['w']), b = number(t['h']);
  return "${t['type'] ?? ''}:${t['shape'] ?? 'rectangle'}:${max(a, b).toStringAsFixed(6)}:${min(a, b).toStringAsFixed(6)}";
}

bool mixedStandTypesAllowed(Json p) => p['allowMixedStandTypes'] == true;
int compareStandModels(Json a, Json b) =>
    standTypeKey(a).compareTo(standTypeKey(b));

List<Json> standPortions(Json p, String tableId) => [
  for (final g in rows(p, 'groups'))
    for (final a in (g['standAlloc'] as List? ?? []).cast<Json>())
      if (a['table'] == tableId)
        {
          ...a,
          'group': g['id'],
          'name': g['name'],
          'color': exhibitorColor(p, g),
        },
]..sort((a, b) => number(a['offset']).compareTo(number(b['offset'])));
int exhibitorColor(Json p, Json group) {
  const palette = [
    0xff80cbc4,
    0xffffcc80,
    0xff90caf9,
    0xffce93d8,
    0xffa5d6a7,
    0xffef9a9a,
    0xfffff176,
    0xffb0bec5,
  ];
  return palette[max(
        0,
        rows(p, 'groups').indexWhere((g) => g['id'] == group['id']),
      ) %
      palette.length];
}

List<(double, double)> availableStandIntervals(Json p, Json t) {
  var cursor = 0.0;
  final result = <(double, double)>[];
  for (final a in standPortions(p, t['id'])) {
    final start = number(a['offset']), end = start + number(a['length']);
    if (start > cursor + .000001) result.add((cursor, start - cursor));
    cursor = max(cursor, end);
  }
  if (cursor < standLength(t) - .000001) {
    result.add((cursor, standLength(t) - cursor));
  }
  return result;
}

void setStandPortion(
  Json p,
  Json group,
  Json table, {
  double offset = 0,
  double? length,
  bool whole = false,
}) {
  final size = length ?? standLength(table);
  if (!isStandBooking(group) ||
      furnitureUse(table) != furnitureUses[1] ||
      !offset.isFinite ||
      !size.isFinite ||
      size <= 0 ||
      offset < 0 ||
      offset + size > standLength(table) + .000001 ||
      table['shape'] == 'cercle' &&
          (!whole || offset != 0 || size != standLength(table))) {
    throw const FormatException('Attribution incompatible avec ce stand.');
  }
  if (!mixedStandTypesAllowed(p)) {
    final ids = (group['standAlloc'] as List? ?? [])
        .map((a) => a['table'])
        .toSet();
    if (tables(p)
        .where((t) => ids.contains(t['id']))
        .any((t) => standTypeKey(t) != standTypeKey(table))) {
      throw const FormatException(
        'Ce stand doit utiliser des tables du même modèle et des mêmes dimensions. La mixité des tables peut être autorisée dans les réglages d’attribution de l’événement.',
      );
    }
  }
  final existing = standPortions(p, table['id']);
  if (existing.any(
    (a) =>
        offset < number(a['offset']) + number(a['length']) - .000001 &&
            offset + size > number(a['offset']) + .000001 ||
        whole ||
        a['whole'] == true,
  )) {
    throw const FormatException('Cette portion est déjà attribuée.');
  }
  group['standAlloc'] ??= <Json>[];
  (group['standAlloc'] as List).add({
    'id': uid(),
    'table': table['id'],
    'offset': offset,
    'length': size,
    'whole': whole,
  });
}

Json standSummary(Json p) {
  var requestedTables = 0,
      assignedTables = 0,
      requestedMetres = 0.0,
      assignedMetres = 0.0;
  for (final g in rows(
    p,
    'groups',
  ).where((g) => isStandBooking(g) && g['waiting'] != true)) {
    final alloc = (g['standAlloc'] as List? ?? []).cast<Json>();
    if ((g['standUnit'] ?? 'Tables') == 'Tables') {
      requestedTables += (g['requestedTables'] as int? ?? 1);
      assignedTables += alloc.length;
    } else {
      requestedMetres += number(g['requestedMetres']);
      assignedMetres += alloc.fold<double>(
        0,
        (s, a) => s + number(a['length']),
      );
    }
  }
  return {
    'requestedTables': requestedTables,
    'assignedTables': assignedTables,
    'requestedMetres': requestedMetres,
    'assignedMetres': assignedMetres,
  };
}

bool standAllocationIsContiguous(Json p, Json group) {
  final parts = (group['standAlloc'] as List? ?? []).cast<Json>();
  if (parts.length < 2) return true;
  final byId = {for (final t in tables(p)) t['id']: t};
  bool connects(Json a, Json b) {
    if (a['table'] == b['table']) {
      return (number(a['offset']) + number(a['length']) - number(b['offset']))
              .abs() <
          .000001;
    }
    final ta = byId[a['table']], tb = byId[b['table']];
    return ta != null &&
        tb != null &&
        (number(a['offset']) + number(a['length']) - standLength(ta)).abs() <
            .000001 &&
        number(b['offset']).abs() < .000001 &&
        standContinues(ta, tb);
  }

  final reached = <int>{0}, pending = <int>[0];
  while (pending.isNotEmpty) {
    final i = pending.removeLast();
    for (var n = 0; n < parts.length; n++) {
      if (!reached.contains(n) &&
          (connects(parts[i], parts[n]) || connects(parts[n], parts[i]))) {
        reached.add(n);
        pending.add(n);
      }
    }
  }
  return reached.length == parts.length;
}

List<String> standAllocationWarnings(Json p) {
  final result = <String>[];
  final stands = tables(p)
      .where((t) => furnitureUse(t) == furnitureUses[1])
      .toList();
  for (final g in rows(
    p,
    'groups',
  ).where((g) => isStandBooking(g) && g['waiting'] != true)) {
    final metres = (g['standUnit'] ?? 'Tables') != 'Tables';
    final allocations = (g['standAlloc'] as List? ?? []).cast<Json>();
    final assigned = metres
        ? allocations.fold<double>(0, (sum, a) => sum + number(a['length']))
        : allocations.length.toDouble();
    final requested = metres
        ? number(g['requestedMetres'])
        : number(g['requestedTables'], 1);
    if (metres && !standAllocationIsContiguous(p, g)) {
      result.add(
        '${g['name']} : les mètres linéaires sont répartis sur des portions non contiguës. Réattribuer le stand sur une suite de tables sans allée ni portion occupée entre elles.',
      );
    }
    if (!mixedStandTypesAllowed(p)) {
      final ids = allocations.map((a) => a['table']).toSet();
      if (stands
              .where((t) => ids.contains(t['id']))
              .map(standTypeKey)
              .toSet()
              .length >
          1) {
        result.add(
          "${g['name']} : plusieurs modèles de tables sont attribués alors que la mixité est désactivée. L’attribution existante est conservée ; réattribuer le stand ou autoriser la mixité.",
        );
      }
    }
    if (assigned + .000001 >= requested) continue;
    String reason;
    final matching = stands
        .where(
          (t) =>
              g['requestedType'] == null ||
              g['requestedType'] == '' ||
              g['requestedType'] == t['type'],
        )
        .toList();
    if (stands.isEmpty) {
      reason = 'Aucune table du plan n’a l’usage Stand / exposition. Modifier l’usage des tables destinées aux exposants dans leurs propriétés ou par sélection multiple.';
    } else if (matching.isEmpty) {
      reason = 'Aucune table de stand ne correspond au modèle demandé.';
    } else if (matching.every(
      (t) =>
          tableOutsideRoom(p, t) ||
          rows(
            p,
            'items',
          ).where((b) => b['id'] != t['id']).any((b) => overlaps(t, b)),
    )) {
      reason = 'Les tables de stand correspondantes sont hors salle ou en chevauchement.';
    } else if (g['locked'] == true) {
      reason = 'L’attribution de ce stand est verrouillée.';
    } else {
      reason = metres
          ? 'Longueur continue de stand disponible insuffisante (tables du même modèle si la mixité est désactivée) ou incompatible avec le partage demandé. Les mètres ne sont pas répartis entre des tables séparées par une allée. Vérifier les attributions existantes et les tables rondes (tables entières uniquement).'
          : 'Nombre de tables libres insuffisant dans un même modèle. Regrouper les tables du modèle demandé ou autoriser la mixité dans les réglages d’attribution de l’événement.';
    }
    result.add(
      '${g['name']} : ${(requested - assigned).toStringAsFixed(metres ? 2 : 0)} ${metres ? 'm' : 'table(s)'} restant(s). $reason',
    );
  }
  return result;
}

// Adjacent frontage may have different depths; only the linear edge counts.
bool standContinues(Json a, Json b) {
  if (number(a['angle']) % 360 != 0 || number(b['angle']) % 360 != 0) {
    Point<double> direction(Json t) {
      final angle =
          (number(t['angle']) + (number(t['w']) >= number(t['h']) ? 0 : 90)) *
          pi /
          180;
      return Point(cos(angle), sin(angle));
    }

    final u = direction(a), v = direction(b);
    if (u.x * v.x + u.y * v.y < .999999) return false;
    final aa = furnitureCorners(a), bb = furnitureCorners(b);
    double along(Point<double> p) => p.x * u.x + p.y * u.y;
    double across(Point<double> p) => -p.x * u.y + p.y * u.x;
    return (aa.map(along).reduce(max) - bb.map(along).reduce(min)).abs() <=
            .01 &&
        min(aa.map(across).reduce(max), bb.map(across).reduce(max)) -
                max(aa.map(across).reduce(min), bb.map(across).reduce(min)) >
            .01;
  }

  final horizontal = number(a['w']) >= number(a['h']);
  if (horizontal != (number(b['w']) >= number(b['h']))) return false;
  final axis = horizontal ? 'x' : 'y', length = horizontal ? 'w' : 'h';
  final cross = horizontal ? 'y' : 'x', depth = horizontal ? 'h' : 'w';
  return (number(a[axis]) + number(a[length]) - number(b[axis])).abs() <= .01 &&
      min(
                number(a[cross]) + number(a[depth]),
                number(b[cross]) + number(b[depth]),
              ) -
              max(number(a[cross]), number(b[cross])) >
          .01;
}

List<(Json, double, double)> contiguousStandPortions(
  Json p,
  Json g,
  List<Json> candidates,
  double requested,
) {
  final share = g['shareTable'] != 'Non';
  final nodes = <(Json, double, double)>[
    for (final table in candidates.where((t) => t['shape'] != 'cercle'))
      if (share) ...[
        for (final interval in availableStandIntervals(p, table))
          (table, interval.$1, interval.$2),
      ] else if (standPortions(p, table['id']).isEmpty)
        (table, 0.0, standLength(table)),
  ];
  List<(Json, double, double)> best = [];
  double lengthOf(List<(Json, double, double)> path) =>
      path.fold(0.0, (v, n) => v + n.$3);
  List<(Json, double, double)>? visit(
    (Json, double, double) node,
    double left,
    List<(Json, double, double)> prefix,
  ) {
    final used = share ? min(left, node.$3) : node.$3;
    final path = [...prefix, (node.$1, node.$2, used)];
    if (lengthOf(path) > lengthOf(best)) best = path;
    if (used >= left - .000001) return path;
    if ((node.$2 + node.$3 - standLength(node.$1)).abs() > .000001) return null;
    for (final next in nodes) {
      if (next.$2 > .000001 ||
          path.any((n) => n.$1['id'] == next.$1['id']) ||
          (!mixedStandTypesAllowed(p) &&
              standTypeKey(node.$1) != standTypeKey(next.$1)) ||
          !standContinues(node.$1, next.$1)) {
        continue;
      }
      final result = visit(next, left - used, path);
      if (result != null) return result;
    }
    return null;
  }

  for (final node in nodes) {
    final complete = visit(node, requested, []);
    if (complete != null) return complete;
  }
  return best;
}

void allocateStands(Json p) {
  final gs = rows(
    p,
    'groups',
  ).where((g) => isStandBooking(g) && g['waiting'] != true).toList();
  for (final g in gs.where((g) => g['locked'] != true)) {
    g['standAlloc'] = <Json>[];
  }
  for (final g in gs.where((g) => g['locked'] != true)) {
    final candidates = tables(p)
        .where(
          (t) =>
              furnitureUse(t) == furnitureUses[1] &&
              !tableOutsideRoom(p, t) &&
              !rows(
                p,
                'items',
              ).where((b) => b['id'] != t['id']).any((b) => overlaps(t, b)) &&
              (g['requestedType'] == null ||
                  g['requestedType'] == '' ||
                  g['requestedType'] == t['type']),
        )
        .toList();
    candidates.sort((a, b) {
      final score = preferenceScore(
        p,
        g,
        a,
      ).compareTo(preferenceScore(p, g, b));
      if (score != 0) return score;
      final row = number(a['y']).compareTo(number(b['y']));
      return row == 0 ? number(a['x']).compareTo(number(b['x'])) : row;
    });
    var remaining = (g['standUnit'] ?? 'Tables') == 'Tables'
        ? number(g['requestedTables'], 1)
        : number(g['requestedMetres']);
    final metres = (g['standUnit'] ?? 'Tables') != 'Tables';
    if (metres) {
      for (final part in contiguousStandPortions(p, g, candidates, remaining)) {
        setStandPortion(
          p,
          g,
          part.$1,
          offset: part.$2,
          length: part.$3,
          whole: g['shareTable'] == 'Non',
        );
      }
      continue;
    }
    var wholeCandidates = candidates;
    if (!mixedStandTypesAllowed(p)) {
      final models = <String, List<Json>>{};
      for (final t in candidates.where(
        (t) => standPortions(p, t['id']).isEmpty,
      )) {
        models.putIfAbsent(standTypeKey(t), () => []).add(t);
      }
      wholeCandidates = [];
      for (final model in models.values) {
        if (model.length >= remaining) {
          wholeCandidates = model;
          break;
        }
        if (model.length > wholeCandidates.length) wholeCandidates = model;
      }
    }
    for (final t in wholeCandidates) {
      if (remaining <= .000001) break;
      final share =
          metres && g['shareTable'] != 'Non' && t['shape'] != 'cercle';
      if (!share) {
        if (standPortions(p, t['id']).isNotEmpty ||
            metres && t['shape'] == 'cercle') {
          continue;
        }
        setStandPortion(p, g, t, whole: true);
        remaining -= metres ? standLength(t) : 1;
      } else {
        for (final interval in availableStandIntervals(p, t)) {
          if (remaining <= .000001) break;
          final n = min(interval.$2, remaining);
          setStandPortion(p, g, t, offset: interval.$1, length: n);
          remaining -= n;
        }
      }
    }
  }
}

void changeFurnitureUsage(Json p, Set<String> ids, String usage) {
  if (!furnitureUses.contains(usage)) {
    throw const FormatException('Usage inconnu');
  }
  for (final t in tables(p).where((t) => ids.contains(t['id']))) {
    if (t['kind'] != 'table' && usage == furnitureUses[1]) {
      throw const FormatException('Un stand nécessite une table.');
    }
  }
  for (final t in tables(p).where((t) => ids.contains(t['id']))) {
    if (furnitureUse(t) == usage) continue;
    t['usage'] = usage;
    for (final g in rows(p, 'groups')) {
      (g['alloc'] as List).removeWhere((a) => a['table'] == t['id']);
      (g['standAlloc'] as List?)?.removeWhere((a) => a['table'] == t['id']);
      for (final seat in (g['seats'] as List? ?? [])) {
        if (seat['table'] == t['id']) {
          seat.remove('table');
          seat.remove('slot');
        }
      }
    }
  }
}

List<Point<double>> furnitureCorners(Json t, [double padding = 0]) {
  final angle = number(t['angle']) * pi / 180;
  final cx = number(t['x']) + number(t['w']) / 2,
      cy = number(t['y']) + number(t['h']) / 2;
  final w = number(t['w']) / 2 + padding, h = number(t['h']) / 2 + padding;
  return [
    for (final v in [Point(-w, -h), Point(w, -h), Point(w, h), Point(-w, h)])
      Point(
        cx + v.x * cos(angle) - v.y * sin(angle),
        cy + v.x * sin(angle) + v.y * cos(angle),
      ),
  ];
}

bool rotatedOverlap(Json a, Json b, [double padding = 0]) {
  if (isPlanAnnotation(a) || isPlanAnnotation(b)) return false;
  final aa = furnitureCorners(a, padding), bb = furnitureCorners(b);
  for (final polygon in [aa, bb]) {
    for (var i = 0; i < 4; i++) {
      final edge = polygon[(i + 1) % 4] - polygon[i],
          axis = Point(-edge.y, edge.x);
      final ap = aa.map((v) => v.x * axis.x + v.y * axis.y),
          bp = bb.map((v) => v.x * axis.x + v.y * axis.y);
      if (ap.reduce(max) <= bp.reduce(min) + .000001 ||
          bp.reduce(max) <= ap.reduce(min) + .000001) {
        return false;
      }
    }
  }
  return true;
}

bool audienceFits(Json p, Json t, List<Json> others) {
  final corners = furnitureCorners(t);
  final wall = number(eventComfort(p)['wallGap']);
  final room = p['room'] as Json;
  if (corners.any(
    (v) =>
        v.x < wall - .000001 ||
        v.y < wall - .000001 ||
        v.x > number(room['width']) - wall + .000001 ||
        v.y > number(room['height']) - wall + .000001,
  )) {
    return false;
  }
  if (!polygonFits({
    ...t,
    'x': corners.map((v) => v.x).reduce(min),
    'y': corners.map((v) => v.y).reduce(min),
    'w':
        corners.map((v) => v.x).reduce(max) -
        corners.map((v) => v.x).reduce(min),
    'h':
        corners.map((v) => v.y).reduce(max) -
        corners.map((v) => v.y).reduce(min),
  }, room)) {
    return false;
  }
  return !others
      .where((b) => b['id'] != t['id'])
      .any((b) => rotatedOverlap(t, b));
}

/// Positions only furniture. Reservation proximity is applied by allocation.
int arrangeAudience(Json p, Json settings) {
  final scene = rows(
    p,
    'items',
  ).where((t) => t['id'] == settings['scene']).firstOrNull;
  if (scene == null || scene['kind'] != 'zone') {
    throw const FormatException('Choisir une zone scène.');
  }
  final comfort = eventComfort(p), room = p['room'] as Json;
  final targets = tables(p)
      .where(
        (t) =>
            ['chair', 'bench', 'pmr'].contains(t['kind']) &&
            t['fixed'] != true &&
            furnitureUse(t) == furnitureUses.first,
      )
      .toList();
  final placed = physicalPlanItems(p)
      .where((t) => !targets.contains(t))
      .toList();
  final gap = number(comfort['chairGap'], .1),
      rowGap = number(comfort['rowGap'], .8);
  final aisle = eventCirculation(p), wall = number(comfort['wallGap']);
  final side = settings['side'] ?? 'Bas';
  final center = Point(
    number(scene['x']) + number(scene['w']) / 2,
    number(scene['y']) + number(scene['h']) / 2,
  );
  final direction = switch (side) {
    'Haut' => -pi / 2,
    'Gauche' => pi,
    'Droite' => 0,
    _ => pi / 2,
  };
  final vertical = side == 'Haut' || side == 'Bas';
  final usable =
      (vertical ? number(room['width']) : number(room['height'])) - 2 * wall;
  final maxDepth = targets.isEmpty
      ? .5
      : targets.map((t) => number(t['h'])).reduce(max);
  final first =
      number(comfort['sceneGap'], 1.5) +
      (vertical ? number(scene['h']) : number(scene['w'])) / 2 +
      maxDepth / 2;
  final limit = (vertical ? number(room['height']) : number(room['width']));
  final maxRows = max(1, (limit / (maxDepth + rowGap)).ceil());
  final maxWidth = targets.isEmpty
      ? .5
      : targets.map((t) => number(t['w'])).reduce(max);
  var outside = 0, row = 0, cursor = -usable / 2;
  final arc = settings['layout'] == audienceLayouts[2];
  final fan = settings['layout'] == audienceLayouts[1];
  final fanAngle =
      max(
        number(settings['leftAngle'], 45),
        number(settings['rightAngle'], 45),
      ) *
      pi /
      180;
  var angular = -number(settings['opening'], 90) * pi / 360;
  targets.sort((a, b) {
    final accessibility = (b['kind'] == 'pmr' ? 1 : 0).compareTo(
      a['kind'] == 'pmr' ? 1 : 0,
    );
    return accessibility != 0 ? accessibility : compareFurnitureNumbers(a, b);
  });
  for (final t in targets) {
    final savedCursor = cursor;
    if (t['kind'] == 'pmr' && !arc) cursor = -aisle / 2 - number(t['w']) - gap;
    final width = number(t['w']);
    var found = false;
    while (row < maxRows) {
      var radius =
          first + row * (maxDepth + rowGap) / (fan ? cos(fanAngle) : 1);
      double along, bearing;
      if (arc) {
        final step = 2 * asin(((width + gap) / (2 * radius)).clamp(0.0, .95));
        final half = number(settings['opening'], 90) * pi / 360;
        if (angular + step > half) {
          row++;
          angular = -half;
          continue;
        }
        final deviation = angular + step / 2;
        bearing = direction - deviation;
        along = 0;
        angular += step;
        // Central main aisle: no chair in the reserved angular interval.
        if ((deviation * radius).abs() < aisle / 2 + width / 2) continue;
      } else {
        if (cursor + width > usable / 2) {
          row++;
          cursor = -usable / 2;
          continue;
        }
        along = cursor + width / 2;
        final tilt = fan
            ? along < -usable / 6
                  ? -number(settings['leftAngle'], 45) * pi / 180
                  : along > usable / 6
                  ? number(settings['rightAngle'], 45) * pi / 180
                  : 0.0
            : 0.0;
        bearing = direction + tilt;
        cursor += max(width, maxWidth) + gap;
        if (fan
            ? (along.abs() - usable / 6).abs() < aisle / 2 + width / 2
            : along.abs() < aisle / 2 + width / 2) {
          continue;
        }
        if (fan) radius -= max(0, along.abs() - usable / 6) * tan(tilt.abs());
      }
      final cx = arc
          ? center.x + radius * cos(bearing)
          : center.x + radius * cos(direction) - along * sin(direction);
      final cy = arc
          ? center.y + radius * sin(bearing)
          : center.y + radius * sin(direction) + along * cos(direction);
      final proposal = {
        ...t,
        'x': cx - width / 2,
        'y': cy - number(t['h']) / 2,
        'angle': bearing * 180 / pi - 90,
        'audienceLayout': true,
      };
      if (fan && !fanStageClearanceFits(p, proposal, scene, settings)) continue;
      if (audienceFits(p, proposal, placed) &&
          !placed
              .where(isSeatingFurniture)
              .any((other) => rotatedOverlap(proposal, other, gap / 2))) {
        t.addAll(proposal);
        t.remove('unplacedByArrangement');
        placed.add(t);
        found = true;
        if (t['kind'] == 'pmr' && !arc) cursor = savedCursor;
        break;
      }
    }
    if (!found) {
      t['x'] = number(room['width']) + aisle + outside % 5 * (maxWidth + gap);
      t['y'] = (outside ~/ 5) * (maxDepth + rowGap);
      t['unplacedByArrangement'] = true;
      outside++;
    }
  }
  p['audienceSettings'] = {...settings};
  return outside;
}

void validateMixedFurniture(Json p) {
  if (p['allowMixedStandTypes'] != null && p['allowMixedStandTypes'] is! bool) {
    throw const FormatException('Réglage de mixité des tables invalide.');
  }
  if (p['audienceSettings'] != null) {
    final a = p['audienceSettings'];
    if (a is! Map ||
        !audienceLayouts.contains(a['layout']) ||
        !seatingSideNames.contains(a['side']) ||
        !rows(
          p,
          'items',
        ).any((t) => t['id'] == a['scene'] && t['kind'] == 'zone') ||
        ['leftAngle', 'rightAngle'].any(
          (k) =>
              !number(a[k], 45).isFinite ||
              number(a[k], 45) < 0 ||
              number(a[k], 45) > 75,
        ) ||
        !number(a['fanClearanceAngle'], 30).isFinite ||
        number(a['fanClearanceAngle'], 30) < 0 ||
        number(a['fanClearanceAngle'], 30) > 75 ||
        !number(a['opening'], 90).isFinite ||
        number(a['opening'], 90) < 10 ||
        number(a['opening'], 90) > 160) {
      throw const FormatException('Disposition face à la scène invalide');
    }
  }

  if (p['assignmentMode'] != null &&
          !assignmentModes.contains(p['assignmentMode']) ||
      p['standUnit'] != null && !standUnits.contains(p['standUnit']) ||
      p['seatingAssignment'] != null &&
          !['Attribué', 'Libre'].contains(p['seatingAssignment'])) {
    throw const FormatException('Mode d’attribution invalide');
  }
  for (final t in tables(p)) {
    if (!furnitureUses.contains(furnitureUse(t)) ||
        !number(t['angle']).isFinite) {
      throw const FormatException('Usage ou angle invalide');
    }
    final capacity = ['chair', 'bench', 'pmr'].contains(t['kind'])
        ? autonomousCapacity(p, {...t, 'blockedSlots': []})
        : t['capacity'] as int;
    final slots = (t['blockedSlots'] as List? ?? []);
    if (slots.toSet().length != slots.length ||
        slots.any((s) => s is! int || s < 0 || s >= capacity)) {
      throw const FormatException('Place bloquée invalide');
    }
    var end = 0.0;
    for (final a in standPortions(p, t['id'])) {
      final start = number(a['offset'], -1), len = number(a['length'], -1);
      if (furnitureUse(t) != furnitureUses[1] ||
          a['whole'] == true &&
              (start != 0 || (len - standLength(t)).abs() > .000001) ||
          t['shape'] == 'cercle' && a['whole'] != true ||
          !start.isFinite ||
          !len.isFinite ||
          start < end - .000001 ||
          len <= 0 ||
          start + len > standLength(t) + .000001) {
        throw const FormatException('Portions de stand invalides');
      }
      end = start + len;
    }
  }
  final ids = tables(p).map((t) => t['id']).toSet();
  for (final g in rows(p, 'groups')) {
    if (isStandBooking(g)) {
      if (!standUnits.contains(g['standUnit'] ?? 'Tables') ||
          number(g['requestedTables'], 1) <= 0 ||
          !number(g['requestedMetres'], 1).isFinite ||
          number(g['requestedMetres'], 1) <= 0) {
        throw const FormatException('Demande exposant invalide');
      }
      if ((g['standAlloc'] as List? ?? []).any(
        (a) => !ids.contains(a['table']),
      )) {
        throw const FormatException('Stand manquant');
      }
    }
  }
}

void allocateNumberedSeats(Json p) {
  final ts = tables(p)
      .where(
        (t) =>
            furnitureUse(t) == furnitureUses.first &&
            !tableOutsideRoom(p, t) &&
            !rows(
              p,
              'items',
            ).where((b) => b['id'] != t['id']).any((b) => overlaps(t, b)),
      )
      .toList();
  final taken = <String>{};
  final capacities = {
    for (final t in ts) t['id']: PlanGeometry(p, rows(p, 'items')).capacity(t),
  };
  final legacy = {
    for (final g in rows(p, 'groups').where((g) => !isStandBooking(g)))
      g['id']: assignedPeople(p, g),
  };
  for (final g in rows(p, 'groups').where((g) => !isStandBooking(g))) {
    final seats = List.generate(g['count'] as int, (i) => individualSeat(g, i));
    g['seats'] = seats;
    for (final seat in seats) {
      if (g['locked'] == true && seat['table'] == null) {
        final old = legacy[g['id']]![(seat['number'] as int) - 1];
        seat['table'] = old['table']?['id'];
        seat['slot'] = old['slot'];
      }
      final id = seat['table'], slot = seat['slot'];
      final fixed = g['locked'] == true || seat['fixed'] == true;
      if (fixed &&
          capacities.containsKey(id) &&
          slot is int &&
          slot >= 0 &&
          slot < capacities[id]!) {
        taken.add('$id:$slot');
      } else {
        seat.remove('table');
        seat.remove('slot');
      }
    }
    g['alloc'] = <Json>[];
  }
  for (final g in rows(p, 'groups').where((g) => !isStandBooking(g))) {
    final seats = (g['seats'] as List).cast<Json>();
    final order = [...seats]
      ..sort(
        (a, b) => (b['need'] == 'Fauteuil' ? 1 : 0).compareTo(
          a['need'] == 'Fauteuil' ? 1 : 0,
        ),
      );
    for (final seat in order) {
      if (seat['table'] != null || freeSeating(p)) continue;
      final child = (seat['number'] as int) <= (g['childChairs'] as int? ?? 0);
      final candidates = ts
          .where((t) => t['shape'] != 'chaise enfant' || child)
          .where(
            (t) => seat['need'] == 'Fauteuil'
                ? t['kind'] == 'pmr' || adaptedPlaces(t).isNotEmpty
                : t['kind'] != 'pmr',
          )
          .toList();
      final linked = int.tryParse('${seat['companion'] ?? ''}');
      final companion = linked == null
          ? null
          : seats.where((s) => s['number'] == linked).firstOrNull;
      final previous = seats.where((s) => s['table'] != null).lastOrNull;
      final target = ts
          .where((t) => t['id'] == (companion?['table'] ?? previous?['table']))
          .firstOrNull;
      candidates.sort(
        (a, b) =>
            (preferenceScore(p, g, a) +
                    (target == null
                        ? 0
                        : tableDistance(a, target) *
                              (companion == null ? 1 : 10)))
                .compareTo(
                  preferenceScore(p, g, b) +
                      (target == null
                          ? 0
                          : tableDistance(b, target) *
                                (companion == null ? 1 : 10)),
                ),
      );

      for (final t in candidates) {
        final n = capacities[t['id']]!;
        final blocked = (t['blockedSlots'] as List? ?? []).cast<int>();
        // Blocked places retain their numbers; they are skipped, never renumbered.
        final physical = n;
        int? slot;
        for (var i = 0; i < physical; i++) {
          if (!blocked.contains(i) && !taken.contains('${t['id']}:$i')) {
            slot = i;
            break;
          }
        }
        if (slot == null) continue;
        seat['table'] = t['id'];
        seat['slot'] = slot;
        taken.add('${t['id']}:$slot');
        break;
      }
    }
    final counts = <String, int>{};
    for (final seat in seats) {
      if (seat['table'] != null) {
        counts[seat['table']] = (counts[seat['table']] ?? 0) + 1;
      }
    }
    g['alloc'] = [
      for (final e in counts.entries) {'table': e.key, 'count': e.value},
    ];
  }
}

String standAllocationText(Json p, Json g) => (g['standAlloc'] as List? ?? [])
    .map((a) {
      final t = tables(p).where((t) => t['id'] == a['table']).firstOrNull;
      return '${t?['label'] ?? 'Table absente'} : ${a['whole'] == true && g['standUnit'] != 'Mètres linéaires' ? 'table entière' : '${number(a['length']).toStringAsFixed(2)} m'}';
    })
    .join(', ');
String furnitureShortLabel(Json t) {
  final label = '${t['label']}';
  final match = t['kind'] == 'chair'
      ? RegExp(r'^Chaise\s*(\d+)$', caseSensitive: false).firstMatch(label)
      : null;
  return match == null ? label : 'C${match.group(1)}';
}

String furniturePlanLabel(Json p, Json t) {
  if (t['kind'] == 'chair') return furnitureShortLabel(t);
  if (furnitureUse(t) == furnitureUses[1]) {
    final names = standPortions(p, t['id']).map((a) => a['name']).toSet();
    return '${t['label']}\n${names.isEmpty ? 'Stand libre' : names.join(' / ')}';
  }
  if (furnitureUse(t) == 'Service') return '${t['label']}\nService';
  return '${t['label']}\n${occupancy(p, t['id'])}/${effectiveCapacity(p, t)}${unplacedTable(p, t) ? '\nNon placée' : ''}';
}

String standSummaryLabel(Json p) {
  final s = standSummary(p);
  return 'Stands : ${s['assignedTables']}/${s['requestedTables']} tables attribuées • ${number(s['assignedMetres']).toStringAsFixed(2)}/${number(s['requestedMetres']).toStringAsFixed(2)} m livrés.';
}

int usableSeatCapacity(Json p, Json t) =>
    max(0, effectiveCapacity(p, t) - (t['blockedSlots'] as List? ?? []).length);

void rebuildSeatAllocations(Json p) {
  for (final g in rows(p, 'groups').where((g) => !isStandBooking(g))) {
    final counts = <String, int>{};
    for (final seat in (g['seats'] as List? ?? [])) {
      if (seat['table'] != null) {
        counts[seat['table']] = (counts[seat['table']] ?? 0) + 1;
      }
    }
    g['alloc'] = [
      for (final e in counts.entries) {'table': e.key, 'count': e.value},
    ];
  }
}

void setSeatingAssignment(Json p, String mode) {
  if (!['Libre', 'Attribué'].contains(mode)) {
    throw const FormatException('Placement invalide');
  }
  if (mode == 'Libre' && !freeSeating(p)) {
    for (final g in rows(
      p,
      'groups',
    ).where((g) => !isStandBooking(g) && g['locked'] != true)) {
      for (final seat in (g['seats'] as List? ?? [])) {
        if (seat['fixed'] != true) {
          seat.remove('table');
          seat.remove('slot');
        }
      }
      g['alloc'] = <Json>[];
    }
    final locked = {
      for (final g in rows(p, 'groups').where((g) => g['locked'] == true))
        g['id']: g['alloc'],
    };
    rebuildSeatAllocations(p);
    for (final g in rows(
      p,
      'groups',
    ).where((g) => locked.containsKey(g['id']))) {
      g['alloc'] = locked[g['id']];
    }
  }
  p['seatingAssignment'] = mode;
}

Point<double> rotatedLocalPoint(Json t, Point<double> point) {
  final angle = number(t['angle']) * pi / 180,
      cx = number(t['w']) / 2,
      cy = number(t['h']) / 2;
  return Point(
    cx + (point.x - cx) * cos(angle) - (point.y - cy) * sin(angle),
    cy + (point.x - cx) * sin(angle) + (point.y - cy) * cos(angle),
  );
}

/// The central block keeps sceneGap; diagonal blocks leave the stage corners clear.
bool fanStageClearanceFits(Json p, Json item, Json scene, Json settings) {
  final direction = switch (settings['side']) {
    'Haut' => -pi / 2,
    'Gauche' => pi,
    'Droite' => 0.0,
    _ => pi / 2,
  };
  final vertical =
      settings['side'] == 'Haut' || (settings['side'] ?? 'Bas') == 'Bas';
  final center = Point(
    number(scene['x']) + number(scene['w']) / 2,
    number(scene['y']) + number(scene['h']) / 2,
  );
  final depth = (vertical ? number(scene['h']) : number(scene['w'])) / 2;
  final halfFront = (vertical ? number(scene['w']) : number(scene['h'])) / 2;
  final comfort = eventComfort(p);
  final delta =
      ((number(item['angle']) + 90 - direction * 180 / pi + 180) % 360) - 180;
  final tilted = delta.abs() > .000001;
  final extra = tilted ? number(comfort['fanSideGap'], 1) : 0.0;
  final slope = tilted
      ? tan(number(settings['fanClearanceAngle'], 30) * pi / 180)
      : 0.0;
  return furnitureCorners(item).every((point) {
    final x = point.x - center.x, y = point.y - center.y;
    final forward = x * cos(direction) + y * sin(direction),
        lateral = -x * sin(direction) + y * cos(direction);
    final required =
        depth +
        number(comfort['sceneGap'], 1.5) +
        extra +
        max(0, lateral.abs() - halfFront) * slope;
    return forward >= required - .000001;
  });
}

String furnitureTooltip(Json p, Json t, [PlanGeometry? geometry]) {
  final type = rows(p, 'types').where((v) => v['id'] == t['type']).firstOrNull;
  final kind = switch (t['kind']) {
    'chair' => t['shape'] == 'chaise enfant' ? 'Chaise enfant' : 'Chaise',
    'bench' => 'Banc',
    'pmr' => 'Emplacement PMR',
    'table' => 'Table',
    _ => objectLabels[t['kind']] ?? 'Objet',
  };
  final lines = <String>[
    '$kind : ${furnitureShortLabel(t)}',
    if (type != null) 'Modèle de mobilier : ${type['name']}',
    'Dimensions : ${number(t['w']).toStringAsFixed(2)} × ${number(t['h']).toStringAsFixed(2)} m',
    'Position : X ${number(t['x']).toStringAsFixed(2)} m ; Y ${number(t['y']).toStringAsFixed(2)} m',
    if (t['fixed'] == true) 'Position fixée',
    if (unplacedTable(p, t)) 'Hors salle — non placé',
  ];
  if (isSeatingFurniture(t)) {
    lines.add('Usage : ${furnitureUse(t)}');
    if (furnitureUse(t) == furnitureUses[1]) {
      final portions = standPortions(p, t['id']);
      lines.add(
        portions.isEmpty
            ? 'Stand libre'
            : portions
                  .map(
                    (a) =>
                        'Réservé à ${a['name']} : ${number(a['length']).toStringAsFixed(2)} m',
                  )
                  .join('\n'),
      );
    } else if (furnitureUse(t) == furnitureUses.first) {
      final people = tablePeople(p, t, geometry);
      final blocked = Set<int>.from(t['blockedSlots'] as List? ?? []);
      lines.add(
        '${occupancy(p, t['id'])} attribuée(s) / ${max(0, people.length - blocked.length)} place(s) utilisable(s)',
      );
      for (var n = 0; n < people.length; n++) {
        final person = people[n];
        if (blocked.contains(n)) {
          lines.add('Place ${n + 1} : bloquée / réservée sans occupant');
          continue;
        }
        if (person == null) {
          lines.add('Place ${n + 1} : libre');
          continue;
        }
        final seat = person['seat'] as Json, group = person['group'] as Json;
        final name = (seat['name'] ?? '').toString().trim();
        lines.add(
          'Place ${n + 1} : réservée à ${name.isEmpty ? group['name'] : '$name — ${group['name']}'}${seat['fixed'] == true || group['locked'] == true ? ' (verrouillée)' : ''}',
        );
        if ((seat['need'] ?? '') != '') lines.add('Mobilité : ${seat['need']}');
        if ((seat['number'] as int) <= (group['childChairs'] as int? ?? 0)) {
          lines.add('Chaise enfant');
        }
        if (mealsEnabled(p)) {
          lines.add('Repas : ${seat['meal']}');
          if ((seat['allergy'] ?? '') != '') {
            lines.add('Allergies : ${seat['allergy']}');
          }
        }
      }
    }
  }
  if ((t['note'] ?? '').toString().trim().isNotEmpty) {
    lines.add('Note : ${t['note']}');
  }
  return lines.join('\n');
}
