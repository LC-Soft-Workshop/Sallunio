import 'dart:convert';
import 'dart:math';

import 'parcours.dart';

part 'mixed_furniture.dart';
part 'organizer_features.dart';

bool isPlanAnnotation(Json item) =>
    ['info', 'text', 'image', 'arrow'].contains(item['kind']);
List<Json> physicalPlanItems(Json p) =>
    rows(p, 'items').where((i) => !isPlanAnnotation(i)).toList();

typedef Json = Map<String, dynamic>;
const zoneColors = <String, int>{
  'Bleu': 0xffbed8e9,
  'Gris': 0xffd7ddda,
  'Vert': 0xffa9d8bf,
  'Orange': 0xffffd9ad,
  'Jaune': 0xfff6dc96,
  'Violet': 0xffd3c3ed,
  'Rose': 0xfff3c4d6,
  'Blanc': 0xffffffff,
};
const zoneFills = [
  'Plein',
  'Hachures',
  'Hachures croisées',
  'Contour seul',
  'Invisible',
];
const joiningModes = ['Aucun', 'Petits côtés', 'Grands côtés', 'Les deux'];
const objectLabels = {
  'obstacle': 'Obstacle',
  'zone': 'Zone',
  'info': 'Espace informatif',
  'text': 'Texte',
  'image': 'Image',
  'arrow': 'Flèche',
  'entry': 'Entrée',
  'exit': 'Sortie',
  'door': 'Porte',
};
const comfortFieldLabels = <String, String>{
  'childChairWidth': 'Largeur proposée des chaises enfant (m)',
  'childChairDepth': 'Profondeur proposée des chaises enfant (m)',
  'benchSeatWidth': 'Largeur par personne sur un banc (m)',
  'chairGap': 'Écart entre les sièges d’une rangée (m)',
  'rowGap': 'Passage libre entre les rangées de sièges (m)',
  'sceneGap': 'Distance libre devant la scène (m)',
  'fanSideGap':
      'Dégagement supplémentaire des blocs inclinés près de la scène (m)',
  'seatWidth': 'Largeur par personne à table (m)',
  'seatDepth': 'Profondeur réservée derrière une assise (m)',
  'pmrSeatWidth': 'Largeur d’une place PMR (m)',
  'pmrDepth': 'Profondeur d’une place PMR (m)',
  'aisleWidth': 'Largeur libre des allées (m)',
  'pmrAisleWidth': 'Largeur libre des allées avec PMR (m)',
  'tableGap': 'Distance entre bords des tables hors jonctions (m)',
  'wallGap': 'Distance table–mur hors appui autorisé (m)',
  'exhibitorGap': 'Espace exposants dos à dos (m)',
  'parcoursWallGap': 'Espace exposant entre table et mur en parcours (m)',
};
Json comfortableDefaults(Json p) {
  final meal = mealsEnabled(p);
  return {
    'childChairWidth': .4,
    'childChairDepth': .4,
    'benchSeatWidth': .55,
    'chairGap': .1,
    'rowGap': .9,
    'sceneGap': 1.5,
    'fanSideGap': 1.0,
    'seatWidth': meal ? .65 : .6,
    'seatDepth': meal ? .6 : .5,
    'pmrSeatWidth': .9,
    'pmrDepth': 1.3,
    'aisleWidth': 1.2,
    'pmrAisleWidth': 1.5,
    'tableGap': meal ? 2.4 : 2.2,
    'wallGap': meal ? 1.8 : 1.7,
    'exhibitorGap': 1.4,
    'parcoursWallGap': .8,
    'preferMainAisles': 'Oui',
  };
}

Json eventComfort(Json p) => {
  'childChairWidth': .4,
  'childChairDepth': .4,
  'benchSeatWidth': .55,
  'chairGap': .1,
  'rowGap': .8,
  'sceneGap': 1.5,
  'fanSideGap': 1.0,
  'seatWidth': .6,
  'seatDepth': .55,
  'pmrSeatWidth': .9,
  'pmrDepth': 1.2,
  'aisleWidth': number(p['aisle']),
  'pmrAisleWidth': number(p['aisle']),
  'tableGap': number(p['aisle']),
  'wallGap': number(p['aisle']) / 2,
  'exhibitorGap': number((p['parcoursSettings'] as Map?)?['exhibitorGap'], 1.2),
  'parcoursWallGap': number(p['aisle']) / 2,
  'preferMainAisles': 'Non',
  ...?p['comfort'] as Map<String, dynamic>?,
};
bool eventHasPmr(Json p) => rows(p, 'groups').any(groupHasPmr);
double eventCirculation(Json p) => p['comfort'] == null
    ? number(p['aisle'])
    : number(eventComfort(p)[eventHasPmr(p) ? 'pmrAisleWidth' : 'aisleWidth']);
double eventTableGap(Json p) {
  if (p['comfort'] == null) return number(p['aisle']);
  if (p['arrangementMode'] == 'Parcours') return eventCirculation(p);
  final c = eventComfort(p);
  return max(
    number(c['tableGap']),
    2 * number(c['seatDepth']) + eventCirculation(p),
  );
}

double eventWallGap(Json p) => p['comfort'] == null
    ? number(p['aisle']) / 2
    : number(
        eventComfort(p)[p['arrangementMode'] == 'Parcours'
            ? 'parcoursWallGap'
            : 'wallGap'],
      );
double eventExhibitorGap(Json p) => number(eventComfort(p)['exhibitorGap']);
Json comfortTable(Json p, Json t) {
  if (p['comfort'] == null || t['kind'] != 'table') return t;
  final c = eventComfort(p);
  return {
    ...t,
    '_seatWidth': number(c['seatWidth']),
    '_seatDepth': number(c['seatDepth']),
    'adaptedPlaces': <Json>[
      for (final place in adaptedPlaces(t))
        {
          ...place,
          'width': max(number(place['width']), number(c['pmrSeatWidth'])),
          'depth': max(number(place['depth']), number(c['pmrDepth'])),
        },
    ],
  };
}

double tablePassageGap(Json p, Json a, Json b, PlanGeometry geo) {
  final base = eventTableGap(p);
  if (p['comfort'] == null || p['arrangementMode'] == 'Parcours') return base;
  final ea = geo.bounds(a), eb = geo.bounds(b);
  double horizontal = number(a['x']) < number(b['x'])
      ? number(ea['x']) +
            number(ea['w']) -
            number(a['x']) -
            number(a['w']) +
            number(b['x']) -
            number(eb['x'])
      : number(eb['x']) +
            number(eb['w']) -
            number(b['x']) -
            number(b['w']) +
            number(a['x']) -
            number(ea['x']);
  double vertical = number(a['y']) < number(b['y'])
      ? number(ea['y']) +
            number(ea['h']) -
            number(a['y']) -
            number(a['h']) +
            number(b['y']) -
            number(eb['y'])
      : number(eb['y']) +
            number(eb['h']) -
            number(b['y']) -
            number(b['h']) +
            number(a['y']) -
            number(ea['y']);
  final beside =
      number(a['x']) + number(a['w']) <= number(b['x']) ||
      number(b['x']) + number(b['w']) <= number(a['x']);
  return max(base, (beside ? horizontal : vertical) + eventCirculation(p));
}

double _pointSegmentDistance(
  Point<double> point,
  Point<double> a,
  Point<double> b,
) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final length = dx * dx + dy * dy;
  final t = length == 0
      ? 0.0
      : ((point.x - a.x) * dx + (point.y - a.y) * dy) / length;
  final fraction = t.clamp(0.0, 1.0);
  return point.distanceTo(Point(a.x + fraction * dx, a.y + fraction * dy));
}

List<(Point<double>, Point<double>)> mainAisleGuides(Json p) {
  final guides = <(Point<double>, Point<double>)>[];
  for (final zone in rows(p, 'items').where(
    (i) =>
        i['kind'] == 'zone' &&
        (i['mainAisle'] == 'Oui' || i['parcoursPassage'] == 'Oui'),
  )) {
    final x = number(zone['x']),
        y = number(zone['y']),
        w = number(zone['w']),
        h = number(zone['h']);
    guides.add(
      w >= h
          ? (Point(x, y + h / 2), Point(x + w, y + h / 2))
          : (Point(x + w / 2, y), Point(x + w / 2, y + h)),
    );
  }
  if (guides.isNotEmpty) return guides;
  for (final path in parcoursPaths(p)) {
    for (var i = 1; i < path.length; i++) {
      guides.add((path[i - 1], path[i]));
    }
  }
  if (guides.isNotEmpty) return guides;
  final ts = tables(p).where((t) => !unplacedTable(p, t)).toList();
  final geo = PlanGeometry(p, rows(p, 'items'));
  for (var i = 0; i < ts.length; i++) {
    for (var j = i + 1; j < ts.length; j++) {
      final a = geo.bounds(ts[i]), b = geo.bounds(ts[j]);
      final l = max(number(a['x']), number(b['x'])),
          r = min(
            number(a['x']) + number(a['w']),
            number(b['x']) + number(b['w']),
          );
      final top = max(number(a['y']), number(b['y'])),
          bottom = min(
            number(a['y']) + number(a['h']),
            number(b['y']) + number(b['h']),
          );
      if (bottom > top &&
          (number(b['x']) - number(a['x']) - number(a['w']) >=
                  eventCirculation(p) ||
              number(a['x']) - number(b['x']) - number(b['w']) >=
                  eventCirculation(p))) {
        final left = number(a['x']) < number(b['x']) ? a : b,
            right = identical(left, a) ? b : a;
        final x =
            (number(left['x']) + number(left['w']) + number(right['x'])) / 2;
        guides.add((Point(x, top), Point(x, bottom)));
      }
      if (r > l &&
          (number(b['y']) - number(a['y']) - number(a['h']) >=
                  eventCirculation(p) ||
              number(a['y']) - number(b['y']) - number(b['h']) >=
                  eventCirculation(p))) {
        final upper = number(a['y']) < number(b['y']) ? a : b,
            lower = identical(upper, a) ? b : a;
        final y =
            (number(upper['y']) + number(upper['h']) + number(lower['y'])) / 2;
        guides.add((Point(l, y), Point(r, y)));
      }
    }
  }
  return guides;
}

double pmrPlaceDistance(
  Json p,
  Json table,
  int slot,
  List<(Point<double>, Point<double>)> guides,
  PlanGeometry geo,
) {
  if (guides.isEmpty) return 0;
  final points = placeLabelPositions(
    geo.view(table),
    geo.capacity(table),
    geo.blocked[table['id']] ?? {},
  );
  if (slot < 0 || slot >= points.length) return double.infinity;
  final point = Point(
    number(table['x']) + points[slot].x,
    number(table['y']) + points[slot].y,
  );
  return guides
      .map((guide) => _pointSegmentDistance(point, guide.$1, guide.$2))
      .reduce(min);
}

const accessAudiences = [
  'Tous publics',
  'PMR avec accompagnants',
  'Non-PMR uniquement',
];
bool isPlanAccess(Json item) => ['entry', 'exit'].contains(item['kind']);
bool groupHasPmr(Json group) => List.generate(
  group['count'] as int,
  (i) => individualSeat(group, i),
).any((seat) => (seat['need'] ?? '').toString().trim().isNotEmpty);
bool accessCompatible(Json p, Json item, Json group) {
  if (!isPlanAccess(item)) return true;
  // Count physical accesses, independently of their inclusion in preferences.
  if (rows(p, 'items').where((i) => i['kind'] == item['kind']).length <= 1) {
    return true;
  }
  final audience = item['accessAudience'] ?? accessAudiences.first;
  return audience == accessAudiences.first ||
      (groupHasPmr(group)
          ? audience == accessAudiences[1]
          : audience == accessAudiences[2]);
}

List<Json> groupProximityTargets(Json p, Json group) =>
    proximityTargets(p)
        .where((item) => accessCompatible(p, item, group))
        .toList();

bool canIncludeInProximity(Json item) =>
    ['zone', 'entry', 'exit'].contains(item['kind']);
List<Json> proximityTargets(Json p) => rows(p, 'items')
    .where(
      (item) =>
          canIncludeInProximity(item) && item['proximityEnabled'] == 'Oui',
    )
    .toList();
String proximityTargetName(Json item) {
  final label = (item['label'] ?? '').toString().trim();
  return label.isEmpty ? '${objectLabels[item['kind']]} sans libellé' : label;
}

Map<String, String> reservationPlacePreferences(Json group) =>
    Map<String, String>.from(group['placeProximity'] as Map? ?? {});
List<Json> proximityPlaces(Json p, String id) =>
    proximityTargets(p).where((item) => item['id'] == id).toList();
void prunePlacePreferences(Json p) {
  if (p['audienceSettings'] is Map &&
      !rows(p, 'items').any(
        (t) => t['id'] == p['audienceSettings']['scene'] && t['kind'] == 'zone',
      )) {
    p.remove('audienceSettings');
    if (p['arrangementMode'] == 'Scène') p['arrangementMode'] = 'Standard';
  }

  final ids = proximityTargets(p).map((item) => item['id']).toSet();
  for (final group in rows(p, 'groups')) {
    (group['placeProximity'] as Map?)?.removeWhere(
      (key, value) => !ids.contains(key),
    );
  }
}

// Preserve existing objects from the local trial as ordinary free zones.
void migrateLegacyProximity(Json p) {
  if (p['items'] is! List || p['groups'] is! List) return;
  for (final item in rows(p, 'items')) {
    if (item['kind'] == 'toilet') {
      item['kind'] = 'zone';
      item['zoneColor'] ??= 'Bleu';
      item['zoneFill'] ??= 'Plein';
    }
  }
  for (final group in rows(p, 'groups')) {
    final preferences = group['placeProximity'];
    if (preferences is Map) {
      for (final legacy in ['toilet', 'entry', 'exit']) {
        preferences.remove(legacy);
      }
    }
  }
}

const eventIconNames = [
  'Sapin de Noël',
  'Brocante',
  'Loto',
  'Spectacle',
  'Événement',
  'Café',
  'Repas',
  'Musique',
  'Fête',
  'Conférence',
  'Sport',
  'Atelier',
  'Association',
  'Cadeau',
];
String defaultEventIcon(String activity) => switch (activity) {
  'Marché de Noël' => 'Sapin de Noël',
  'Brocante' => 'Brocante',
  'Loto' => 'Loto',
  'Soirée' => 'Spectacle',
  _ => 'Événement',
};
String eventIconName(Json event) => eventIconNames.contains(event['icon'])
    ? event['icon'] as String
    : defaultEventIcon(eventActivity(event));

const roomActivities = [
  'Personnalisé',
  'Marché de Noël',
  'Brocante',
  'Loto',
  'Soirée',
];
const seatingModes = ['Longs côtés', 'Tous côtés', 'Un côté'];
const seatingSideNames = ['Haut', 'Droite', 'Bas', 'Gauche'];
Json activityDefaults(String activity) => {
  'mealService': ['Marché de Noël', 'Brocante', 'Loto'].contains(activity)
      ? 'Non'
      : 'Oui',
  'defaultSides': ['Marché de Noël', 'Brocante'].contains(activity)
      ? 'Un côté'
      : activity == 'Loto'
      ? 'Tous côtés'
      : 'Longs côtés',
};
String eventActivity(Json p) {
  final activity = p['activity'] ?? p['room']['activity'] ?? 'Personnalisé';
  return activity == 'Soirée repas' ? 'Soirée' : activity;
}

bool mealsEnabled(Json p) =>
    (p['mealService'] ?? p['room']['mealService'] ?? 'Oui') == 'Oui';

String eventSeatingSides(Json p) =>
    p['defaultSides'] ?? p['room']['defaultSides'] ?? 'Longs côtés';

void migrateEventSettings(Json p) {
  migrateLegacyProximity(p);
  if (![
    'activity',
    'mealService',
    'defaultSides',
  ].any((key) => p['room'].containsKey(key))) {
    return;
  }
  p['activity'] = eventActivity(p);
  p['mealService'] = mealsEnabled(p) ? 'Oui' : 'Non';
  p['defaultSides'] = eventSeatingSides(p);
  for (final key in ['activity', 'mealService', 'defaultSides']) {
    p['room'].remove(key);
  }
}

String rotateSeatingSide(String side, int degrees) {
  final index = seatingSideNames.indexOf(side);
  return index < 0 ? side : seatingSideNames[(index + degrees ~/ 90) % 4];
}

String uid() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(999999)}';
double number(dynamic v, [double fallback = 0]) =>
    double.tryParse('$v'.replaceAll(',', '.')) ?? fallback;
Json clone(Json v) => jsonDecode(jsonEncode(v)) as Json;
List<Json> rows(Json v, String key) => (v[key] as List).cast<Json>();

