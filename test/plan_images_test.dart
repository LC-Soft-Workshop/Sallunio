import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/event_backup.dart';
import 'package:tableo/exports.dart';
import 'package:tableo/parcours.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'plan_toolbar_test.dart' show clickTool;
import 'card_branding_test.dart' show LogoDialog;

Json image(String id) => {
  'id': id,
  'kind': 'image',
  'label': 'Logo test',
  'shape': 'rectangle',
  'x': 1.0,
  'y': 1.0,
  'w': 4.0,
  'h': 2.0,
  'fixed': false,
  'angle': 0.0,
  'imageData': base64Encode(
    File('test/fixtures/logo-fiches.png').readAsBytesSync(),
  ),
};
void main() {
  test('Images are portable annotations, excluded from collisions and selectively clearable', () {
    final p = demoProject();
    final t = tables(p).first;
    final signature = parcoursSignature(p);
    final a = image('logo')
      ..['x'] = t['x']
      ..['y'] = t['y'];
    rows(p, 'items').add(a);
    validateProject(p);
    expect(parcoursSignature(p), signature);
    expect(overlaps(a, t), false);
    expect(physicalPlanItems(p).contains(a), false);
    final restored = readEventBackup(jsonEncode(eventBackup([p]))).single;
    expect(rows(restored, 'items').last['imageData'], a['imageData']);
    rotateTable(a, p);
    expect(a['angle'], 90);
    clearRoom(p, {'zones', 'obstacles', 'texts', 'infos'});
    expect(rows(p, 'items').contains(a), true);
    clearRoom(p, {'images'});
    expect(rows(p, 'items').contains(a), false);
  });
  test('Invalid embedded image is rejected', () {
    final p = demoProject();
    rows(p, 'items').add(image('bad')..['imageData'] = 'invalid');
    expect(() => validateProject(p), throwsFormatException);
  });
  test('PDF includes several embedded images and rotation', () async {
    final p = demoProject();
    rows(p, 'items').addAll([
      image('one'),
      image('two')
        ..['x'] = 7.0
        ..['angle'] = 90.0,
    ]);
    await Directory('tmp/pdfs').create(recursive: true);
    await exportPdf(
      p,
      'tmp/pdfs/plan-images.pdf',
      overwriteConfirmed: true,
      includeSummary: false,
      includeCards: false,
    );
    expect(await File('tmp/pdfs/plan-images.pdf').length(), greaterThan(1000));
  });
  testWidgets('Add multiple independent images, rotate and show clear option', (
    t,
  ) async {
    desktop(t);
    final store = SnapshotStore()..saved['items'] = <Json>[];
    await t.pumpWidget(Tableo(store: store, fileDialogs: LogoDialog()));
    await t.pumpAndSettle();
    for (var n = 0; n < 2; n++) {
      await clickTool(t, 'add');
      await t.tap(find.text('Image').last);
      await t.pumpAndSettle();
      for (
        var wait = 0;
        wait < 30 && find.text('Ajouter une image').evaluate().isEmpty;
        wait++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pumpAndSettle();
      }
      expect(find.text('Ajouter une image'), findsOneWidget);
      await t.tap(find.text('Enregistrer').last);
      await t.pumpAndSettle();
    }
    final images = rows(store.saved, 'items');
    expect(images.length, 2);
    expect(images[0]['id'], isNot(images[1]['id']));
    final imageKey = find.byKey(ValueKey('plan-item-${images.last['id']}'));
    final oldX = number(images.last['x']);
    final drag = await t.startGesture(t.getCenter(imageKey));
    await drag.moveBy(const Offset(20, 0));
    await t.pump();
    await drag.moveBy(const Offset(30, 0));
    await t.pump();
    await drag.up();
    await t.pumpAndSettle();
    expect(number(rows(store.saved, 'items').last['x']), greaterThan(oldX));
    await clickTool(t, 'rotate');
    await t.tap(
      find.byWidgetPredicate(
        (w) => w is PopupMenuItem<String> && w.value == 'selection',
      ),
    );
    await t.pumpAndSettle();
    expect(rows(store.saved, 'items').last['angle'], 90);
    await clickTool(t, 'clear-room');
    expect(find.text('Images'), findsOneWidget);
    await t.tap(find.text('Annuler').last);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
