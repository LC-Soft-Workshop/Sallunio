import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/exports.dart';
import 'package:tableo/event_backup.dart';
import 'package:tableo/parcours.dart';
import 'package:tableo/plan_export.dart';

import 'plan_annotations_test.dart' show annotation;
import 'attributions_test.dart' show SnapshotStore, desktop;
import 'plan_toolbar_test.dart' show clickTool;

Json arrow(String id) => {
  ...annotation('info', id),
  'kind': 'arrow',
  'shape': 'rectangle',
  'w': 3.0,
  'h': .7,
  'zoneColor': 'Orange',
  'opacity': 1.0,
  'angle': 30.0,
};
void main() {
  test('Decorative shapes and arrows preserve geometry, backups, layers and selective clearing', () {
    final p = demoProject(), original = demoProject();
    final before = parcoursSignature(p);
    final circle = annotation('info', 'circle')
      ..['shape'] = 'cercle'
      ..['w'] = 2.0
      ..['h'] = 2.0
      ..['annotationFill'] = 'Contour';
    final oval = annotation('info', 'oval')..['shape'] = 'ovale';
    rows(p, 'items').addAll([circle, oval, arrow('arrow')]);
    validateProject(p);
    expect(parcoursSignature(p), before);
    expect(overlaps(circle, tables(p).first), false);
    expect(
      physicalPlanItems(p).where((i) => ['info', 'arrow'].contains(i['kind'])),
      isEmpty,
    );
    expect(planPaintOrder(p).first['kind'], 'info');
    expect(planPaintOrder(p).last['kind'], 'arrow');
    expect(readEventBackup(jsonEncode(eventBackup([p]))).single, p);
    arrange(p);
    arrange(original);
    expect(
      tables(p).map((t) => [t['x'], t['y']]),
      tables(original).map((t) => [t['x'], t['y']]),
    );
    clearRoom(p, {'arrows'});
    expect(rows(p, 'items').any((i) => i['kind'] == 'arrow'), false);
    expect(rows(p, 'items').contains(circle), true);
  });
  test('SVG uses oval geometry, polygon arrows, and outline without fill', () {
    expect(
      annotationFigureSvg(annotation('info', 'oval')..['shape'] = 'ovale'),
      contains('<ellipse'),
    );
    final svg = annotationFigureSvg(
      arrow('arrow')..['annotationFill'] = 'Contour',
    );
    expect(svg, contains('<polygon'));
    expect(svg, contains('fill="none"'));
    expect(annotationVertices(arrow('arrow')).length, 7);
  });
  test(
    'PDF exports circular and oval spaces, triangle and rotated arrows',
    () async {
      final p = demoProject()..['items'] = <Json>[];
      rows(p, 'items').addAll([
        annotation('info', 'circle')..addAll({
          'shape': 'cercle',
          'label': 'Espace rond',
          'x': .5,
          'y': .5,
          'w': 2.0,
          'h': 2.0,
          'annotationFill': 'Contour',
        }),
        annotation('info', 'oval')..addAll({
          'shape': 'ovale',
          'label': 'Espace ovale',
          'x': 3.0,
          'y': .5,
          'w': 4.0,
          'h': 2.0,
        }),
        annotation('info', 'triangle')..addAll({
          'shape': 'triangle',
          'label': 'Triangle',
          'x': 8.0,
          'y': .5,
          'w': 2.0,
          'h': 2.0,
        }),
        arrow('arrow')
          ..addAll({'x': 1.0, 'y': 4.0, 'w': 5.0, 'h': .8, 'angle': 0.0}),
        arrow('rotated')..addAll({
          'x': 8.0,
          'y': 4.0,
          'w': 3.0,
          'h': .8,
          'angle': 90.0,
          'annotationFill': 'Contour',
        }),
      ]);
      await Directory('tmp/pdfs').create(recursive: true);
      await exportPdf(
        p,
        'tmp/pdfs/annotation-shapes.pdf',
        overwriteConfirmed: true,
        includeSummary: false,
        includeCards: false,
      );
    },
  );
  testWidgets('Create a circular informative space and a configurable arrow', (
    t,
  ) async {
    desktop(t);
    final store = SnapshotStore()..saved['items'] = <Json>[];
    await t.pumpWidget(Tableo(store: store));
    await t.pumpAndSettle();
    await clickTool(t, 'add');
    await t.tap(find.text('Espace informatif'));
    await t.pumpAndSettle();
    final shape = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == 'Forme',
    );
    await t.ensureVisible(shape);
    await t.tap(shape);
    await t.pumpAndSettle();
    await t.tap(find.text('cercle').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Enregistrer').last);
    await t.pumpAndSettle();
    final circle = rows(store.saved, 'items').single;
    expect(circle['shape'], 'cercle');
    expect(circle['w'], circle['h']);
    final handles = find.byWidgetPredicate(
      (w) =>
          w is GestureDetector &&
          w.child is Container &&
          (w.child as Container).constraints?.maxWidth == 16,
    );
    final resize = await t.startGesture(t.getCenter(handles.last));
    await resize.moveBy(const Offset(20, 5));
    await t.pump();
    await resize.moveBy(const Offset(20, 5));
    await t.pump();
    await resize.up();
    await t.pumpAndSettle();
    final resized = rows(store.saved, 'items').single;
    expect(resized['w'], greaterThan(circle['w']));
    expect(resized['w'], resized['h']);

    await clickTool(t, 'add');
    await t.tap(find.text('Flèche'));
    await t.pumpAndSettle();
    final angle = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == 'Angle (degrés, 0 : vers la droite)',
    );
    await t.ensureVisible(angle);
    await t.enterText(angle, '30');
    await t.tap(find.text('Enregistrer').last);
    await t.pumpAndSettle();
    final item = rows(store.saved, 'items').last;
    expect(item['kind'], 'arrow');
    expect(item['angle'], 30);
    expect(find.byKey(ValueKey('plan-item-${item['id']}')), findsOneWidget);
    await clickTool(t, 'clear-room');
    expect(find.text('Flèches'), findsOneWidget);
    await t.tap(find.text('Annuler').last);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