Json newProject(String name) => {
  'id': uid(),
  'joining': 'Aucun',
  'attendanceTarget': null,
  'name': name,
  'version': 1,
  'aisle': .9,
  'room': {
    'name': 'Salle principale',
    'alias': '',
    'address': '',
    'width': 12.0,
    'height': 9.0,
  },
  'rooms': <Json>[],
  'items': <Json>[],
  'types': <Json>[],
  'groups': <Json>[],
  'meals': ['Normal', 'Végétarien', 'Sans gluten', 'Ne mange pas'],
  'history': <Json>[],
  'retentionDays': 0,
};
Json demoProject() {
  final p = newProject('Repas associatif • démonstration');
  p['types'] = [
    {
      'id': 'rect',
      'name': 'Table 180',
      'shape': 'rectangle',
      'w': 1.8,
      'h': .8,
      'capacity': 6,
      'quantity': 12,
      'source': 'Salle',
      'enabled': true,
      'limit': 12,
      'seating': 'Chaises',
    },
    {
      'id': 'round',
      'name': 'Table ronde',
      'shape': 'cercle',
      'w': 1.5,
      'h': 1.5,
      'capacity': 6,
      'quantity': 2,
      'source': 'Emprunté',
      'enabled': true,
      'limit': 2,
      'seating': 'Chaises',
    },
    {
      'id': 'bench',
      'name': 'Banc 200',
      'shape': 'banc',
      'w': 2.0,
      'h': .35,
      'capacity': 3,
      'quantity': 8,
      'source': 'Propre',
      'enabled': true,
      'limit': 8,
      'seating': 'Bancs',
    },
  ];
  for (var i = 0; i < 6; i++) {
    rows(p, 'items').add({
      'id': uid(),
      'kind': 'table',
      'type': 'rect',
      'label': 'T${i + 1}',
      'shape': 'rectangle',
      'x': 1.0 + (i % 3) * 3.2,
      'y': 1.1 + (i ~/ 3) * 3.2,
      'w': 1.8,
      'h': .8,
      'capacity': 6,
      'fixed': false,
      'seating': 'Chaises',
      'sides': 'Longs côtés',
    });
  }
  rows(p, 'items').addAll([
    {
      'id': uid(),
      'kind': 'zone',
      'label': 'Cuisine',
      'shape': 'rectangle',
      'x': 9.8,
      'y': 6.4,
      'w': 2.0,
      'h': 2.2,
      'fixed': true,
    },
    {
      'id': uid(),
      'kind': 'entry',
      'label': 'Entrée PMR',
      'shape': 'rectangle',
      'x': 0.0,
      'y': 7.2,
      'w': 1.0,
      'h': 1.0,
      'fixed': true,
    },
    {
      'id': uid(),
      'kind': 'exit',
      'label': 'Sortie secours',
      'shape': 'rectangle',
      'x': 11.0,
      'y': .0,
      'w': 1.0,
      'h': .8,
      'fixed': true,
    },
  ]);
  rows(p, 'groups').addAll([
    {
      'id': uid(),
      'name': 'Camille (fictif)',
      'count': 12,
      'meal': 'Normal',
      'allergy': '',
      'needs': '',
      'companion': false,
      'alloc': <Json>[],
    },
    {
      'id': uid(),
      'name': 'Morgan (fictif)',
      'count': 4,
      'meal': 'Végétarien',
      'allergy': 'Exemple : noix',
      'needs': 'Fauteuil',
      'companion': true,
      'alloc': <Json>[],
    },
    {
      'id': uid(),
      'name': 'Alex (fictif)',
      'count': 3,
      'meal': 'Ne mange pas',
      'allergy': '',
      'needs': '',
      'companion': false,
      'alloc': <Json>[],
    },
  ]);
  return p;
}

List<Json> tables(Json p) =>
    rows(p, 'items').where(isSeatingFurniture).toList();
int occupancy(Json p, String id) => rows(p, 'groups').fold(
  0,
  (n, g) =>
      n +
      (g['alloc'] as List)
          .where((a) => a['table'] == id)
          .fold<int>(0, (s, a) => s + (a['count'] as int)),
);
bool overlaps(Json a, Json b, [double margin = 0]) =>
    isPlanAnnotation(a) || isPlanAnnotation(b)
    ? false
    : number(a['angle']) != 0 || number(b['angle']) != 0
    ? rotatedOverlap(a, b, margin)
    : number(a['x']) < number(b['x']) + number(b['w']) + margin - .000001 &&
          number(a['x']) + number(a['w']) + margin > number(b['x']) + .000001 &&
          number(a['y']) < number(b['y']) + number(b['h']) + margin - .000001 &&
          number(a['y']) + number(a['h']) + margin > number(b['y']) + .000001;
double seatEnvelope(Json a) => a['kind'] == 'table' && a['capacity'] != 0
    ? adaptedPlaces(a).fold<double>(
        number(a['_seatDepth'], a['seating'] == 'Bancs' ? .4 : .55),
        (depth, place) => max(depth, number(place['depth'], 1.2)),
      )
    : 0;
List<Point<double>> roomPolygon(Json room) {
  final text = '${room['polygon'] ?? ''}'.trim();
  if (text.isEmpty) return [];
  final pts = text.split(';').map((pair) {
    final xy = pair.trim().split(',');
    if (xy.length != 2) {
      throw const FormatException('Contour : x,y ; x,y avec décimales à point');
    }
    final x = double.tryParse(xy[0]), y = double.tryParse(xy[1]);
    if (x == null ||
        y == null ||
        !x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        y < 0 ||
        x > number(room['width']) ||
        y > number(room['height'])) {
      throw const FormatException('Point de contour hors dimensions');
    }
    return Point(x, y);
  }).toList();
  if (pts.length < 3) {
    throw const FormatException('Contour : au moins trois points');
  }
  return pts;
}

bool inside(Point<double> point, List<Point<double>> polygon) {
  var result = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i], b = polygon[j];
    if ((a.y > point.y) != (b.y > point.y) &&
        point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
      result = !result;
    }
  }
  return result;
}

bool polygonFits(Json e, Json room) {
  final polygon = roomPolygon(room);
  if (polygon.isEmpty) return true;
  final x = number(e['x']),
      y = number(e['y']),
      w = number(e['w']),
      h = number(e['h']);
  for (var d = 0.0; d <= w; d += .05) {
    if (!inside(Point(x + d, y), polygon) ||
        !inside(Point(x + d, y + h), polygon)) {
      return false;
    }
  }
  for (var d = 0.0; d <= h; d += .05) {
    if (!inside(Point(x, y + d), polygon) ||
        !inside(Point(x + w, y + d), polygon)) {
      return false;
    }
  }
  return inside(Point(x + w, y + h), polygon);
}

Map<String, double> seatedEdges(Json a) {
  if (a['capacity'] == 0) return {};
  if (furnitureUse(a) != 'Places assises' ||
      a['kind'] != 'table' ||
      (a['shape'] == 'cercle' && a['sides'] != 'Un côté')) {
    return {};
  }
  final w = number(a['w']), h = number(a['h']);
  if (a['sides'] == 'Un côté') {
    final edge =
        const {
          'Haut': 'top',
          'Droite': 'right',
          'Bas': 'bottom',
          'Gauche': 'left',
        }[a['seatSide']] ??
        (w >= h ? 'bottom' : 'right');
    return {
      edge: ['left', 'right'].contains(edge) ? h : w,
    };
  }
  if (a['sides'] == 'Longs côtés') {
    return w >= h ? {'top': w, 'bottom': w} : {'left': h, 'right': h};
  }
  return {'top': w, 'bottom': w, 'left': h, 'right': h};
}

const joinGapSideNames = ['Les deux bords', 'Premier bord', 'Second bord'];

/// Missing means inherit; an explicit zero is a real override.
Json tableJoinSettings(Json p, Json t) {
  if (t['joinGap'] != null) return t;
  final type = rows(p, 'types').where((v) => v['id'] == t['type']).firstOrNull;
  if (type?['joinGap'] != null) return type!;
  return p;
}

double tableJoinEdgeGap(Json p, Json t, String edge) {
  if (t['_joinEdgeGaps'] is Map) return number(t['_joinEdgeGaps'][edge]);
  final settings = tableJoinSettings(p, t);
  final side = settings['joinGapSides'] ?? joinGapSideNames.first;
  final rotation =
      t['rotation'] as int? ?? (number(t['w']) < number(t['h']) ? 90 : 0);
  const edges = ['top', 'right', 'bottom', 'left'];
  final original = edges[(edges.indexOf(edge) - rotation ~/ 90) % 4];
  final first = original == 'left' || original == 'top';
  if (side == 'Premier bord' && !first || side == 'Second bord' && first) {
    return 0;
  }
  return number(settings['joinGap']);
}

double tableJoinDistance(Json p, Json a, String ae, Json b, String be) =>
    max(tableJoinEdgeGap(p, a, ae), tableJoinEdgeGap(p, b, be));

/// Applies a table's junction settings to its existing neighbours locally.
/// The chosen table stays anchored; only its collinear neighbours move.
/// A blocked proposal leaves every existing position intact.
String? applyTableJoinGapLocally(Json p, Json before, String id) {
  final current = tables(p).firstWhere((t) => t['id'] == id);
  final old = tables(before).firstWhere((t) => t['id'] == id);
  if (current['shape'] == 'cercle') return null;
  for (final key in ['x', 'y', 'w', 'h', 'rotation']) {
    if (current[key] != old[key]) return null;
  }
  final oldTables = tables(before)
      .where(
        (t) => t['unplacedByArrangement'] != true && t['shape'] != 'cercle',
      )
      .toList();
  final links = <(String, String, String, String)>[];
  bool near(double a, double b) => (a - b).abs() < .00001;
  for (var i = 0; i < oldTables.length; i++) {
    for (var j = i + 1; j < oldTables.length; j++) {
      final a = oldTables[i], b = oldTables[j];
      final sharedBlock =
          a['parcoursBlock'] != null &&
          a['parcoursBlock'] == b['parcoursBlock'];
      final joined =
          joinedEdges(before, a, b) ??
          joinedEdges(before, {...a, 'joinGap': 0.0}, {...b, 'joinGap': 0.0});
      if (!sharedBlock && joined == null && before['joining'] == 'Aucun') {
        continue;
      }
      final ax = number(a['x']),
          ay = number(a['y']),
          aw = number(a['w']),
          ah = number(a['h']);
      final bx = number(b['x']),
          by = number(b['y']),
          bw = number(b['w']),
          bh = number(b['h']);
      void add(String ae, String be, double gap) {
        if (joined == (ae, be) ||
            sharedBlock &&
                (near(gap, tableJoinDistance(before, a, ae, b, be)) ||
                    near(gap, 0))) {
          links.add((a['id'] as String, b['id'] as String, ae, be));
        }
      }

      if (min(ay + ah, by + bh) > max(ay, by) + .00001) {
        add('right', 'left', bx - ax - aw);
        add('left', 'right', ax - bx - bw);
      }
      if (min(ax + aw, bx + bw) > max(ax, bx) + .00001) {
        add('bottom', 'top', by - ay - ah);
        add('top', 'bottom', ay - by - bh);
      }
    }
  }
  final originals = {for (final t in oldTables) t['id'] as String: t};
  final translations = <String, Point<double>>{};
  for (final link in links.where((l) => l.$1 == id || l.$2 == id)) {
    final edge = link.$1 == id ? link.$3 : link.$4;
    final neighborId = link.$1 == id ? link.$2 : link.$1;
    final otherEdge = link.$1 == id ? link.$4 : link.$3;
    final neighbor = originals[neighborId]!;
    final horizontal = edge == 'left' || edge == 'right';
    final positive = edge == 'right' || edge == 'bottom';
    final actual = switch (edge) {
      'right' => number(neighbor['x']) - number(old['x']) - number(old['w']),
      'left' =>
        number(old['x']) - number(neighbor['x']) - number(neighbor['w']),
      'bottom' => number(neighbor['y']) - number(old['y']) - number(old['h']),
      _ => number(old['y']) - number(neighbor['y']) - number(neighbor['h']),
    };
    final gap = tableJoinDistance(
      p,
      current,
      edge,
      tables(p).firstWhere((t) => t['id'] == neighborId),
      otherEdge,
    );
    final delta = (gap - actual) * (positive ? 1 : -1);
    if (delta.abs() < .00001) continue;
    final cut =
        number(old[horizontal ? 'x' : 'y']) +
        (positive ? number(old[horizontal ? 'w' : 'h']) : 0);
    bool onSide(String node) {
      final t = originals[node]!;
      final start = number(t[horizontal ? 'x' : 'y']);
      final end = start + number(t[horizontal ? 'w' : 'h']);
      return positive ? start >= cut - .00001 : end <= cut + .00001;
    }

    final side = <String>{neighborId}, pending = <String>[neighborId];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      for (final l in links.where((l) => l.$1 == node || l.$2 == node)) {
        final sameAxis = horizontal
            ? ['left', 'right'].contains(l.$3)
            : ['top', 'bottom'].contains(l.$3);
        if (!sameAxis) continue;
        final next = l.$1 == node ? l.$2 : l.$1;
        if (next != id && onSide(next) && side.add(next)) pending.add(next);
      }
    }
    for (final node in side) {
      if (originals[node]!['fixed'] == true ||
          originals[node]!['capacity'] == 0) {
        return 'Écart enregistré. Une pièce fixée bloque l’ouverture de cette jonction ; aucune table n’a été déplacée.';
      }
      final offset = Point<double>(
        horizontal ? delta : 0,
        horizontal ? 0 : delta,
      );
      final previous = translations[node];
      if (previous == null) {
        translations[node] = offset;
      } else if (previous.distanceTo(offset) > .00001) {
        return 'Écart enregistré. Ces jonctions demandent des déplacements incompatibles ; aucune table n’a été déplacée.';
      }
    }
  }
  if (translations.isEmpty) return null;
  final candidate = clone(p);
  final moved = <Json>[];
  for (final t in tables(candidate)) {
    final offset = translations[t['id']];
    if (offset == null) continue;
    t['x'] = number(t['x']) + offset.x;
    t['y'] = number(t['y']) + offset.y;
    moved.add(t);
  }
  final items = rows(
    candidate,
    'items',
  ).where((i) => i['unplacedByArrangement'] != true).toList();
  final geometry = PlanGeometry(candidate, items);
  if (moved.any(
    (t) => !fits(candidate, t, items, passages: false, geometry: geometry),
  )) {
    return 'Écart enregistré. L’ouverture serait bloquée par un mur ou un autre objet ; aucune table n’a été déplacée.';
  }
  for (final t in tables(p)) {
    final offset = translations[t['id']];
    if (offset != null) {
      t['x'] = number(t['x']) + offset.x;
      t['y'] = number(t['y']) + offset.y;
    }
  }
  return 'Ouverture appliquée aux jonctions existantes, sans redisposition de la salle.';
}

List<(double, double)> tableJoinPositions(Json p, Json item, Json neighbor) {
  final x = number(neighbor['x']),
      y = number(neighbor['y']),
      w = number(neighbor['w']),
      h = number(neighbor['h']),
      iw = number(item['w']),
      ih = number(item['h']);
  return [
    (
      x + w + tableJoinDistance(p, neighbor, 'right', item, 'left'),
      y + (h - ih) / 2,
    ),
    (
      x - iw - tableJoinDistance(p, neighbor, 'left', item, 'right'),
      y + (h - ih) / 2,
    ),
    (
      x + (w - iw) / 2,
      y + h + tableJoinDistance(p, neighbor, 'bottom', item, 'top'),
    ),
    (
      x + (w - iw) / 2,
      y - ih - tableJoinDistance(p, neighbor, 'top', item, 'bottom'),
    ),
  ];
}

/// Centred junction accepts different dimensions; circles never join.
(String, String)? joinedEdges(Json p, Json a, Json b) {
  final mode = p['joining'] ?? 'Aucun';
  if (mode == 'Aucun' ||
      a['kind'] != 'table' ||
      b['kind'] != 'table' ||
      a['shape'] == 'cercle' ||
      b['shape'] == 'cercle') {
    return null;
  }
  bool near(double x, double y) => (x - y).abs() < .00001;
  final ax = number(a['x']),
      ay = number(a['y']),
      aw = number(a['w']),
      ah = number(a['h']);
  final bx = number(b['x']),
      by = number(b['y']),
      bw = number(b['w']),
      bh = number(b['h']);
  (String, String)? contact;
  if (near(ay + ah / 2, by + bh / 2)) {
    if (near(ax + aw + tableJoinDistance(p, a, 'right', b, 'left'), bx)) {
      contact = ('right', 'left');
    }
    if (near(bx + bw + tableJoinDistance(p, b, 'right', a, 'left'), ax)) {
      contact = ('left', 'right');
    }
  }
  if (near(ax + aw / 2, bx + bw / 2)) {
    if (near(ay + ah + tableJoinDistance(p, a, 'bottom', b, 'top'), by)) {
      contact = ('bottom', 'top');
    }
    if (near(by + bh + tableJoinDistance(p, b, 'bottom', a, 'top'), ay)) {
      contact = ('top', 'bottom');
    }
  }
  if (contact == null) return null;
  bool allowed(Json t, String edge) {
    if (mode == 'Les deux') return true;
    final w = number(t['w']), h = number(t['h']);
    if (near(w, h)) return true;
    final edgeLength = ['left', 'right'].contains(edge) ? h : w;
    return mode == 'Petits côtés'
        ? edgeLength == min(w, h)
        : edgeLength == max(w, h);
  }

  return allowed(a, contact.$1) && allowed(b, contact.$2) ? contact : null;
}

const wallModes = [
  'Aucun',
  'Mur gauche',
  'Mur droit',
  'Mur haut',
  'Mur bas',
  'Gauche + droit',
  'Haut + bas',
  'Tous les murs',
];
Set<String> wallSides(Json p) {
  if (roomPolygon(p['room']).isNotEmpty &&
      p['wallSupport'] != 'Tous les murs') {
    return {};
  }
  return switch (p['wallSupport'] ?? 'Aucun') {
    'Mur gauche' => {'left'},
    'Mur droit' => {'right'},
    'Mur haut' => {'top'},
    'Mur bas' => {'bottom'},
    'Gauche + droit' || 'Gauche + droit / allée centrale' => {'left', 'right'},
    'Haut + bas' || 'Haut + bas / allée centrale' => {'top', 'bottom'},
    'Tous les murs' => {'left', 'right', 'top', 'bottom'},
    _ => {},
  };
}

