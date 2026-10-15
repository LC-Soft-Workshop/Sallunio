import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/main.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/event_backup.dart';
import 'package:tableo/exports.dart';
import 'package:tableo/parcours.dart';

import 'joining_test.dart' show table;
import 'plan_images_test.dart' show image;
import 'plan_annotations_test.dart' show annotation;
import 'annotation_shapes_test.dart' show arrow;
import 'attributions_test.dart' show SnapshotStore, desktop;
import 'plan_toolbar_test.dart' show clickTool;

List<String> ids(Json p) =>
    planPaintOrder(p).map((i) => i['id'] as String).toList();
int layerIndex(WidgetTester t, String id) => t
    .widget<Stack>(find.byKey(const ValueKey('plan-canvas')))
    .children
    .indexWhere((w) => w.key == ValueKey(('plan-layer', id, 'body')));
void main() {
  test('All four order operations preserve geometry and restore through full backup', () {
    final p = demoProject()
      ..['items'] = [
        image('image'),
        annotation('info', 'space'),
        table('table', 1, 1),
        arrow('arrow'),
      ];
    final items = clone({'items': p['items']}),
        signature = parcoursSignature(p);
    expect(ids(p), ['image', 'space', 'table', 'arrow']);
    changePlanLayer(p, {'image'}, 'front');
    expect(ids(p), ['space', 'table', 'arrow', 'image']);
    changePlanLayer(p, {'image'}, 'backward');
    expect(ids(p), ['space', 'table', 'image', 'arrow']);
    changePlanLayer(p, {'image'}, 'forward');
    expect(ids(p).last, 'image');
    changePlanLayer(p, {'image'}, 'back');
    expect(ids(p).first, 'image');
    expect(p['items'], items['items']);
    expect(parcoursSignature(p), signature);
    expect(ids(readEventBackup(jsonEncode(eventBackup([p]))).single), ids(p));
    changePlanLayer(p, {'image', 'space'}, 'front');
    expect(ids(p), ['table', 'arrow', 'image', 'space']);
    changePlanLayer(p, {'image', 'space'}, 'backward');
    expect(ids(p), ['table', 'image', 'space', 'arrow']);
    rows(p, 'items').add(image('new'));
    expect(ids(p).last, 'new');
  });
  for (final kind in ['image', 'circle', 'arrow']) {
    testWidgets(
      '$kind resize handles stay above covering furniture throughout resize',
      (t) async {
        desktop(t);
        final decor = kind == 'image'
            ? image('decor')
            : kind == 'arrow'
            ? (arrow('decor')..['angle'] = 0.0)
            : (annotation('info', 'decor')..['shape'] = 'cercle');
        decor['w'] = 4.0;
        decor['h'] = kind == 'circle' ? 4.0 : 3.0;
        decor['x'] = 1.0;
        decor['y'] = 1.0;
        final cover = table('cover', 4.5, number(decor['h']) + .5);
        final store = SnapshotStore()..saved['items'] = [decor, cover];
        await t.pumpWidget(Tableo(store: store));
        await t.pumpAndSettle();
        final handle = find.byKey(
          const ValueKey('annotation-resize-decor-true-true'),
        );
        expect(handle, findsNothing);
        await t.tap(find.byKey(const ValueKey('plan-item-decor')));
        await t.pump(const Duration(milliseconds: 400));
        await t.pumpAndSettle();
        expect(handle, findsOneWidget);
        void checkTop() {
          final stack = t.widget<Stack>(
            find.byKey(const ValueKey('plan-canvas')),
          );
          expect(
            stack.children.indexWhere(
              (w) =>
                  w.key == const ValueKey('annotation-resize-decor-true-true'),
            ),
            greaterThan(layerIndex(t, 'cover')),
          );
        }

        checkTop();
        final drag = await t.startGesture(t.getCenter(handle));
        await drag.moveBy(const Offset(20, 5));
        await t.pump();
        checkTop();
        await drag.moveBy(const Offset(20, 5));
        await t.pump();
        checkTop();
        await drag.up();
        await t.pumpAndSettle();
        final restored = rows(store.saved, 'items');
        expect(number(restored.first['w']), greaterThan(4));
        expect(restored.last, cover);
        if (kind == 'circle') expect(restored.first['w'], restored.first['h']);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(handle, findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Layer toolbar moves objects, undo restores default, context menu exposes commands',
    (t) async {
      desktop(t);
      final store = SnapshotStore()
        ..saved['items'] = [image('image'), table('table', 1, 1)];
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      final img = find.byKey(const ValueKey('plan-item-image'));
      await t.tapAt(t.getBottomRight(img) - const Offset(15, 15));
      await t.pumpAndSettle();
      expect(layerIndex(t, 'image'), lessThan(layerIndex(t, 'table')));
      await clickTool(t, 'layers');
      await t.tap(find.text('Mettre au premier plan'));
      await t.pumpAndSettle();
      expect(layerIndex(t, 'image'), greaterThan(layerIndex(t, 'table')));
      expect(ids(store.saved).last, 'image');
      await t.tap(find.byIcon(Icons.undo).first);
      await t.pumpAndSettle();
      expect(layerIndex(t, 'image'), lessThan(layerIndex(t, 'table')));
      await clickTool(t, 'layers');
      await t.tap(find.text('Mettre au premier plan'));
      await t.pumpAndSettle();
      final mouse = await t.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: 2,
      );
      await mouse.down(t.getCenter(img));
      await mouse.up();
      await t.pumpAndSettle();
      for (final label in planLayerActions.values) {
        expect(find.text(label), findsOneWidget);
      }
      await t.tap(find.text('Mettre à l’arrière-plan'));
      await t.pumpAndSettle();
      expect(layerIndex(t, 'image'), lessThan(layerIndex(t, 'table')));
      expect(t.takeException(), isNull);
    },
  );
  test('PDF honors custom foreground and background image order', () async {
    final p = demoProject()
      ..['items'] = [image('image')..['h'] = 3.0, table('table', 1.5, 1.5)];
    await Directory('tmp/pdfs').create(recursive: true);
    for (final action in ['front', 'back']) {
      changePlanLayer(p, {'image'}, action);
      await exportPdf(
        p,
        'tmp/pdfs/layers-$action.pdf',
        overwriteConfirmed: true,
        includeSummary: false,
        includeCards: false,
      );
      expect(
        await File('tmp/pdfs/layers-$action.pdf').length(),
        greaterThan(1000),
      );
    }
  });
}
