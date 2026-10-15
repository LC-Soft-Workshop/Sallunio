import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/parcours.dart';
import 'package:tableo/parcours_painter.dart';
import 'package:tableo/exports.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'parcours_test.dart' show market;
import 'plan_toolbar_test.dart' show clickTool;
import 'imposed_parcours_test.dart' show perimeterMarket;

Json annotation(String kind, String id) => {
  'id': id,
  'kind': kind,
  'label': kind == 'info' ? 'Espace repas' : 'Bienvenue au salon',
  'shape': 'rectangle',
  'x': 0.0,
  'y': 0.0,
  'w': 8.0,
  'h': 5.0,
  'fixed': false,
  'fontSize': 18.0,
  'bold': true,
  'italic': true,
  'underline': true,
  'zoneColor': 'Bleu',
  'opacity': .3,
};
void main() {
  test('Annotations never change collisions, placement, capacity or route fingerprint', () {
    final original = demoProject()..['groups'] = <Json>[];
    final decorated = clone(original);
    rows(
      decorated,
      'items',
    ).addAll([annotation('info', 'info'), annotation('text', 'text')]);
    expect(issues(decorated), issues(original));
    expect(
      workspaceStats(decorated)['capacity'],
      workspaceStats(original)['capacity'],
    );
    arrange(original);
    arrange(decorated);
    expect(tables(decorated), tables(original));
    expect(planPaintOrder(decorated).first['kind'], 'info');
    expect(planPaintOrder(decorated).last['kind'], 'text');
    validateProject(decorated);
    final p = market(count: 12), q = clone(market(count: 12));
    rows(
      q,
      'items',
    ).addAll([annotation('info', 'info'), annotation('text', 'text')]);
    arrangeParcours(p);
    arrangeParcours(q);
    expect(tables(q), tables(p));
    final paths = parcoursPaths(q);
    rows(q, 'items').last['x'] = 3.0;
    expect(parcoursCurrent(q), true);
    expect(
      parcoursPaths(q).map((v) => v.toString()),
      paths.map((v) => v.toString()),
    );
  });
  test(
    'Clear selection, protection and text rotation are independent from stock',
    () {
      final p = demoProject();
      final info = annotation('info', 'info'),
          text = annotation('text', 'text')..['fixed'] = true;
      rows(p, 'items').addAll([info, text]);
      final types = clone(p)['types'];
      clearRoom(p, {'zones', 'obstacles'});
      expect(rows(p, 'items').where(isPlanAnnotation).length, 2);
      clearRoom(p, {'texts'});
      expect(rows(p, 'items').any((i) => i['id'] == 'text'), true);
      text['fixed'] = false;
      rotateTable(text, p);
      expect(text['angle'], 90);
      expect(text['w'], 8.0);
      clearRoom(p, {'texts', 'infos'});
      expect(rows(p, 'items').any(isPlanAnnotation), false);
      expect(p['types'], types);
    },
  );
  test('Full PDF includes formatted movable annotations', () async {
    final p = demoProject();
    rows(p, 'items').addAll([
      annotation('info', 'info')
        ..['labelDx'] = 1.0
        ..['labelDy'] = -.5,
      annotation('text', 'text')
        ..['x'] = 2.0
        ..['y'] = 5.0
        ..['w'] = 5.0
        ..['h'] = .5,
    ]);
    await Directory('tmp/pdfs').create(recursive: true);
    await exportPdf(
      p,
      'tmp/pdfs/annotations.pdf',
      overwriteConfirmed: true,
      includeSummary: false,
      includeCards: false,
    );
  });
  testWidgets('Opaque informative space never hides the closed visitor route', (
    t,
  ) async {
    desktop(t);
    final p = perimeterMarket(extras: 20);
    p['parcoursSettings']['circulation'] = 'Fermé';
    arrange(p);
    expect(parcoursPaths(p), isNotEmpty);
    rows(p, 'items').add(
      annotation('info', 'opaque-info')
        ..['opacity'] = 1.0
        ..['w'] = 25.0
        ..['h'] = 12.0,
    );
    final store = SnapshotStore()..saved = p;
    await t.pumpWidget(Tableo(store: store));
    await t.pumpAndSettle();
    final stack = t.widget<Stack>(find.byKey(const ValueKey('plan-canvas')));
    final infoIndex = stack.children.indexWhere(
      (w) =>
          w is Positioned &&
          w.child is GestureDetector &&
          w.child.key == const ValueKey('plan-item-opaque-info'),
    );
    final routeIndex = stack.children.indexWhere(
      (w) =>
          w is Positioned &&
          w.child is IgnorePointer &&
          (w.child as IgnorePointer).child is CustomPaint &&
          ((w.child as IgnorePointer).child as CustomPaint).painter
              is ParcoursPainter,
    );
    expect(infoIndex, greaterThanOrEqualTo(0));
    expect(routeIndex, greaterThan(infoIndex));
    expect(parcoursCurrent(store.saved), true);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Add informative space and text, move its label, then remove texts selectively',
    (t) async {
      desktop(t);
      final store = SnapshotStore()..saved['items'] = <Json>[];
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      await clickTool(t, 'add');
      await t.tap(find.text('Espace informatif'));
      await t.pumpAndSettle();
      await t.tap(find.text('Enregistrer').last);
      await t.pumpAndSettle();
      final info = rows(store.saved, 'items').single;
      final key = find.byKey(ValueKey('annotation-label-${info['id']}'));
      await t.drag(key, const Offset(30, -30));
      await t.pumpAndSettle();
      expect(rows(store.saved, 'items').single['labelDx'], greaterThan(0));
      await clickTool(t, 'add');
      await t.tap(find.text('Texte'));
      await t.pumpAndSettle();
      await t.tap(find.text('Enregistrer').last);
      await t.pumpAndSettle();
      expect(
        rows(store.saved, 'items').where((i) => i['kind'] == 'text').length,
        1,
      );
      await clickTool(t, 'rotate');
      await t.tap(
        find.byWidgetPredicate(
          (w) => w is PopupMenuItem<String> && w.value == 'selection',
        ),
      );
      await t.pumpAndSettle();
      expect(
        rows(
          store.saved,
          'items',
        ).firstWhere((i) => i['kind'] == 'text')['angle'],
        90,
      );
      await clickTool(t, 'clear-room');
      await t.pumpAndSettle();
      expect(find.text('Textes'), findsOneWidget);
      expect(find.text('Espaces informatifs'), findsOneWidget);
      await t.tap(find.text('Annuler').last);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
}