Set<String> tableWallSides(Json p, Json table) {
  final allowed = wallSides(p);
  if (parcoursActive(p)) {
    final w = number(table['w']), h = number(table['h']);
    final ends = (w - h).abs() < .00001
        ? (['Haut', 'Bas'].contains(table['seatSide'])
              ? <String>{'left', 'right'}
              : <String>{'top', 'bottom'})
        : w > h
        ? <String>{'left', 'right'}
        : <String>{'top', 'bottom'};
    allowed.retainAll(ends);
    allowed.removeAll(seatedEdges(table).keys);
  }
  return allowed;
}

Set<String> wallEdges(Json p, Json t) {
  if (t['kind'] != 'table' || t['shape'] == 'cercle') return {};
  final room = p['room'];
  final allowed = tableWallSides(p, t);
  return allowed
      .where(
        (edge) => switch (edge) {
          'left' => number(t['x']).abs() < .00001,
          'right' =>
            (number(t['x']) + number(t['w']) - number(room['width'])).abs() <
                .00001,
          'top' => number(t['y']).abs() < .00001,
          _ =>
            (number(t['y']) + number(t['h']) - number(room['height'])).abs() <
                .00001,
        },
      )
      .toSet();
}

class PlanGeometry {
  final Json project;
  final List<Json> items;
  final blocked = <String, Set<String>>{};
  final parents = <String, String>{};
  PlanGeometry(this.project, this.items) {
    for (final i in items) {
      parents[i['id']] = i['id'];
      blocked[i['id']] = wallEdges(project, i);
    }
    if ((project['joining'] ?? 'Aucun') == 'Aucun') return;
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        final a = items[i], b = items[j], contact = joinedEdges(project, a, b);
        if (contact != null) {
          blocked[a['id']]!.add(contact.$1);
          blocked[b['id']]!.add(contact.$2);
          parents[root(a['id'])] = root(b['id']);
        }
      }
    }
  }
  String root(String id) {
    final parent = parents[id];
    if (parent == null || parent == id) return id;
    return parents[id] = root(parent);
  }

  bool sameAssembly(Json a, Json b) => root(a['id']) == root(b['id']);
  // Ignore a gap only when samples lie in furniture or its configured junctions.
  // A free narrow gap between arms of a U-shaped assembly still requires an aisle.
  bool internalContact(Json a, Json b) {
    if (joinedEdges(project, a, b) != null) return true;
    if (parcoursInternalContact(project, a, b)) return true;
    if (!sameAssembly(a, b)) return false;
    final ax = number(a['x']),
        ay = number(a['y']),
        aw = number(a['w']),
        ah = number(a['h']);
    final bx = number(b['x']),
        by = number(b['y']),
        bw = number(b['w']),
        bh = number(b['h']);
    final gapX = max(0.0, max(ax, bx) - min(ax + aw, bx + bw));
    final gapY = max(0.0, max(ay, by) - min(ay + ah, by + bh));
    if (gapX < .00001 && gapY < .00001) return true;
    Point<double> start, end;
    if (gapX > 0 && gapY == 0) {
      final y = (max(ay, by) + min(ay + ah, by + bh)) / 2;
      start = Point(ax < bx ? ax + aw : bx + bw, y);
      end = Point(max(ax, bx), y);
    } else if (gapY > 0 && gapX == 0) {
      final x = (max(ax, bx) + min(ax + aw, bx + bw)) / 2;
      start = Point(x, ay < by ? ay + ah : by + bh);
      end = Point(x, max(ay, by));
    } else {
      return false;
    }
    final assembly = items
        .where((i) => i['kind'] == 'table' && root(i['id']) == root(a['id']))
        .toList();
    final occupied = <Json>[...assembly];
    for (var i = 0; i < assembly.length; i++) {
      for (var j = i + 1; j < assembly.length; j++) {
        final u = assembly[i], v = assembly[j];
        final edges = joinedEdges(project, u, v);
        if (edges == null) continue;
        final horizontal = ['left', 'right'].contains(edges.$1);
        final left = horizontal
            ? min(
                number(u['x']) + number(u['w']),
                number(v['x']) + number(v['w']),
              )
            : max(number(u['x']), number(v['x']));
        final right = horizontal
            ? max(number(u['x']), number(v['x']))
            : min(
                number(u['x']) + number(u['w']),
                number(v['x']) + number(v['w']),
              );
        final top = horizontal
            ? max(number(u['y']), number(v['y']))
            : min(
                number(u['y']) + number(u['h']),
                number(v['y']) + number(v['h']),
              );
        final bottom = horizontal
            ? min(
                number(u['y']) + number(u['h']),
                number(v['y']) + number(v['h']),
              )
            : max(number(u['y']), number(v['y']));
        occupied.add({
          'x': left,
          'y': top,
          'w': right - left,
          'h': bottom - top,
        });
      }
    }
    for (var n = 1; n < 20; n++) {
      final x = start.x + (end.x - start.x) * n / 20,
          y = start.y + (end.y - start.y) * n / 20;
      if (!occupied.any(
        (i) =>
            x >= number(i['x']) - .000001 &&
            x <= number(i['x']) + number(i['w']) + .000001 &&
            y >= number(i['y']) - .000001 &&
            y <= number(i['y']) + number(i['h']) + .000001,
      )) {
        return false;
      }
    }
    return true;
  }

  Json view(Json table) => comfortTable(project, table);
  Json bounds(Json a) => envelope(view(a), blocked[a['id']] ?? {});
  int capacity(Json t) {
    if (furnitureUse(t) != 'Places assises') return 0;
    if (t['kind'] != 'table') return autonomousCapacity(project, t);
    t = view(t);
    final base = baseCapacity(t);
    final extra = adaptedPlaces(t).fold<int>(
      0,
      (sum, place) =>
          sum +
          max(
            0,
            ((number(place['width'], .9) - number(t['_seatWidth'], .6)) /
                        number(t['_seatWidth'], .6) -
                    .000001)
                .ceil(),
          ),
    );
    return max(0, base - extra);
  }

  int baseCapacity(Json t) {
    if (furnitureUse(t) != 'Places assises') return 0;
    if (t['kind'] != 'table') return autonomousCapacity(project, t);
    t = view(t);
    final base = ordinaryCapacity(t, blocked[t['id']] ?? {});
    return project['comfort'] == null
        ? base
        : min(base, comfortableCapacity(t));
  }
}

int ordinaryCapacity(Json t, Set<String> removed) {
  final declared = t['capacity'] as int;
  final seated = seatedEdges(t);
  final total = seated.values.fold<double>(0, (s, n) => s + n);
  final remaining = seated.entries.where((e) => !removed.contains(e.key));
  if (total == 0 || !seated.keys.any(removed.contains)) return declared;
  final length = remaining.fold<double>(0, (s, e) => s + e.value);
  final comfortable = remaining.fold<int>(
    0,
    (s, e) => s + (e.value / number(t['_seatWidth'], .6) + .000001).floor(),
  );
  return min(
    declared,
    min((declared * length / total + .000001).floor(), comfortable),
  );
}

int effectiveCapacity(Json p, Json t, [PlanGeometry? geometry]) =>
    (geometry ?? PlanGeometry(p, rows(p, 'items'))).capacity(t);

Json envelope(Json a, [Set<String> blocked = const {}]) {
  final m = a['kind'] == 'table' && a['capacity'] != 0
      ? number(a['_seatDepth'], a['seating'] == 'Bancs' ? .4 : .55)
      : 0.0;
  final edges = seatedEdges(a);
  final adapted = <String, double>{};
  if (a['kind'] == 'table' && adaptedPlaces(a).isNotEmpty) {
    final extra = adaptedPlaces(a).fold<int>(
      0,
      (sum, place) =>
          sum +
          max(
            0,
            ((number(place['width'], .9) - number(a['_seatWidth'], .6)) /
                        number(a['_seatWidth'], .6) -
                    .000001)
                .ceil(),
          ),
    );
    final positions = placeLabelPositions(
      a,
      max(0, ordinaryCapacity(a, blocked) - extra),
      blocked,
    );
    for (final place in adaptedPlaces(a)) {
      final slot = place['slot'] as int;
      if (slot < 0 || slot >= positions.length) continue;
      final point = positions[slot];
      final edge = point.x < 0
          ? 'left'
          : point.x > number(a['w'])
          ? 'right'
          : point.y < 0
          ? 'top'
          : 'bottom';
      adapted[edge] = max(adapted[edge] ?? m, number(place['depth'], 1.2));
    }
  }
  double margin(String edge) => blocked.contains(edge)
      ? 0
      : (a['shape'] == 'cercle' && a['sides'] != 'Un côté') ||
            edges.containsKey(edge)
      ? adapted[edge] ?? m
      : 0;
  final left = margin('left'),
      right = margin('right'),
      top = margin('top'),
      bottom = margin('bottom');
  return {
    ...a,
    'x': number(a['x']) - left,
    'y': number(a['y']) - top,
    'w': number(a['w']) + left + right,
    'h': number(a['h']) + top + bottom,
  };
}

bool fits(
  Json p,
  Json a,
  List<Json> others, {
  bool passages = true,
  PlanGeometry? geometry,
}) {
  if (a['audienceLayout'] == true || number(a['angle']) != 0) {
    return audienceFits(p, a, others);
  }
  final geo =
      geometry ??
      PlanGeometry(p, [...others.where((i) => i['id'] != a['id']), a]);
  final e = geo.bounds(a), room = p['room'] as Json;
  if (!polygonFits(e, room)) return false;
  if (!wallClearanceFits(p, a)) return false;
  const epsilon = .0000001;
  if (number(e['x']) < -epsilon ||
      number(e['y']) < -epsilon ||
      number(e['x']) + number(e['w']) > number(room['width']) + epsilon ||
      number(e['y']) + number(e['h']) > number(room['height']) + epsilon) {
    return false;
  }
  return !others
      .where((b) => b['id'] != a['id'] && !isPlanAnnotation(b))
      .any(
        (b) =>
            overlaps(a, b) ||
            (isSeatingFurniture(a) &&
                isSeatingFurniture(b) &&
                (a['kind'] != 'table' || b['kind'] != 'table') &&
                overlaps(a, b, number(eventComfort(p)['chairGap'], .1))) ||
            (a['kind'] == 'table' &&
                b['kind'] == 'table' &&
                overlaps(
                  a,
                  b,
                  passages && !geo.internalContact(a, b) ? eventTableGap(p) : 0,
                )),
      );
}

bool wallClearanceFits(Json p, Json table) {
  if (table['kind'] != 'table' || furnitureUse(table) == 'Service') return true;
  final gap = furnitureUse(table) == furnitureUses[1]
      ? number(eventComfort(p)['parcoursWallGap'])
      : eventWallGap(p);
  final allowed = table['shape'] == 'cercle'
      ? <String>{}
      : tableWallSides(p, table);
  final envelopeBounds = p['comfort'] == null
      ? table
      : envelope(comfortTable(p, table));
  double reserve(String edge) {
    if (allowed.contains(edge)) return 0;
    if (p['comfort'] == null) return gap;
    final seat = switch (edge) {
      'left' => number(table['x']) - number(envelopeBounds['x']),
      'right' =>
        number(envelopeBounds['x']) +
            number(envelopeBounds['w']) -
            number(table['x']) -
            number(table['w']),
      'top' => number(table['y']) - number(envelopeBounds['y']),
      _ =>
        number(envelopeBounds['y']) +
            number(envelopeBounds['h']) -
            number(table['y']) -
            number(table['h']),
    };
    return max(
      gap,
      seat == 0
          ? 0
          : seat +
                (p['arrangementMode'] == 'Parcours' ? 0 : eventCirculation(p)),
    );
  }

  final left = reserve('left');
  final right = reserve('right');
  final top = reserve('top');
  final bottom = reserve('bottom');
  final bounds = {
    ...table,
    'x': number(table['x']) - left,
    'y': number(table['y']) - top,
    'w': number(table['w']) + left + right,
    'h': number(table['h']) + top + bottom,
  };
  final room = p['room'];
  const epsilon = .0000001;
  return number(bounds['x']) >= -epsilon &&
      number(bounds['y']) >= -epsilon &&
      number(bounds['x']) + number(bounds['w']) <=
          number(room['width']) + epsilon &&
      number(bounds['y']) + number(bounds['h']) <=
          number(room['height']) + epsilon &&
      polygonFits(bounds, room);
}

bool tableOutsideRoom(Json p, Json table) {
  const epsilon = .0000001;
  final room = p['room'] as Json;
  return number(table['x']) < -epsilon ||
      number(table['y']) < -epsilon ||
      number(table['x']) + number(table['w']) >
          number(room['width']) + epsilon ||
      number(table['y']) + number(table['h']) >
          number(room['height']) + epsilon ||
      !polygonFits(table, room);
}

bool unplacedTable(Json p, Json table) =>
    table['unplacedByArrangement'] == true &&
    (number(table['x']) >= number(p['room']['width']) ||
        number(table['y']) >= number(p['room']['height']));

int comfortableCapacity(Json t) {
  if (t['capacity'] == 0) return 0;
  if (t['sides'] == 'Un côté') {
    return seatedEdges(t).values.fold<int>(
      0,
      (sum, length) =>
          sum + (length / number(t['_seatWidth'], .6) + .000001).floor(),
    );
  }
  if (t['shape'] == 'cercle') {
    return (pi * number(t['w']) / number(t['_seatWidth'], .6) + .000001)
        .floor();
  }
  return (max(number(t['w']), number(t['h'])) / number(t['_seatWidth'], .6) +
                  .000001)
              .floor() *
          2 +
      (t['sides'] == 'Tous côtés'
          ? (min(number(t['w']), number(t['h'])) / number(t['_seatWidth'], .6) +
                        .000001)
                    .floor() *
                2
          : 0);
}

List<String> issues(Json p) => _preparationChecks(p).$1;
List<String> preparationNotes(Json p) => _preparationChecks(p).$2;

(List<String>, List<String>) _preparationChecks(Json p) {
  final result = <String>[];
  final notes = <String>[];
  final items = physicalPlanItems(p);
  final geo = PlanGeometry(p, items);
  result.addAll(parcoursWarnings(p));
  for (final g in rows(p, 'groups')) {
    final error = childChairReservationError(p, g);
    if (error != null) result.add('${g['name']} : $error');
  }
  for (final t in tables(p)) {
    if (unplacedTable(p, t)) {
      result.add(
        parcoursActive(p) && t['parcoursUnplacedReason'] != null
            ? '${t['label']} : hors salle, ${t['parcoursUnplacedReason']}. Revoir les réglages du parcours ou le mobilier.'
            : '${t['label']} : hors salle, pas assez de place pour disposer toutes les tables. Réduire le nombre de tables ou revoir les dimensions et les passages.',
      );
      continue;
    }
    if (!fits(p, t, [], passages: false, geometry: geo)) {
      result.add(
        !wallClearanceFits(p, t)
            ? '${t['label']} : dégagement au mur insuffisant (au moins ${eventWallGap(p).toStringAsFixed(2)} m sans appui autorisé). Décaler la table.'
            : '${t['label']} : assises hors salle. Décaler la table.',
      );
    }
    // Comfort is an indicative model recommendation, independent of occupancy.
    // Capacity and geometry violations remain actionable checks below.
    if (t['kind'] == 'table' &&
        furnitureUse(t) == furnitureUses.first &&
        t['capacity'] > comfortableCapacity(geo.view(t))) {
      notes.add(
        '${t['label']} : capacité définie ${t['capacity']}, repère de confort ${comfortableCapacity(geo.view(t))} places (${(number(eventComfort(p)['seatWidth']) * 100).toStringAsFixed(0)} cm/place, indicatif).',
      );
    }
    final capacity = geo.capacity(t);
    if (t['kind'] == 'table' &&
        furnitureUse(t) == furnitureUses.first &&
        capacity < t['capacity']) {
      notes.add(
        '${t['label']} : ${p['comfort'] != null
            ? 'réglages de confort et places adaptées'
            : adaptedPlaces(t).isEmpty
            ? 'jonction sans assises'
            : 'espace adapté et faces sans assises'} ; $capacity places utilisables sur ${t['capacity']} déclarées.',
      );
    }
    if (occupancy(p, t['id']) > capacity) {
      result.add(
        '${t['label']} : capacité utilisable dépassée ($capacity). Réattribuer des places.',
      );
    }
    final people = tablePeople(p, t, geo);
    final positions = placeLabelPositions(
      geo.view(t),
      capacity,
      geo.blocked[t['id']] ?? {},
    );
    for (final place in adaptedPlaces(t)) {
      if (place['slot'] >= capacity) {
        result.add(
          '${t['label']} : emplacement adapté devenu inutilisable. Revoir les places adaptées.',
        );
      }
    }
    for (var slot = 0; slot < people.length; slot++) {
      final person = people[slot];
      if (person == null) continue;
      final seat = person['seat'];
      if (seat['need'] == 'Fauteuil' &&
          t['kind'] != 'pmr' &&
          !adaptedPlaces(t).any((place) => place['slot'] == slot)) {
        result.add(
          '${t['label']} place ${slot + 1} : prévoir un emplacement adapté pour ${person['group']['name']}.',
        );
      }
      final wanted = seat['table'] == t['id']
          ? int.tryParse('${seat['slot']}')
          : null;
      if (wanted != null && wanted != slot) {
        result.add(
          '${t['label']} : emplacement demandé indisponible pour ${person['group']['name']} place ${seat['number']}.',
        );
      }
      final companion = int.tryParse('${seat['companion']}');
      if (companion != null) {
        final adjacent = List.generate(people.length, (n) => n).any(
          (n) =>
              n != slot &&
              n < positions.length &&
              slot < positions.length &&
              people[n]?['group']['id'] == person['group']['id'] &&
              people[n]?['index'] == companion - 1 &&
              positions[n].distanceTo(positions[slot]) <= 1.2,
        );
        if (!adjacent) {
          notes.add(
            '${t['label']} : rapprocher l’accompagnant de la place ${slot + 1}.',
          );
        }
      }
    }
  }
  for (var i = 0; i < items.length; i++) {
    for (var j = i + 1; j < items.length; j++) {
      final a = items[i], b = items[j];
      if (a['kind'] == 'zone' && b['kind'] == 'zone') continue;
      if (overlaps(a, b)) {
        result.add(
          '${a['label']} / ${b['label']} : chevauchement physique (boîtes englobantes).',
        );
      } else if (a['audienceLayout'] != true &&
          b['audienceLayout'] != true &&
          a['kind'] == 'table' &&
          b['kind'] == 'table' &&
          !geo.internalContact(a, b) &&
          overlaps(a, b, tablePassageGap(p, a, b, geo))) {
        result.add(
          '${a['label']} / ${b['label']} : passage inférieur au repère ${tablePassageGap(p, a, b, geo).toStringAsFixed(2)} m. Décaler.',
        );
      }
    }
  }
  for (final g in rows(p, 'groups')) {
    if (g['waiting'] == true) continue;
    final assigned = (g['alloc'] as List).fold<int>(
      0,
      (s, a) => s + (a['count'] as int),
    );
    if (isStandBooking(g)) {
      final delivered = (g['standAlloc'] as List? ?? []).fold<double>(
        0,
        (s, a) => s + number(a['length']),
      );
      final tablesCount = (g['standAlloc'] as List? ?? []).length;
      if (g['standUnit'] == 'Mètres linéaires'
          ? delivered + .000001 < number(g['requestedMetres'])
          : tablesCount < number(g['requestedTables'], 1)) {
        result.add(
          '${g['name']} : stand incomplet (${standAllocationText(p, g)}).',
        );
      }
      continue;
    }
    if (!freeSeating(p) && assigned != g['count']) {
      result.add('${g['name']} : $assigned/${g['count']} places attribuées.');
    }
    if ('${g['needs'] ?? ''}'.isNotEmpty) {
      notes.add(
        '${g['name']} : ${g['needs']} — trajet continu, place adaptée et accompagnant à vérifier sur site ; aucune accessibilité certifiée.',
      );
    }
    for (final s in (g['seats'] as List? ?? []).cast<Json>().take(g['count'])) {
      if ('${s['need'] ?? ''}'.isNotEmpty) {
        notes.add(
          '${g['name']} place ${s['number']} : ${s['need']}. Cheminement et place adaptée à vérifier ; accompagnant ${s['companion'] ?? ''}.',
        );
      }
      final companion = '${s['companion'] ?? ''}';
      final linked = int.tryParse(companion);
      if (companion.isNotEmpty &&
          (linked == null ||
              linked < 1 ||
              linked > g['count'] ||
              linked == s['number'])) {
        result.add(
          '${g['name']} place ${s['number']} : lien d’accompagnant invalide. Corriger dans Préférences.',
        );
      }
    }
    if ((g['seats'] as List? ?? []).length > g['count']) {
      result.add(
        '${g['name']} : détails anonymes au-delà du nouvel effectif. Ouvrir Préférences pour les corriger.',
      );
    }
    if (g['separate'] != null && g['separate'] != '') {
      final other = rows(p, 'groups').where((v) => v['id'] == g['separate']);
      if (other.isNotEmpty &&
          (g['alloc'] as List).any(
            (a) => (other.first['alloc'] as List).any(
              (b) => a['table'] == b['table'],
            ),
          )) {
        result.add(
          '${g['name']} / ${other.first['name']} : contrainte de séparation non satisfaite.',
        );
      }
    }
  }
  return (result, notes);
}

