import 'dart:math';

import 'domain.dart';
import 'parcours.dart';

bool visibleInPlanPdf(Json item) =>
    !(item['kind'] == 'zone' && item['zoneFill'] == 'Invisible');

String _hex(int color) =>
    '#${(color & 0xffffff).toRadixString(16).padLeft(6, '0')}';

String planMarkerSvg(String name, int color, double x, double y) {
  final shape = planMarkerShape(name);
  final geometry = shape == PlanMarkerShape.circle
      ? 'circle cx="$x" cy="$y" r="5.5"'
      : 'polygon points="${planMarkerVertices(shape).map((p) => '${x - 5.5 + p.x * 11},${y - 5.5 + p.y * 11}').join(' ')}"';
  return '<$geometry fill="${_hex(color)}" stroke="white" stroke-width="1"/>';
}

String planSvg(
  Json p, {
  bool? tablesOnly,
  bool withGrid = true,
  bool showMarkers = true,
  bool transparentBackground = false,
  bool includeRoute = true,
  bool drawItems = true,
  String? onlyItemId,
  PlanGeometry? sharedGeometry,
}) {
  const unit = 100.0;
  final width = number(p['room']['width']) * unit,
      height = number(p['room']['height']) * unit;
  final geometry = sharedGeometry ?? PlanGeometry(p, rows(p, 'items'));
  final markers = planMarkerColors(p);
  final svg = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $width $height">${withGrid && !transparentBackground ? '<rect width="$width" height="$height" fill="white"/>' : ''}',
  );
  if (withGrid) {
    for (var x = unit; x < width; x += unit) {
      svg.write('<line x1="$x" y1="0" x2="$x" y2="$height" stroke="#e5ebe7"/>');
    }
    for (var y = unit; y < height; y += unit) {
      svg.write('<line x1="0" y1="$y" x2="$width" y2="$y" stroke="#e5ebe7"/>');
    }
    final polygon = roomPolygon(p['room']);
    if (polygon.isNotEmpty) {
      final points = polygon
          .map((point) => '${point.x * unit},${point.y * unit}')
          .join(' ');
      final outline = polygon
          .map((point) => '${point.x * unit} ${point.y * unit}')
          .join(' L ');
      svg.write(
        '<path d="M 0 0 H $width V $height H 0 Z M $outline Z" fill="#bdc8c1" fill-rule="evenodd"/><polygon points="$points" fill="none" stroke="#536a61" stroke-width="2"/>',
      );
    }
  }
  var index = 0;
  if (includeRoute && tablesOnly != true && p['showParcours'] != false) {
    if (parcoursCurrent(p)) {
      for (final b in p['parcoursPlan']['blocks'] as List) {
        svg.write(
          '<rect x="${number(b['x']) * unit}" y="${number(b['y']) * unit}" width="${number(b['w']) * unit}" height="${number(b['h']) * unit}" fill="#bf8f20" fill-opacity="0.08"/>',
        );
      }
    }
    for (final route in parcoursPaths(p)) {
      final points = route.map((v) => '${v.x * unit},${v.y * unit}').join(' ');
      svg.write(
        '<polyline points="$points" fill="none" stroke="#1565c0" stroke-width="3" stroke-linejoin="round"/>',
      );
    }
  }
  if (includeRoute &&
      tablesOnly != true &&
      p['showParcours'] != false &&
      parcoursCurrent(p)) {
    for (final arrow in parcoursArrows(p)) {
      svg.write(
        '<polyline points="${arrow.map((v) => '${v.x * unit},${v.y * unit}').join(' ')}" fill="none" stroke="#1565c0" stroke-width="3"/>',
      );
    }
  }
  for (final item in planPaintOrder(
    p,
  ).where((i) => visibleInPlanPdf(i) && !isPlanAnnotation(i))) {
    if (!drawItems || onlyItemId != null && item['id'] != onlyItemId) continue;
    if (tablesOnly != null && isSeatingFurniture(item) != tablesOnly) continue;
    final x = number(item['x']) * unit, y = number(item['y']) * unit;
    final w = number(item['w']) * unit, h = number(item['h']) * unit;
    final occupied = item['kind'] == 'table' ? occupancy(p, item['id']) : 0;
    final capacity = item['kind'] == 'table' ? geometry.capacity(item) : 0;
    final color = switch (item['kind']) {
      'table' =>
        occupied == 0
            ? 0xffd7ddda
            : occupied < capacity
            ? 0xffffd9ad
            : 0xffa9d8bf,
      'zone' => zoneColors[item['zoneColor']] ?? zoneColors['Bleu']!,
      'entry' => 0xffd3c3ed,
      'exit' => 0xfff6dc96,
      'door' => 0xfff6c4aa,
      _ => 0xffc6ceca,
    };
    final fill = item['kind'] == 'zone' && item['zoneFill'] == 'Contour seul'
        ? 'none'
        : _hex(color);
    final shape = switch (item['shape']) {
      'cercle' =>
        'ellipse cx="${w / 2}" cy="${h / 2}" rx="${w / 2}" ry="${h / 2}"',
      'triangle' => 'polygon points="${w / 2},0 $w,$h 0,$h"',
      _ => 'rect width="$w" height="$h" rx="3"',
    };
    final conflict =
        item['kind'] == 'table' &&
        !fits(p, item, rows(p, 'items'), geometry: geometry);
    final served =
        p['showParcours'] != false &&
        parcoursCurrent(p) &&
        (p['parcoursPlan']['services'] as List? ?? []).any(
          (s) => s['id'] == item['id'],
        );
    final stroke = conflict
        ? '#ff0000'
        : served
        ? '#1565c0'
        : '#527567';
    svg.write(
      '<g transform="translate($x $y) rotate(${number(item['angle'])} ${w / 2} ${h / 2})"><$shape fill="$fill"/><defs><clipPath id="clip$index"><$shape/></clipPath></defs>',
    );
    if (furnitureUse(item) == furnitureUses[1]) {
      for (final a in standPortions(p, item['id'])) {
        final start = number(a['offset']) / standLength(item),
            extent = number(a['length']) / standLength(item);
        svg.write(
          number(item['w']) >= number(item['h'])
              ? '<rect x="${start * w}" y="0" width="${extent * w}" height="$h" fill="${_hex(a['color'])}"/>'
              : '<rect x="0" y="${start * h}" width="$w" height="${extent * h}" fill="${_hex(a['color'])}"/>',
        );
      }
    }
    if (item['zoneFill'] == 'Hachures' ||
        item['zoneFill'] == 'Hachures croisées') {
      svg.write(
        '<g clip-path="url(#clip$index)" stroke="#527567" stroke-opacity="0.6">',
      );
      for (var start = -h; start < w + h; start += 9) {
        svg.write('<line x1="$start" y1="0" x2="${start + h}" y2="$h"/>');
        if (item['zoneFill'] == 'Hachures croisées') {
          svg.write('<line x1="$start" y1="0" x2="${start - h}" y2="$h"/>');
        }
      }
      svg.write('</g>');
    }
    svg.write(
      '<$shape fill="none" stroke="$stroke" stroke-width="${conflict ? 3 : 1.5}"/>',
    );
    if (item['kind'] == 'table') {
      var mx = 7.0, my = h - 7;
      for (final name in tableMarkers(p, item['id'])) {
        if (mx + 5 > w) {
          mx = 7;
          my -= 14;
        }
        if (showMarkers) svg.write(planMarkerSvg(name, markers[name]!, mx, my));
        mx += 14;
      }
      if (conflict) {
        svg.write(
          '<polygon points="${max(0, w - 14)},0 $w,0 $w,14" fill="red"/>',
        );
      }
    }
    svg.write('</g>');
    index++;
  }
  if (withGrid) {
    svg.write(
      '<rect width="$width" height="$height" fill="none" stroke="#536a61" stroke-width="2"/>',
    );
  }
  svg.write('</svg>');
  return svg.toString();
}

String annotationFigureSvg(Json item) {
  final w = number(item['w']) * 50, h = number(item['h']) * 50;
  final shape = annotationEllipse(item)
      ? 'ellipse cx="${w / 2}" cy="${h / 2}" rx="${w / 2}" ry="${h / 2}"'
      : 'polygon points="${annotationVertices(item).map((v) => '${v.x * w},${v.y * h}').join(' ')}"';
  final color = _hex(zoneColors[item['zoneColor']] ?? zoneColors['Bleu']!);
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-1 -1 ${w + 2} ${h + 2}"><$shape fill="${item['annotationFill'] == 'Contour' ? 'none' : color}" fill-opacity="${number(item['opacity'], .25)}" stroke="$color" stroke-width="1"/></svg>';
}
