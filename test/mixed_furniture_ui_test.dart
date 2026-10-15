import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';

import 'flutter_paths.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'mixed_furniture_test.dart'
    show standPlan, exhibitor, audiencePlan, seatedGroup;

Finder dropdown(String label) => find.byWidgetPredicate(
  (w) =>
      w is DropdownButtonFormField<String> && w.decoration.labelText == label,
);
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> choose(WidgetTester t, String label, String value) async {
  final f = dropdown(label);
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
  await t.tap(find.text(value).last);
  await t.pumpAndSettle();
}

Future<void> save(WidgetTester t) async {
  await t.tap(find.text('Enregistrer').last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Fan corner exclusion angle is editable independently from comfort distances',
    (t) async {
      desktop(t);
      final store = SnapshotStore()..saved = audiencePlan(count: 12);
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      await t.tap(find.text('Disposer mobilier'));
      await t.pumpAndSettle();
      await choose(t, 'Mode de disposition', 'Sièges face à une scène');
      await t.tap(find.text('Disposer').last);
      await t.pumpAndSettle();
      await choose(t, 'Mode de déploiement', audienceLayouts[1]);
      final angle = field(
        'Angle du dégagement près des coins de la scène (degrés)',
      );
      await t.ensureVisible(angle);
      await t.enterText(angle, '0');
      await save(t);
      expect(store.saved['audienceSettings']['fanClearanceAngle'], 0.0);
      expect(eventComfort(store.saved)['fanSideGap'], 1.0);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Inventory adds autonomous chairs and benches together with computed capacity',
    (t) async {
      desktop(t);
      final store = SnapshotStore()..saved = audiencePlan(count: 0);
      store.saved['types'] = [
        for (final shape in ['chaise', 'banc'])
          {
            'id': shape,
            'name': shape,
            'shape': shape,
            'w': shape == 'banc' ? 2.2 : .5,
            'h': .5,
            'capacity': shape == 'banc' ? 8 : 1,
            'quantity': 2,
            'limit': 2,
            'source': 'Propre',
            'enabled': true,
            'seating': 'Chaises',
          },
      ];
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      await t.tap(find.text('Mobilier').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Ajouter tout le mobilier sélectionné'));
      await t.pumpAndSettle();
      expect(tables(store.saved).length, 4);
      expect(tables(store.saved).where((v) => v['kind'] == 'bench').length, 2);
      expect(workspaceStats(store.saved)['capacity'], 10);
      validateProject(store.saved);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Mixed plan renders exhibitor names and rotated autonomous seating',
    (t) async {
      desktop(t);
      final store = SnapshotStore()..saved = audiencePlan(count: 20);
      store.saved['mealService'] = 'Non';
      store.saved['joining'] = 'Petits côtés';
      final stands = standPlan();
      for (final item in tables(stands)) {
        item['y'] = 11.0;
        rows(store.saved, 'items').add(item);
      }
      store.saved['groups'] = [
        exhibitor('a', 3),
        exhibitor('b', 1.2),
        seatedGroup('c', 8),
      ];
      arrangeAudience(store.saved, {
        'scene': 'scene',
        'layout': audienceLayouts[2],
        'side': 'Bas',
        'opening': 100.0,
      });
      allocate(store.saved);
      final capture = GlobalKey();
      await t.runAsync(() async {
        final font = FontLoader('Roboto')
          ..addFont(
            File('C:/Windows/Fonts/arial.ttf')
                .readAsBytes()
                .then((v) => v.buffer.asByteData()),
          );
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            File(materialIconsPath())
                .readAsBytes()
                .then((v) => v.buffer.asByteData()),
          );
        await icons.load();
      });
      await t.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: Tableo(store: store),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('output/qa').create(recursive: true);
        await File('output/qa/mixed-furniture.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    },
  );

  testWidgets(
    'Exhibitor editor shows table/metre requests and manual stand allocation saves',
    (t) async {
      desktop(t);
      final store = SnapshotStore()..saved = standPlan();
      store.saved['groups'] = [exhibitor('a', 3)];
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      await t.tap(find.text('Réservations').first);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Modifier'),
        140,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('reservations-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.drag(
        find.byKey(const ValueKey('reservations-list')),
        const Offset(0, -200),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Modifier'));
      await t.pumpAndSettle();
      expect(field('Mètres linéaires demandés'), findsOneWidget);
      expect(field('Nombre de tables demandé'), findsNothing);
      await t.enterText(field('Mètres linéaires demandés'), '2,40');
      await save(t);
      expect(
        number(rows(store.saved, 'groups').single['requestedMetres']),
        2.4,
      );
      await t.tap(find.text('Tables').last);
      await t.pumpAndSettle();
      expect(find.text('Stand de Exposant a'), findsOneWidget);
      await t.tap(find.text('Attribuer').first);
      await t.pumpAndSettle();
      await t.enterText(field('Longueur attribuée (m)'), '1,20');
      await save(t);
      await save(t);
      expect(
        number(rows(store.saved, 'groups').single['standAlloc'][0]['length']),
        1.2,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Scene mode uses named zones and angles; spacing remains in event comfort',
    (t) async {
      desktop(t);
      final store = SnapshotStore()..saved = audiencePlan(count: 8);
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      await t.tap(find.text('Disposer mobilier'));
      await t.pumpAndSettle();
      await choose(t, 'Mode de disposition', 'Sièges face à une scène');
      await t.tap(find.text('Disposer').last);
      await t.pumpAndSettle();
      expect(
        find.text('Disposition des sièges face à la scène'),
        findsOneWidget,
      );
      expect(find.text('Scène'), findsWidgets);
      await choose(t, 'Mode de déploiement', audienceLayouts[2]);
      await save(t);
      expect(store.saved['arrangementMode'], 'Scène');
      expect(tables(store.saved).any((v) => number(v['angle']) != 0), true);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Chair editor can reserve a numbered place without touching stock or the layout',
    (t) async {
      desktop(t);
      final store = SnapshotStore()..saved = audiencePlan(count: 4);
      store.saved['groups'] = [seatedGroup('a', 2)];
      arrangeAudience(store.saved, {
        'scene': 'scene',
        'layout': audienceLayouts.first,
        'side': 'Bas',
      });
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      final id = tables(store.saved).first['id'];
      final item = find.byKey(ValueKey('plan-item-$id'));
      await t.tap(item);
      await t.pump(const Duration(milliseconds: 60));
      await t.tap(item);
      await t.pumpAndSettle();
      expect(find.text('Modifier c0'), findsOneWidget);
      await save(t);
      expect(find.text('Places numérotées — c0'), findsOneWidget);
      await choose(t, 'Place 1', 'Exposant a — personne 1');
      await save(t);
      final g = rows(store.saved, 'groups').single;
      expect(g['seats'][0]['table'], id);
      expect(g['seats'][0]['fixed'], true);
      expect(g['alloc'].single['count'], 1);
      expect(t.takeException(), isNull);
    },
  );
}