// Private preparation information: displayed only in the reservation views.
List<String> reservationPreferenceChecks(Json p) {
  if (freeSeating(p)) return [];
  final result = <String>[];
  final checked = <String>{};
  for (final group in rows(p, 'groups')) {
    for (final entry in reservationPreferences(p, group).entries) {
      final pair = [group['id'] as String, entry.key]..sort();
      if (!checked.add(pair.join('|'))) continue;
      final other = rows(p, 'groups').firstWhere((g) => g['id'] == entry.key);
      final a = assignedTables(p, group), b = assignedTables(p, other);
      final names = '${group['name']} / ${other['name']}';
      if (a.isEmpty || b.isEmpty) {
        result.add(
          '$names : préférence de proximité non vérifiable, attribution manquante.',
        );
        continue;
      }
      final distance = a
          .expand((t) => b.map((u) => tableDistance(t, u)))
          .reduce(min);
      final target = entry.value == 'near' ? 3.0 : farPreferenceDistance(p);
      if (entry.value == 'near'
          ? distance > target + .000001
          : distance < target - .000001) {
        result.add(
          '$names : préférence ${entry.value == 'near' ? 'proche' : 'loin'} à revoir (${distance.toStringAsFixed(1)} m entre tables, repère ${target.toStringAsFixed(1)} m).',
        );
      }
    }
  }
  for (final group in rows(p, 'groups')) {
    for (final preference in reservationPlacePreferences(group).entries) {
      final places = proximityPlaces(p, preference.key);
      final assigned = assignedTables(p, group);
      if (places.isEmpty) continue;
      final name = proximityTargetName(places.single);
      if (!accessCompatible(p, places.single, group)) {
        result.add(
          '${group['name']} / $name : préférence ignorée, accès incompatible avec le public du groupe.',
        );
        continue;
      }
      if (places.isEmpty || assigned.isEmpty) {
        result.add(
          '${group['name']} / $name : préférence non vérifiable, ${places.isEmpty ? 'élément absent du plan' : 'attribution manquante'}.',
        );
        continue;
      }
      final distance = assigned
          .expand((table) => places.map((place) => tableDistance(table, place)))
          .reduce(min);
      final target = preference.value == 'near'
          ? 3.0
          : farPreferenceDistance(p);
      if (preference.value == 'near'
          ? distance > target + .000001
          : distance < target - .000001) {
        result.add(
          '${group['name']} / $name : préférence ${preference.value == 'near' ? 'proche' : 'loin'} à revoir (${distance.toStringAsFixed(1)} m, repère ${target.toStringAsFixed(1)} m).',
        );
      }
    }
  }
  return result;
}

/// Full-height reservation zones define sectors, filled from left to right.
Json? findPosition(
  Json p,
  Json item,
  List<Json> others, {
  bool fromCorner = false,
  bool fromCenter = false,
}) {
  final width = number(p['room']['width']),
      height = number(p['room']['height']);
  final barriers =
      others
          .where(
            (i) =>
                i['kind'] == 'zone' &&
                number(i['y']) <= .6 &&
                number(i['y']) + number(i['h']) >= height - .6,
          )
          .toList()
        ..sort((a, b) => number(a['x']).compareTo(number(b['x'])));
  var start = 0.0;
  final regions = <(double, double)>[];
  for (final barrier in barriers) {
    final left = number(barrier['x']).clamp(0.0, width);
    final right = (number(barrier['x']) + number(barrier['w'])).clamp(
      0.0,
      width,
    );
    if (left > start) regions.add((start, left));
    start = max(start, right);
  }
  if (start < width) regions.add((start, width));
  Json? nearest;
  double distance(Json candidate) =>
      pow(
        number(candidate['x']) + number(candidate['w']) / 2 - width / 2,
        2,
      ).toDouble() +
      pow(
        number(candidate['y']) + number(candidate['h']) / 2 - height / 2,
        2,
      ).toDouble();
  for (final region in regions) {
    final candidate = _findPositionInRegion(
      p,
      item,
      others,
      region.$1,
      region.$2,
      fromCorner: fromCorner,
      fromCenter: fromCenter,
    );
    if (candidate != null) {
      if (!fromCenter) return candidate;
      if (nearest == null || distance(candidate) < distance(nearest)) {
        nearest = candidate;
      }
    }
  }
  return nearest;
}

Json? _findPositionInRegion(
  Json p,
  Json item,
  List<Json> others,
  double minX,
  double maxX, {
  bool fromCorner = false,
  bool fromCenter = false,
}) {
  final baseGeometry = PlanGeometry(
    p,
    others.where((v) => v['id'] != item['id']).toList(),
  );
  bool valid(Json candidate, {bool contact = false}) {
    if (number(candidate['x']) < minX - .000001 ||
        number(candidate['x']) + number(candidate['w']) > maxX + .000001) {
      return false;
    }
    if (contact) return fits(p, candidate, others);
    // Grid/spacing candidates do not add a join; reuse the existing assembly graph.
    // Exact joins were checked separately with their complete geometry.
    baseGeometry.blocked[candidate['id']] = wallEdges(p, candidate);
    return fits(p, candidate, others, geometry: baseGeometry);
  }

  final contacts = <Json>[];
  if (!fromCorner &&
      (p['joining'] ?? 'Aucun') != 'Aucun' &&
      item['kind'] == 'table' &&
      item['capacity'] != 0) {
    for (final neighbor in others.where(
      (i) => i['kind'] == 'table' && i['capacity'] != 0,
    )) {
      final candidates = [
        for (final pos in tableJoinPositions(p, item, neighbor))
          {...item, 'x': pos.$1, 'y': pos.$2},
      ];
      for (final candidate in candidates) {
        if (joinedEdges(p, candidate, neighbor) != null &&
            valid(candidate, contact: true)) {
          contacts.add(candidate);
        }
      }
    }
  }
  contacts.sort((a, b) {
    if (fromCenter) {
      double distance(Json c) =>
          pow(
            number(c['x']) +
                number(c['w']) / 2 -
                number(p['room']['width']) / 2,
            2,
          ).toDouble() +
          pow(
            number(c['y']) +
                number(c['h']) / 2 -
                number(p['room']['height']) / 2,
            2,
          ).toDouble();
      final proximity = distance(a).compareTo(distance(b));
      if (proximity != 0) return proximity;
    }
    final vertical = number(item['h']) > number(item['w']);
    final primary = number(a[vertical ? 'x' : 'y'])
        .compareTo(number(b[vertical ? 'x' : 'y']));
    return primary != 0
        ? primary
        : number(a[vertical ? 'y' : 'x'])
              .compareTo(number(b[vertical ? 'y' : 'x']));
  });
  if (contacts.isNotEmpty) return contacts.first;
  if (fromCenter) {
    final width = number(p['room']['width']),
        height = number(p['room']['height']);
    final w = number(item['w']), h = number(item['h']);
    final xs = <double>{(width - w) / 2}, ys = <double>{(height - h) / 2};
    for (var x = max(.6, minX); x + w <= maxX + .000001; x += .2) {
      xs.add(x);
    }
    for (var y = .6; y + h <= height; y += .2) {
      ys.add(y);
    }
    if (wallSides(p).contains('left')) xs.add(0);
    if (wallSides(p).contains('right')) xs.add(width - w);
    if (wallSides(p).contains('top')) ys.add(0);
    if (wallSides(p).contains('bottom')) ys.add(height - h);
    final points = [
      for (final x in xs)
        for (final y in ys) (x, y),
    ];
    double distance((double, double) point) =>
        pow(point.$1 + w / 2 - width / 2, 2).toDouble() +
        pow(point.$2 + h / 2 - height / 2, 2).toDouble();
    points.sort((a, b) {
      final d = distance(a).compareTo(distance(b));
      if (d != 0) return d;
      final y = a.$2.compareTo(b.$2);
      return y != 0 ? y : a.$1.compareTo(b.$1);
    });
    for (final point in points) {
      final candidate = {...item, 'x': point.$1, 'y': point.$2};
      if (valid(candidate)) return candidate;
    }
    return null;
  }
  for (final edge in wallSides(p)) {
    if (fromCorner && edge != 'left' && edge != 'top') continue;
    for (
      var d = .6;
      d < max(number(p['room']['width']), number(p['room']['height']));
      d += .2
    ) {
      final candidate = {
        ...item,
        'x': edge == 'left'
            ? 0.0
            : edge == 'right'
            ? number(p['room']['width']) - number(item['w'])
            : d,
        'y': edge == 'top'
            ? 0.0
            : edge == 'bottom'
            ? number(p['room']['height']) - number(item['h'])
            : d,
      };
      if (item['kind'] == 'table' &&
          item['shape'] != 'cercle' &&
          valid(candidate)) {
        return candidate;
      }
    }
  }
  // Try exact edge-to-edge spacing before the fallback search grid.
  final gap = eventTableGap(p);
  for (final neighbor in others.where(
    (v) => !fromCorner && v['kind'] == 'table' && v['capacity'] != 0,
  )) {
    for (final pos in [
      (
        number(neighbor['x']) + number(neighbor['w']) + gap,
        number(neighbor['y']),
      ),
      (
        number(neighbor['x']),
        number(neighbor['y']) + number(neighbor['h']) + gap,
      ),
      (number(neighbor['x']) - number(item['w']) - gap, number(neighbor['y'])),
      (number(neighbor['x']), number(neighbor['y']) - number(item['h']) - gap),
    ]) {
      final candidate = {...item, 'x': pos.$1, 'y': pos.$2};
      if (valid(candidate)) return candidate;
    }
  }
  for (var y = .6; y < number(p['room']['height']); y += .2) {
    for (
      var x = max(.6, minX);
      x + number(item['w']) <= maxX + .000001;
      x += .2
    ) {
      final candidate = {...item, 'x': x, 'y': y};
      if (valid(candidate)) return candidate;
    }
  }
  return null;
}

Json snapToJoin(Json p, Json item, List<Json> others) {
  if (item['fixed'] == true || item['kind'] != 'table') {
    return item;
  }
  Json result = item;
  var distance = .14;
  for (final neighbor in others.where(
    (i) => i['id'] != item['id'] && i['kind'] == 'table',
  )) {
    for (final pos in tableJoinPositions(p, item, neighbor)) {
      final d = sqrt(
        pow(number(item['x']) - pos.$1, 2) + pow(number(item['y']) - pos.$2, 2),
      );
      final candidate = {...item, 'x': pos.$1, 'y': pos.$2};
      if (d < distance &&
          joinedEdges(p, candidate, neighbor) != null &&
          fits(p, candidate, others)) {
        distance = d;
        result = candidate;
      }
    }
  }
  for (final edge in wallSides(p)) {
    final candidate = {...item};
    if (edge == 'left') candidate['x'] = 0.0;
    if (edge == 'right') {
      candidate['x'] = number(p['room']['width']) - number(item['w']);
    }
    if (edge == 'top') candidate['y'] = 0.0;
    if (edge == 'bottom') {
      candidate['y'] = number(p['room']['height']) - number(item['h']);
    }
    final d = sqrt(
      pow(number(item['x']) - number(candidate['x']), 2) +
          pow(number(item['y']) - number(candidate['y']), 2),
    );
    if (item['shape'] != 'cercle' &&
        d < distance &&
        fits(p, candidate, others)) {
      distance = d;
      result = candidate;
    }
  }
  return result;
}

/// A detached snapshot shared by the plan, the table list and the result total.
/// No widgets read mutable group allocations from inside a cached layout callback.
List<Json> tableAssignments(Json p, [PlanGeometry? geometry]) {
  final geo = geometry ?? PlanGeometry(p, rows(p, 'items'));
  return tables(p).map((t) {
    final groups = <Json>[];
    for (final g in rows(p, 'groups')) {
      final count = (g['alloc'] as List)
          .where((a) => a['table'] == t['id'])
          .fold<int>(0, (s, a) => s + (a['count'] as int));
      if (count > 0) {
        groups.add({'id': g['id'], 'name': g['name'], 'count': count});
      }
    }
    return {
      'id': t['id'],
      'label': t['label'],
      'capacity': tableOutsideRoom(p, t)
          ? 0
          : max(0, geo.capacity(t) - (t['blockedSlots'] as List? ?? []).length),
      'occupied': groups.fold<int>(0, (s, g) => s + (g['count'] as int)),
      'groups': groups,
    };
  }).toList();
}

Json workspaceStats(Json p, [List<Json>? assignments]) {
  final ts = assignments ?? tableAssignments(p);
  final target = p['attendanceTarget'] as int?;
  final reserved = rows(p, 'groups').fold<int>(
    0,
    (s, g) =>
        s + (isStandBooking(g) || g['waiting'] == true ? 0 : g['count'] as int),
  );
  final capacity = ts.fold<int>(0, (s, t) => s + (t['capacity'] as int));
  final assigned = ts.fold<int>(0, (s, t) => s + (t['occupied'] as int));
  final free = ts.fold<int>(
    0,
    (s, t) => s + max(0, (t['capacity'] as int) - (t['occupied'] as int)),
  );
  final overbooked = ts.fold<int>(
    0,
    (s, t) => s + max(0, (t['occupied'] as int) - (t['capacity'] as int)),
  );
  return {
    'target': target,
    'reservations': rows(p, 'groups').length,
    'reserved': reserved,
    'capacity': capacity,
    'assigned': assigned,
    'free': free,
    'overbooked': overbooked,
    'alerts': <String>[
      if (target != null && reserved > target)
        'Effectif réservé supérieur à l’objectif de ${reserved - target} personne(s).',
      if (reserved > capacity)
        'Effectif réservé supérieur à la capacité utilisable de ${reserved - capacity} personne(s).',
      if (overbooked > 0)
        '$overbooked attribution(s) au-delà de la capacité de certaines tables : à corriger.',
    ],
  };
}

void clearReservations(Json p) => p['groups'] = <Json>[];
const roomClearChoices = <String, String>{
  'tables': 'Mobilier placé',
  'assignments': 'Assignations',
  'zones': 'Zones',
  'infos': 'Espaces informatifs',
  'texts': 'Textes',
  'images': 'Images',
  'arrows': 'Flèches',
  'access': 'Entrées, sorties et portes (PMR, secours…)',
  'obstacles': 'Obstacles et autres objets',
};

