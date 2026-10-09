import 'dart:math';

import 'domain.dart';

bool visibleInPlanPdf(Json item) =>
    !(item['kind'] == 'zone' && item['zoneFill'] == 'Invisible');

String _hex(int color) =>
    '#${(color & 0xffffff).toRadixString(16).padLeft(6, '0')}';

String planSvg(Json p) {
  const unit = 100.0;
  final width = number(p['room']['width']) * unit,
      height = number(p['room']['height']) * unit;
  final geometry = PlanGeometry(p, rows(p, 'items'));
  final markers = planMarkerColors(p);
  final svg = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $width $height"><rect width="$width" height="$height" fill="white"/>',
  );
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
  var index = 0;
  for (final item in rows(p, 'items').where(visibleInPlanPdf)) {
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
    final stroke = conflict ? '#ff0000' : '#527567';
    svg.write(
      '<g transform="translate($x $y)"><$shape fill="$fill"/><defs><clipPath id="clip$index"><$shape/></clipPath></defs>',
    );
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
          my -= 12;
        }
        svg.write(
          '<circle cx="$mx" cy="$my" r="4.5" fill="${_hex(markers[name]!)}" stroke="white"/>',
        );
        mx += 12;
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
  svg.write(
    '<rect width="$width" height="$height" fill="none" stroke="#536a61" stroke-width="2"/></svg>',
  );
  return svg.toString();
}
