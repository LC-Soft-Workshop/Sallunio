import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/parcours.dart';
import 'package:tableo/parcours_snapshot.dart';

import 'parcours_ui_test.dart' show desktop, fonts;
import 'parcours_zones_test.dart' show servicePlan;
import 'ui_test.dart' show MemoryStore, immediateArrangement;

void main() {
  testWidgets(
    'Snapshot selects a bar behind overlapping invisible aisles without editing until accepted',
    (tester) async {
      desktop(tester);
      await fonts(tester);
      final p = servicePlan(selected: false);
      p['parcoursSettings']['circulation'] = 'Ouvert';
      rows(p, 'items').add({
        'id': 'aisle',
        'kind': 'zone',
        'shape': 'rectangle',
        'fixed': false,
        'label': 'Allée fictive',
        'zoneFill': 'Invisible',
        'x': 0.0,
        'y': 3.0,
        'w': 18.0,
        'h': 4.0,
      });
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: Tableo(
            store: MemoryStore([p]),
            arrangementRunner: immediateArrangement,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disposer tables'));
      await tester.pumpAndSettle();
      final snapshot = find.byKey(const ValueKey('parcours-snapshot'));
      final rect = tester.getRect(snapshot), scale = rect.width / 18;
      await tester.tapAt(rect.topLeft + Offset(9 * scale, 5 * scale));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ParcoursSnapshot>(find.byType(ParcoursSnapshot)).selected,
        {'bar'},
      );
      expect(
        rows(p, 'items').firstWhere((i) => i['id'] == 'bar')['parcoursAccess'],
        'À exclure',
      );
      final passage = find.byKey(const ValueKey('parcours-passage-aisle'));
      await tester.ensureVisible(passage);
      await tester.pumpAndSettle();
      await tester.tap(passage);
      await tester.pumpAndSettle();
      await tester.ensureVisible(snapshot);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('output/qa').createSync(recursive: true);
        File('output/qa/parcours-snapshot.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
      await tester.tap(find.text('Disposer'));
      await tester.pumpAndSettle();
      expect(
        rows(p, 'items').firstWhere((i) => i['id'] == 'bar')['parcoursAccess'],
        'À desservir',
      );
      expect(
        rows(
          p,
          'items',
        ).firstWhere((i) => i['id'] == 'aisle')['parcoursPassage'],
        'Oui',
      );
      expect(parcoursWarnings(p), isEmpty);
      expect(p['parcoursPlan']['services'].single['id'], 'bar');
      await tester.tap(find.text('Disposer tables'));
      await tester.pumpAndSettle();
      final refreshed = tester.widget<ParcoursSnapshot>(
        find.byType(ParcoursSnapshot),
      );
      expect(
        rows(
          refreshed.project,
          'items',
        ).where((i) => i['kind'] == 'table').first['x'],
        tables(p).first['x'],
      );
      expect(refreshed.selected, {'bar'});
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Zone properties expose route controls only for eligible events',
    (tester) async {
      desktop(tester);
      await fonts(tester);
      for (final activity in ['Brocante', 'Loto']) {
        final p = servicePlan()..['activity'] = activity;
        rows(p, 'items').add({
          'id': 'invisible',
          'kind': 'zone',
          'shape': 'rectangle',
          'fixed': false,
          'label': 'Allée fictive',
          'zoneFill': 'Invisible',
          'x': 0.0,
          'y': 3.0,
          'w': 18.0,
          'h': 4.0,
        });
        await tester.pumpWidget(
          Tableo(key: ValueKey(activity), store: MemoryStore([p])),
        );
        await tester.pumpAndSettle();
        final zone = find.byKey(const ValueKey('plan-item-bar'));
        await tester.tap(zone);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tap(zone);
        await tester.pumpAndSettle();
        expect(
          find.text('Rôle dans le parcours visiteurs'),
          activity == 'Brocante' ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );
}