void clearRoom(
  Json p,
  Set<String> choices, {
  bool includeLocked = false,
  Set<String>? furnitureIds,
}) {
  final items = rows(p, 'items');
  final removed = items
      .where(
        (i) =>
            (choices.contains('tables') &&
                (furnitureIds == null || furnitureIds.contains(i['id'])) &&
                [
                  'table',
                  'banc',
                  'bench',
                  'chair',
                  'pmr',
                ].contains(i['kind'])) ||
            (choices.contains('zones') && i['kind'] == 'zone') ||
            (choices.contains('infos') && i['kind'] == 'info') ||
            (choices.contains('texts') && i['kind'] == 'text') ||
            (choices.contains('images') && i['kind'] == 'image') ||
            (choices.contains('arrows') && i['kind'] == 'arrow') ||
            (choices.contains('access') &&
                ['entry', 'exit', 'door'].contains(i['kind'])) ||
            (choices.contains('obstacles') &&
                !isPlanAnnotation(i) &&
                ![
                  'table',
                  'banc',
                  'bench',
                  'chair',
                  'pmr',
                  'zone',
                  'entry',
                  'exit',
                  'door',
                ].contains(i['kind'])),
      )
      .map((i) => i['id'])
      .toSet();
  if (!includeLocked) {
    removed.removeAll(
      items.where((i) => i['fixed'] == true).map((i) => i['id']),
    );
  }
  items.removeWhere((i) => removed.contains(i['id']));
  prunePlacePreferences(p);
  for (final group in rows(p, 'groups')) {
    final before = (group['alloc'] as List).length;
    (group['standAlloc'] as List?)?.removeWhere(
      (a) =>
          !tables(p).any((t) => t['id'] == a['table']) ||
          choices.contains('assignments') &&
              (includeLocked || group['locked'] != true),
    );
    (group['alloc'] as List).removeWhere(
      (a) =>
          (choices.contains('assignments') &&
              (includeLocked || group['locked'] != true)) ||
          removed.contains(a['table']),
    );
    for (final seat in (group['seats'] as List? ?? []).cast<Json>()) {
      if (removed.contains(seat['table']) ||
          choices.contains('assignments') &&
              (includeLocked ||
                  group['locked'] != true && seat['fixed'] != true)) {
        seat.remove('table');
        seat.remove('slot');
        seat.remove('fixed');
      }
    }
    if (removed.contains(group['reserved'])) group['reserved'] = '';
    if (before != (group['alloc'] as List).length ||
        (choices.contains('assignments') &&
            (includeLocked || group['locked'] != true))) {
      group['placementReview'] = true;
      if ((group['alloc'] as List).isEmpty) group['locked'] = false;
    }
  }
}

void removeReservation(Json p, String id) {
  rows(p, 'groups').removeWhere((g) => g['id'] == id);
  for (final g in rows(p, 'groups')) {
    if (g['separate'] == id) g['separate'] = '';
    (g['proximity'] as Map?)?.remove(id);
  }
}

void resizeReservation(Json group, int count, {int? previousCount}) {
  if (count < 1) {
    throw const FormatException(
      'Un groupe garde au moins une place ; supprimer le groupe pour tout retirer',
    );
  }
  final oldCount = previousCount ?? group['count'] as int;
  var budget = count;
  final kept = <Json>[];
  for (final a in (group['alloc'] as List).cast<Json>()) {
    final take = min(budget, a['count'] as int);
    if (take > 0) kept.add({...a, 'count': take});
    budget -= take;
  }
  group['alloc'] = kept;
  group['count'] = count;
  if (group['seats'] is List) {
    final seats = (group['seats'] as List)
        .cast<Json>()
        .take(count)
        .map(clone)
        .toList();
    for (var i = 0; i < seats.length; i++) {
      seats[i]['number'] = i + 1;
      final linked = int.tryParse('${seats[i]['companion'] ?? ''}');
      if (linked == null || linked < 1 || linked > count || linked == i + 1) {
        seats[i]['companion'] = '';
      }
    }
    group['seats'] = seats;
  }
  if (oldCount != count) group['placementReview'] = true;
}

void removeAnonymousPlace(Json group, int index) {
  final count = group['count'] as int;
  if (count <= 1) {
    throw const FormatException(
      'Supprimer le groupe pour retirer sa dernière place',
    );
  }
  if (index < 0 || index >= count) {
    throw const FormatException('Numéro de place invalide');
  }
  final existing = (group['seats'] as List? ?? []).cast<Json>();
  final seats = List<Json>.generate(
    count,
    (i) => i < existing.length
        ? clone(existing[i])
        : {
            'number': i + 1,
            'meal': group['meal'],
            'need': '',
            'allergy': '',
            'companion': '',
          },
  );
  seats.removeAt(index);
  for (final s in seats) {
    final linked = int.tryParse('${s['companion'] ?? ''}');
    if (linked == index + 1) {
      s['companion'] = '';
    } else if (linked != null && linked > index + 1) {
      s['companion'] = '${linked - 1}';
    }
  }
  group['seats'] = seats;
  resizeReservation(group, count - 1);
}

Json allocationSummary(Json p) {
  final geo = PlanGeometry(p, rows(p, 'items'));
  final requested = rows(p, 'groups').fold<int>(
    0,
    (s, g) =>
        s + (isStandBooking(g) || g['waiting'] == true ? 0 : g['count'] as int),
  );
  final assigned = tableAssignments(
    p,
    geo,
  ).fold<int>(0, (s, t) => s + (t['occupied'] as int));
  final excluded = tables(p)
      .where((t) => !fits(p, t, rows(p, 'items'), geometry: geo))
      .map((t) => t['label'])
      .toList();
  return {
    'requested': requested,
    'assigned': assigned,
    'remaining': max(0, requested - assigned),
    'excluded': excluded,
  };
}

class AddResult {
  final int placed, remaining;
  const AddResult(this.placed, this.remaining);
}

AddResult addFurniture(
  Json p,
  List<Json> types, {
  bool all = false,
  int? requestedCount,
}) {
  var placed = 0, remaining = 0;
  final items = rows(p, 'items');
  for (final type in types.where((t) => t['enabled'] == true)) {
    final available = max(
      0,
      min(type['quantity'] as int, type['limit'] as int) -
          items.where((i) => i['type'] == type['id']).length,
    );
    final requested = all
        ? available
        : min(available, max(0, requestedCount ?? 1));
    for (var n = 0; n < requested; n++) {
      final bench = type['shape'] == 'banc';
      final childChair = type['shape'] == 'chaise enfant';
      final chair = ['chaise', 'chaise enfant'].contains(type['shape']),
          pmr = type['shape'] == 'emplacement PMR';
      var labelNumber = bench
          ? items.where((i) => i['kind'] == 'bench').length + 1
          : chair
          ? items.where((i) => i['kind'] == 'chair').length + 1
          : tables(p).length + 1;
      String label() =>
          '${bench
              ? 'Banc '
              : chair
              ? (childChair ? 'CE' : 'C')
              : pmr
              ? 'PMR '
              : 'T'}$labelNumber';
      while (items.any((i) => furnitureShortLabel(i) == label())) {
        labelNumber++;
      }
      final item = {
        'id': uid(),
        'kind': bench
            ? 'bench'
            : chair
            ? 'chair'
            : pmr
            ? 'pmr'
            : 'table',
        'usage':
            type['usage'] ??
            (bench || chair || pmr
                ? furnitureUses.first
                : eventAssignmentMode(p) == assignmentModes[1]
                ? furnitureUses[1]
                : furnitureUses.first),
        'type': type['id'],
        'label': label(),
        'shape': type['shape'],
        'x': 1.0,
        'y': 1.0,
        'w': pmr
            ? max(number(type['w']), number(eventComfort(p)['pmrSeatWidth']))
            : type['w'],
        'h': pmr
            ? max(number(type['h']), number(eventComfort(p)['pmrDepth']))
            : type['h'],
        'capacity': chair || pmr ? 1 : type['capacity'],
        'fixed': false,
        'seating': type['seating'],
        'sides': type['sides'] ?? eventSeatingSides(p),
        'seatSide': type['seatSide'] ?? 'Bas',
      };
      final positioned = findPosition(p, item, items);
      if (positioned == null) {
        remaining += requested - n;
        break;
      }
      items.add(positioned);
      placed++;
    }
  }
  return AddResult(placed, remaining);
}

/// Apply only complete proposals: an unplaced table must never be left under
/// a table already moved by a partial proposal.
const arrangementCorners = [
  'Haut gauche',
  'Haut droite',
  'Bas gauche',
  'Bas droite',
  'Centre',
];

int arrange(Json p) {
  if (p['arrangementMode'] == 'Scène') {
    return arrangeAudience(
      p,
      Map<String, dynamic>.from(p['audienceSettings'] as Map? ?? {}),
    );
  }
  if (parcoursActive(p)) return arrangeParcours(p);
  clearParcoursLayout(p);
  final corner = p['arrangementCorner'] ?? arrangementCorners.first;
  final right = corner == 'Haut droite' || corner == 'Bas droite';
  final bottom = corner == 'Bas gauche' || corner == 'Bas droite';
  final working = clone(p);
  final width = number(p['room']['width']),
      height = number(p['room']['height']);
  for (final item in rows(working, 'items')) {
    final originalGaps = {
      for (final e in ['left', 'right', 'top', 'bottom'])
        e: tableJoinEdgeGap(p, item, e),
    };
    item['_joinEdgeGaps'] = {
      'left': originalGaps[right ? 'right' : 'left'],
      'right': originalGaps[right ? 'left' : 'right'],
      'top': originalGaps[bottom ? 'bottom' : 'top'],
      'bottom': originalGaps[bottom ? 'top' : 'bottom'],
    };

    if (item['sides'] == 'Un côté') {
      item['seatSide'] ??= number(item['w']) >= number(item['h'])
          ? 'Bas'
          : 'Droite';
    }
    if (right) {
      item['x'] = width - number(item['x']) - number(item['w']);
      item['seatSide'] = switch (item['seatSide']) {
        'Gauche' => 'Droite',
        'Droite' => 'Gauche',
        _ => item['seatSide'],
      };
    }
    if (bottom) {
      item['y'] = height - number(item['y']) - number(item['h']);
      item['seatSide'] = switch (item['seatSide']) {
        'Haut' => 'Bas',
        'Bas' => 'Haut',
        _ => item['seatSide'],
      };
    }
  }
  if (right) {
    working['wallSupport'] = switch (working['wallSupport']) {
      'Mur gauche' => 'Mur droit',
      'Mur droit' => 'Mur gauche',
      _ => working['wallSupport'],
    };
  }
  if (bottom) {
    working['wallSupport'] = switch (working['wallSupport']) {
      'Mur haut' => 'Mur bas',
      'Mur bas' => 'Mur haut',
      _ => working['wallSupport'],
    };
  }
  final polygon = roomPolygon(p['room']);
  if (polygon.isNotEmpty) {
    working['room']['polygon'] = polygon
        .map(
          (point) =>
              '${right ? width - point.x : point.x},${bottom ? height - point.y : point.y}',
        )
        .join(';');
  }
  _arrangeFromTopLeft(working);
  final proposed = {for (final item in tables(working)) item['id']: item};
  final result = clone(p);
  for (final item in tables(result)) {
    if (item['fixed'] == true || item['capacity'] == 0) continue;
    final point = proposed[item['id']]!;
    if (point['unplacedByArrangement'] == true) {
      item['unplacedByArrangement'] = true;
      continue;
    }
    item.remove('unplacedByArrangement');
    item['x'] = right
        ? width - number(point['x']) - number(item['w'])
        : point['x'];
    item['y'] = bottom
        ? height - number(point['y']) - number(item['h'])
        : point['y'];
  }
  _parkUnplacedTables(result);
  final geometry = PlanGeometry(result, rows(result, 'items'));
  final invalid = tables(result)
      .where(
        (item) =>
            item['fixed'] != true &&
            item['capacity'] != 0 &&
            !unplacedTable(result, item) &&
            !fits(result, item, rows(result, 'items'), geometry: geometry),
      )
      .toList();
  for (final item in invalid) {
    item['unplacedByArrangement'] = true;
  }
  if (invalid.isNotEmpty) _parkUnplacedTables(result);
  final originals = {for (final item in tables(p)) item['id']: item};
  for (final item in tables(result)) {
    if (item['fixed'] == true || item['capacity'] == 0) continue;
    originals[item['id']]!['x'] = item['x'];
    originals[item['id']]!['y'] = item['y'];
    if (item['unplacedByArrangement'] == true) {
      originals[item['id']]!['unplacedByArrangement'] = true;
    } else {
      originals[item['id']]!.remove('unplacedByArrangement');
    }
  }
  return tables(result).where((t) => unplacedTable(result, t)).length;
}

void parkUnplacedTables(Json p) => _parkUnplacedTables(p);

void _parkUnplacedTables(Json p) {
  final pending = tables(p)
      .where(
        (t) =>
            t['unplacedByArrangement'] == true &&
            t['fixed'] != true &&
            t['capacity'] != 0,
      )
      .toList();
  final width = number(p['room']['width']),
      height = number(p['room']['height']);
  var x = width + max(.6, eventTableGap(p)), y = .6, columnWidth = 0.0;
  for (final table in pending) {
    final w = number(table['w']), h = number(table['h']);
    if (y > .6 && y + h > height) {
      x += columnWidth + max(.6, eventTableGap(p));
      y = .6;
      columnWidth = 0;
    }
    var candidate = {...table, 'x': x, 'y': y};
    while (rows(p, 'items').any(
      (i) =>
          i['id'] != table['id'] &&
          !pending.contains(i) &&
          overlaps(candidate, i, .3),
    )) {
      x += w + .6;
      candidate = {...table, 'x': x, 'y': y};
    }
    table['x'] = x;
    table['y'] = y;
    columnWidth = max(columnWidth, w);
    y += h + max(.6, eventTableGap(p));
  }
}

/// Natural label order: C2 precedes C10, independently of inventory order.
int compareFurnitureNumbers(Json a, Json b) {
  final left = RegExp(r'\d+|\D+')
      .allMatches(furnitureShortLabel(a))
      .map((m) => m.group(0)!)
      .toList();
  final right = RegExp(r'\d+|\D+')
      .allMatches(furnitureShortLabel(b))
      .map((m) => m.group(0)!)
      .toList();
  for (var i = 0; i < min(left.length, right.length); i++) {
    final x = int.tryParse(left[i]), y = int.tryParse(right[i]);
    final order = x != null && y != null
        ? x.compareTo(y)
        : left[i].toLowerCase().compareTo(right[i].toLowerCase());
    if (order != 0) return order;
  }
  final length = left.length.compareTo(right.length);
  return length != 0
      ? length
      : a['id'].toString().compareTo(b['id'].toString());
}

int _arrangeFromTopLeft(Json p) {
  final originals = tables(p);
  final placed = physicalPlanItems(p)
      .where(
        (v) =>
            !isSeatingFurniture(v) ||
            v['fixed'] == true ||
            furnitureUse(v) == 'Service',
      )
      .map((v) => Map<String, dynamic>.from(v))
      .toList();
  final proposals = <String, Json>{};
  var failed = 0;
  final movable = originals
      .where((v) => v['fixed'] != true && furnitureUse(v) != 'Service')
      .toList();
  movable.sort((a, b) {
    final standOrder = (furnitureUse(b) == furnitureUses[1] ? 1 : 0).compareTo(
      furnitureUse(a) == furnitureUses[1] ? 1 : 0,
    );
    if (standOrder != 0) return standOrder;
    if (furnitureUse(a) == furnitureUses[1] &&
        furnitureUse(b) == furnitureUses[1]) {
      final model = compareStandModels(a, b);
      if (model != 0) return model;
    }
    final area = (number(b['w']) * number(b['h'])).compareTo(
      number(a['w']) * number(a['h']),
    );
    return area != 0 ? area : compareFurnitureNumbers(a, b);
  });
  for (final t in movable) {
    final candidate = findPosition(
      p,
      t,
      placed,
      fromCorner: proposals.isEmpty && p['arrangementCorner'] != null,
      fromCenter: p['arrangementCorner'] == 'Centre',
    );
    if (candidate == null) {
      failed++;
    } else {
      proposals[t['id'] as String] = candidate;
      placed.add(candidate);
    }
  }
  for (final t in originals) {
    final candidate = proposals[t['id']];
    if (candidate != null) {
      t['x'] = candidate['x'];
      t['y'] = candidate['y'];
      t.remove('unplacedByArrangement');
    } else if (t['fixed'] != true && t['capacity'] != 0) {
      t['unplacedByArrangement'] = true;
    }
  }
  return failed;
}

/// Manual collective rotation keeps each table centre and its assignments.
/// Any resulting clearance conflict remains visible and can be undone.
void rotateTables(Json p) {
  for (final t in tables(p)) {
    rotateTable(t, p);
  }
}

void rotateTable(Json t, [Json? p]) {
  if (isPlanAnnotation(t)) {
    t['angle'] = (number(t['angle']) + 90) % 360;
    return;
  }
  if (t['audienceLayout'] == true || number(t['angle']) != 0) {
    t['angle'] = (number(t['angle']) + 90) % 360;
    return;
  }
  if (t['rotation'] == null && p != null) {
    final types = rows(p, 'types').where((type) => type['id'] == t['type']);
    if (types.isNotEmpty) {
      final type = types.first;
      t['rotation'] =
          (number(t['w']) < number(t['h'])) !=
              (number(type['w']) < number(type['h']))
          ? 90
          : 0;
    }
  }
  final w = number(t['w']), h = number(t['h']);
  t['x'] = number(t['x']) + (w - h) / 2;
  t['y'] = number(t['y']) + (h - w) / 2;
  t['w'] = h;
  t['h'] = w;
  if (t['sides'] == 'Un côté') {
    t['seatSide'] = rotateSeatingSide(t['seatSide'] ?? 'Bas', 90);
  }
  t['rotation'] = ((t['rotation'] as int? ?? 0) + 90) % 360;
}

