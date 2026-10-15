import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/exports.dart';
import 'package:tableo/plan_export.dart';

void main() {
  test('Special needs include individual mobility and child chairs on plan and lists', () async {
    final p = demoProject()..['mealService'] = 'Non';
    final g = rows(p, 'groups').first;
    p['groups'] = [g];
    g.addAll({
      'count': 3,
      'needs': '',
      'childChairs': 1,
      'seats': [
        {'number': 1, 'need': 'Fauteuil'},
        {'number': 2, 'need': 'Autre mobilité'},
        {'number': 3, 'need': ''},
      ],
      'alloc': [
        {'table': tables(p).first['id'], 'count': 3},
      ],
    });
    final before = clone(p);
    final text = reservationSpecialNeeds(g);
    expect(text, contains('Fauteuil roulant : 1'));
    expect(text, contains('Autre mobilité : 1'));
    expect(text, contains('Chaise enfant : 1'));
    expect(tableMarkers(p, tables(p).first['id']), contains('Chaise enfant'));
    expect(planMarkerShape('Chaise enfant'), PlanMarkerShape.square);
    expect(
      planMarkerSvg('Chaise enfant', 0xffad1457, 0, 0),
      startsWith('<polygon'),
    );
    expect(furnitureTooltip(p, tables(p).first), contains('Chaise enfant'));
    p['groups'] = [
      g,
      {
        ...clone(g),
        'id': 'waiting-needs',
        'name': 'En attente fictif',
        'waiting': true,
        'alloc': <Json>[],
      },
    ];
    await Directory('tmp/pdfs').create(recursive: true);
    await exportPdf(
      p,
      'tmp/pdfs/special-needs.pdf',
      includeCards: false,
      includeReception: true,
      includeWaiting: true,
      overwriteConfirmed: true,
    );
    expect(File('tmp/pdfs/special-needs.pdf').lengthSync(), greaterThan(1000));
    expect(g, rows(before, 'groups').first);
  });
}