bool propagateFurniture(Json p, Json oldType, Json newType) {
  var resized = false;
  final dimensionsChanged =
      oldType['w'] != newType['w'] ||
      oldType['h'] != newType['h'] ||
      oldType['shape'] != newType['shape'];
  for (final item in rows(
    p,
    'items',
  ).where((i) => i['type'] == newType['id'])) {
    final rotated = item['rotation'] != null
        ? (item['rotation'] as int) % 180 == 90
        : (number(item['w']) < number(item['h'])) !=
              (number(oldType['w']) < number(oldType['h']));
    if (dimensionsChanged) {
      final w = rotated ? newType['h'] : newType['w'];
      final h = rotated ? newType['w'] : newType['h'];
      resized = resized || item['w'] != w || item['h'] != h;
      item['w'] = w;
      item['h'] = h;
      item['rotation'] ??= rotated ? 90 : 0;
    }
    if (oldType['shape'] != newType['shape']) {
      item['kind'] = switch (newType['shape']) {
        'banc' => 'bench',
        'chaise' || 'chaise enfant' => 'chair',
        'emplacement PMR' => 'pmr',
        _ => 'table',
      };
    }
    for (final key in ['capacity', 'shape', 'seating']) {
      item[key] = newType[key];
    }
    if (dimensionsChanged) {
      for (final g in rows(p, 'groups')) {
        final allocations = (g['standAlloc'] as List? ?? []);
        for (final a in allocations.where((a) => a['table'] == item['id'])) {
          if (a['whole'] == true) {
            a['offset'] = 0.0;
            a['length'] = standLength(item);
          } else if (number(a['offset']) + number(a['length']) >
              standLength(item)) {
            a['length'] = max(0, standLength(item) - number(a['offset']));
            g['placementReview'] = true;
          }
        }
        allocations.removeWhere(
          (a) => a['table'] == item['id'] && number(a['length']) <= 0,
        );
      }
    }
    if (newType['sides'] != null) item['sides'] = newType['sides'];
    if (newType['seatSide'] != null) {
      item['seatSide'] = rotateSeatingSide(
        newType['seatSide'],
        item['rotation'] as int? ?? (rotated ? 90 : 0),
      );
    }
  }
  final affected = tables(p).where((i) => i['type'] == newType['id']).toList();
  final usage =
      [
        'chaise',
        'chaise enfant',
        'banc',
        'emplacement PMR',
      ].contains(newType['shape'])
      ? furnitureUses.first
      : newType['usage'];
  if (usage != null) {
    // Apply the confirmed model usage and remove only incompatible allocations.
    changeFurnitureUsage(
      p,
      affected.map((i) => i['id'] as String).toSet(),
      usage,
    );
  }
  return resized;
}

bool canResizePlanObject(Json item) =>
    ['zone', 'entry', 'exit', 'door'].contains(item['kind']) &&
    item['fixed'] != true;

/// Stable visual layering, without changing saved objects or collision checks.
List<Json> planPaintOrder(Json p) {
  final background = physicalPlanItems(p)
      .where((i) => !isSeatingFurniture(i))
      .toList();
  final zones = background.where((i) => i['kind'] == 'zone').toList();
  final positions = {for (var i = 0; i < zones.length; i++) zones[i]['id']: i};
  zones.sort((a, b) {
    final invisible = (a['zoneFill'] == 'Invisible' ? 0 : 1).compareTo(
      b['zoneFill'] == 'Invisible' ? 0 : 1,
    );
    return invisible != 0
        ? invisible
        : positions[a['id']]!.compareTo(positions[b['id']]!);
  });
  var zi = 0;
  final result = <Json>[
    ...rows(p, 'items').where((i) => i['kind'] == 'image'),
    ...rows(p, 'items').where((i) => i['kind'] == 'info'),
    for (final item in background)
      if (item['kind'] == 'zone') zones[zi++] else item,
    ...rows(p, 'items').where(isSeatingFurniture),
    ...rows(p, 'items').where((i) => i['kind'] == 'arrow'),
    ...rows(p, 'items').where((i) => i['kind'] == 'text'),
  ];
  final saved = p['planLayerOrder'];
  if (saved is List) {
    final rank = {for (var n = 0; n < saved.length; n++) saved[n]: n};
    final fallback = {
      for (var n = 0; n < result.length; n++) result[n]['id']: saved.length + n,
    };
    result.sort(
      (a, b) => (rank[a['id']] ?? fallback[a['id']]!).compareTo(
        rank[b['id']] ?? fallback[b['id']]!,
      ),
    );
  }
  return result;
}

void resizeZone(
  Json p,
  Json item,
  Json origin,
  double dx,
  double dy,
  String corner, {
  bool preserveAspect = false,
}) {
  if (!canResizePlanObject(item)) return;
  if (number(origin['angle']) != 0 || preserveAspect) {
    final preview = {...item};
    if (resizeRotatedBox(
          preview,
          origin,
          dx,
          dy,
          corner.contains('right'),
          corner.contains('bottom'),
          preserveAspect: preserveAspect,
        ) &&
        furnitureCorners(preview).every(
          (v) =>
              v.x >= 0 &&
              v.y >= 0 &&
              v.x <= number(p['room']['width']) &&
              v.y <= number(p['room']['height']),
        )) {
      item.addAll(preview);
    }
    return;
  }

  final left = corner.contains('left'), top = corner.contains('top');
  final right = number(origin['x']) + number(origin['w']);
  final bottom = number(origin['y']) + number(origin['h']);
  final x = left
      ? (number(origin['x']) + dx).clamp(0.0, right - .2)
      : number(origin['x']);
  final y = top
      ? (number(origin['y']) + dy).clamp(0.0, bottom - .2)
      : number(origin['y']);
  var w = left
      ? right - x
      : (number(origin['w']) + dx).clamp(
          .2,
          max(.2, number(p['room']['width']) - x),
        );
  var h = top
      ? bottom - y
      : (number(origin['h']) + dy).clamp(
          .2,
          max(.2, number(p['room']['height']) - y),
        );
  if (['cercle', 'carré'].contains(item['shape'])) {
    w = h = min(w, h);
  }
  item['x'] = left ? right - w : x;
  item['y'] = top ? bottom - h : y;
  item['w'] = w;
  item['h'] = h;
}

enum PlanMarkerShape { circle, hexagon, triangle, square }

PlanMarkerShape planMarkerShape(String name) => switch (name) {
  'Mobilité / PMR' || 'Emplacement adapté' => PlanMarkerShape.hexagon,
  'Allergie' => PlanMarkerShape.triangle,
  'Chaise enfant' => PlanMarkerShape.square,
  _ => PlanMarkerShape.circle,
};

List<Point<double>> planMarkerVertices(PlanMarkerShape shape) =>
    switch (shape) {
      PlanMarkerShape.hexagon => const [
        Point(.25, 0.0),
        Point(.75, 0.0),
        Point(1.0, .5),
        Point(.75, 1.0),
        Point(.25, 1.0),
        Point(0.0, .5),
      ],
      PlanMarkerShape.triangle => const [
        Point(.5, 0.0),
        Point(1.0, 1.0),
        Point(0.0, 1.0),
      ],
      PlanMarkerShape.square => const [
        Point(0.0, 0.0),
        Point(1.0, 0.0),
        Point(1.0, 1.0),
        Point(0.0, 1.0),
      ],
      PlanMarkerShape.circle => const [],
    };

Map<String, int> planMarkerColors(Json p) {
  final names = <String>{
    'Mobilité / PMR',
    if (mealsEnabled(p)) 'Allergie',
    ...mealTotals(p).keys.map((meal) => 'Repas : $meal'),
    ...tables(p).expand((table) => tableMarkers(p, table['id'])),
  }.toList();
  const fixed = {
    'Mobilité / PMR': 0xff6a1b9a,
    'Chaise enfant': 0xffad1457,
    'Allergie': 0xffb71c1c,
    'Emplacement adapté': 0xff00838f,
    'Repas : Normal': 0xff1565c0,
    'Repas : Végétarien': 0xff2e7d32,
    'Repas : Sans gluten': 0xffef6c00,
    'Repas : Ne mange pas': 0xff37474f,
  };
  const custom = [
    0xffc2185b,
    0xff00acc1,
    0xffb79500,
    0xff6d4c41,
    0xff455a64,
    0xff7cb342,
    0xff5c6bc0,
    0xffd84315,
  ];
  var index = 0;
  final used = fixed.values.toSet();
  int nextCustomColor() {
    while (true) {
      final color = index < custom.length
          ? custom[index]
          : 0xff000000 | (((index * 0x9e3779) & 0x7f7f7f) + 0x303030);
      index++;
      if (used.add(color)) return color;
    }
  }

  return {for (final name in names) name: fixed[name] ?? nextCustomColor()};
}

Set<String> tableMarkers(Json p, String id) {
  final markers = <String>{};
  final matching = tables(p).where((t) => t['id'] == id);
  if (matching.isNotEmpty && adaptedPlaces(matching.first).isNotEmpty) {
    markers.add('Emplacement adapté');
  }
  final seats = <Json>[];
  for (final group in rows(p, 'groups')) {
    for (final index in groupTablePeople(group)[id] ?? <int>[]) {
      seats.add(individualSeat(group, index));
      if (index < (group['childChairs'] as int? ?? 0)) {
        markers.add('Chaise enfant');
      }
    }
  }
  for (final seat in seats) {
    if ((seat['need'] ?? '').toString().trim().isNotEmpty) {
      markers.add('Mobilité / PMR');
    }
    if (mealsEnabled(p) &&
        (seat['allergy'] ?? '').toString().trim().isNotEmpty) {
      markers.add('Allergie');
    }
    if (mealsEnabled(p) && (seat['meal'] ?? '').toString().isNotEmpty) {
      markers.add('Repas : ${seat['meal']}');
    }
  }
  return markers;
}

String reservationSpecialNeeds(Json group) {
  final counts = <String, int>{};
  for (var i = 0; i < group['count']; i++) {
    final need = (individualSeat(group, i)['need'] ?? '').toString().trim();
    if (need.isEmpty) continue;
    final label = need == 'Fauteuil' ? 'Fauteuil roulant' : need;
    counts[label] = (counts[label] ?? 0) + 1;
  }
  final children = group['childChairs'] as int? ?? 0;
  return [
    for (final entry in counts.entries) '${entry.key} : ${entry.value}',
    if (children > 0) 'Chaise enfant : $children',
  ].join('\n');
}

Map<String, String> reservationPreferences(Json p, Json group) {
  final result = <String, String>{};
  final ids = rows(p, 'groups').map((g) => g['id']).toSet();
  for (final entry in (group['proximity'] as Map? ?? {}).entries) {
    if (ids.contains(entry.key) && entry.key != group['id']) {
      result[entry.key as String] = entry.value as String;
    }
  }
  for (final other in rows(p, 'groups')) {
    final mode = (other['proximity'] as Map? ?? {})[group['id']];
    if (mode != null && other['id'] != group['id']) {
      result[other['id'] as String] = mode as String;
    }
  }
  return result;
}

void setReservationPreference(
  Json p,
  Json group,
  String otherId,
  String? mode,
) {
  if (otherId == group['id'] ||
      !rows(p, 'groups').any((g) => g['id'] == otherId)) {
    throw const FormatException('Choisir une autre réservation existante');
  }
  if (mode != null && !['near', 'far'].contains(mode)) {
    throw const FormatException('Préférence invalide');
  }
  for (final other in rows(p, 'groups').where((g) => g['id'] == otherId)) {
    (other['proximity'] as Map?)?.remove(group['id']);
  }
  final preferences = Map<String, dynamic>.from(
    group['proximity'] as Map? ?? {},
  );
  preferences.remove(otherId);
  if (mode != null) preferences[otherId] = mode;
  group['proximity'] = preferences;
}

double tableDistance(Json a, Json b) => sqrt(
  pow(
        number(a['x']) +
            number(a['w']) / 2 -
            number(b['x']) -
            number(b['w']) / 2,
        2,
      ) +
      pow(
        number(a['y']) +
            number(a['h']) / 2 -
            number(b['y']) -
            number(b['h']) / 2,
        2,
      ),
);
List<Json> assignedTables(Json p, Json group) {
  final ids = {
    ...(group['alloc'] as List)
        .where((a) => a['count'] > 0)
        .map((a) => a['table']),
    ...(group['standAlloc'] as List? ?? []).map((a) => a['table']),
  };
  return tables(p).where((t) => ids.contains(t['id'])).toList();
}

double farPreferenceDistance(Json p) =>
    sqrt(
      pow(number(p['room']['width']), 2) + pow(number(p['room']['height']), 2),
    ) /
    2;
double preferenceScore(Json p, Json group, Json table) {
  var score = 0.0;
  final preferences = reservationPreferences(p, group);
  for (final other in rows(p, 'groups')) {
    final mode = preferences[other['id']];
    if (mode == null) continue;
    final positions = assignedTables(p, other);
    if (positions.isEmpty) continue;
    final distance = positions.map((t) => tableDistance(table, t)).reduce(min);
    score += mode == 'near' ? distance : -2 * distance;
  }
  for (final preference in reservationPlacePreferences(group).entries) {
    final places = proximityPlaces(p, preference.key);
    if (places.isEmpty || !accessCompatible(p, places.single, group)) continue;
    final distance = places
        .map((place) => tableDistance(table, place))
        .reduce(min);
    score += preference.value == 'near' ? distance : -2 * distance;
  }
  return score;
}

void allocate(Json p) {
  if (rows(p, 'groups').any((g) => g['waiting'] == true)) {
    final original = rows(p, 'groups');
    p['groups'] = original.where((g) => g['waiting'] != true).toList();
    try {
      allocate(p);
    } finally {
      p['groups'] = original;
    }
    return;
  }
  allocateStands(p);
  if (freeSeating(p)) return;
  if (tables(p).any((t) => t['kind'] != 'table' || t['blockedSlots'] != null)) {
    allocateNumberedSeats(p);
    return;
  }
  final ts =
      tables(p).where((t) => furnitureUse(t) == 'Places assises').toList()
        ..sort((a, b) {
          final row = (number(a['y']) / 1.5).floor().compareTo(
            (number(b['y']) / 1.5).floor(),
          );
          return row == 0 ? number(a['x']).compareTo(number(b['x'])) : row;
        });
  for (final g in rows(
    p,
    'groups',
  ).where((g) => g['locked'] != true && !isStandBooking(g))) {
    g['alloc'] = <Json>[];
  }
  final gs =
      rows(
          p,
          'groups',
        ).where((g) => g['locked'] != true && !isStandBooking(g)).toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
  if (ts.any((t) => adaptedPlaces(t).isNotEmpty)) {
    int mobility(Json g) => List.generate(
      g['count'],
      (i) => individualSeat(g, i),
    ).where((s) => s['need'] == 'Fauteuil').length;
    gs.sort((a, b) {
      final priority = mobility(b).compareTo(mobility(a));
      return priority == 0
          ? (b['count'] as int).compareTo(a['count'] as int)
          : priority;
    });
  }
  final geo = PlanGeometry(p, rows(p, 'items'));
  final usable = ts
      .where((t) => fits(p, t, rows(p, 'items'), geometry: geo))
      .toList();
  final used = {for (final t in ts) t['id']: occupancy(p, t['id'])};
  final preferences = {
    for (final g in rows(p, 'groups')) g['id']: reservationPreferences(p, g),
  };
  final groupsById = {for (final g in rows(p, 'groups')) g['id']: g};
  final ranks = {for (var i = 0; i < gs.length; i++) gs[i]['id']: i};
  final hasPreferences =
      preferences.values.any((v) => v.isNotEmpty) ||
      gs.any((g) => reservationPlacePreferences(g).isNotEmpty);
  while (gs.isNotEmpty) {
    if (hasPreferences) {
      int linksToPlaced(Json group) =>
          preferences[group['id']]!.keys
              .where((id) => (groupsById[id]!['alloc'] as List).isNotEmpty)
              .length +
          reservationPlacePreferences(group).keys
              .where(
                (id) => groupProximityTargets(
                  p,
                  group,
                ).any((item) => item['id'] == id),
              )
              .length;
      gs.sort((a, b) {
        final linked = linksToPlaced(b).compareTo(linksToPlaced(a));
        if (linked != 0) return linked;
        final degree = preferences[b['id']]!.length.compareTo(
          preferences[a['id']]!.length,
        );
        if (degree != 0) return degree;
        final count = (b['count'] as int).compareTo(a['count'] as int);
        return count != 0 ? count : ranks[a['id']]!.compareTo(ranks[b['id']]!);
      });
    }
    final g = gs.removeAt(0);
    var left = g['count'] as int;
    final forbidden = <String>{};
    for (final other in rows(
      p,
      'groups',
    ).where((v) => v['id'] == g['separate'] || v['separate'] == g['id'])) {
      forbidden.addAll(
        (other['alloc'] as List).map((a) => a['table'] as String),
      );
    }
    final allowed = usable
        .where(
          (t) =>
              (g['reserved'] == null ||
                  g['reserved'] == '' ||
                  t['id'] == g['reserved']) &&
              !forbidden.contains(t['id']),
        )
        .toList();
    final wheelchair = List.generate(
      g['count'],
      (i) => individualSeat(g, i),
    ).where((s) => s['need'] == 'Fauteuil').length;
    if (wheelchair > 0) {
      final ranks = {
        for (var i = 0; i < allowed.length; i++) allowed[i]['id']: i,
      };
      int availableAdapted(Json t) {
        final people = tablePeople(p, t, geo);
        return adaptedPlaces(t)
            .where(
              (place) =>
                  place['slot'] < people.length &&
                  people[place['slot']] == null,
            )
            .length;
      }

      allowed.sort((a, b) {
        final score = min(
          wheelchair,
          availableAdapted(b),
        ).compareTo(min(wheelchair, availableAdapted(a)));
        return score == 0 ? ranks[a['id']]!.compareTo(ranks[b['id']]!) : score;
      });
    }
    if (preferences[g['id']]!.isNotEmpty ||
        reservationPlacePreferences(g).isNotEmpty) {
      final scores = {
        for (final t in allowed) t['id']: preferenceScore(p, g, t),
      };
      final initialOrder = {
        for (var i = 0; i < allowed.length; i++) allowed[i]['id']: i,
      };
      allowed.sort((a, b) {
        final score = scores[a['id']]!.compareTo(scores[b['id']]!);
        return score != 0
            ? score
            : initialOrder[a['id']]!.compareTo(initialOrder[b['id']]!);
      });
    }
    if (groupHasPmr(g) && eventComfort(p)['preferMainAisles'] == 'Oui') {
      final guides = mainAisleGuides(p);
      final mobility =
          List.generate(g['count'] as int, (i) => individualSeat(g, i))
              .where(
                (seat) => (seat['need'] ?? '').toString().trim().isNotEmpty,
              )
              .length;
      final scores = <String, double>{};
      for (final t in allowed) {
        final slots = adaptedPlaces(t).isEmpty
            ? List.generate(geo.capacity(t), (i) => i)
            : adaptedPlaces(t).map((place) => place['slot'] as int).toList();
        scores[t['id']] = slots.isEmpty
            ? double.infinity
            : slots
                  .map((slot) => pmrPlaceDistance(p, t, slot, guides, geo))
                  .reduce(min);
      }
      final order = {
        for (var i = 0; i < allowed.length; i++) allowed[i]['id']: i,
      };
      int available(Json t) => adaptedPlaces(t)
          .where(
            (place) =>
                place['slot'] < geo.capacity(t) &&
                tablePeople(p, t, geo)[place['slot']] == null,
          )
          .length;
      final free = {
        for (final t in allowed) t['id']: min(mobility, available(t)),
      };
      allowed.sort((a, b) {
        final adapted = free[b['id']]!.compareTo(free[a['id']]!);
        if (adapted != 0) return adapted;
        final distance = scores[a['id']]!.compareTo(scores[b['id']]!);
        return distance != 0
            ? distance
            : order[a['id']]!.compareTo(order[b['id']]!);
      });
    }
    final whole = allowed
        .where((t) => geo.capacity(t) - used[t['id']]! >= left)
        .toList();
    final order = whole.isNotEmpty
        ? [whole.first, ...allowed.where((t) => t != whole.first)]
        : allowed;
    for (final t in order) {
      final take = min(left, max(0, geo.capacity(t) - used[t['id']]!));
      if (take > 0) {
        (g['alloc'] as List).add({'table': t['id'], 'count': take});
        used[t['id']] = used[t['id']]! + take;
        left -= take;
      }
      if (left == 0) break;
    }
    if (left == 0) g['placementReview'] = false;
  }
}

Map<String, int> mealTotals(Json p) {
  if (!mealsEnabled(p)) return {};
  final totals = {for (final m in p['meals']) m as String: 0};
  for (final g in rows(p, 'groups')) {
    final seats = (g['seats'] as List? ?? []).cast<Json>();
    for (var i = 0; i < g['count']; i++) {
      final meal = i < seats.length
          ? seats[i]['meal'] as String
          : g['meal'] as String;
      totals[meal] = (totals[meal] ?? 0) + 1;
    }
  }
  return totals;
}

List<Point<double>> placeLabelPositions(
  Json table,
  int count,
  Set<String> blocked,
) {
  final positions = <Point<double>>[];
  if (count == 0) return positions;
  if (table['kind'] != 'table') {
    return List.generate(
      count,
      (i) => number(table['w']) >= number(table['h'])
          ? Point(number(table['w']) * (i + .5) / count, number(table['h']) / 2)
          : Point(
              number(table['w']) / 2,
              number(table['h']) * (i + .5) / count,
            ),
    );
  }
  final width = number(table['w']), height = number(table['h']);
  final turns = ((table['rotation'] as int? ?? 0) ~/ 90) % 4;
  if (turns != 0) {
    const names = ['top', 'right', 'bottom', 'left'];
    final original = {
      ...table,
      'rotation': 0,
      'w': turns.isOdd ? height : width,
      'h': turns.isOdd ? width : height,
    };
    if (table['sides'] == 'Un côté') {
      original['seatSide'] = rotateSeatingSide(
        table['seatSide'] ?? 'Bas',
        (4 - turns) * 90,
      );
    }
    final previousBlocked = blocked
        .map((edge) => names[(names.indexOf(edge) + 4 - turns) % 4])
        .toSet();
    for (final point in placeLabelPositions(original, count, previousBlocked)) {
      var x = point.x,
          y = point.y,
          w = number(original['w']),
          h = number(original['h']);
      for (var turn = 0; turn < turns; turn++) {
        final oldX = x;
        x = h - y;
        y = oldX;
        final oldW = w;
        w = h;
        h = oldW;
      }
      positions.add(Point(x, y));
    }
    return positions;
  }
  if (table['shape'] == 'cercle' && table['sides'] != 'Un côté') {
    for (var i = 0; i < count; i++) {
      final angle = 2 * pi * i / count;
      positions.add(
        Point(
          width / 2 + (width / 2 + .25) * cos(angle),
          height / 2 + (height / 2 + .25) * sin(angle),
        ),
      );
    }
    return positions;
  }
  final edges = seatedEdges(table).entries
      .where((edge) => !blocked.contains(edge.key))
      .toList();
  if (edges.isEmpty) return positions;
  final total = edges.fold<double>(0, (sum, edge) => sum + edge.value);
  final counts = edges
      .map((edge) => (count * edge.value / total).floor())
      .toList();
  var left = count - counts.fold<int>(0, (sum, value) => sum + value);
  final remainder = List.generate(edges.length, (i) => i)
    ..sort(
      (a, b) => (count * edges[b].value / total - counts[b]).compareTo(
        count * edges[a].value / total - counts[a],
      ),
    );
  for (final index in remainder) {
    if (left-- > 0) counts[index]++;
  }
  if (adaptedPlaces(table).isNotEmpty) {
    final widths = List.generate(count, (slot) {
      final match = adaptedPlaces(table)
          .where((place) => place['slot'] == slot);
      return match.isEmpty
          ? number(table['_seatWidth'], .6)
          : number(match.first['width'], .9);
    });
    // Partition consecutive numbered places across the available seated edges.
    // Prefer the usual distribution, while leaving the configured widths intact.
    var states = <int, (double, List<int>)>{0: (0, <int>[])};
    for (var edge = 0; edge < edges.length; edge++) {
      final next = <int, (double, List<int>)>{};
      for (final state in states.entries) {
        var extent = 0.0;
        for (var take = 0; take <= count - state.key; take++) {
          if (take > 0) extent += widths[state.key + take - 1];
          if (extent > edges[edge].value + .000001) break;
          final end = state.key + take,
              cost = state.value.$1 + pow(take - counts[edge], 2);
          if (!next.containsKey(end) || cost < next[end]!.$1) {
            next[end] = (cost.toDouble(), [...state.value.$2, take]);
          }
        }
      }
      states = next;
    }
    final proposal = states[count];
    if (proposal != null) {
      for (var edge = 0; edge < counts.length; edge++) {
        counts[edge] = proposal.$2[edge];
      }
    }
  }
  for (var edge = 0; edge < edges.length; edge++) {
    final firstSlot = positions.length;
    final widths = List.generate(counts[edge], (i) {
      final matching = adaptedPlaces(table)
          .where((place) => place['slot'] == firstSlot + i);
      return matching.isEmpty
          ? number(table['_seatWidth'], .6)
          : number(matching.first['width'], .9);
    });
    final extent = widths.fold<double>(0, (sum, width) => sum + width);
    var consumed = 0.0;
    for (var i = 0; i < counts[edge]; i++) {
      final fraction = (consumed + widths[i] / 2) / extent;
      consumed += widths[i];
      positions.add(switch (edges[edge].key) {
        'top' => Point(width * fraction, -.25),
        'bottom' => Point(width * fraction, height + .25),
        'left' => Point(-.25, height * fraction),
        _ => Point(width + .25, height * fraction),
      });
    }
  }
  return positions;
}

List<String?> tablePlaceLabels(Json p, Json table, [PlanGeometry? geometry]) {
  return tablePeople(p, table, geometry)
      .map(
        (person) => person == null
            ? null
            : (person['seat']['name'] ?? '').toString().trim().isEmpty
            ? person['group']['name'] as String
            : person['seat']['name'] as String,
      )
      .toList();
}

List<Json> adaptedPlaces(Json table) =>
    (table['adaptedPlaces'] as List? ?? []).cast<Json>();

Json individualSeat(Json group, int index) {
  final seats = (group['seats'] as List? ?? []).cast<Json>();
  return {
    'number': index + 1,
    'name': '',
    'meal': group['meal'] ?? '',
    'need': group['needs'] ?? '',
    'allergy': group['allergy'] ?? '',
    'companion': '',
    if (index < seats.length) ...seats[index],
  };
}

/// Remove stale position references in an editing draft, preserving identities.
void pruneIndividualPlaces(Json p, Json group) {
  final allowed = assignedTables(p, group);
  for (final seat in (group['seats'] as List? ?? []).cast<Json>()) {
    if (seat['table'] == null) continue;
    final matching = allowed
        .where((table) => table['id'] == seat['table'])
        .toList();
    if (matching.isEmpty) {
      seat.remove('table');
      seat.remove('slot');
    } else if (seat['slot'] != null &&
        (seat['slot'] < 0 ||
            seat['slot'] >= effectiveCapacity(p, matching.first))) {
      seat.remove('slot');
    }
  }
}

Map<String, List<int>> groupTablePeople(Json group) {
  final budget = <String, int>{};
  for (final allocation in (group['alloc'] as List).cast<Json>()) {
    budget[allocation['table']] =
        (budget[allocation['table']] ?? 0) + (allocation['count'] as int);
  }
  final result = {for (final id in budget.keys) id: <int>[]};
  final assigned = <int>{};
  for (var i = 0; i < group['count']; i++) {
    final id = individualSeat(group, i)['table'];
    if (budget.containsKey(id) && result[id]!.length < budget[id]!) {
      result[id]!.add(i);
      assigned.add(i);
    }
  }
  for (var i = 0; i < group['count']; i++) {
    if (assigned.contains(i)) continue;
    for (final id in budget.keys) {
      if (result[id]!.length < budget[id]!) {
        result[id]!.add(i);
        break;
      }
    }
  }
  for (final indices in result.values) {
    indices.sort();
  }
  return result;
}

/// Quantities remain the source of truth; individual places follow allocations.
List<Json?> tablePeople(Json p, Json table, [PlanGeometry? geometry]) {
  final geo = geometry ?? PlanGeometry(p, rows(p, 'items'));
  final capacity = effectiveCapacity(p, table, geometry);
  final result = List<Json?>.filled(capacity, null);
  final blockedSlots = Set<int>.from(table['blockedSlots'] as List? ?? []);
  final people = <Json>[];
  for (final group in rows(p, 'groups')) {
    for (final index in groupTablePeople(group)[table['id']] ?? <int>[]) {
      people.add({
        'group': group,
        'index': index,
        'seat': individualSeat(group, index),
      });
    }
  }
  final pending = <Json>[];
  for (final person in people) {
    final seat = person['seat'];
    final slot = seat['table'] == table['id']
        ? int.tryParse('${seat['slot']}')
        : null;
    if (slot != null &&
        slot >= 0 &&
        slot < capacity &&
        !blockedSlots.contains(slot) &&
        result[slot] == null) {
      result[slot] = person;
    } else {
      pending.add(person);
    }
  }
  bool prefer(Json person) =>
      person['seat']['need'] == 'Fauteuil' ||
      eventComfort(p)['preferMainAisles'] == 'Oui' &&
          (person['seat']['need'] ?? '').toString().trim().isNotEmpty;
  final order = {for (var i = 0; i < pending.length; i++) pending[i]: i};
  if (adaptedPlaces(table).isNotEmpty) {
    pending.sort((a, b) {
      final priority = (prefer(b) ? 1 : 0).compareTo(prefer(a) ? 1 : 0);
      return priority == 0 ? order[a]!.compareTo(order[b]!) : priority;
    });
  }
  for (final person in pending) {
    var slot = -1;
    if (prefer(person)) {
      final candidates = adaptedPlaces(table).toList();
      if (eventComfort(p)['preferMainAisles'] == 'Oui') {
        final guides = mainAisleGuides(p);
        candidates.sort(
          (a, b) => pmrPlaceDistance(
            p,
            table,
            a['slot'],
            guides,
            geo,
          ).compareTo(pmrPlaceDistance(p, table, b['slot'], guides, geo)),
        );
      }
      for (final place in candidates) {
        final n = place['slot'] as int;
        if (n >= 0 &&
            n < capacity &&
            !blockedSlots.contains(n) &&
            result[n] == null) {
          slot = n;
          break;
        }
      }
    }
    if (slot < 0 &&
        prefer(person) &&
        eventComfort(p)['preferMainAisles'] == 'Oui') {
      final guides = mainAisleGuides(p);
      final freeSlots = List.generate(
        capacity,
        (i) => i,
      ).where((i) => !blockedSlots.contains(i) && result[i] == null).toList();
      freeSlots.sort(
        (a, b) => pmrPlaceDistance(
          p,
          table,
          a,
          guides,
          geo,
        ).compareTo(pmrPlaceDistance(p, table, b, guides, geo)),
      );
      if (freeSlots.isNotEmpty) slot = freeSlots.first;
    }
    slot = slot < 0
        ? List.generate(capacity, (i) => i)
                  .where((i) => !blockedSlots.contains(i) && result[i] == null)
                  .firstOrNull ??
              -1
        : slot;
    if (slot >= 0) result[slot] = person;
  }
  return result;
}

List<Json> assignedPeople(Json p, Json group) {
  final result = List<Json>.generate(
    group['count'],
    (_) => {'table': null, 'slot': null},
  );
  for (final table in tables(p)) {
    final people = tablePeople(p, table);
    for (var slot = 0; slot < people.length; slot++) {
      final person = people[slot];
      if (person != null && person['group']['id'] == group['id']) {
        result[person['index']] = {'table': table, 'slot': slot};
      }
    }
  }
  return result;
}

// RFC-style quoted cells, commas/semicolons, embedded newlines and UTF-8 BOM.
List<List<String>> parseCsv(String input) {
  input = input.replaceFirst('\uFEFF', '');
  final first = input.split('\n').first;
  final delimiter = ';'.allMatches(first).length >= ','.allMatches(first).length
      ? ';'
      : ',';
  final result = <List<String>>[], row = <String>[];
  var cell = '', quoted = false;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (c == '"') {
      if (quoted && i + 1 < input.length && input[i + 1] == '"') {
        cell += '"';
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == delimiter && !quoted) {
      row.add(cell.trim());
      cell = '';
    } else if (c == '\n' && !quoted) {
      row.add(cell.trim());
      if (row.any((s) => s.isNotEmpty)) result.add(List.of(row));
      row.clear();
      cell = '';
    } else if (c != '\r' || quoted) {
      cell += c;
    }
  }
  if (quoted) throw const FormatException('Guillemet non fermé dans le CSV');
  row.add(cell.trim());
  if (row.any((s) => s.isNotEmpty)) result.add(List.of(row));
  return result;
}

void validateProject(Json p) {
  final layers = p['planLayerOrder'];
  if (layers != null &&
      (layers is! List ||
          layers.any((id) => id is! String) ||
          layers.toSet().length != layers.length)) {
    throw const FormatException('Ordre d’affichage invalide.');
  }

  if (p['icon'] != null && !eventIconNames.contains(p['icon'])) {
    throw const FormatException('Icône d’événement inconnue.');
  }
  validateMixedFurniture(p);
  if (p['comfort'] != null) {
    if (p['comfort'] is! Map) {
      throw const FormatException('Préférences de confort invalides');
    }
    final c = eventComfort(p);
    for (final key in comfortFieldLabels.keys) {
      final value = number(c[key], -1);
      if (!value.isFinite ||
          value <
              (['chairGap', 'sceneGap', 'fanSideGap'].contains(key)
                  ? 0
                  : key == 'exhibitorGap'
                  ? .6
                  : .3) ||
          value >
              ([
                    'tableGap',
                    'wallGap',
                    'exhibitorGap',
                    'parcoursWallGap',
                  ].contains(key)
                  ? 10
                  : 3)) {
        throw FormatException('Valeur de confort invalide : $key');
      }
    }
    if (!['Oui', 'Non'].contains(c['preferMainAisles']) ||
        number(c['pmrSeatWidth']) < number(c['seatWidth']) ||
        number(c['pmrAisleWidth']) < number(c['aisleWidth'])) {
      throw const FormatException('Préférences PMR incohérentes');
    }
  }

  for (final owner in [p, ...rows(p, 'types'), ...rows(p, 'items')]) {
    if (owner['joinGap'] != null &&
            (owner['joinGap'] is! num ||
                !number(owner['joinGap']).isFinite ||
                number(owner['joinGap']) < 0 ||
                number(owner['joinGap']) > 2) ||
        owner['joinGapSides'] != null &&
            !joinGapSideNames.contains(owner['joinGapSides'])) {
      throw const FormatException(
        'Espacement de jonction invalide (0 à 200 cm).',
      );
    }
  }
  if (p['arrangementMode'] != null &&
      !['Standard', 'Parcours', 'Scène'].contains(p['arrangementMode'])) {
    throw const FormatException('Mode de disposition invalide');
  }
  if (p['parcoursSettings'] != null) {
    final settings = p['parcoursSettings'];
    if (settings is Map &&
        settings['circulation'] != null &&
        !parcoursCirculations.contains(settings['circulation'])) {
      throw const FormatException('Type de parcours invalide');
    }
    if (settings is Map &&
        settings['wallLayout'] != null &&
        !parcoursWallLayouts.contains(settings['wallLayout'])) {
      throw const FormatException('Appui des rangées invalide');
    }
    if (settings is! Map ||
        !parcoursClosures.contains(settings['closure']) ||
        !parcoursOrientations.contains(settings['orientation']) ||
        !number(settings['exhibitorGap'], -1).isFinite ||
        number(settings['exhibitorGap']) < .6 ||
        number(settings['exhibitorGap']) > 10) {
      throw const FormatException('Réglages du parcours invalides');
    }
  }
  // Generated route guides are advisory: never trust stale imported geometry.
  if (p['parcoursPlan'] != null && !validParcoursPlan(p['parcoursPlan'])) {
    throw const FormatException('Parcours invalide');
  }
  if (p['arrangementCorner'] != null &&
      !arrangementCorners.contains(p['arrangementCorner'])) {
    throw const FormatException('Coin de disposition invalide');
  }
  if (p['tableCards'] != null) {
    final style = p['tableCards'];
    if (style is! Map ||
        (style['message'] != null &&
            (style['message'] is! String || style['message'].length > 400))) {
      throw const FormatException('Personnalisation des fiches invalide');
    }
    if (style['logo'] != null) {
      if (style['logo'] is! String) {
        throw const FormatException('Logo invalide');
      }
      final bytes = base64Decode(style['logo']);
      if (bytes.length < 8 ||
          bytes.length > 5 * 1024 * 1024 ||
          !((bytes[0] == 137 &&
                  bytes[1] == 80 &&
                  bytes[2] == 78 &&
                  bytes[3] == 71) ||
              (bytes[0] == 255 && bytes[1] == 216))) {
        throw const FormatException('Logo PNG ou JPEG attendu');
      }
    }
  }
  if (p['attendanceTarget'] != null &&
      (p['attendanceTarget'] is! int || p['attendanceTarget'] < 0)) {
    throw const FormatException('Objectif de personnes invalide');
  }
  if (p['joining'] != null && !joiningModes.contains(p['joining'])) {
    throw const FormatException('Mode d’accolement invalide');
  }
  if (p['version'] != 1 ||
      p['id'] is! String ||
      p['name'] is! String ||
      p['room'] is! Map) {
    throw const FormatException('Projet Sallunio/Tableo version 1 attendu');
  }
  if (number(p['room']['width']) <= 0 ||
      number(p['room']['height']) <= 0 ||
      number(p['room']['width']) > 200 ||
      number(p['room']['height']) > 200) {
    throw const FormatException('Dimensions de salle invalides');
  }
  roomPolygon(p['room']);
  if (p['room']['name'] is! String ||
      !number(p['aisle'], -1).isFinite ||
      number(p['aisle'], -1) < .5 ||
      eventTableGap(p) > 3) {
    throw const FormatException('Salle ou passage invalide');
  }
  for (final k in ['items', 'types', 'groups', 'rooms', 'history', 'meals']) {
    if (p[k] is! List) throw FormatException('Champ $k invalide');
  }
  if ((p['meals'] as List).isEmpty ||
      (p['meals'] as List).any((m) => m is! String || m.isEmpty)) {
    throw const FormatException('Liste de repas invalide');
  }
  migrateLegacyProximity(p);
  final typeIds = <String>{};
  for (final t in rows(p, 'types')) {
    if (t['id'] is! String ||
        !typeIds.add(t['id']) ||
        t['name'] is! String ||
        t['source'] is! String ||
        t['enabled'] is! bool ||
        ![
          'rectangle',
          'carré',
          'cercle',
          'banc',
          'chaise',
          'chaise enfant',
          'emplacement PMR',
        ].contains(t['shape']) ||
        number(t['w']) <= 0 ||
        number(t['h']) <= 0 ||
        t['capacity'] is! int ||
        t['capacity'] < 0 ||
        t['capacity'] > 100 ||
        t['quantity'] is! int ||
        t['quantity'] < 1 ||
        t['limit'] is! int ||
        t['limit'] < 1 ||
        t['limit'] > t['quantity']) {
      throw const FormatException('Type de mobilier invalide');
    }
  }
  for (final r in rows(p, 'rooms')) {
    if (r['name'] is! String ||
        number(r['width']) <= 0 ||
        number(r['height']) <= 0) {
      throw const FormatException('Salle mémorisée invalide');
    }
    roomPolygon(r);
  }
  for (final h in rows(p, 'history')) {
    if (h['date'] is! String ||
        h['room'] is! Map ||
        h['items'] is! List ||
        h['types'] is! List) {
      throw const FormatException('Historique invalide');
    }
  }
  final ids = <String>{};
  for (final t in rows(p, 'items')) {
    if (t['parcoursAccess'] != null &&
            !parcoursZoneAccess.contains(t['parcoursAccess']) ||
        t['parcoursPassage'] != null &&
            !['Non', 'Oui'].contains(t['parcoursPassage'])) {
      throw const FormatException('Rôle de zone dans le parcours invalide');
    }
    if (t['adaptedPlaces'] != null) {
      if (t['adaptedPlaces'] is! List || t['adaptedPlaces'].length > 100) {
        throw const FormatException('Emplacements adaptés invalides');
      }
      final slots = <int>{};
      for (final place in t['adaptedPlaces']) {
        if (place is! Map ||
            place['slot'] is! int ||
            place['slot'] < 0 ||
            place['slot'] >= 100 ||
            !slots.add(place['slot']) ||
            !number(place['width']).isFinite ||
            number(place['width']) < .6 ||
            number(place['width']) > 3 ||
            !number(place['depth']).isFinite ||
            number(place['depth']) < .55 ||
            number(place['depth']) > 3) {
          throw const FormatException('Emplacement adapté invalide');
        }
      }
    }
    if (t['kind'] == 'image') {
      try {
        final data = t['imageData'];
        if (data is! String || data.length > 16000000) {
          throw const FormatException();
        }
        final bytes = base64Decode(data);
        if (bytes.length < 8 ||
            bytes[0] != 137 ||
            bytes[1] != 80 ||
            bytes[2] != 78 ||
            bytes[3] != 71) {
          throw const FormatException();
        }
      } catch (_) {
        throw const FormatException('Image du plan invalide.');
      }
    }
    if (isPlanAnnotation(t)) {
      if (t['annotationFill'] != null &&
          !['Plein', 'Contour'].contains(t['annotationFill'])) {
        throw const FormatException('Style de forme invalide.');
      }
      if (t['label'] is! String ||
          t['label'].length > 1000 ||
          !number(t['fontSize'], 16).isFinite ||
          number(t['fontSize'], 16) < 6 ||
          number(t['fontSize'], 16) > 120 ||
          !number(t['opacity'], .25).isFinite ||
          number(t['opacity'], .25) < 0 ||
          number(t['opacity'], .25) > 1 ||
          ['labelDx', 'labelDy', 'angle'].any((k) => !number(t[k]).isFinite) ||
          [
            'bold',
            'italic',
            'underline',
          ].any((k) => t[k] != null && t[k] is! bool)) {
        throw const FormatException('Espace informatif ou texte invalide.');
      }
    }
    if (t['note'] != null &&
        (t['note'] is! String || t['note'].length > 1000)) {
      throw const FormatException('Note d’organisation invalide');
    }
    if (t['id'] is! String ||
        !ids.add(t['id']) ||
        t['label'] is! String ||
        t['fixed'] is! bool ||
        ![
          'rectangle',
          'carré',
          'cercle',
          'triangle',
          if (t['kind'] == 'info') 'ovale',
          'banc',
          'chaise',
          'chaise enfant',
          'emplacement PMR',
        ].contains(t['shape']) ||
        number(t['x'], -1) < 0 ||
        number(t['y'], -1) < 0 ||
        !number(t['x']).isFinite ||
        !number(t['y']).isFinite ||
        !number(t['w']).isFinite ||
        !number(t['h']).isFinite ||
        number(t['w']) <= 0 ||
        number(t['h']) <= 0 ||
        ![
          'table',
          'obstacle',
          'zone',
          'info',
          'text',
          'image',
          'arrow',
          'entry',
          'exit',
          'door',
          'bench',
          'chair',
          'pmr',
        ].contains(t['kind'])) {
      throw const FormatException('Objet du plan invalide');
    }
    if (t['mainAisle'] != null &&
        (t['kind'] != 'zone' || !['Oui', 'Non'].contains(t['mainAisle']))) {
      throw const FormatException('Allée principale invalide');
    }
    if (t['accessAudience'] != null &&
        (!isPlanAccess(t) || !accessAudiences.contains(t['accessAudience']))) {
      throw const FormatException('Public autorisé de l’accès invalide');
    }
    if (t['proximityEnabled'] != null &&
        (!canIncludeInProximity(t) ||
            !['Oui', 'Non'].contains(t['proximityEnabled']))) {
      throw const FormatException('Inclusion dans la proximité invalide');
    }
    if (t['kind'] == 'table' &&
        (t['capacity'] is! int || t['capacity'] < 0 || t['capacity'] > 100)) {
      throw const FormatException('Capacité invalide');
    }
  }
  final groupIds = <String>{};
  final tableIds = tables(p).map((t) => t['id']).toSet();
  for (final g in rows(p, 'groups')) {
    if (g['note'] != null &&
        (g['note'] is! String || g['note'].length > 1000)) {
      throw const FormatException('Note d’organisation invalide');
    }
    if (g['childChairs'] != null &&
        (g['childChairs'] is! int ||
            g['childChairs'] < 0 ||
            g['childChairs'] > number(g['count']))) {
      throw const FormatException('Nombre de chaises enfant invalide');
    }
    if (g['id'] is! String ||
        !groupIds.add(g['id']) ||
        !(p['meals'] as List).contains(g['meal']) ||
        g['allergy'] is! String ||
        g['needs'] is! String ||
        g['name'] is! String ||
        g['count'] is! int ||
        g['count'] < 1 ||
        g['count'] > 10000 ||
        g['alloc'] is! List) {
      throw const FormatException('Réservation invalide');
    }
    for (final a in g['alloc']) {
      if (!tableIds.contains(a['table']) ||
          a['count'] is! int ||
          a['count'] < 1) {
        throw const FormatException('Attribution invalide');
      }
    }
    if (g['seats'] != null) {
      if (g['seats'] is! List) {
        throw const FormatException('Places anonymes invalides');
      }
      for (final s in g['seats']) {
        if (s['name'] != null &&
                (s['name'] is! String || s['name'].length > 200) ||
            s['slot'] != null &&
                (s['slot'] is! int || s['slot'] < 0 || s['slot'] >= 100) ||
            s['table'] != null && s['table'] is! String) {
          throw const FormatException(
            'Identité ou emplacement individuel invalide',
          );
        }
        if (s['number'] is! int ||
            s['number'] < 1 ||
            !(p['meals'] as List).contains(s['meal']) ||
            s['need'] is! String ||
            s['allergy'] is! String ||
            s['companion'] is! String) {
          throw const FormatException('Place anonyme invalide');
        }
      }
    }
  }
  for (final g in rows(p, 'groups')) {
    if (g['placeProximity'] != null && g['placeProximity'] is! Map) {
      throw const FormatException('Préférences de lieux invalides');
    }
    for (final entry in (g['placeProximity'] as Map? ?? {}).entries) {
      if (!proximityTargets(p).any((item) => item['id'] == entry.key) ||
          !['near', 'far'].contains(entry.value)) {
        throw const FormatException('Préférence de lieu invalide');
      }
    }
    if (g['proximity'] != null && g['proximity'] is! Map) {
      throw const FormatException('Préférences invalides');
    }
    for (final entry in (g['proximity'] as Map? ?? {}).entries) {
      if (entry.key == g['id'] ||
          !groupIds.contains(entry.key) ||
          !['near', 'far'].contains(entry.value)) {
        throw const FormatException('Relation entre réservations invalide');
      }
    }
  }
}

/// Normalized outlines shared by screen and PDF decorative figures.
List<Point<double>> annotationVertices(Json item) => item['kind'] == 'arrow'
    ? const [
        Point(0, .3),
        Point(.65, .3),
        Point(.65, 0),
        Point(1, .5),
        Point(.65, 1),
        Point(.65, .7),
        Point(0, .7),
      ]
    : item['shape'] == 'triangle'
    ? const [Point(.5, 0), Point(1, 1), Point(0, 1)]
    : const [Point(0, 0), Point(1, 0), Point(1, 1), Point(0, 1)];
bool annotationEllipse(Json item) =>
    ['cercle', 'ovale'].contains(item['shape']);

const planLayerActions = <String, String>{
  'front': 'Mettre au premier plan',
  'forward': 'Avancer d’un niveau',
  'backward': 'Reculer d’un niveau',
  'back': 'Mettre à l’arrière-plan',
};
void changePlanLayer(Json p, Set<String> ids, String action) {
  if (!planLayerActions.containsKey(action)) {
    throw const FormatException('Ordre d’affichage inconnu.');
  }
  final order = planPaintOrder(p).map((i) => i['id'] as String).toList();
  final chosen = order.where(ids.contains).toList();
  if (chosen.isEmpty) return;
  if (action == 'front' || action == 'back') {
    order.removeWhere(ids.contains);
    if (action == 'front') {
      order.addAll(chosen);
    } else {
      order.insertAll(0, chosen);
    }
  } else if (action == 'forward') {
    for (var n = order.length - 2; n >= 0; n--) {
      if (ids.contains(order[n]) && !ids.contains(order[n + 1])) {
        final next = order[n + 1];
        order[n + 1] = order[n];
        order[n] = next;
      }
    }
  } else {
    for (var n = 1; n < order.length; n++) {
      if (ids.contains(order[n]) && !ids.contains(order[n - 1])) {
        final previous = order[n - 1];
        order[n - 1] = order[n];
        order[n] = previous;
      }
    }
  }
  p['planLayerOrder'] = order;
}

/// Absolute rotation from captured geometry; allocation and inventory remain intact.
bool rotatePlanFromOrigins(
  Json p,
  List<Json> origins,
  Point<double> pivot,
  double degrees,
) {
  if (p['planLocked'] == true ||
      p['eventLocked'] == true ||
      !degrees.isFinite ||
      !pivot.x.isFinite ||
      !pivot.y.isFinite) {
    return false;
  }
  final byId = {for (final item in rows(p, 'items')) item['id']: item};
  final proposals = <Json>[];
  final radians = degrees * pi / 180;
  for (final origin in origins) {
    final target = byId[origin['id']];
    if (target == null || target['fixed'] == true) return false;
    final x = number(origin['x']) + number(origin['w']) / 2 - pivot.x;
    final y = number(origin['y']) + number(origin['h']) / 2 - pivot.y;
    final nx =
        pivot.x + x * cos(radians) - y * sin(radians) - number(origin['w']) / 2;
    final ny =
        pivot.y + x * sin(radians) + y * cos(radians) - number(origin['h']) / 2;
    if (!nx.isFinite || !ny.isFinite || nx < -.000001 || ny < -.000001) {
      return false;
    }
    proposals.add({
      'id': origin['id'],
      'x': max(0.0, nx),
      'y': max(0.0, ny),
      'angle': (number(origin['angle']) + degrees) % 360,
    });
  }
  for (final proposal in proposals) {
    byId[proposal['id']]!.addAll(proposal);
  }
  return true;
}

/// Resize in the object's own axes, keeping the opposite world-space corner fixed.
bool resizeRotatedBox(
  Json item,
  Json origin,
  double dx,
  double dy,
  bool right,
  bool bottom, {
  bool preserveAspect = false,
}) {
  final a = number(origin['angle']) * pi / 180;
  final lx = dx * cos(a) + dy * sin(a), ly = -dx * sin(a) + dy * cos(a);
  var w = max(.2, number(origin['w']) + (right ? lx : -lx));
  var h = max(.2, number(origin['h']) + (bottom ? ly : -ly));
  if (['cercle', 'carré'].contains(origin['shape'])) {
    final delta = lx.abs() > ly.abs()
        ? (right ? lx : -lx)
        : (bottom ? ly : -ly);
    w = h = max(.2, number(origin['w']) + delta);
  } else if (preserveAspect) {
    final ow = number(origin['w']), oh = number(origin['h']);
    final fx = (right ? lx : -lx) / ow, fy = (bottom ? ly : -ly) / oh;
    final factor = max(
      max(.2 / ow, .2 / oh),
      1 + (fx.abs() > fy.abs() ? fx : fy),
    );
    w = ow * factor;
    h = oh * factor;
  }
  final oldAnchor = rotatedLocalPoint(
    origin,
    Point(
      right ? 0.0 : number(origin['w']),
      bottom ? 0.0 : number(origin['h']),
    ),
  );
  final updated = {...origin, 'w': w, 'h': h};
  final newAnchor = rotatedLocalPoint(
    updated,
    Point(right ? 0.0 : w, bottom ? 0.0 : h),
  );
  final x = number(origin['x']) + oldAnchor.x - newAnchor.x,
      y = number(origin['y']) + oldAnchor.y - newAnchor.y;
  if (x < -.000001 || y < -.000001 || ![x, y, w, h].every((v) => v.isFinite)) {
    return false;
  }
  item.addAll({'x': max(0.0, x), 'y': max(0.0, y), 'w': w, 'h': h});
  return true;
}
